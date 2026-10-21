import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/action_item_provider.dart';

/// Coach: assign an action item to a client. Returns true if assigned.
Future<bool> showAssignActionItemSheet(
    BuildContext context, WidgetRef ref, String clientId) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AssignSheet(clientId: clientId, ref: ref),
  );
  return result ?? false;
}

class _AssignSheet extends StatefulWidget {
  final String clientId;
  final WidgetRef ref;
  const _AssignSheet({required this.clientId, required this.ref});

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  String _category = 'daily';
  DateTime? _due;
  bool _saving = false;

  static const _categories = [
    ('daily', '📋 Daily'),
    ('weekly', '🗓️ Weekly'),
    ('nutrition', '🥗 Nutrition'),
    ('workout', '💪 Workout'),
    ('accountability', '🤝 Accountability'),
  ];

  // One-tap templates the coach can drop in (title, category).
  static const _quickPicks = [
    ('Upload Progress Photos', 'weekly', '📸'),
    ('Log all meals today', 'nutrition', '🍽️'),
    ('Complete today\'s workout', 'workout', '💪'),
    ('Hit your protein goal', 'nutrition', '🥩'),
    ('Submit weekly check-in', 'accountability', '✅'),
    ('Get 8 hours of sleep', 'daily', '😴'),
  ];

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final ok = await widget.ref.read(actionItemServiceProvider).assignActionItem(
          clientId: widget.clientId,
          title: _title.text.trim(),
          description: _desc.text.trim(),
          category: _category,
          dueDate: _due, // points are awarded automatically by the scoring engine

        );
    if (!mounted) return;
    if (ok) {
      widget.ref.invalidate(clientActionItemsProvider(widget.clientId));
      widget.ref.invalidate(actionCompletionProvider(widget.clientId));
      Navigator.pop(context, true);
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not assign — please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      decoration: const BoxDecoration(
        color: AppColors.bgDarkSecondary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: AppColors.surfaceDarkElevated,
                borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 18),
        const Text('Assign Action Item',
            style: TextStyle(
                color: AppColors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),
        const Text('Quick add',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: _quickPicks.map((q) {
          return GestureDetector(
            onTap: () => setState(() { _title.text = q.$1; _category = q.$2; }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _title.text == q.$1 ? AppColors.purple : AppColors.surfaceDarkElevated)),
              child: Text('${q.$3} ${q.$1}',
                  style: const TextStyle(color: AppColors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          );
        }).toList()),
        const SizedBox(height: 16),
        _field(_title, 'Title (e.g. Hit 140g protein today)', autofocus: true),
        const SizedBox(height: 12),
        _field(_desc, 'Details (optional)', maxLines: 2),
        const SizedBox(height: 16),
        const Text('Category',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _categories.map((c) {
            final sel = _category == c.$1;
            return GestureDetector(
              onTap: () => setState(() => _category = c.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? AppColors.purple : AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: sel ? AppColors.purple : AppColors.surfaceDarkElevated),
                ),
                child: Text(c.$2,
                    style: TextStyle(
                        color: sel ? Colors.white : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                    color: AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.surfaceDarkElevated)),
                child: Row(children: [
                  const Icon(Icons.event, color: AppColors.purple, size: 18),
                  const SizedBox(width: 10),
                  Text(
                      _due == null
                          ? 'Due date (optional)'
                          : '${_due!.month}/${_due!.day}/${_due!.year}',
                      style: TextStyle(
                          color: _due == null
                              ? AppColors.textTertiary
                              : AppColors.white,
                          fontSize: 13)),
                ]),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Assign Action Item'),
          ),
        ),
      ]),
    );
  }

  Widget _field(TextEditingController c, String hint,
          {int maxLines = 1, bool autofocus = false}) =>
      TextField(
        controller: c,
        maxLines: maxLines,
        autofocus: autofocus,
        style: const TextStyle(color: AppColors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
          filled: true,
          fillColor: AppColors.surfaceDark,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _due = picked);
  }
}
