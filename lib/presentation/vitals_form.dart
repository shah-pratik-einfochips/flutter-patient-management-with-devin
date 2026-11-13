import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/patient_repository.dart';
import '../domain/patient.dart';
import 'components.dart';
import 'providers.dart';

class VitalsFormPage extends ConsumerStatefulWidget {
  const VitalsFormPage({super.key, required this.patient});
  final Patient patient;
  @override
  ConsumerState<VitalsFormPage> createState() => _VitalsFormPageState();
}

class _VitalsFormPageState extends ConsumerState<VitalsFormPage> {
  VitalDraft draft = VitalDraft();
  bool saving = false;

  Future<void> save() async {
    if (saving || draft.errors(widget.patient.birthDate).isNotEmpty) return;
    setState(() => saving = true);
    try {
      await ref
          .read(patientsProvider.notifier)
          .addReading(widget.patient.id, draft.reading());
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

  Widget unitPicker(
    String label,
    String value,
    List<String> options,
    VitalMetric metric,
    VitalDraft Function(String) update,
  ) => ChoiceField(
    label: label,
    value: value,
    options: options,
    onChanged: (value) => setState(() {
      final inputs = {...draft.inputs}..remove(metric);
      draft = update(value).copyWith(inputs: inputs);
    }),
  );

  @override
  Widget build(BuildContext context) {
    final reading = draft.reading();
    return PopScope(
      canPop: !saving,
      child: AppPage(
        title: 'Add vitals',
        actions: [
          TextButton(
            key: const ValueKey('saveVitals'),
            onPressed:
                saving || draft.errors(widget.patient.birthDate).isNotEmpty
                ? null
                : save,
            child: Text(saving ? 'Saving…' : 'Save'),
          ),
        ],
        children: [
          Text(widget.patient.name),
          OutlinedButton(
            key: const ValueKey('readingDate'),
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: dateOnly(draft.date),
                firstDate: widget.patient.birthDate ?? DateTime(1),
                lastDate: dateOnly(DateTime.now()),
              );
              if (date != null && mounted) {
                setState(
                  () => draft = draft.copyWith(
                    date: DateTime(
                      date.year,
                      date.month,
                      date.day,
                      draft.date.hour,
                      draft.date.minute,
                    ),
                  ),
                );
              }
            },
            child: Text('Reading date: ${isoDate(draft.date)}'),
          ),
          OutlinedButton(
            key: const ValueKey('readingTime'),
            onPressed: () async {
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(draft.date),
              );
              if (time != null && mounted) {
                setState(
                  () => draft = draft.copyWith(
                    date: DateTime(
                      draft.date.year,
                      draft.date.month,
                      draft.date.day,
                      time.hour,
                      time.minute,
                    ),
                  ),
                );
              }
            },
            child: Text(
              'Reading time: ${TimeOfDay.fromDateTime(draft.date).format(context)}',
            ),
          ),
          const Text(
            'Leave unmeasured vitals blank. Blood pressure requires both values.',
          ),
          for (final metric in VitalMetric.values) ...[
            TextFormField(
              key: ValueKey(
                '${metric.name}-${metric == VitalMetric.height
                    ? draft.heightUnit
                    : metric == VitalMetric.weight
                    ? draft.weightUnit
                    : metric == VitalMetric.temperature
                    ? draft.temperatureUnit
                    : metric.unit}',
              ),
              initialValue: draft.inputs[metric] ?? '',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText:
                    '${metric.label} (${metric == VitalMetric.height
                        ? draft.heightUnit == 'ft/in'
                              ? 'feet'
                              : 'cm'
                        : metric == VitalMetric.weight
                        ? draft.weightUnit
                        : metric == VitalMetric.temperature
                        ? '°${draft.temperatureUnit}'
                        : metric.unit})',
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(
                () => draft = draft.copyWith(
                  inputs: {...draft.inputs, metric: value},
                ),
              ),
            ),
            if (metric == VitalMetric.height) ...[
              unitPicker(
                'Height unit',
                draft.heightUnit,
                const ['cm', 'ft/in'],
                metric,
                (v) => draft.copyWith(heightUnit: v, inches: ''),
              ),
              if (draft.heightUnit == 'ft/in')
                TextFormField(
                  key: const ValueKey('inches'),
                  decoration: const InputDecoration(
                    labelText: 'Additional inches (0–11.99)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (v) =>
                      setState(() => draft = draft.copyWith(inches: v)),
                ),
            ],
            if (metric == VitalMetric.weight)
              unitPicker(
                'Weight unit',
                draft.weightUnit,
                const ['kg', 'lbs'],
                metric,
                (v) => draft.copyWith(weightUnit: v),
              ),
            if (metric == VitalMetric.temperature)
              unitPicker(
                'Temperature unit',
                draft.temperatureUnit,
                const ['C', 'F'],
                metric,
                (v) => draft.copyWith(temperatureUnit: v),
              ),
            if (reading.values[metric] != null &&
                metric.outsideReference(reading.values[metric]!))
              Text(
                'Warning: outside illustrative adult reference range.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
          if (reading.meanArterialPressure != null)
            Text(
              'Calculated MAP: ${formatValue(reading.meanArterialPressure!)} mmHg',
            ),
          TextFormField(
            decoration: const InputDecoration(
              labelText: 'Symptoms (optional)',
              border: OutlineInputBorder(),
            ),
            minLines: 1,
            maxLines: 4,
            onChanged: (v) =>
                setState(() => draft = draft.copyWith(symptoms: v)),
          ),
          const Text(
            'Reference ranges are illustrative only, not age-adjusted, and must not be used for diagnosis or treatment.',
          ),
          ValidationErrors(draft.errors(widget.patient.birthDate)),
        ],
      ),
    );
  }
}
