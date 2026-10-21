import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/ai_nutrition_provider.dart';
import '../../domain/chat_turn.dart';

class AiChatBubble extends StatelessWidget {
  final ChatMessage message;

  /// FIT-090's `Send it again`. Only a failed turn offers it.
  final VoidCallback? onRetry;

  const AiChatBubble({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    // FIT-090. A failed turn used to render as a coach bubble — same avatar,
    // same styling — so a transport failure was indistinguishable from
    // nutrition advice, and there was no way to retry but to retype.
    if (message.failed) return _failed(context);

    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.purple.withValues(alpha: 0.2),
                shape: BoxShape.circle),
              child: const Icon(Icons.psychology, color: AppColors.purple, size: 20)),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Photo thumbnail (user messages with an image)
                if (isUser && message.image != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(message.image!,
                      width: 180, height: 180, fit: BoxFit.cover)),
                  const SizedBox(height: 6),
                ],
                // Text bubble
                if (message.content.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isUser ? AppColors.purple : AppColors.surfaceDark,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isUser ? 16 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 16)),
                      border: isUser ? null : Border.all(color: AppColors.surfaceDarkElevated)),
                    child: Text(message.content,
                      style: const TextStyle(
                        color: AppColors.white, fontSize: 14, height: 1.5))),
              ])),
          if (isUser) ...[
            const SizedBox(width: 8),
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surfaceDarkElevated)),
              child: const Icon(Icons.person_outline, color: AppColors.white, size: 20)),
          ],
        ]));
  }

  Widget _failed(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Semantics(
          container: true,
          label: message.content,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceDarkElevated),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.textTertiary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(message.content,
                      style: const TextStyle(
                          color: AppColors.textTertiary, fontSize: 13)),
                ),
                if (onRetry != null)
                  TextButton(
                    onPressed: onRetry,
                    child: const Text(sendItAgainLabel,
                        style:
                            TextStyle(color: AppColors.purple, fontSize: 13)),
                  ),
              ],
            ),
          ),
        ),
      );
}
