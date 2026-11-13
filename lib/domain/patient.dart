import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

const examinationTypes = [
  'Routine checkup',
  'Emergency',
  'Follow-up',
  'Consultation',
  'Diagnostic',
  'Preventive',
];

enum ProfileField {
  firstName('First name'),
  lastName('Last name'),
  medicalId('Medical ID'),
  gender('Administrative gender'),
  ethnicity('Ethnicity (optional)'),
  phone('Phone'),
  email('Email'),
  bloodType('Blood type'),
  allergies('Allergies'),
  medications('Medications'),
  conditions('Health conditions'),
  examinationPurpose('Purpose of examination'),
  examinationType('Type of examination'),
  performedBy('Performed by'),
  referredBy('Referred by');

  const ProfileField(this.label);
  final String label;
}

class Patient {
  Patient({
    String? id,
    Map<ProfileField, String> fields = const {},
    this.birthDate,
    this.consentGranted = false,
    List<VitalReading> vitals = const [],
  }) : id = id ?? const Uuid().v4(),
       fields = Map.unmodifiable(fields),
       vitals = List.unmodifiable(vitals);

  final String id;
  final Map<ProfileField, String> fields;
  final DateTime? birthDate;
  final bool consentGranted;
  final List<VitalReading> vitals;
  String value(ProfileField field) =>
      fields[field] ??
      switch (field) {
        ProfileField.gender => 'unknown',
        ProfileField.bloodType => 'Unknown',
        _ => '',
      };
  String get name =>
      '${value(ProfileField.firstName)} ${value(ProfileField.lastName)}'.trim();
  String get medicalId => value(ProfileField.medicalId).trim();
  String get normalizedMedicalId => medicalId.toLowerCase();

  Patient withField(ProfileField field, String value) =>
      copyWith(fields: {...fields, field: value});
  Patient copyWith({
    Map<ProfileField, String>? fields,
    DateTime? birthDate,
    bool? consentGranted,
    List<VitalReading>? vitals,
  }) => Patient(
    id: id,
    fields: fields ?? this.fields,
    birthDate: birthDate ?? this.birthDate,
    consentGranted: consentGranted ?? this.consentGranted,
    vitals: vitals ?? this.vitals,
  );

  List<String> errors({DateTime? now}) {
    final today = dateOnly(now ?? DateTime.now());
    return [
      for (final field in [
        ProfileField.firstName,
        ProfileField.lastName,
        ProfileField.medicalId,
      ])
        if (value(field).trim().isEmpty) '${field.label} is required.',
      if (birthDate == null)
        'Select a date of birth.'
      else if (dateOnly(birthDate!).isAfter(today))
        'Date of birth cannot be in the future.',
      if (value(ProfileField.email).trim().isNotEmpty &&
          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
              .hasMatch(value(ProfileField.email)))
        'Enter a valid email address.',
      if (!consentGranted)
        'Consent is required for local profile storage in this prototype.',
      if (value(ProfileField.examinationType).trim().isNotEmpty &&
          !examinationTypes.contains(value(ProfileField.examinationType)))
        'Select a listed examination type.',
    ];
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'fields': fields.map((k, v) => MapEntry(k.name, v)),
    'birthDate': birthDate == null ? null : isoDate(birthDate!),
    'consentGranted': consentGranted,
    'vitals': vitals.map((v) => v.toJson()).toList(),
  };
  factory Patient.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported patient schema');
    }
    final rawDate = json['birthDate'] as String?;
    final birth = rawDate == null ? null : parseDate(rawDate);
    if (rawDate != null && birth == null) {
      throw const FormatException('Invalid date of birth');
    }
    return Patient(
      id: json['id'] as String,
      fields: (json['fields'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(ProfileField.values.byName(k), v as String),
      ),
      birthDate: birth,
      consentGranted: json['consentGranted'] as bool,
      vitals: (json['vitals'] as List<dynamic>)
          .map((v) => VitalReading.fromJson(v as Map<String, dynamic>))
          .toList(),
    );
  }
}

DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
DateTime? parseDate(String text) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return null;
  final date = DateTime.tryParse(text);
  return date != null && isoDate(date) == text ? dateOnly(date) : null;
}

enum VitalMetric {
  systolic('Systolic blood pressure', 'mmHg', 20, 350, 90, 119),
  diastolic('Diastolic blood pressure', 'mmHg', 10, 250, 60, 79),
  heartRate('Heart rate', 'bpm', 10, 350, 60, 100),
  height('Height', 'cm', 20, 300),
  weight('Weight', 'kg', 0.1, 700),
  temperature('Temperature', '°C', 25, 45, 36.1, 37.2),
  respiratoryRate('Respiratory rate', 'breaths/min', 1, 100, 12, 20),
  oxygen('SpO2', '%', 1, 100, 95, 100),
  pain('Pain level', '/10', 0, 10, 0, 3);

  const VitalMetric(
    this.label,
    this.unit,
    this.minimum,
    this.maximum, [
    this.referenceMin,
    this.referenceMax,
  ]);
  final String label, unit;
  final double minimum, maximum;
  final double? referenceMin, referenceMax;
  bool outsideReference(double value) =>
      referenceMin != null && (value < referenceMin! || value > referenceMax!);
}

