import 'dart:async' show unawaited;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/observability/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../workout/presentation/widgets/section_load_failure.dart';
import '../domain/ai_nutrition_provider.dart';
import 'widgets/ai_chat_bubble.dart';

class AiNutritionScreen extends ConsumerStatefulWidget {
  const AiNutritionScreen({super.key});

  @override
  ConsumerState<AiNutritionScreen> createState() => _AiNutritionScreenState();
}

class _AiNutritionScreenState extends ConsumerState<AiNutritionScreen> {
  final _messageController = TextEditingController();
  final _scrollController  = ScrollController();
  final _picker            = ImagePicker();
  final _speech            = SpeechToText();
  bool _isLoading   = false;
  bool _isListening = false;
  bool _speechReady = false;

  /// FIT-089 draws exactly these three chips. The screen shipped six, in a
  /// different voice ("Analyze my breakfast", "Generate a 7-day meal plan").
  ///
  /// The three the board dropped are not capabilities that disappear — every
  /// one of them is a sentence the user can still type, and the meal planner
  /// and grocery list have their own routes in the overflow menu. What changes
  /// is which three the screen offers first, and that is the board's call.
  final List<String> _quickPrompts = [
    'Plan my week',
    'Read my plate',
    'Rest-day meals',
  ];

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    _speechReady = await _speech.initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _speech.stop();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String message, {File? image}) async {
    if (message.trim().isEmpty && image == null) return;
    _messageController.clear();
    // The notifier draws a failed turn (with "Send it again") and records it.
    await _whileThinking(() => ref
        .read(aiNutritionNotifierProvider.notifier)
        .sendMessage(message, image: image));
  }

  Future<void> _retryTurn() => _whileThinking(
      () => ref.read(aiNutritionNotifierProvider.notifier).retryLastTurn());

  Future<void> _whileThinking(Future<void> Function() turn) async {
    final epoch = _epoch;
    setState(() => _isLoading = true);
    await turn();
    if (!mounted || epoch != _epoch) return;
    setState(() => _isLoading = false);
    _scrollToBottom();
  }

  /// P0-FL-60b · bumped when the account changes: what an earlier one started
  /// no longer touches this screen.
  int _epoch = 0;

  /// The half-typed (or dictated) question is the member's who left.
  void _forget() {
    _epoch++;
    _messageController.clear();
    if (_isListening) unawaited(_speech.cancel());
    setState(() => _isLoading = _isListening = false);
  }

  void _say(String message) {
    if (!mounted) return;
    // A SnackBar is a live region on its own. The default 4 s: it covers the
    // composer.
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Source sheet → picker → read in flight: a second tap opens nothing.
  bool _pickingPhoto = false;

  /// P0-FL-56a · one readable photo, or null: the person cancelled (silent),
  /// or a failure that was recorded and said here. The picker was unguarded —
  /// a denied permission was an uncaught error and the button did nothing.
  Future<File?> _pickPhoto() async {
    if (_pickingPhoto) return null;
    _pickingPhoto = true;
    // The member this photo belongs to, fixed before the pick.
    final auth = Supabase.instance.client.auth;
    final uid = auth.currentUser?.id;
    bool sameMember() => auth.currentUser?.id == uid;
    try {
      final source = await _showImageSourceSheet();
      if (source == null) return null;
      final XFile? xfile;
      try {
        xfile = await _picker.pickImage(source: source, imageQuality: 80);
      } catch (e, st) {
        reportError('aiNutrition.photo.pick.${source.name}', e, st);
        if (!sameMember()) return null;
        final camera = source == ImageSource.camera;
        final what = camera ? 'camera' : 'photos';
        // image_picker's permission codes end `_access_denied`.
        _say(e is PlatformException && e.code.endsWith('_access_denied')
            ? "Couldn't open your $what — allow ${camera ? 'camera' : 'photo'} "
                'access in Settings, then try again.'
            : couldntMessage('open your $what', e));
        return null;
      }
      if (xfile == null) return null;
      try {
        // Openable? An unreadable file was sent anyway and came back as a
        // turn the assistant had failed.
        final photo = File(xfile.path);
        await photo.openRead(0, 1).drain<void>();
        // Another member signed in meanwhile: not their photo to analyze.
        if (!sameMember()) {
          reportError('aiNutrition.photo.identity',
              StateError('the member changed during a pick'));
          return null;
        }
        return photo;
      } catch (e, st) {
        reportError('aiNutrition.photo.read', e, st);
        if (sameMember()) _say(couldntMessage('use that photo', e));
        return null;
      }
    } finally {
      _pickingPhoto = false;
    }
  }

  Future<void> _pickAndAnalyzePhoto() async {
    final photo = await _pickPhoto();
    if (photo == null || !mounted) return;
    await _sendMessage('Analyze this meal photo for me.', image: photo);
  }

  Future<ImageSource?> _showImageSourceSheet() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.surfaceDarkElevated,
              borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined, color: AppColors.purple),
            title: const Text('Take Photo', style: TextStyle(color: AppColors.white)),
            onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: AppColors.purple),
            title: const Text('Choose from Gallery', style: TextStyle(color: AppColors.white)),
            onTap: () => Navigator.pop(context, ImageSource.gallery)),
          const SizedBox(height: 8),
        ])));
  }

  Future<void> _toggleVoice() async {
    if (!_speechReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition not available on this device.')));
      return;
    }
    if (_isListening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() => _isListening = false);
    } else {
      if (!mounted) return;
      setState(() => _isListening = true);
      final epoch = _epoch;
      await _speech.listen(
        onResult: (result) {
          if (!mounted || epoch != _epoch) return; // another member's composer
          _messageController.text = result.recognizedWords;
          _messageController.selection = TextSelection.fromPosition(
            TextPosition(offset: _messageController.text.length));
          if (result.finalResult) {
            if (!mounted) return;
            setState(() => _isListening = false);
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        localeId: 'en_US',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // A new notifier is a new account (see `_OneMember`).
    ref.listen(aiNutritionNotifierProvider.notifier, (was, now) {
      if (!identical(was, now)) _forget();
    });
    final messages = ref.watch(aiNutritionNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgDark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.white),
          tooltip: 'Back',
          onPressed: () => context.pop()),
        title: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: AppColors.purple.withValues(alpha: 0.2),
              shape: BoxShape.circle),
            child: const Icon(Icons.psychology, color: AppColors.purple, size: 18)),
          const SizedBox(width: 8),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AI Nutrition Coach',
              style: TextStyle(color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            Text('Powered by Claude',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
          ]),
        ]),
        actions: [
          PopupMenuButton(
            // FIT-089 names this. Without it the control falls back to
            // MaterialLocalizations' generic "Show menu".
            tooltip: 'More options',
            icon: const Icon(Icons.more_vert, color: AppColors.white),
            color: AppColors.surfaceDark,
            itemBuilder: (_) => [
              PopupMenuItem(
                onTap: () => context.push('/meal-plan'),
                child: const Row(children: [
                  Icon(Icons.calendar_today_outlined, color: AppColors.purple, size: 18),
                  SizedBox(width: 8),
                  Text('Meal Plan', style: TextStyle(color: AppColors.white)),
                ])),
              PopupMenuItem(
                onTap: () => context.push('/grocery-list'),
                child: const Row(children: [
                  Icon(Icons.shopping_cart_outlined, color: AppColors.purple, size: 18),
                  SizedBox(width: 8),
                  Text('Grocery List', style: TextStyle(color: AppColors.white)),
                ])),
              PopupMenuItem(
                onTap: () => ref.read(aiNutritionNotifierProvider.notifier).clearChat(),
                child: const Row(children: [
                  Icon(Icons.refresh, color: AppColors.error, size: 18),
                  SizedBox(width: 8),
                  Text('Clear Chat', style: TextStyle(color: AppColors.error)),
                ])),
            ]),
        ]),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: messages.length + (_isLoading ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == messages.length && _isLoading) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.purple.withValues(alpha: 0.2),
                        shape: BoxShape.circle),
                      child: const Icon(Icons.psychology, color: AppColors.purple, size: 20)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.surfaceDarkElevated)),
                      child: const Row(children: [
                        SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(color: AppColors.purple, strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('Thinking...', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                      ])),
                  ]));
              }
              final m = messages[index];
              return AiChatBubble(
                message: m,
                // Only the turn the conversation is currently sitting on can
                // be re-sent; an older failure is history.
                onRetry: m.failed && index == messages.length - 1
                    ? (_isLoading ? null : _retryTurn)
                    : null,
              );
            })),

        // Quick prompts
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _quickPrompts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => _sendMessage(_quickPrompts[i]),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.purple.withValues(alpha: 0.3))),
                child: Text(_quickPrompts[i],
                  style: const TextStyle(color: AppColors.purple, fontSize: 12)))))),

        const SizedBox(height: 8),

        // Input row
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          decoration: BoxDecoration(
            color: AppColors.bgDarkSecondary,
            border: Border(top: BorderSide(color: AppColors.surfaceDarkElevated))),
          child: Row(children: [
            // Photo button.
            //
            // F-22: it was unnamed. FIT-003 declares "Scan a meal" for exactly
            // this — pick a photo and have it analysed — so the name is the
            // package's own.
            Semantics(
              button: true,
              label: 'Scan a meal',
              enabled: !_isLoading,
              child: GestureDetector(
              onTap: _isLoading ? null : _pickAndAnalyzePhoto,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surfaceDarkElevated)),
                child: Icon(Icons.camera_alt_outlined,
                  color: _isLoading ? AppColors.textTertiary : AppColors.purple, size: 20)))),
            const SizedBox(width: 8),

            // Text field
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _isListening
                      ? AppColors.purple
                      : AppColors.surfaceDarkElevated,
                    width: _isListening ? 1.5 : 1)),
                child: TextField(
                  controller: _messageController,
                  style: const TextStyle(color: AppColors.white),
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: _isListening ? 'Listening...' : 'Ask about your nutrition',
                    hintStyle: TextStyle(
                      color: _isListening ? AppColors.purple : AppColors.textTertiary),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                  onSubmitted: _isLoading ? null : (v) => _sendMessage(v)))),
            const SizedBox(width: 8),

            // Voice button
            GestureDetector(
              onTap: _isLoading ? null : _toggleVoice,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: _isListening
                    ? AppColors.purple
                    : AppColors.surfaceDark,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _isListening
                      ? AppColors.purple
                      : AppColors.surfaceDarkElevated)),
                child: Icon(
                  _isListening ? Icons.mic : Icons.mic_none_outlined,
                  color: AppColors.white, size: 20))),
            const SizedBox(width: 8),

            // Send button
            GestureDetector(
              onTap: _isLoading ? null : () => _sendMessage(_messageController.text),
              child: Container(
                width: 40, height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.purple,
                  shape: BoxShape.circle),
                child: const Icon(Icons.send, color: AppColors.white, size: 18))),
          ])),
      ]),
    );
  }
}
