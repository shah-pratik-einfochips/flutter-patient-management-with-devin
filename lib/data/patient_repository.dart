import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/patient.dart';

class EncryptedRecord {
  EncryptedRecord(this.id, List<int> payload)
    : payload = Uint8List.fromList(payload);
  final String id;
  final Uint8List payload;
}

abstract interface class RecordStore {
  Future<List<EncryptedRecord>> readAll();
  Future<void> write(EncryptedRecord record);
  Future<void> close();
}

abstract interface class KeyStore {
  Future<String?> read();
  Future<void> write(String value);
}

class PlatformKeyStore implements KeyStore {
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );
  static const _key = 'patient-health-encryption-v1';
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
}

class SqliteRecordStore implements RecordStore {
  SqliteRecordStore({this.databaseName = 'patient-health.db'}) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+\.db$').hasMatch(databaseName)) {
      throw ArgumentError('Database name must be a plain filename');
    }
  }
  final String databaseName;
  Database? _database;
  Future<Database> _open() async {
    return _database ??= await openDatabase(
      '${await getDatabasesPath()}/$databaseName',
      version: 1,
      onCreate: (db, version) => db.execute(
        'CREATE TABLE patients (id TEXT PRIMARY KEY NOT NULL, payload BLOB NOT NULL)',
      ),
      onUpgrade: (db, oldVersion, newVersion) =>
          throw StateError('Database migration is not implemented'),
    );
  }

  @override
  Future<List<EncryptedRecord>> readAll() async =>
      (await (await _open()).query('patients'))
          .map(
            (row) => EncryptedRecord(
              row['id'] as String,
              row['payload'] as Uint8List,
            ),
          )
          .toList();
  @override
  Future<void> write(EncryptedRecord record) async {
    await (await _open()).insert('patients', {
      'id': record.id,
      'payload': record.payload,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}

class PatientCipher {
  final _algorithm = AesGcm.with256bits();
  Future<List<int>> newKey() async =>
      (await _algorithm.newSecretKey()).extractBytes();
  Future<Uint8List> encrypt(Patient patient, List<int> key) async {
    final box = await _algorithm.encrypt(
      utf8.encode(jsonEncode(patient.toJson())),
      secretKey: SecretKey(key),
      aad: utf8.encode(patient.id),
    );
    return Uint8List.fromList(box.concatenation());
  }

  Future<Patient> decrypt(EncryptedRecord record, List<int> key) async {
    final box = SecretBox.fromConcatenation(
      record.payload,
      nonceLength: 12,
      macLength: 16,
    );
    final data = await _algorithm.decrypt(
      box,
      secretKey: SecretKey(key),
      aad: utf8.encode(record.id),
    );
    final patient = Patient.fromJson(
      jsonDecode(utf8.decode(data)) as Map<String, dynamic>,
    );
    if (patient.id != record.id) {
      throw const FormatException('Record identity mismatch');
    }
    return patient;
  }
}

class PatientValidationException implements Exception {
  const PatientValidationException(this.message);
  final String message;
}

abstract interface class PatientRepository {
  Future<List<Patient>> load();
  Future<List<Patient>> save(Patient patient);
  Future<List<Patient>> addReading(String patientId, VitalReading reading);
  Future<void> close();
}

class LocalPatientRepository implements PatientRepository {
  LocalPatientRepository(this.records, this.keys, {PatientCipher? cipher})
    : cipher = cipher ?? PatientCipher();
  final RecordStore records;
  final KeyStore keys;
  final PatientCipher cipher;
  List<int>? _key;
  List<Patient> _patients = [];
  bool _loaded = false;
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  @override
  Future<List<Patient>> load() => _serial(() async {
    _loaded = false;
    final all = await records.readAll();
    final encoded = await keys.read();
    if (encoded == null) {
      if (all.isNotEmpty) throw StateError('Encryption key is unavailable');
      _key = await cipher.newKey();
      await keys.write(base64Encode(_key!));
    } else {
      _key = base64Decode(encoded);
      if (_key!.length != 32) {
        throw const FormatException('Invalid encryption key');
      }
    }
    final decoded = <Patient>[];
    for (final record in all) {
      decoded.add(await cipher.decrypt(record, _key!));
    }
    _patients = decoded
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _loaded = true;
    return List.unmodifiable(_patients);
  });

  @override
  Future<List<Patient>> save(Patient patient) =>
      _serial(() => _persist(patient));
  @override
  Future<List<Patient>> addReading(String patientId, VitalReading reading) =>
      _serial(() async {
        final matches = _patients.where((p) => p.id == patientId);
        if (matches.isEmpty) {
          throw const PatientValidationException(
            'Patient is unavailable. Reopen the profile.',
          );
        }
        final patient = matches.first;
        return _persist(patient.copyWith(vitals: [...patient.vitals, reading]));
      });

  Future<List<Patient>> _persist(Patient patient) async {
    if (!_loaded || _key == null) {
      throw StateError('Secure storage is not open');
    }
    final errors = [
      ...patient.errors(),
      ...patient.vitals.expand((v) => v.errors(birthDate: patient.birthDate)),
    ];
    if (errors.isNotEmpty) throw PatientValidationException(errors.first);
    if (_patients.any(
      (p) =>
          p.id != patient.id &&
          p.normalizedMedicalId == patient.normalizedMedicalId,
    )) {
      throw const PatientValidationException(
        'A patient with this medical ID already exists.',
      );
    }
    await records.write(
      EncryptedRecord(patient.id, await cipher.encrypt(patient, _key!)),
    );
    _patients = [..._patients.where((p) => p.id != patient.id), patient]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List.unmodifiable(_patients);
  }

  @override
  Future<void> close() => _serial(() async {
    _loaded = false;
    _key = null;
    _patients = [];
    await records.close();
  });
}
