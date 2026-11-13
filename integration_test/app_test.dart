import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patient_health/app.dart';
import 'package:patient_health/data/patient_repository.dart';
import 'package:patient_health/domain/patient.dart';
import 'package:patient_health/presentation/providers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'secure platform storage survives reopening and app saves vitals',
    (tester) async {
      final name = 'integration-${DateTime.now().microsecondsSinceEpoch}.db';
      final first = LocalPatientRepository(
        SqliteRecordStore(databaseName: name),
        PlatformKeyStore(),
      );
      await first.load();
      final patient = Patient(
        fields: {
          ProfileField.firstName: 'Synthetic',
          ProfileField.lastName: 'Integration',
          ProfileField.medicalId: 'INTEGRATION-001',
          ProfileField.examinationType: 'Follow-up',
        },
        birthDate: DateTime(1990, 1, 1),
        consentGranted: true,
      );
      await first.save(patient);
      await first.close();
      final repository = LocalPatientRepository(
        SqliteRecordStore(databaseName: name),
        PlatformKeyStore(),
      );
      final loaded = await repository.load();
      expect(loaded.single.id, patient.id);
      expect(loaded.single.value(ProfileField.examinationType), 'Follow-up');
      addTearDown(repository.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(repository)],
          retry: (_, _) => null,
          child: const PatientHealthApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Synthetic Integration'), findsOneWidget);
      await tester.tap(find.text('Synthetic Integration'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add vitals'));
      await tester.pumpAndSettle();
      final heart = find.byKey(const ValueKey('heartRate-bpm'));
      await tester.scrollUntilVisible(
        heart,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(heart, '72');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('saveVitals')));
      await tester.pumpAndSettle();
      expect(
        (await repository.load()).single.vitals.single.values[VitalMetric
            .heartRate],
        72,
      );
      expect(find.text('Last seven days'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
