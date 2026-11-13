import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../data/patient_repository.dart';
import '../domain/patient.dart';
import 'components.dart';
import 'providers.dart';

class PatientFormPage extends ConsumerStatefulWidget {
  const PatientFormPage({super.key, this.patient});
  final Patient? patient;
  @override
  ConsumerState<PatientFormPage> createState() => _PatientFormPageState();
}

class _PatientFormPageState extends ConsumerState<PatientFormPage> {
  late Patient draft = widget.patient ?? Patient();
  bool saving = false;

  Widget field(ProfileField field) => TextFormField(
    key: ValueKey(field.name),
    initialValue: draft.value(field),
    decoration: InputDecoration(
      labelText: field.label,
      border: const OutlineInputBorder(),
    ),
    keyboardType: switch (field) {
      ProfileField.email => TextInputType.emailAddress,
      ProfileField.phone => TextInputType.phone,
      _ => TextInputType.text,
    },
    textCapitalization:
        [ProfileField.email, ProfileField.medicalId].contains(field)
        ? TextCapitalization.none
        : TextCapitalization.sentences,
    autocorrect: ![ProfileField.email, ProfileField.medicalId].contains(field),
    onChanged: (value) => setState(() => draft = draft.withField(field, value)),
  );
  Widget choice(ProfileField field, List<String> options) => ChoiceField(
    key: ValueKey(field.name),
    label: field.label,
    value: draft.value(field),
    options: options,
    onChanged: (v) => setState(() => draft = draft.withField(field, v)),
  );

  Future<void> save() async {
    if (saving || draft.errors().isNotEmpty) return;
    setState(() => saving = true);
    try {
      await ref.read(patientsProvider.notifier).save(draft);
      if (mounted) context.pop();
    } catch (error) {
      if (mounted) {
        await showSaveError(
          context,
          error is PatientValidationException ? error.message : 'Unable to save securely. Existing records have not been reset. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AppPage(
      title: widget.patient == null ? 'New patient' : 'Edit patient',
      actions: [
        TextButton(
          key: const ValueKey('savePatient'),
          onPressed: saving || draft.errors().isNotEmpty ? null : save,
          child: Text(saving ? 'Saving…' : 'Save'),
        ),
      ],
      children: [
        const SectionTitle('Demographics'),
        field(ProfileField.firstName),
        field(ProfileField.lastName),
        field(ProfileField.medicalId),
        OutlinedButton(
          key: const ValueKey('birthDate'),
          onPressed: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: draft.birthDate ?? dateOnly(DateTime.now()),
              firstDate: DateTime(1),
              lastDate: dateOnly(DateTime.now()),
            );
            if (date != null && mounted) {
              setState(() => draft = draft.copyWith(birthDate: date));
            }
          },
          child: Text(
            'Date of birth: ${draft.birthDate == null ? 'Select date' : DateFormat.yMMMd().format(draft.birthDate!)}',
          ),
        ),
        choice(ProfileField.gender, const [
          'unknown',
          'female',
          'male',
          'other',
        ]),
        field(ProfileField.ethnicity),
        const SectionTitle('Contact'),
        field(ProfileField.phone),
        field(ProfileField.email),
        const SectionTitle('Clinical details'),
        choice(ProfileField.bloodType, const [
          'Unknown',
          'A+',
          'A-',
          'B+',
          'B-',
          'AB+',
          'AB-',
          'O+',
          'O-',
        ]),
        field(ProfileField.allergies),
        field(ProfileField.medications),
        field(ProfileField.conditions),
        const SectionTitle('Examination'),
        field(ProfileField.examinationPurpose),
        choice(ProfileField.examinationType, examinationTypes),
        field(ProfileField.performedBy),
        field(ProfileField.referredBy),
        const SectionTitle('Consent'),
        CheckboxListTile(
          key: const ValueKey('consent'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Consent to local profile storage'),
          value: draft.consentGranted,
          onChanged: (v) => setState(
            () => draft = draft.copyWith(consentGranted: v ?? false),
          ),
        ),
        const Text(
          'Prototype consent flag only. Formal consent records, revocation workflows, and clinical authorization are not implemented.',
        ),
        ValidationErrors(draft.errors()),
      ],
    ),
  );
}
