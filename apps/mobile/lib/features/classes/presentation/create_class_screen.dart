import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/theme/app_background.dart';
import '../domain/class_provider.dart';

/// Coach: publish a group class — either an online group call or an in-person
/// class. Writes to the `classes` table (RLS: coaches manage their own).
class CreateClassScreen extends ConsumerStatefulWidget {
  const CreateClassScreen({super.key});

  @override
  ConsumerState<CreateClassScreen> createState() => _CreateClassScreenState();
}

class _CreateClassScreenState extends ConsumerState<CreateClassScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _location = TextEditingController();
  final _link = TextEditingController();
  final _price = TextEditingController();

  String _type = 'hiit';
  bool _isOnline = false;
  bool _paid = false;
  int _duration = 60;
  int _capacity = 20;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);
  bool _saving = false;

  static const _types = ['hiit', 'strength', 'yoga', 'cardio', 'pilates', 'dance', 'boxing', 'meditation'];

  @override
  void dispose() {
    _title.dispose(); _desc.dispose(); _location.dispose(); _link.dispose(); _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a class title'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _saving = true);
    final when = DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
    try {
      await ref.read(liveClassServiceProvider).createClass(
        title: _title.text.trim(),
        description: _desc.text.trim(),
        type: _type,
        scheduledAt: when,
        durationMinutes: _duration,
        isOnline: _isOnline,
        location: _location.text.trim().isEmpty ? null : _location.text.trim(),
        meetingLink: _link.text.trim().isEmpty ? null : _link.text.trim(),
        maxCapacity: _capacity,
        price: _paid ? double.tryParse(_price.text.trim()) : null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create class.'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent, elevation: 0,
          iconTheme: const IconThemeData(color: AppColors.white),
          title: const Text('New Class',
              style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            _field('Title', _title, hint: 'e.g. Morning Yoga Flow'),
            _field('Description', _desc, hint: 'What to expect, what to bring…', maxLines: 3),
            _label('Category'),
            Wrap(spacing: 8, runSpacing: 8, children: _types.map((t) {
              final on = _type == t;
              return GestureDetector(
                onTap: () => setState(() => _type = t),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: on ? AppColors.purple.withValues(alpha: 0.2) : AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: on ? AppColors.purple : AppColors.surfaceDarkElevated)),
                  child: Text(t[0].toUpperCase() + t.substring(1),
                      style: TextStyle(color: on ? AppColors.purple : AppColors.textSecondary, fontSize: 12)),
                ),
              );
            }).toList()),
            const SizedBox(height: 16),
            // Online vs in-person
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceDarkElevated)),
              child: Row(children: [
                const Icon(Icons.videocam_outlined, color: Color(0xFF60A5FA), size: 20),
                const SizedBox(width: 10),
                const Expanded(child: Text('Online group call',
                    style: TextStyle(color: AppColors.white, fontSize: 14))),
                Switch(value: _isOnline, activeThumbColor: AppColors.purple,
                    onChanged: (v) => setState(() => _isOnline = v)),
              ]),
            ),
            const SizedBox(height: 4),
            Text(_isOnline
                ? 'Unlimited spots. The link is shown only to registered members.'
                : 'Limited seats. Members see the address and spots left.',
                style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
            const SizedBox(height: 12),
            if (_isOnline)
              _field('Meeting link', _link, hint: 'https://zoom.us/j/…')
            else ...[
              _field('Location / address', _location, hint: 'e.g. Studio A · 120 Market St'),
              _label('Capacity (seats)'),
              _stepper(_capacity, (v) => setState(() => _capacity = v), min: 1, step: 1),
            ],
            _label('Date'),
            _pickerTile(Icons.calendar_today_outlined,
                '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                () async {
              final d = await showDatePicker(context: context, initialDate: _date,
                  firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
              if (d != null && mounted) setState(() => _date = d);
            }),
            _label('Start time'),
            _pickerTile(Icons.schedule_rounded, _time.format(context), () async {
              final t = await showTimePicker(context: context, initialTime: _time);
              if (t != null && mounted) setState(() => _time = t);
            }),
            _label('Duration (minutes)'),
            _stepper(_duration, (v) => setState(() => _duration = v), min: 15, step: 15),
            const SizedBox(height: 16),
            // Free vs paid
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceDarkElevated)),
              child: Row(children: [
                const Icon(Icons.attach_money_rounded, color: AppColors.success, size: 20),
                const SizedBox(width: 10),
                const Expanded(child: Text('Charge for this class',
                    style: TextStyle(color: AppColors.white, fontSize: 14))),
                Switch(value: _paid, activeThumbColor: AppColors.purple,
                    onChanged: (v) => setState(() => _paid = v)),
              ]),
            ),
            const SizedBox(height: 4),
            Text(_paid ? 'Members pay to register.' : 'This class is free to join.',
                style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
            if (_paid) _field('Price (USD)', _price, hint: 'e.g. 25', number: true),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.purple, foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Publish Class', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            )),
          ],
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(t, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)));

  Widget _field(String label, TextEditingController c, {String? hint, int maxLines = 1, bool number = false}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(label),
      TextField(
        controller: c, maxLines: maxLines,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        style: const TextStyle(color: AppColors.white),
        decoration: InputDecoration(
          hintText: hint, hintStyle: const TextStyle(color: AppColors.textTertiary),
          filled: true, fillColor: AppColors.surfaceDark,
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.surfaceDarkElevated)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.purple))),
      ),
    ]);

  Widget _pickerTile(IconData icon, String value, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceDark, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceDarkElevated)),
      child: Row(children: [
        Icon(icon, color: AppColors.purple, size: 18),
        const SizedBox(width: 10),
        Text(value, style: const TextStyle(color: AppColors.white, fontSize: 14)),
      ]),
    ),
  );

  Widget _stepper(int value, ValueChanged<int> onChanged, {required int min, required int step}) => Row(children: [
    _stepBtn(Icons.remove, () { if (value - step >= min) onChanged(value - step); }),
    Container(width: 64, alignment: Alignment.center,
        child: Text('$value', style: const TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700))),
    _stepBtn(Icons.add, () => onChanged(value + step)),
  ]);

  Widget _stepBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(color: AppColors.surfaceDark, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.surfaceDarkElevated)),
      child: Icon(icon, color: AppColors.purple, size: 20),
    ),
  );
}
