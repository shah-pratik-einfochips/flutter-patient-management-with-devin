import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/patient_repository.dart';
import '../domain/patient.dart';

final repositoryProvider = Provider<PatientRepository>((ref) {
  final repository = LocalPatientRepository(
    SqliteRecordStore(),
    PlatformKeyStore(),
  );
  ref.onDispose(() => unawaited(repository.close()));
  return repository;
});

class StorageUnavailable implements Exception {
  const StorageUnavailable();
}

final patientsProvider =
    AsyncNotifierProvider<PatientController, List<Patient>>(
      PatientController.new,
    );

class PatientController extends AsyncNotifier<List<Patient>> {
  @override
  Future<List<Patient>> build() async {
    try {
      return await ref.watch(repositoryProvider).load();
    } catch (_) {
      throw const StorageUnavailable();
    }
  }

  Future<void> save(Patient patient) async {
    if (!state.hasValue) throw const StorageUnavailable();
    state = AsyncData(await ref.read(repositoryProvider).save(patient));
  }

  Future<void> addReading(String patientId, VitalReading reading) async {
    if (!state.hasValue) throw const StorageUnavailable();
    state = AsyncData(
      await ref.read(repositoryProvider).addReading(patientId, reading),
    );
  }
}
