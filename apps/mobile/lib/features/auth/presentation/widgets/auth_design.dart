import 'package:flutter/material.dart';
import '../../../../core/widgets/named_icon_button.dart';

/// Shared visual design for the auth screens (login / signup / forgot / reset).
///
/// ── DESIGN SOURCE ──────────────────────────────────────────────────────────
/// The authoritative handoff package, frames FIT-007 (Sign in, LOCKED),
/// FIT-011 (Sign up), FIT-012 (Forgot password), FIT-013 (Set a new password).
/// Component specs `fld`, `fc-btn`, `fc-btn2`, `tap`, `lbl` and the token
/// values come from its `manifest.json`. Intake: docs/DESIGN_INTAKE_REPORT.md.
///
/// These four screens share every widget below, so this one file carries the
/// whole unauthenticated surface.
class AuthColors {
  // Values mirror the design tokens exactly. They stay `const` literals rather
  // than reads of TwelveCircleTheme.semantics because call sites use them
  // inside `const TextStyle(...)`, which a non-const read would break.
  // docs/DESIGN_INTAKE_REPORT.md §10 records that a per-feature palette is
  // itself a deviation from "no parallel theme"; collapsing it into
  // context.helix is follow-up work, not a colour decision.
  static const bg          = Color(0xFF0A0A0B); // --bg        (already correct)
  static const field       = Color(0xFF1B1B20); // --surf-hi   ← 0xFF17151D
  static const fieldBorder = Color(0x14FFFFFF); // --line 8%   ← 0xFF2A2733
  static const purple      = Color(0xFF7C3AED); // --violet    ← 0xFF8A3DF0
  static const purpleLight = Color(0xFFA78BFA); // --violet-txt← 0xFFB06BFF
  static const text        = Color(0xFFF4F3F6); // --ink       ← pure white
  static const sub         = Color(0xFF9B96A3); // --grey      ← 0xFFB6ABC8
  static const hint        = Color(0xFF8B8595); // --dim       ← 0xFF6E6780
  static const amber       = Color(0xFFE0A030); // --amber, for the notice block
}

/// Page shell: dark gradient + purple top glow, optional back chevron, heading,
/// subtitle, the form [children], and a pinned [footer].
class AuthScaffold extends StatelessWidget {
  final String title;
  /// Optional: FIT-007 carries a heading and no subtitle. A screen that has
  /// nothing to say below the heading should render nothing, not an empty line.
  final String? subtitle;
  /// Rendered between the heading and the form — the design's notice block
  /// (FIT-007 shows an amber session-expiry / red OAuth-error panel here).
  final Widget? notice;
  final List<Widget> children;
  final Widget? footer;
  final VoidCallback? onBack;
  const AuthScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.notice,
    required this.children,
    this.footer,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuthColors.bg,
      resizeToAvoidBottomInset: true,
      body: Stack(fit: StackFit.expand, children: [
        // dark wash with purple haze up top
        const DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF100A18), Color(0xFF0A0A0B), Color(0xFF0C0911)], stops: [0.0, 0.4, 1.0]))),
        const Align(alignment: Alignment(0, -1.0), child: SizedBox(width: 460, height: 300,
          child: DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(radius: 0.7,
            colors: [Color(0x408A3DF0), Color(0x000C0A12)]))))),

        SafeArea(child: Column(children: [
          Expanded(child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (onBack != null) ...[
                NamedIconButton(
                  label: 'Back',
                  onTap: onBack,
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: AuthColors.purpleLight, size: 22)),
                const SizedBox(height: 18),
              ] else const SizedBox(height: 6),
              // `h1` — 24px. Was 38px/w800: the design builds hierarchy from
              // size and space, and caps weight at 500.
              Text(title, style: const TextStyle(color: AuthColors.text, fontSize: 24,
                fontWeight: FontWeight.w500, height: 1.1, letterSpacing: -0.6)),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(subtitle!, style: const TextStyle(color: AuthColors.sub, fontSize: 15, height: 1.55)),
              ],
              if (notice != null) ...[const SizedBox(height: 16), notice!],
              const SizedBox(height: 26),
              ...children,
            ]),
          )),
          if (footer != null) Padding(padding: const EdgeInsets.only(bottom: 14, top: 6), child: footer!),
        ])),
      ]),
    );
  }
}

