import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patient_health/app.dart';
import 'package:patient_health/data/patient_repository.dart';
import 'package:patient_health/domain/patient.dart';
import 'package:patient_health/presentation/providers.dart';

import 'support.dart';

void main() {
  Future<LocalPatientRepository> openApp(
    WidgetTester tester, {
    bool withPatient = false,
  }) async {
    final repository = LocalPatientRepository(MemoryRecords(), MemoryKeys());
    await repository.load();
    if (withPatient) await repository.save(syntheticPatient());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repository)],
        retry: (_, _) => null,
        child: const PatientHealthApp(),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('empty patient list and explicit DOB selection', (tester) async {
    await openApp(tester);
    expect(find.text('No patients yet'), findsOneWidget);
    await tester.tap(find.text('Add patient'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('savePatient')))
          .onPressed,
      isNull,
    );
    expect(find.text('Date of birth: Select date'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('birthDate')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Date of birth: Select date'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('birthDate')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Date of birth: Select date'), findsNothing);
  });
  testWidgets('examination dropdown exposes and selects all six choices', (
    tester,
  ) async {
    await openApp(tester);
    await tester.tap(find.text('Add patient'));
    await tester.pumpAndSettle();
    final picker = find.byKey(ValueKey(ProfileField.examinationType.name));
    await tester.scrollUntilVisible(
      picker,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(picker);
    await tester.pumpAndSettle();
    for (final type in examinationTypes) {
      expect(find.text(type), findsOneWidget);
    }
    await tester.tap(find.text('Emergency'));
    await tester.pumpAndSettle();
    expect(find.text('Emergency'), findsOneWidget);
  });
  testWidgets('vital entry saves a valid reading and shows updated dashboard', (
    tester,
  ) async {
    final repository = await openApp(tester, withPatient: true);
    await tester.tap(find.text('Synthetic Patient'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add vitals'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('saveVitals')))
          .onPressed,
      isNull,
    );
    final heart = find.byKey(const ValueKey('heartRate-bpm'));
    await tester.scrollUntilVisible(
      heart,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(heart, '72');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('saveVitals')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('saveVitals')));
    await tester.pumpAndSettle();
    expect(
      (await repository.load()).single.vitals.single.values[VitalMetric
          .heartRate],
      72,
    );
    expect(find.text('Last seven days'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('search filters profiles', (tester) async {
    await openApp(tester, withPatient: true);
    await tester.enterText(find.byType(TextField).first, 'no-match');
    await tester.pumpAndSettle();
    expect(find.text('No matching patients'), findsOneWidget);
    expect(find.text('Synthetic Patient'), findsNothing);
  });
  testWidgets('storage failure shows retry without internal error details', (
    tester,
  ) async {
    final keys = MemoryKeys()..value = 'invalid key';
    final repository = LocalPatientRepository(MemoryRecords(), keys);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repository)],
        retry: (_, _) => null,
        child: const PatientHealthApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Storage unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('invalid key'), findsNothing);
  });
}
