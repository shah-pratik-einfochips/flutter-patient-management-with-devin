import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
  });
  final String title;
  final List<Widget> children, actions;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final child in children)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: child,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Text(
    title,
    style: Theme.of(context).textTheme.titleMedium
        ?.copyWith(color: Theme.of(context).colorScheme.primary),
  );
}

class ChoiceField extends StatelessWidget {
  const ChoiceField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label, value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value.isEmpty ? null : value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    hint: const Text('Select an option'),
    items: options
        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
        .toList(),
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
  );
}

class PrototypeNotice extends StatelessWidget {
  const PrototypeNotice({super.key});
  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Local prototype · synthetic data only',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Not connected to a clinical backend. Reference ranges are illustrative adult values, not medical advice.',
          ),
        ],
      ),
    ),
  );
}

class ValidationErrors extends StatelessWidget {
  const ValidationErrors(this.errors, {super.key});
  final List<String> errors;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (errors.isNotEmpty) const SectionTitle('Before saving'),
      for (final error in errors)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );
}

String formatValue(double value) => NumberFormat('0.0').format(value);
String formatDate(DateTime value) => DateFormat.yMMMd().add_jm().format(value);

Future<void> showSaveError(BuildContext context, String message) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unable to save'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
