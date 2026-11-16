/// Who may open an exercise for editing -- the database's rule (migration 199,
/// owner decision 15), so the app never offers an edit the server will refuse.
///
///   * an admin: any exercise;
///   * a PLATFORM exercise (no owning coach, shared by every coach): the content
///     editors -- admin or content_manager (`is_content_editor()`, 083). Other
///     coaches read and use it but cannot replace its media;
///   * a PRIVATE exercise: the coach who owns it (and an admin).
///
/// Before 199 the Edit button showed for every coach on every exercise, and a
/// coach "editing" a platform exercise could replace its shared media.
const Set<String> kContentEditorRolesForMedia = {'admin', 'content_manager'};

bool canEditExercise({
  required String? role,
  required String? uid,
  required String? exerciseCoachId,
}) {
  if (role == 'admin') return true;
  if (exerciseCoachId == null || exerciseCoachId.isEmpty) {
    return kContentEditorRolesForMedia.contains(role);
  }
  return uid != null && exerciseCoachId == uid;
}
