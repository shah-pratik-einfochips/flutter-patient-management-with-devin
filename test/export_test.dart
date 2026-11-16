import 'package:flutter_test/flutter_test.dart';
import 'package:patient_health/domain/patient.dart';
import 'package:patient_health/presentation/export.dart';

import 'support.dart';

void main() {
  Patient withVitals({String medicalId = 'TEST-001'}) => Patient(
    fields: {
      ProfileField.firstName: 'Synthetic',
      ProfileField.lastName: 'Patient',
      ProfileField.medicalId: medicalId,
    },
    birthDate: DateTime(1990, 1, 1),
    consentGranted: true,
    vitals: [
      VitalReading(
        values: {VitalMetric.heartRate: 70, VitalMetric.oxygen: 90},
        symptoms: 'note, with comma',
      ),
    ],
  );

  test('CSV quotes commas and marks out-of-range values', () {
    final csv = patientCsv(withVitals());
    expect(csv, contains('"note, with comma"'));
    expect(csv, contains('reading_date,metric,value,unit'));
    expect(csv, contains('yes'));
    expect(csv, contains('Heart rate'));
  });

  test('CSV quotes embedded quotes and commas in profile fields', () {
    final patient = syntheticPatient().withField(
      ProfileField.lastName,
      'Doe, "JD"',
    );
    expect(patientCsv(patient), contains('"Synthetic Doe, ""JD"""'));
  });

  test('CSV and PDF files are written and filenames are sanitized', () async {
    final csv = await exportCsv(withVitals(medicalId: 'PT/2024/001'));
    final pdf = await exportPdf(withVitals(medicalId: 'PT/2024/001'));
    expect(csv.path.split('/').last, isNot(contains('/')));
    expect(pdf.path.split('/').last, isNot(contains('/')));
    expect(await csv.length(), greaterThan(0));
    final bytes = await pdf.readAsBytes();
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
  });
}
