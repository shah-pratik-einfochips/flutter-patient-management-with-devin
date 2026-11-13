# patient_health (Flutter)

Cross-platform patient-health prototype for Android and iOS built with Flutter, Riverpod, go_router, fl_chart, and encrypted SQLite storage.

> Synthetic-data-only prototype. Do not use real patient data. No backend/FHIR API, authentication, audit trail, or compliance certification is implemented. Medical ranges are illustrative adult values, not clinical decision support.

## Requirements

- Flutter stable SDK compatible with `pubspec.yaml` (developed with Flutter 3.47.2 / Dart 3.13.2)
- Android: min API 26, compile/target API 36
- iOS: deployment target 17.0; CocoaPods installed (required by `flutter_secure_storage`)

## Getting started

```sh
flutter pub get
flutter run -d <device-id>
```

App identifiers: Android `com.example.patient_health`, iOS `com.example.patientHealthFlutter` (distinct from the native apps).

## Project structure

- `lib/main.dart` – entry point (`PatientHealthApp` within a Riverpod `ProviderScope`)
- `lib/app.dart` – routes
- `lib/domain` – validation and unit conversions
- `lib/data` – encrypted SQLite storage and platform key storage
- `test/` – unit and widget tests
- `integration_test/` – device integration tests

## Common commands

```sh
dart format lib test integration_test   # format
flutter analyze                         # static analysis
flutter test --coverage                 # unit/widget tests (coverage/lcov.info)
flutter test integration_test/app_test.dart -d <device-id> --no-uninstall   # integration (test device only)
flutter build apk --debug               # Android debug build
```

## Security

Patient payloads are AES-256-GCM encrypted before SQLite storage, with UUIDs authenticated as associated data. The key is held in Android Keystore-backed encrypted preferences or iOS Keychain (`unlocked_this_device`). Android backup is disabled and the activity uses `FLAG_SECURE`.

## Documentation

- `requirements.md` – product requirements
- `todo.md` – task list
- `AGENTS.md` – development notes
