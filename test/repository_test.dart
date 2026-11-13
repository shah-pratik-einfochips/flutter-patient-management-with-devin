import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patient_health/data/patient_repository.dart';
import 'package:patient_health/domain/patient.dart';
import 'package:patient_health/presentation/providers.dart';

import 'support.dart';

void main() {
  late MemoryRecords records;
  late MemoryKeys keys;
  late LocalPatientRepository repository;
  setUp(() {
    records = MemoryRecords();
    keys = MemoryKeys();
    repository = LocalPatientRepository(records, keys);
  });
  test('save, reload, and edit encrypted records', () async {
    expect(await repository.load(), isEmpty);
    final patient = syntheticPatient();
    await repository.save(patient);
    await repository.addReading(
      patient.id,
      VitalReading(values: {VitalMetric.heartRate: 72}),
    );
    final second = LocalPatientRepository(records, keys);
    final loaded = await second.load();
    expect(loaded.single.vitals.single.values[VitalMetric.heartRate], 72);
    await second.save(
      loaded.single.withField(ProfileField.firstName, 'Updated'),
    );
    expect((await repository.load()).single.name, 'Updated Patient');
    expect(
      latin1.decode(records.rows.values.single.payload).contains('TEST-001'),
      isFalse,
    );
  });
  test('missing key with existing records fails closed', () async {
    await repository.load();
    await repository.save(syntheticPatient());
    keys.value = null;
    await expectLater(repository.load(), throwsStateError);
    expect(keys.value, isNull);
    expect(records.rows, hasLength(1));
    await expectLater(
      repository.save(syntheticPatient(medicalId: 'TEST-002')),
      throwsStateError,
    );
  });
  test('invalid stored key fails closed', () async {
    keys.value = base64Encode([1, 2]);
    await expectLater(repository.load(), throwsFormatException);
    expect(records.rows, isEmpty);
  });
  test('duplicate medical ID rejected case-insensitively', () async {
    await repository.load();
    await repository.save(syntheticPatient());
    await expectLater(
      repository.save(syntheticPatient(medicalId: ' test-001 ')),
      throwsA(isA<PatientValidationException>()),
    );
    expect(records.rows, hasLength(1));
  });
  test('invalid profiles and vitals rejected', () async {
    await repository.load();
    await expectLater(
      repository.save(Patient()),
      throwsA(isA<PatientValidationException>()),
    );
    final patient = syntheticPatient();
    await repository.save(patient);
    await expectLater(
      repository.addReading(
        patient.id,
        VitalReading(values: {VitalMetric.pain: 11}),
      ),
      throwsA(isA<PatientValidationException>()),
    );
    expect((await repository.load()).single.vitals, isEmpty);
  });
  test('tampering rejected without resetting records', () async {
    await repository.load();
    await repository.save(syntheticPatient());
    records.rows.values.single.payload.last ^= 1;
    await expectLater(repository.load(), throwsA(isA<Exception>()));
    expect(records.rows, hasLength(1));
  });
  test('record substitution rejected', () async {
    await repository.load();
    await repository.save(syntheticPatient());
    final payload = records.rows.values.single.payload;
    records.rows.clear();
    records.rows['other-id'] = EncryptedRecord('other-id', payload);
    await expectLater(repository.load(), throwsA(isA<Exception>()));
  });
  test('wrong key cannot decrypt a record', () async {
    final cipher = PatientCipher();
    final patient = syntheticPatient();
    final payload = await cipher.encrypt(patient, await cipher.newKey());
    await expectLater(
      cipher.decrypt(
        EncryptedRecord(patient.id, payload),
        await cipher.newKey(),
      ),
      throwsA(isA<Exception>()),
    );
  });
  test('same patient encrypts differently each time', () async {
    final cipher = PatientCipher();
    final key = await cipher.newKey();
    final patient = syntheticPatient();
    expect(
      await cipher.encrypt(patient, key),
      isNot(equals(await cipher.encrypt(patient, key))),
    );
  });
  test('disk failure preserves previous state and queue recovers', () async {
    await repository.load();
    final patient = syntheticPatient();
    await repository.save(patient);
    records.failWrites = true;
    await expectLater(
      repository.save(patient.withField(ProfileField.firstName, 'Changed')),
      throwsStateError,
    );
    records.failWrites = false;
    expect((await repository.load()).single.name, patient.name);
    await repository.save(patient.withField(ProfileField.firstName, 'Updated'));
    expect((await repository.load()).single.name, 'Updated Patient');
  });
  test('concurrent readings are not lost', () async {
    await repository.load();
    final patient = syntheticPatient();
    await repository.save(patient);
    await Future.wait(
      List.generate(
        5,
        (_) => repository.addReading(
          patient.id,
          VitalReading(values: {VitalMetric.heartRate: 70}),
        ),
      ),
    );
    expect((await repository.load()).single.vitals, hasLength(5));
  });
  test(
    'database path traversal is rejected',
    () => expect(
      () => SqliteRecordStore(databaseName: '../other.db'),
      throwsArgumentError,
    ),
  );
  test('Riverpod controller updates patient state', () async {
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repository)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    expect(await container.read(patientsProvider.future), isEmpty);
    await container.read(patientsProvider.notifier).save(syntheticPatient());
    expect(container.read(patientsProvider).requireValue, hasLength(1));
  });
  test(
    'Riverpod controller wraps storage errors without exposing details',
    () async {
      keys.value = 'invalid key';
      final container = ProviderContainer(
        overrides: [repositoryProvider.overrideWithValue(repository)],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);
      await expectLater(
        container.read(patientsProvider.future),
        throwsA(isA<StorageUnavailable>()),
      );
      expect(container.read(patientsProvider).hasError, isTrue);
    },
  );
}
