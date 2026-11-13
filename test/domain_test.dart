import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:patient_health/domain/patient.dart';

import 'support.dart';

void main() {
  final now = DateTime(2026, 10, 28, 12);
  group('Patient profiles', () {
    test(
      'valid profile',
      () => expect(syntheticPatient().errors(now: now), isEmpty),
    );
    test(
      'missing required fields and consent',
      () => expect(Patient().errors(now: now), hasLength(5)),
    );
    test('whitespace required fields', () {
      final patient = syntheticPatient()
          .withField(ProfileField.firstName, ' ')
          .withField(ProfileField.lastName, '\n')
          .withField(ProfileField.medicalId, '\t');
      expect(patient.errors(now: now), hasLength(3));
    });
    test(
      'DOB must be explicitly selected',
      () => expect(
        Patient(
          fields: syntheticPatient().fields,
          consentGranted: true,
        ).errors(now: now),
        contains('Select a date of birth.'),
      ),
    );
    test(
      'future DOB rejected',
      () => expect(
        syntheticPatient().copyWith(birthDate: DateTime(2999)).errors(now: now),
        isNotEmpty,
      ),
    );
    test('impossible dates rejected', () {
      expect(parseDate('2026-02-30'), isNull);
      expect(parseDate('2024-02-29'), DateTime(2024, 2, 29));
      expect(parseDate('01/02/2026'), isNull);
    });
    test('email validation', () {
      expect(
        syntheticPatient()
            .withField(ProfileField.email, 'bad@')
            .errors(now: now),
        isNotEmpty,
      );
      expect(
        syntheticPatient()
            .withField(ProfileField.email, 'test@example.com')
            .errors(now: now),
        isEmpty,
      );
    });
    test(
      'consent required',
      () => expect(
        syntheticPatient().copyWith(consentGranted: false).errors(now: now),
        isNotEmpty,
      ),
    );
    test('all six examination options are valid', () {
      expect(examinationTypes, hasLength(6));
      for (final type in examinationTypes) {
        expect(
          syntheticPatient()
              .withField(ProfileField.examinationType, type)
              .errors(now: now),
          isEmpty,
        );
      }
    });
    test(
      'unlisted examination rejected',
      () => expect(
        syntheticPatient()
            .withField(ProfileField.examinationType, 'Invalid')
            .errors(now: now),
        isNotEmpty,
      ),
    );
    test(
      'medical ID normalization',
      () => expect(
        syntheticPatient(medicalId: ' TEST-001 ').normalizedMedicalId,
        'test-001',
      ),
    );
    test('round trip retains DOB, examination, and vitals', () {
      final patient = syntheticPatient()
          .withField(ProfileField.examinationType, 'Emergency')
          .copyWith(
            vitals: [
              VitalReading(date: now, values: {VitalMetric.heartRate: 72}),
            ],
          );
      final decoded = Patient.fromJson(
        jsonDecode(jsonEncode(patient.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.toJson(), patient.toJson());
    });
    test(
      'unknown schema is not silently accepted',
      () => expect(
        () => Patient.fromJson({
          ...syntheticPatient().toJson(),
          'schemaVersion': 2,
        }),
        throwsFormatException,
      ),
    );
    test(
      'immutable profile collections',
      () => expect(
        () => syntheticPatient().fields[ProfileField.firstName] = 'Changed',
        throwsUnsupportedError,
      ),
    );
  });
  group('Vitals and conversions', () {
    VitalReading reading(Map<VitalMetric, double> values) =>
        VitalReading(date: now, values: values);
    test('unit conversions', () {
      expect(UnitConversion.kilograms(100), closeTo(45.359237, 0.000001));
      expect(UnitConversion.centimeters(5, 10), closeTo(177.8, 0.000001));
      expect(UnitConversion.celsius(98.6), closeTo(37, 0.000001));
      expect(UnitConversion.celsius(32), 0);
    });
    test('strict decimal input rejects partial and non-finite values', () {
      for (final value in [
        '',
        '70abc',
        'NaN',
        'Infinity',
        '1,000',
        '1 2',
        '1.2.3',
        '1e3',
      ]) {
        expect(
          decimalInput(value, decimalSeparator: '.'),
          isNull,
          reason: value,
        );
      }
      expect(decimalInput(' 70.5 ', decimalSeparator: '.'), 70.5);
      expect(decimalInput('37,5', decimalSeparator: ','), 37.5);
    });
    test('MAP calculation', () {
      expect(
        reading({VitalMetric.systolic: 120, VitalMetric.diastolic: 80})
            .meanArterialPressure,
        closeTo(93.333333, 0.00001),
      );
      expect(reading({VitalMetric.systolic: 120}).meanArterialPressure, isNull);
    });
    test(
      'valid vitals',
      () => expect(
        reading({VitalMetric.heartRate: 70, VitalMetric.pain: 0})
            .errors(birthDate: DateTime(1990), now: now),
        isEmpty,
      ),
    );
    test(
      'empty vitals rejected',
      () => expect(
        reading({}).errors(birthDate: DateTime(1990), now: now),
        isNotEmpty,
      ),
    );
    test('partial BP rejected', () {
      for (final metric in [VitalMetric.systolic, VitalMetric.diastolic]) {
        expect(
          reading({metric: 100}).errors(birthDate: DateTime(1990), now: now),
          isNotEmpty,
        );
      }
    });
    test(
      'inverted BP rejected',
      () => expect(
        reading({VitalMetric.systolic: 80, VitalMetric.diastolic: 120})
            .errors(birthDate: DateTime(1990), now: now),
        isNotEmpty,
      ),
    );
    test('invalid values rejected for every metric', () {
      for (final metric in VitalMetric.values) {
        for (final value in [
          double.nan,
          double.infinity,
          double.negativeInfinity,
          metric.minimum - 1,
          metric.maximum + 1,
        ]) {
          expect(
            reading({metric: value})
                .errors(birthDate: DateTime(1990), now: now),
            isNotEmpty,
          );
        }
      }
    });
    test(
      'future date rejected',
      () => expect(
        VitalReading(
          date: now.add(const Duration(minutes: 1)),
          values: {VitalMetric.heartRate: 70},
        ).errors(birthDate: DateTime(1990), now: now),
        isNotEmpty,
      ),
    );
    test(
      'reading before DOB rejected',
      () => expect(
        reading({VitalMetric.heartRate: 70})
            .errors(birthDate: now.add(const Duration(days: 1)), now: now),
        isNotEmpty,
      ),
    );
    test('illustrative ranges', () {
      expect(VitalMetric.heartRate.outsideReference(130), isTrue);
      expect(VitalMetric.heartRate.outsideReference(70), isFalse);
      expect(VitalMetric.height.outsideReference(180), isFalse);
    });
    test('selected units normalize correctly', () {
      final draft = VitalDraft(
        date: now,
        inputs: {
          VitalMetric.height: '5',
          VitalMetric.weight: '100',
          VitalMetric.temperature: '98.6',
        },
        heightUnit: 'ft/in',
        inches: '10',
        weightUnit: 'lbs',
        temperatureUnit: 'F',
      );
      expect(draft.errors(DateTime(1990), now: now), isEmpty);
      expect(
        draft.reading().values[VitalMetric.height],
        closeTo(177.8, 0.000001),
      );
      expect(
        draft.reading().values[VitalMetric.weight],
        closeTo(45.359237, 0.000001),
      );
      expect(
        draft.reading().values[VitalMetric.temperature],
        closeTo(37, 0.000001),
      );
    });
    test(
      'invalid optional input is not silently discarded',
      () => expect(
        VitalDraft(
          date: now,
          inputs: {VitalMetric.heartRate: '70', VitalMetric.pain: 'bad'},
        ).errors(DateTime(1990), now: now),
        isNotEmpty,
      ),
    );
    test('inches validation', () {
      for (final inches in ['12', '-1', 'bad']) {
        expect(
          VitalDraft(
            date: now,
            inputs: {VitalMetric.height: '5'},
            heightUnit: 'ft/in',
            inches: inches,
          ).errors(DateTime(1990), now: now),
          isNotEmpty,
        );
      }
      expect(
        VitalDraft(
          date: now,
          inputs: {VitalMetric.heartRate: '70'},
          heightUnit: 'ft/in',
          inches: '6',
        ).errors(DateTime(1990), now: now),
        isNotEmpty,
      );
    });
    test('seven-day window includes boundary and excludes future', () {
      final start = DateTime(2026, 10, 22);
      final dates = [
        start.subtract(const Duration(milliseconds: 1)),
        start,
        now,
        now.add(const Duration(milliseconds: 1)),
      ];
      expect(
        recentReadings(
          dates.map((d) => VitalReading(date: d)).toList(),
          now: now,
        ).map((r) => r.date),
        [start, now],
      );
    });
  });
}
