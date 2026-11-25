import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../dashboard/domain/still_reading.dart' show readAsClientPageOwner;
import '../data/coach_note_service.dart';

final coachNoteServiceProvider =
    Provider<CoachNoteService>((ref) => CoachNoteService());

final clientNotesProvider =
    FutureProvider.family<List<CoachNote>, String>((ref, clientId) async {
  // Whose notes these are is decided by RLS (`coach manages own notes`), not
  // by anything in the query, so the answer belongs to the coach signed in
  // when it was read. Keyed by the client alone, it was shown to the next
  // coach who opened the same client on this device or tab.
  readAsClientPageOwner(ref, clientId);
  return ref.watch(coachNoteServiceProvider).getNotes(clientId);
});