class VitalReading {
  VitalReading({
    String? id,
    DateTime? date,
    Map<VitalMetric, double> values = const {},
    this.symptoms = '',
  }) : id = id ?? const Uuid().v4(),
       date = date ?? DateTime.now(),
       values = Map.unmodifiable(values);
  final String id, symptoms;
  final DateTime date;
  final Map<VitalMetric, double> values;
  double? get meanArterialPressure {
    final systolic = values[VitalMetric.systolic],
        diastolic = values[VitalMetric.diastolic];
    return systolic == null || diastolic == null
        ? null
        : (systolic + 2 * diastolic) / 3;
  }

  List<String> errors({DateTime? birthDate, DateTime? now}) => [
    if (date.isAfter(now ?? DateTime.now()))
      'Reading date cannot be in the future.',
    if (birthDate == null || date.isBefore(dateOnly(birthDate)))
      'Reading date cannot precede date of birth.',
    if (values.isEmpty) 'Enter at least one vital sign.',
    for (final entry in values.entries)
      if (!entry.value.isFinite ||
          entry.value < entry.key.minimum ||
          entry.value > entry.key.maximum)
        '${entry.key.label} must be within ${entry.key.minimum}–${entry.key.maximum} ${entry.key.unit}.',
    if (values.containsKey(VitalMetric.systolic) !=
        values.containsKey(VitalMetric.diastolic))
      'Enter both systolic and diastolic pressure.',
    if (values[VitalMetric.systolic] != null &&
        values[VitalMetric.diastolic] != null &&
        values[VitalMetric.systolic]! <= values[VitalMetric.diastolic]!)
      'Systolic pressure must exceed diastolic pressure.',
  ];
  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toUtc().toIso8601String(),
    'values': values.map((k, v) => MapEntry(k.name, v)),
    'symptoms': symptoms,
  };
  factory VitalReading.fromJson(Map<String, dynamic> json) => VitalReading(
    id: json['id'] as String,
    date: DateTime.parse(json['date'] as String).toLocal(),
    symptoms: json['symptoms'] as String,
    values: (json['values'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(VitalMetric.values.byName(k), (v as num).toDouble()),
    ),
  );
}

List<VitalReading> recentReadings(
  List<VitalReading> readings, {
  DateTime? now,
}) {
  final end = now ?? DateTime.now();
  final start = DateTime(end.year, end.month, end.day - 6);
  return readings
      .where((r) => !r.date.isBefore(start) && !r.date.isAfter(end))
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));
}

double? decimalInput(String text, {String? decimalSeparator}) {
  final separator =
      decimalSeparator ?? NumberFormat.decimalPattern().symbols.DECIMAL_SEP;
  final normalized = text.trim().replaceAll(separator, '.');
  if (!RegExp(r'^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$')
      .hasMatch(normalized)) {
    return null;
  }
  final value = double.tryParse(normalized);
  return value != null && value.isFinite ? value : null;
}

class UnitConversion {
  static double kilograms(double pounds) => pounds * 0.45359237;
  static double centimeters(double feet, double inches) =>
      (feet * 12 + inches) * 2.54;
  static double celsius(double fahrenheit) => (fahrenheit - 32) * 5 / 9;
}

class VitalDraft {
  VitalDraft({
    DateTime? date,
    Map<VitalMetric, String> inputs = const {},
    this.heightUnit = 'cm',
    this.weightUnit = 'kg',
    this.temperatureUnit = 'C',
    this.inches = '',
    this.symptoms = '',
  }) : date = date ?? DateTime.now(),
       inputs = Map.unmodifiable(inputs);
  final DateTime date;
  final Map<VitalMetric, String> inputs;
  final String heightUnit, weightUnit, temperatureUnit, inches, symptoms;
  VitalDraft copyWith({
    DateTime? date,
    Map<VitalMetric, String>? inputs,
    String? heightUnit,
    String? weightUnit,
    String? temperatureUnit,
    String? inches,
    String? symptoms,
  }) => VitalDraft(
    date: date ?? this.date,
    inputs: inputs ?? this.inputs,
    heightUnit: heightUnit ?? this.heightUnit,
    weightUnit: weightUnit ?? this.weightUnit,
    temperatureUnit: temperatureUnit ?? this.temperatureUnit,
    inches: inches ?? this.inches,
    symptoms: symptoms ?? this.symptoms,
  );
  VitalReading reading() {
    final values = <VitalMetric, double>{};
    for (final entry in inputs.entries) {
      final value = decimalInput(entry.value);
      if (value == null) continue;
      values[entry.key] = switch (entry.key) {
        VitalMetric.height when heightUnit == 'ft/in' =>
          UnitConversion.centimeters(value, decimalInput(inches) ?? 0),
        VitalMetric.weight when weightUnit == 'lbs' => UnitConversion.kilograms(
          value,
        ),
        VitalMetric.temperature when temperatureUnit == 'F' =>
          UnitConversion.celsius(value),
        _ => value,
      };
    }
    return VitalReading(date: date, values: values, symptoms: symptoms);
  }

  List<String> errors(DateTime? birthDate, {DateTime? now}) => [
    ...reading().errors(birthDate: birthDate, now: now),
    for (final entry in inputs.entries)
      if (entry.value.isNotEmpty && decimalInput(entry.value) == null)
        'Enter a valid number for ${entry.key.label}.',
    if (heightUnit == 'ft/in' &&
        inches.isNotEmpty &&
        (decimalInput(inches) == null ||
            decimalInput(inches)! < 0 ||
            decimalInput(inches)! >= 12 ||
            decimalInput(inputs[VitalMetric.height] ?? '') == null))
      'Enter feet with inches from 0 to less than 12.',
  ];
}
