import 'package:patient_health/data/patient_repository.dart';
import 'package:patient_health/domain/patient.dart';

Patient syntheticPatient({String medicalId = 'TEST-001'}) => Patient(
  fields: {
    ProfileField.firstName: 'Synthetic',
    ProfileField.lastName: 'Patient',
    ProfileField.medicalId: medicalId,
  },
  birthDate: DateTime(1990, 1, 1),
  consentGranted: true,
);

class MemoryRecords implements RecordStore {
  final rows = <String, EncryptedRecord>{};
  bool failWrites = false;
  @override
  Future<List<EncryptedRecord>> readAll() async => rows.values.toList();
  @override
  Future<void> write(EncryptedRecord record) async {
    if (failWrites) throw StateError('Simulated disk failure');
    rows[record.id] = record;
  }

  @override
  Future<void> close() async {}
}

class MemoryKeys implements KeyStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}
