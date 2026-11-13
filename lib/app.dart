import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'domain/patient.dart';
import 'presentation/components.dart';
import 'presentation/patient_detail.dart';
import 'presentation/patient_form.dart';
import 'presentation/providers.dart';
import 'presentation/vitals_form.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const PatientListPage()),
      GoRoute(path: '/new', builder: (_, _) => const PatientFormPage()),
      GoRoute(
        path: '/patient/:id',
        builder: (_, state) =>
            PatientRoute(id: state.pathParameters['id']!, page: 'detail'),
      ),
      GoRoute(
        path: '/patient/:id/edit',
        builder: (_, state) =>
            PatientRoute(id: state.pathParameters['id']!, page: 'edit'),
      ),
      GoRoute(
        path: '/patient/:id/vitals',
        builder: (_, state) =>
            PatientRoute(id: state.pathParameters['id']!, page: 'vitals'),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class PatientHealthApp extends ConsumerWidget {
  const PatientHealthApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Patient Health Flutter',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006B60)),
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF006B60),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    routerConfig: ref.watch(routerProvider),
    builder: (context, child) =>
        PrivacyGate(child: child ?? const SizedBox.shrink()),
  );
}

class PrivacyGate extends StatefulWidget {
  const PrivacyGate({super.key, required this.child});
  final Widget child;
  @override
  State<PrivacyGate> createState() => _PrivacyGateState();
}

class _PrivacyGateState extends State<PrivacyGate> with WidgetsBindingObserver {
  bool obscured = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => obscured = state != AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      if (obscured)
        ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: const Center(child: Text('Patient Health · Locked view')),
        ),
    ],
  );
}

class StorageStatus extends ConsumerWidget {
  const StorageStatus({super.key, this.failed = false});
  final bool failed;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Patient Health')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: failed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const Text('Storage unavailable'),
                  const Text(
                    'Patient data could not be opened securely. No records have been reset. Unlock the device and retry.',
                  ),
                  FilledButton(
                    onPressed: () => ref.invalidate(patientsProvider),
                    child: const Text('Retry'),
                  ),
                ],
              )
            : const CircularProgressIndicator(
                semanticsLabel: 'Opening secure storage',
              ),
      ),
    ),
  );
}

class PatientRoute extends ConsumerWidget {
  const PatientRoute({super.key, required this.id, required this.page});
  final String id, page;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(patientsProvider)
      .when(
        loading: () => const StorageStatus(),
        error: (_, _) => const StorageStatus(failed: true),
        data: (patients) {
          final patient = patients.where((p) => p.id == id).firstOrNull;
          if (patient == null) {
            return const AppPage(
              title: 'Patient unavailable',
              children: [Text('Return to the patient list.')],
            );
          }
          return switch (page) {
            'edit' => PatientFormPage(patient: patient),
            'vitals' => VitalsFormPage(patient: patient),
            _ => PatientDetailPage(patient: patient),
          };
        },
      );
}

class PatientListPage extends ConsumerStatefulWidget {
  const PatientListPage({super.key});
  @override
  ConsumerState<PatientListPage> createState() => _PatientListPageState();
}

class _PatientListPageState extends ConsumerState<PatientListPage> {
  String search = '';
  @override
  Widget build(BuildContext context) => ref
      .watch(patientsProvider)
      .when(
        loading: () => const StorageStatus(),
        error: (_, _) => const StorageStatus(failed: true),
        data: (patients) {
          final filtered = patients.where(
            (p) =>
                search.isEmpty ||
                p.name.toLowerCase().contains(search.toLowerCase()) ||
                p.medicalId.toLowerCase().contains(search.toLowerCase()),
          );
          return AppPage(
            title: 'Patient Health',
            actions: [
              TextButton.icon(
                onPressed: () => context.push('/new'),
                icon: const Icon(Icons.add),
                label: const Text('Add patient'),
              ),
            ],
            children: [
              const PrototypeNotice(),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Search name or medical ID',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => search = v),
              ),
              if (filtered.isEmpty) ...[
                SectionTitle(
                  patients.isEmpty ? 'No patients yet' : 'No matching patients',
                ),
                Text(
                  patients.isEmpty
                      ? 'Add a synthetic patient profile to get started.'
                      : 'Try another name or medical ID.',
                ),
              ],
              for (final Patient patient in filtered)
                Card(
                  child: ListTile(
                    title: Text(patient.name),
                    subtitle: Text(
                      'ID: ${patient.medicalId}\n${patient.vitals.length} readings',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/patient/${patient.id}'),
                  ),
                ),
            ],
          );
        },
      );
}
