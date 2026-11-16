import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../domain/patient.dart';
import 'components.dart';
import 'export.dart';
import 'providers.dart';

class PatientDetailPage extends ConsumerStatefulWidget {
  const PatientDetailPage({super.key, required this.patient});
  final Patient patient;
  @override
  ConsumerState<PatientDetailPage> createState() => _PatientDetailPageState();
}

class _PatientDetailPageState extends ConsumerState<PatientDetailPage> {
  VitalMetric metric = VitalMetric.heartRate;
  bool chart = true;
  String? selectedId;

  Future<void> _export(bool pdf) async {
    final origin = context.findRenderObject() is RenderBox
        ? (context.findRenderObject()! as RenderBox).paintBounds
        : null;
    try {
      await shareExport(widget.patient, pdf: pdf, origin: origin);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The export could not be created. Please retry.'),
          ),
        );
      }
    }
  }

  Future<void> _deletePatient() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete patient'),
        content: Text(
          'Delete ${widget.patient.name} and all recorded vitals? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(patientsProvider.notifier)
          .deletePatient(widget.patient.id);
      if (mounted) context.go('/');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to delete. Please retry.')),
        );
      }
    }
  }

  Future<void> _deleteReading(String readingId) async {
    try {
      await ref
          .read(patientsProvider.notifier)
          .removeReading(widget.patient.id, readingId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to delete. Please retry.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final patient = widget.patient;
    final measured = recentReadings(patient.vitals)
        .where((r) => r.values[metric] != null)
        .toList();
    final values = measured.map((r) => r.values[metric]!).toList();
    final selected = measured.where((r) => r.id == selectedId).firstOrNull;
    return AppPage(
      title: patient.name,
      actions: [
        TextButton(
          onPressed: () => context.push('/patient/${patient.id}/edit'),
          child: const Text('Edit'),
        ),
      ],
      children: [
        const SectionTitle('Patient profile'),
        Text('Medical ID: ${patient.medicalId}'),
        Text(
          'Date of birth: ${patient.birthDate == null ? 'Not recorded' : DateFormat.yMMMd().format(patient.birthDate!)}',
        ),
        for (final field in [
          ProfileField.bloodType,
          ProfileField.allergies,
          ProfileField.medications,
          ProfileField.conditions,
          ProfileField.examinationType,
          ProfileField.examinationPurpose,
          ProfileField.performedBy,
          ProfileField.referredBy,
        ])
          if (patient.value(field).isNotEmpty)
            Text('${field.label}: ${patient.value(field)}'),
        FilledButton.icon(
          onPressed: () => context.push('/patient/${patient.id}/vitals'),
          icon: const Icon(Icons.add),
          label: const Text('Add vitals'),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => _export(false),
              child: const Text('Export CSV'),
            ),
            TextButton(
              onPressed: () => _export(true),
              child: const Text('Export PDF'),
            ),
            TextButton(
              onPressed: _deletePatient,
              child: Text(
                'Delete patient',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
        const SectionTitle('Last seven days'),
        ChoiceField(
          label: 'Vital type',
          value: metric.label,
          options: VitalMetric.values.map((m) => m.label).toList(),
          onChanged: (v) => setState(() {
            metric = VitalMetric.values.firstWhere((m) => m.label == v);
            selectedId = null;
          }),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Chart view'),
          value: chart,
          onChanged: (v) => setState(() => chart = v),
        ),
        if (values.isEmpty)
          Text(
            'No ${metric.label.toLowerCase()} readings in the last seven days.',
          )
        else ...[
          if (chart) ...[
            Semantics(
              label:
                  '${metric.label} trend, ${measured.length} readings in ${metric.unit}. Individual values are listed below.',
              child: SizedBox(height: 240, child: _chart(context, measured)),
            ),
            const Text('Tap a point to inspect its value.'),
            if (selected != null)
              Text(
                'Selected: ${formatDate(selected.date)} · ${formatValue(selected.values[metric]!)} ${metric.unit}',
              ),
          ],
          Text(
            'Average: ${formatValue(values.reduce((a, b) => a + b) / values.length)} ${metric.unit}',
          ),
          Text(
            'Minimum / maximum: ${formatValue(values.reduce((a, b) => a < b ? a : b))} / ${formatValue(values.reduce((a, b) => a > b ? a : b))} ${metric.unit}',
          ),
          for (final reading in measured.reversed)
            Card(
              child: ListTile(
                title: Text(formatDate(reading.date)),
                subtitle: Text(
                  '${formatValue(reading.values[metric]!)} ${metric.unit}${metric.outsideReference(reading.values[metric]!) ? '\nWarning: outside illustrative adult range' : ''}',
                ),
              ),
            ),
        ],
        const Text(
          'Illustrative adult reference ranges only. Not clinical decision support.',
        ),
        const SectionTitle('All readings'),
        if (patient.vitals.isEmpty) const Text('No vitals recorded yet.'),
        for (final reading in [
          ...patient.vitals,
        ]..sort((a, b) => b.date.compareTo(a.date)))
          Card(
            child: ExpansionTile(
              title: Text(formatDate(reading.date)),
              childrenPadding: const EdgeInsets.all(16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final metric in VitalMetric.values)
                  if (reading.values[metric] != null)
                    Text(
                      '${metric.label}: ${formatValue(reading.values[metric]!)} ${metric.unit}${metric.outsideReference(reading.values[metric]!) ? ' — outside illustrative range' : ''}',
                    ),
                if (reading.meanArterialPressure != null)
                  Text(
                    'MAP: ${formatValue(reading.meanArterialPressure!)} mmHg',
                  ),
                if (reading.symptoms.isNotEmpty)
                  Text('Symptoms: ${reading.symptoms}'),
                TextButton(
                  onPressed: () => _deleteReading(reading.id),
                  child: Text(
                    'Delete reading',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _chart(BuildContext context, List<VitalReading> measured) {
    final primary = Theme.of(context).colorScheme.primary;
    final warning = Theme.of(context).colorScheme.error;
    final spots = measured
        .map(
          (r) => FlSpot(
            r.date.millisecondsSinceEpoch.toDouble(),
            r.values[metric]!,
          ),
        )
        .toList();
    final first = spots.first.x, last = spots.last.x;
    return LineChart(
      LineChartData(
        minX: first == last ? first - 60000 : first,
        maxX: first == last ? last + 60000 : last,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: primary,
            barWidth: 2,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) =>
                  metric.outsideReference(spot.y)
                  ? _DiamondDotPainter(radius: 5, color: warning)
                  : FlDotCirclePainter(
                      radius: 4,
                      color: primary,
                      strokeWidth: 0,
                    ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchCallback: (event, response) {
            if (event.isInterestedForInteractions &&
                response?.lineBarSpots?.isNotEmpty == true) {
              setState(
                () => selectedId =
                    measured[response!.lineBarSpots!.first.spotIndex].id,
              );
            }
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) => touched
                .map(
                  (spot) => LineTooltipItem(
                    '${formatValue(spot.y)} ${metric.unit}',
                    const TextStyle(color: Colors.white),
                  ),
                )
                .toList(),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            axisNameWidget: Text(metric.unit),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                formatValue(value),
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: last == first
                  ? 60000
                  : ((last - first) / 2).clamp(60000, double.infinity),
              getTitlesWidget: (value, meta) => Text(
                DateFormat('MM/dd\nHH:mm')
                    .format(DateTime.fromMillisecondsSinceEpoch(value.toInt())),
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
      ),
    );
  }
}

class _DiamondDotPainter extends FlDotPainter {
  const _DiamondDotPainter({required this.radius, required this.color});
  final double radius;
  final Color color;

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    canvas
      ..save()
      ..translate(offsetInCanvas.dx, offsetInCanvas.dy)
      ..rotate(math.pi / 4)
      ..drawRect(
        Rect.fromCenter(center: Offset.zero, width: radius * 2, height: radius * 2),
        Paint()..color = color,
      )
      ..restore();
  }

  @override
  Size getSize(FlSpot spot) => Size.fromRadius(radius);

  @override
  Color get mainColor => color;

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) => this;

  @override
  List<Object?> get props => [radius, color];
}
