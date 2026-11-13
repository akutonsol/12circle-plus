import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/coach_note_service.dart';
import '../domain/coach_note_provider.dart';

/// Coach: private notes about a client (Module 29). Opens a bottom sheet with
/// the existing notes and an inline composer.
Future<void> showCoachNotesSheet(
    BuildContext context, WidgetRef ref, String clientId, String clientName) {
  // Read on each opening. The family outlives the sheet, so a failed read
  // would otherwise be shown again every time it is opened.
  ref.invalidate(clientNotesProvider(clientId));
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NotesSheet(clientId: clientId, clientName: clientName),
  );
}

class _NotesSheet extends ConsumerStatefulWidget {
  final String clientId;
  final String clientName;
  const _NotesSheet({required this.clientId, required this.clientName});
  @override
  ConsumerState<_NotesSheet> createState() => _NotesSheetState();
}

class _NotesSheetState extends ConsumerState<_NotesSheet> {
  final _ctrl = TextEditingController();
  String _tag = 'general';
  bool _saving = false;

  static const _tags = [
    ('general', '📝'),
    ('injury', '🩹'),
    ('motivation', '🔥'),
    ('adherence', '📊'),
    ('program', '🏋️'),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final saved = await ref
        .read(coachNoteServiceProvider)
        .addNote(widget.clientId, _ctrl.text.trim(), tag: _tag);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!saved) {
      // Keep what the coach typed: clearing it on a failed save lost the note
      // with nothing to say it was never kept.
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save note. Try again.')));
      return;
    }
    _ctrl.clear();
    ref.invalidate(clientNotesProvider(widget.clientId));
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(clientNotesProvider(widget.clientId));
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12),
      decoration: const BoxDecoration(
        color: AppColors.bgDarkSecondary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        Center(
          child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: AppColors.surfaceDarkElevated,
                borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          const Icon(Icons.lock_outline, color: AppColors.purple, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Private Notes · ${widget.clientName}',
                style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 4),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Only you can see these — never the client.',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: notesAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.purple)),
            error: (_, __) => const Center(
                child: Text('Could not load notes',
                    style: TextStyle(color: AppColors.textTertiary))),
            data: (notes) => notes.isEmpty
                ? const Center(
                    child: Text('No notes yet. Add your first below.',
                        style: TextStyle(color: AppColors.textTertiary, fontSize: 13)))
                : ListView.builder(
                    itemCount: notes.length,
                    itemBuilder: (_, i) => _NoteTile(
                        note: notes[i],
                        onDelete: () async {
                          await ref
                              .read(coachNoteServiceProvider)
                              .deleteNote(notes[i].id);
                          ref.invalidate(clientNotesProvider(widget.clientId));
                        }),
                  ),
          ),
        ),
        // ── Composer ──
        Wrap(
          spacing: 6,
          children: _tags.map((tg) {
            final sel = _tag == tg.$1;
            return GestureDetector(
              onTap: () => setState(() => _tag = tg.$1),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: sel ? AppColors.purple : AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text('${tg.$2} ${tg.$1}',
                    style: TextStyle(
                        color: sel ? Colors.white : AppColors.textSecondary,
                        fontSize: 11)),
              ),
            );
          }).toList(),
        ),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(color: AppColors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Add a private note…',
                hintStyle:
                    const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                filled: true,
                fillColor: AppColors.surfaceDark,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _saving ? null : _add,
            child: Container(
              width: 44, height: 44,
              decoration: const BoxDecoration(
                  color: AppColors.purple, shape: BoxShape.circle),
              child: _saving
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _NoteTile extends StatelessWidget {
  final CoachNote note;
  final VoidCallback onDelete;
  const _NoteTile({required this.note, required this.onDelete});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceDarkElevated),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(note.emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(note.body,
                  style: const TextStyle(color: AppColors.white, fontSize: 13, height: 1.4)),
              const SizedBox(height: 4),
              Text(
                  '${note.tag} · ${note.createdAt.month}/${note.createdAt.day}/${note.createdAt.year}',
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
            ]),
          ),
          GestureDetector(
            onTap: onDelete,
            child: const Icon(Icons.close, color: AppColors.textTertiary, size: 16),
          ),
        ]),
      );
}
