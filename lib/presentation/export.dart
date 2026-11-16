import 'dart:io';
import 'dart:ui' show Rect;

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/patient.dart';

String patientCsv(Patient patient) {
  String quote(String text) => '"${text.replaceAll('"', '""')}"';
  String fmt(double value) => value == value.truncateToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
  final lines = <String>[
    'name,medical_id,date_of_birth,gender,examination_type',
    [
      patient.name,
      patient.medicalId,
      patient.birthDate == null ? '' : isoDate(patient.birthDate!),
      patient.value(ProfileField.gender),
      patient.value(ProfileField.examinationType),
    ].map(quote).join(','),
    '',
    'reading_date,metric,value,unit,outside_illustrative_range,map,symptoms',
  ];
  final vitals = [...patient.vitals]..sort((a, b) => a.date.compareTo(b.date));
  for (final reading in vitals) {
    final metrics = VitalMetric.values
        .where((m) => reading.values.containsKey(m))
        .toList();
    final rows = metrics.isEmpty ? const <VitalMetric?>[null] : metrics;
    for (var i = 0; i < rows.length; i++) {
      final metric = rows[i];
      final value = metric == null ? null : reading.values[metric];
      lines.add(
        [
          DateFormat('yyyy-MM-dd HH:mm').format(reading.date),
          metric?.label ?? '',
          value == null ? '' : fmt(value),
          metric?.unit ?? '',
          metric != null && value != null && metric.outsideReference(value)
              ? 'yes'
              : '',
          i == 0 && reading.meanArterialPressure != null
              ? fmt(reading.meanArterialPressure!)
              : '',
          i == 0 ? quote(reading.symptoms) : '',
        ].join(','),
      );
    }
  }
  return '${lines.join('\n')}\n';
}

Future<File> exportCsv(Patient patient) {
  final file = File(
    '${Directory.systemTemp.path}/patient-${_fileName(patient)}.csv',
  );
  return file.writeAsString(patientCsv(patient));
}

Future<File> exportPdf(Patient patient) async {
  pw.Widget text(String content, {bool bold = false}) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Text(
      content,
      style: bold
          ? pw.TextStyle(fontWeight: pw.FontWeight.bold)
          : const pw.TextStyle(fontSize: 11),
    ),
  );
  final vitals = [...patient.vitals]..sort((a, b) => a.date.compareTo(b.date));
  final document = pw.Document();
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      build: (context) => [
        text('${patient.name} (${patient.medicalId})', bold: true),
        pw.SizedBox(height: 6),
        text(
          'Date of birth: ${patient.birthDate == null ? 'Not recorded' : isoDate(patient.birthDate!)}',
        ),
        text('Gender: ${patient.value(ProfileField.gender)}'),
        text('Blood type: ${patient.value(ProfileField.bloodType)}'),
        for (final field in [
          ProfileField.examinationType,
          ProfileField.allergies,
          ProfileField.medications,
          ProfileField.conditions,
        ])
          if (patient.value(field).isNotEmpty)
            text('${field.label}: ${patient.value(field)}'),
        pw.SizedBox(height: 12),
        text('Vitals readings (${patient.vitals.length})', bold: true),
        text(
          'All entries are synthetic prototype data. Reference ranges are illustrative adult values.',
        ),
        for (final reading in vitals) ...[
          pw.SizedBox(height: 8),
          text(DateFormat.yMMMd().add_Hm().format(reading.date), bold: true),
          for (final metric in VitalMetric.values)
            if (reading.values[metric] != null)
              text(
                '  ${metric.label}: ${reading.values[metric]!.toStringAsFixed(1)} ${metric.unit}${metric.outsideReference(reading.values[metric]!) ? ' (outside illustrative range)' : ''}',
              ),
          if (reading.meanArterialPressure != null)
            text(
              '  MAP: ${reading.meanArterialPressure!.toStringAsFixed(1)} mmHg',
            ),
          if (reading.symptoms.isNotEmpty)
            text('  Symptoms: ${reading.symptoms}'),
        ],
      ],
    ),
  );
  final file = File(
    '${Directory.systemTemp.path}/patient-${_fileName(patient)}.pdf',
  );
  await file.writeAsBytes(await document.save());
  return file;
}

String _fileName(Patient patient) {
  final base = patient.medicalId.isEmpty ? patient.id : patient.medicalId;
  return base.substring(0, base.length.clamp(0, 24));
}

Future<void> shareExport(Patient patient, {required bool pdf, Rect? origin}) {
  final future = pdf ? exportPdf(patient) : exportCsv(patient);
  return future.then(
    (file) => SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        sharePositionOrigin: origin,
      ),
    ),
  );
}
