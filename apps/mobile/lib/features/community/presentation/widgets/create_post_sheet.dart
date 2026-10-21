import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
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
  final void Function(String content, PostType type) onPost;

  const CreatePostSheet({super.key, required this.onPost});

  @override
  State<CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends State<CreatePostSheet> {
  final _controller = TextEditingController();
  PostType _type = PostType.text;
  bool _empty = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final isEmpty = _controller.text.trim().isEmpty;
      if (isEmpty != _empty) setState(() => _empty = isEmpty);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
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
        child: Column(
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
            ElevatedButton(
              onPressed: _empty
                  ? null
                  : () {
                      widget.onPost(_controller.text.trim(), _type);
                      Navigator.of(context).pop();
                    },
              child: const Text(postSubmitLabel),
            ),
          ],
        ),
      );
}
