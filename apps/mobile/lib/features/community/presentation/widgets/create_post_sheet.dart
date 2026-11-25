import 'dart:async' show FutureOr, StreamSubscription;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, Supabase;

import '../../../../core/observability/app_failure.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../workout/presentation/widgets/section_load_failure.dart'
    show couldntMessage;
import '../../data/models/post_model.dart';
import '../../domain/post_type_choice.dart';
import 'post_type_selector.dart';

/// FIT-067 · "Create post". The board marks it `missing`.
///
/// Its own widget because the sheet's content needs state — the chosen type —
/// and it was being built inside `_CommunityScreenState`, where a `setState`
/// does not rebuild what `showModalBottomSheet` has already handed to the
/// overlay. That is part of why the three chips could not have worked even if
/// they had been wired: there was nowhere for a selection to live.
class CreatePostSheet extends StatefulWidget {
  /// Publishes the post. The type is the caller's to pass on to
  /// `addPost(content, postType:)` — the screen called it with the content
  /// alone, so every post this app wrote was stored as `'general'`.
  ///
  /// Awaited (P0-FL-59e): the sheet goes once it returns. A throw is a post
  /// that was not saved; it is said here and the draft is kept.
  final FutureOr<void> Function(String content, PostType type) onPost;

  /// The member whose draft this is, when the caller opened it for one; else
  /// the member signed in as it is first built. It goes with them.
  final ({String? uid})? owner;

  /// A draft that could not be posted, to go on from.
  final ({String content, PostType type})? draft;

  const CreatePostSheet(
      {super.key, required this.onPost, this.owner, this.draft});

  @override
  State<CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends State<CreatePostSheet> {
  late final _controller = TextEditingController(text: widget.draft?.content);
  late PostType _type = widget.draft?.type ?? PostType.text;
  late bool _empty = _controller.text.trim().isEmpty;
  bool _posting = false;

  /// What to say about a post that was not saved.
  String? _error;

  /// P0-FL-59e · whose draft this is.
  late final String? _owner =
      widget.owner == null ? _signedIn : widget.owner!.uid;
  StreamSubscription<AuthState>? _authSub;

  // No client at all (the sheet alone, in a test) is nobody signed in.
  static String? get _signedIn {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } on Error {
      return null;
    }
  }

  void _follow() {
    try {
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
        if (_signedIn != _owner) _closeForOwner();
      },
          onError: (Object e, StackTrace s) =>
              reportError('CreatePostSheet.onAuthStateChange', e, s));
    } on Error {
      return;
    }
  }

  void _closeForOwner() {
    if (!mounted) return;
    _controller.clear();
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive || route.isFirst) return;
    route.navigator?.removeRoute(route);
  }

  /// False (recorded, draft gone, sheet closed) once someone else is signed in.
  bool _stillOwner(String what) {
    if (_signedIn == _owner) return true;
    reportError('CreatePostSheet.identity',
        StateError('$what: the signed-in account changed'));
    _closeForOwner();
    return false;
  }

  Future<void> _submit() async {
    if (_posting || !_stillOwner('post')) return;
    setState(() {
      _posting = true;
      _error = null;
    });
    try {
      await widget.onPost(_controller.text.trim(), _type);
    } catch (e, st) {
      reportError('CreatePostSheet.post', e, st);
      if (!mounted || !_stillOwner('post')) return;
      setState(() {
        _posting = false;
        _error = couldntMessage('post that', e);
      });
      return;
    }
    if (!mounted || !_stillOwner('post')) return;
    final route = ModalRoute.of(context);
    if (route != null && route.isActive && !route.isFirst) {
      // This sheet, whatever is over it by now.
      route.isCurrent
          ? Navigator.of(context).pop()
          : route.navigator?.removeRoute(route);
    }
  }

  @override
  void initState() {
    super.initState();
    _owner; // captured now, not at the first tap
    _follow();
    _controller.addListener(() {
      final isEmpty = _controller.text.trim().isEmpty;
      if (isEmpty != _empty) setState(() => _empty = isEmpty);
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Never drawn for anyone else, however late the change is heard of.
    if (_signedIn != _owner) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _closeForOwner());
      return const SizedBox.shrink();
    }
    return _buildSheet(context);
  }

  Widget _buildSheet(BuildContext context) => Container(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        decoration: const BoxDecoration(
          color: AppColors.bgDarkSecondary,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        // Scrolls: the failure below adds lines at large text.
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.surfaceDarkElevated,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(
                  child: Text('Create Post',
                      style: TextStyle(
                          color: AppColors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                ),
                // FIT-067 declares it; the sheet could only be dismissed by
                // dragging it away.
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(postCancelLabel,
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLines: 5,
              autofocus: true,
              style: const TextStyle(color: AppColors.white, fontSize: 15),
              decoration: const InputDecoration(
                hintText: composerHint,
                border: InputBorder.none,
                filled: false,
              ),
            ),
            const SizedBox(height: 16),
            PostTypeSelector(
              selected: _type,
              onSelect: (t) => setState(() => _type = t),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Semantics(
                liveRegion: true,
                child: Text(_error!,
                    style: const TextStyle(
                        color: AppColors.error, fontSize: 13, height: 1.4)),
              ),
              const SizedBox(height: 12),
            ],
            ElevatedButton(
              onPressed: _empty || _posting ? null : _submit,
              child: const Text(postSubmitLabel),
            ),
          ],
        )),
      );
}