/// Design component `fld` — 52pt, 12px radius, surface-high fill.
/// [isPassword] adds the `tap` eye toggle.
///
/// [label] renders the design's `lbl` above the field. It is not decoration:
/// runtime measurement on Android found these inputs exposing their *value*
/// and no accessible NAME, because a placeholder hint is not a label. The
/// design supplies one for every field (FIT-007: "Email", "Password").
class AuthField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final String? label;
  final bool isPassword;
  final TextInputType keyboardType;
  final TextInputAction? textInputAction;
  final void Function(String)? onSubmitted;
  const AuthField({
    super.key,
    required this.controller,
    required this.hint,
    this.label,
    this.isPassword = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction,
    this.onSubmitted,
  });
  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  final _focus = FocusNode();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    final field = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _focus.requestFocus(),
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 52, // design `fld` min-height
      decoration: BoxDecoration(
        color: AuthColors.field,
        borderRadius: BorderRadius.circular(12), // design `fld` radius
        border: Border.all(color: focused ? AuthColors.purpleLight : AuthColors.fieldBorder, width: focused ? 1.5 : 1),
      ),
      child: Row(children: [
        const SizedBox(width: 16),
        Expanded(child: TextField(
          controller: widget.controller,
          focusNode: _focus,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          onSubmitted: widget.onSubmitted,
          obscureText: widget.isPassword && _obscure,
          style: const TextStyle(color: AuthColors.text, fontSize: 15),
          cursorColor: AuthColors.purpleLight,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: const TextStyle(color: AuthColors.hint, fontSize: 15),
            border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
        )),
        if (widget.isPassword)
          // Design component `tap`: a 44x44 floor. Measured on-device before
          // this change, the toggle was 19.8 x 20.2 dp with NO accessible name,
          // so a screen-reader user could neither find it nor know what it did.
          // The label is the design's own (`aria-label="Show password"`), not
          // copy invented here.
          Semantics(
            button: true,
            label: _obscure ? 'Show password' : 'Hide password',
            child: InkResponse(
              onTap: () => setState(() => _obscure = !_obscure),
              radius: 24,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                child: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: AuthColors.hint, size: 20),
              ),
            ),
          )
        else
          const SizedBox(width: 16),
      ]),
    ));

    final label = widget.label;
    if (label == null) return field;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // `lbl` — 12px, grey. Deliberately NOT excluded from semantics: it is the
      // only thing that announces what the field below is for.
      //
      // ── WHAT WAS TRIED, AND WHY THIS IS WHERE IT LANDED ────────────────────
      // Verified on-device (emulator-5554), not reasoned about:
      //  1. Wrapping the field in Semantics(label:) — NO effect. The TextField
      //     owns its own node, so the wrapper's label sat beside it and the
      //     tree still reported the input with an empty name.
      //  2. MergeSemantics around label + field — WORSE. It merged the password
      //     visibility toggle in too, so the 44x44 'Show password' button
      //     stopped existing as an independent, focusable control. That traded
      //     one accessibility defect for a more serious one.
      //
      // A true programmatic association would need InputDecoration.labelText,
      // which renders the label INSIDE the field's box and contradicts the
      // design, where `lbl` sits above it. So the label is announced as an
      // adjacent node rather than as the field's own accessible name. That is a
      // real residual limitation and is recorded as such in
      // docs/QA_EVIDENCE.md — not claimed as a fix.
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label,
          style: const TextStyle(color: AuthColors.sub, fontSize: 12, fontWeight: FontWeight.w500)),
      ),
      field,
    ]);
  }
}

/// Design component `fc-btn` — primary CTA, 52pt, 12px radius, violet fill.
///
/// Explicitly flat: the design system states "no gradient, no glow" and sets
/// the button radius to 12, not a pill. The previous gradient + 26px violet
/// drop-shadow is the exact signature it bans.
class AuthButton extends StatelessWidget {
  final String label;
  final bool loading;
  final bool showArrow;
  final VoidCallback? onTap;
  const AuthButton({super.key, required this.label, this.loading = false, this.showArrow = true, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !loading,
      // The Text child supplies the name. Adding `label:` as well produced
      // "Sign in\nSign in" in the on-device semantics tree.
      child: GestureDetector(
        onTap: loading ? null : onTap,
        child: Container(
          height: 52, width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: AuthColors.purple,
          ),
          alignment: Alignment.center,
          child: loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  // w500 — "nothing above 500", and hierarchy comes from size
                  // and space rather than weight.
                  Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
                  if (showArrow) ...[const SizedBox(width: 9),
                    const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18)],
                ]),
        ),
      ),
    );
  }
}

/// The "—— OR ——" divider.
class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key});
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Divider(color: AuthColors.fieldBorder.withValues(alpha: 0.7), thickness: 1)),
    const Padding(padding: EdgeInsets.symmetric(horizontal: 16),
      child: Text('OR', style: TextStyle(color: AuthColors.hint, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2))),
    Expanded(child: Divider(color: AuthColors.fieldBorder.withValues(alpha: 0.7), thickness: 1)),
  ]);
}

/// Design component `fc-btn2` — secondary button, 52pt, hairline outline.
class AuthSocialButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback onTap;
  const AuthSocialButton({super.key, required this.label, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    // Name comes from the Text child; a `label:` here doubled it.
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(color: AuthColors.field, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AuthColors.fieldBorder, width: 1)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          icon, const SizedBox(width: 10),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AuthColors.text, fontSize: 15, fontWeight: FontWeight.w500))),
        ]),
      ),
    ),
  );
}

/// Small white "G" Google glyph.
class GoogleGlyph extends StatelessWidget {
  const GoogleGlyph({super.key});
  @override
  Widget build(BuildContext context) => const Text('G',
    style: TextStyle(color: Color(0xFF4285F4), fontSize: 18, fontWeight: FontWeight.w800));
}

/// "Already have an account? Sign In"-style footer link.
class AuthFooterLink extends StatelessWidget {
  final String prefix;
  final String action;
  final VoidCallback onTap;
  const AuthFooterLink({super.key, required this.prefix, required this.action, required this.onTap});
  @override
  Widget build(BuildContext context) => Center(child: GestureDetector(
    onTap: onTap,
    child: Text.rich(TextSpan(children: [
      TextSpan(text: '$prefix ', style: const TextStyle(color: AuthColors.sub, fontSize: 14)),
      TextSpan(text: action, style: const TextStyle(color: AuthColors.purpleLight, fontSize: 14, fontWeight: FontWeight.w800)),
    ])),
  ));
}
