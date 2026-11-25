import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_provider.dart';
import '../../dashboard/domain/still_reading.dart' show ownedRead, readAsClientPageOwner;
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
  // P0-FL-59f: marked as theirs. The family outlives the sheet and is
  // invalidated as it opens, so for the next coach it is a REFRESH, which holds
  // the last coach's notes as data.
  final uid = ref.watch(currentUserProvider.select((u) => u?.id));
  final service = ref.watch(coachNoteServiceProvider);
  return ownedRead(uid, () => service.getNotes(clientId));
});
