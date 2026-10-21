import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_env.dart';
import 'admin_tokens.dart';

/// V5 §184 — the shared Admin container chrome.
///
/// Extracted because it had been written three times with three names — `_AdminCard` in
/// the metrics panel, `_Card` in the attention queue and again in the Trust screen — and
/// the approved IA has **six pages**, so the next four would have copied it four more
/// times. Three copies of a card is tolerable; seven is how one page quietly stops
/// matching `COMPONENT-SPECS` while the others still do.
///
/// Anatomy is the published spec (`COMPONENT-SPECS.md` › Card):
/// `--adm-color-bg-surface`, `--adm-radius-xl`, and a hairline in
/// `--adm-color-line-default` standing in for `--adm-shadow-edge`'s inset ring, which
/// Flutter has no equivalent for. Every value comes from [AdminColors] / [AdminDims],
/// which are generated from `admin.tokens.css` at `931218b` — so there is no raw hex in
/// the Admin presentation layer outside the generated token file itself.
class AdminCard extends StatelessWidget {
  const AdminCard({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            vertical: AdminDims.space10, horizontal: AdminDims.space8),
        decoration: BoxDecoration(
          color: AdminColors.colorBgSurface,
          borderRadius: BorderRadius.circular(AdminDims.radiusXl),
          border: Border.all(color: AdminColors.colorLineDefault, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title.toUpperCase(),
                style: const TextStyle(
                  color: AdminColors.colorTextMuted,
                  fontSize: AdminDims.typeOverlineSize,
                  fontWeight: FontWeight.w500,
                  // --adm-type-overline-tracking: 0.12em, computed from the token size.
                  letterSpacing: AdminDims.typeOverlineSize * 0.12,
                )),
            const SizedBox(height: AdminDims.space4),
            child,
          ],
        ),
      );
}

/// A single muted line standing in for a card's whole body — the `A11` Loading,
/// Unavailable, permission-denied and zero states.
///
/// It takes the copy from its caller on purpose. The approved design's zero wording
/// differs by surface — *"None"*, *"none raised"*, *"none open"* — and a widget that
/// picked one would impose it everywhere.
class AdminNote extends StatelessWidget {
  const AdminNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AdminDims.space6),
        child: Text(text,
            style: const TextStyle(
              color: AdminColors.colorTextMuted,
              fontSize: AdminDims.typeSmallSize,
            )),
      );
}

/// Secondary prose under a card — a limit the surface is stating about itself, such as
/// `A13·1`'s exclusion or `B-4`'s withheld fields. It WRAPS, because the things said here
/// are sentences and must not be truncated (§183.3).
class AdminFootnote extends StatelessWidget {
  const AdminFootnote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AdminDims.space4),
        child: Text(text,
            style: const TextStyle(
              color: AdminColors.colorTextSubtle,
              fontSize: AdminDims.typeCaptionSize,
            )),
      );
}

/// A labelled row whose value is a STATE rather than a figure — Loading, Unavailable.
///
/// Deliberately not an `AdminMetricTile`: loading and error are not metric absences, and
/// conflating them would let a transient network failure read as a permission boundary.
class AdminPlaceholderRow extends StatelessWidget {
  const AdminPlaceholderRow({required this.label, required this.text, super.key});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AdminDims.space7),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AdminColors.colorTextSecondary,
                      fontSize: AdminDims.typeSmallSize)),
            ),
            const SizedBox(width: AdminDims.space4),
            Flexible(
              child: Text(text,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AdminColors.colorTextSubtle,
                      fontSize: AdminDims.typeSmallSize)),
            ),
          ],
        ),
      );
}

/// Renders an action area according to a CAPABILITY CHECK THAT CAN ITSELF FAIL.
///
/// WHY THIS EXISTS. The first versions of the Trust, Ecosystem and event-authoring actions
/// read their capability with `.valueOrNull ?? false`. `EC-G8` flagged it and was right:
/// on a provider that does I/O — and `admin_can` is an RPC over the network — that
/// converts *"could not load"* into the domain's empty value at the read site. Here the
/// empty value is `false`, which the UI renders as **"Read-only: this requires X"**.
///
/// So a failed capability check told an operator they **lack a permission they may well
/// hold**. That is the same defect as EC-04's green `LOW RISK` badge — "the read failed"
/// and "the answer is no" rendered as one pixel — applied to authorization.
///
/// Four states, kept apart:
///   * **loading** — the check has not answered yet;
///   * **failed** — the check itself could not be made, which is NOT a denial;
///   * **true** — the action;
///   * **false** — the approved read-only state, which is a real answer.
Widget adminCapabilityGate(
  AsyncValue<bool> capability, {
  required Widget Function() allowed,
  required Widget denied,
  String checking = 'Checking your permissions…',
  String failed = 'Your permissions could not be checked. No action is offered, and this '
      'is not a denial.',
}) =>
    capability.when(
      loading: () => AdminFootnote(checking),
      error: (_, __) => AdminFootnote(failed),
      data: (can) => can ? allowed() : denied,
    );

/// WHY THERE IS NO `quiet` VARIANT OF THE GATE, which §189 tried to add and `EC-G7`
/// rejected. A repeated row action cannot print "Checking your permissions…" twenty times,
/// so the obvious move was a flag that rendered the two non-answer states as nothing. That
/// introduces `error: (…) => SizedBox.shrink()` — the exact RC-C shape `EC-G7` ratchets,
/// where a failure and an empty state render identically. The guard was right, and raising
/// its baseline to accommodate this would have been weakening a guard to go green.
///
/// A ROW SLOT NEEDS NO GATE. The decision is made ONCE by the parent, which holds the
/// `AsyncValue`, and each row receives a plain `bool` — so there is no per-row error branch
/// to be silent in. The parent then owes [adminGatedList] around the list, which is
/// where a failed check gets its sentence. `SEC-G9` enforces that pairing, because the
/// arrangement is only honest while something is still speaking.

/// Renders a ROW LIST whose actions depend on a capability, keeping all four states apart
/// without ever hiding the rows.
///
/// WHY THIS EXISTS, AND WHY IT IS NOT A `.valueOrNull` READ. §189 needed a row list whose
/// per-row action appears only for a confirmed `·update`, and tried three shapes that three
/// different guards rejected — each correctly:
///
///   * **`adminCapabilityGate` around the list** (`SEC-G9`). A gate chooses between two
///     widgets, so its honest *"Checking your permissions…"* REPLACED EVERY ROW — hiding
///     records a `·view` capability had already authorized because an answer about a
///     different verb had not arrived. The emptiness then reads as *"there is nothing
///     here"*: the false zero this programme exists to prevent, reached through
///     authorization instead of through a `?? 0`.
///   * **a `quiet` flag on the gate** (`EC-G7`). Silencing the two non-answer states
///     introduces `error: (…) => SizedBox.shrink()`, the RC-C shape where a failure and an
///     empty state render identically.
///   * **`capability.valueOrNull == true` in the parent** (`EC-G8`). `admin_can` is an RPC,
///     so it does I/O, and that read collapses *"could not ask"* into *"no"* at the call
///     site. EC-G8's own note refuses the escape hatch in terms: the indistinguishability
///     *"is the argument for a typed error state, not a bigger allowlist"*.
///
/// So the decision is made ONCE, in a single `when` whose **error arm renders the rows AND
/// states the failure**. Nothing is silent, nothing is hidden, and no state is collapsed:
///
///   * **loading** — rows, no action, nothing said; there is no answer yet and the action
///     has simply not appeared.
///   * **failed** — rows, no action, and the sentence that this is NOT a denial.
///   * **false** — rows, no action, and the approved read-only state naming the capability.
///   * **true** — rows, with the action.
Widget adminGatedList(
  AsyncValue<bool> capability, {
  required List<Widget> Function(bool canAct) rows,
  required String denied,
}) =>
    capability.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows(false),
      ),
      error: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...rows(false),
          const AdminFootnote(
              'Your permissions could not be checked. No action is offered, and this is '
              'not a denial.'),
        ],
      ),
      data: (can) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...rows(can),
          if (!can) AdminFootnote(denied),
        ],
      ),
    );

/// A cross-page link, in the design's own wording and with its own destination.
///
/// WHY THESE EXIST AND WHY THEY ARE NOT INVENTED NAVIGATION. `SCREEN-INVENTORY`'s
/// "Interactions expected" states that *"every 'View audit history' link deep-links to
/// Trust > Audit logs"* and that *"Settings links across to Operations > System events,
/// Trust > Authorization and Trust > AI Guardian"*. The approved Settings screen carries
/// **ten** `View audit history →` links plus six named cross-links, one per section. The
/// built page had none, so an operator reading a Settings section had no route to the
/// record of what changed it.
///
/// THE LABEL IS THE DESIGN'S, NOT A PARAPHRASE, and the destination is a page that really
/// contains the named section. The approved links point at sub-sections — *"Trust →
/// Authorization"* — and this layer has page-level routes with no anchors, so the link lands
/// on the page that holds that section rather than claiming to scroll to it.
class AdminCrossLink extends StatelessWidget {
  const AdminCrossLink({required this.label, required this.route, super.key});

  final String label;
  final String route;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          height: AdminDims.sizeControl, // 44px, RESPONSIVE.md
          child: TextButton(
            onPressed: () => GoRouter.of(context).go(route),
            style: TextButton.styleFrom(
              foregroundColor: AdminColors.colorBrandAccent,
              padding: EdgeInsets.zero,
              minimumSize: const Size(AdminDims.sizeControl, AdminDims.sizeControl),
              alignment: Alignment.centerLeft,
            ),
            child: Text(label,
                style: const TextStyle(
                  fontSize: AdminDims.typeCaptionSize,
                  fontWeight: FontWeight.w500,
                )),
          ),
        ),
      );
}

/// The search box the approved tables carry, with the fields it searches STATED.
///
/// WHY THE FIELD LIST IS ON SCREEN. A search box is a promise about what it looked at, and
/// the two approved placeholders differ in how much they promise: People's reads *"Search
/// name or email"* and names its fields, while Ecosystem's reads only *"Search events"* and
/// does not. Rather than let the narrower one imply it searched everything, each box says
/// which fields it matched — so a zero result is legible as "not in these fields" instead of
/// "not in the system".
///
/// IT FILTERS SERVER-SIDE. Every admin list renders a `limit`-capped page, so filtering what
/// is already on screen would search a twenty-row window and answer "no match" for records
/// that exist. The query goes to the query.
class AdminSearchBox extends StatelessWidget {
  const AdminSearchBox({
    required this.hint,
    required this.fieldsNote,
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// The approved placeholder, verbatim.
  final String hint;

  /// Which fields the match ran over.
  final String fieldsNote;

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: AdminDims.sizeControl, // 44px, RESPONSIVE.md
            child: TextField(
              // `value` is the single source of truth, so a provider reset clears the box.
              controller: TextEditingController(text: value)
                ..selection = TextSelection.collapsed(offset: value.length),
              onChanged: onChanged,
              style: const TextStyle(
                  color: AdminColors.colorTextPrimary,
                  fontSize: AdminDims.typeSmallSize),
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                hintStyle: const TextStyle(
                    color: AdminColors.colorTextMuted,
                    fontSize: AdminDims.typeSmallSize),
                prefixIcon: const Icon(Icons.search,
                    size: 18, color: AdminColors.colorTextMuted),
              ),
            ),
          ),
          AdminFootnote(fieldsNote),
        ],
      );
}

/// The "State system" panel the design places on People, Trust, Operations and Settings, and
/// as "Dashboard states" on the Control Center.
///
/// WHY IT IS A SHARED WIDGET. `SCREEN-INVENTORY`'s **"States designed"** list is a
/// requirements list like the other two, and it names **five states present in all six
/// files** — Loading, Empty, Error, Permission (denied), Degraded — plus Unavailable, Stale,
/// Offline, Skeleton and Read-only on named pages. Four of those ten are **not implemented
/// anywhere**, and before this widget each page named only the states it happened to render,
/// so the four absent ones were silently absent on all six. A shared panel states them once
/// and identically; six hand-written lists would drift.
///
/// WHY THE FOUR ARE NOT BUILT, and why that is not laziness:
///
///   * **Offline** needs a connectivity signal this layer does not have.
///   * **Stale** needs a freshness threshold — how old is stale? — which is a product rule.
///   * **Degraded** needs a definition of partial failure. `A5` uses the word for the
///     *Guardian's* state, which is a different thing: that is a recorded value, not a page
///     condition.
///   * **Skeleton** is a loading *treatment* and this layer renders Loading as text; a
///     shimmer is presentational and would say nothing the text does not.
///
/// Each needs a definition, and inventing one would put a state on screen that no rule
/// produces — the defect this whole programme guards against, applied to chrome.
class AdminStatesPanel extends StatelessWidget {
  const AdminStatesPanel({
    required this.title,
    required this.implemented,
    required this.readOnlyNote,
    super.key,
  });

  /// `State system` on the four pages the design names, `Dashboard states` on the Control
  /// Center — the design's own two labels.
  final String title;

  /// The states this page actually renders, in its own words.
  final String implemented;

  /// The page's read-only posture, IN ITS OWN WORDS.
  ///
  /// NOT A SHARED SENTENCE, and the first version of this widget made that mistake: it used
  /// one line — *"read-only except where an action is shown"* — for all five pages, which
  /// made **Settings claim it has actions it does not have**. Settings and Operations are
  /// read-only outright; People, Trust and the Control Center carry gated actions. A panel
  /// that documents the state system must not misdescribe the page it is on.
  final String readOnlyNote;

  /// The designed states with no implementation, named once for every page.
  static const unimplemented =
      'Not implemented: Offline (no connectivity signal in this layer), Stale (no freshness '
      'threshold is ruled), Degraded (no definition of partial failure — A5 uses the word '
      'for the Guardian\'s own recorded state, which is a different thing) and Skeleton (a '
      'loading treatment; Loading is rendered as text here).';

  @override
  Widget build(BuildContext context) => AdminCard(
        title: title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminFootnote(implemented),
            const AdminFootnote(
                '"Not available to your role" and "Not recorded" are different findings and '
                'are never shown interchangeably.'),
            const AdminFootnote(unimplemented),
            AdminFootnote(readOnlyNote),
          ],
        ),
      );
}

/// The environment strip COMPONENTS.md specifies, and the Control Center screen renders.
///
/// THE RULE IS THE DESIGN'S OWN, stated on the Control Center's architectural-verification
/// panel: *"No banner. Only staging and development show the amber strip at the top."* So
/// production shows **nothing** — and that is the arm worth building carefully, because a
/// strip that appeared in production would be a permanent false alarm, while one that failed
/// to appear in staging lets an operator act on member data believing they are in a sandbox.
///
/// THE STAGING SENTENCE IS VERBATIM: *"Staging environment — changes here do not affect
/// members."* It is also TRUE in this repository rather than merely copied: QA is a separate
/// Supabase project, which is the separation `ENV-5`'s production-ref guard exists to enforce.
///
/// DEVELOPMENT DOES NOT GET THAT SENTENCE. The design says development shows a strip and
/// **does not give its wording**, and the guarantee cannot be carried over: `ENV-4` leaves
/// `dev` with **no backend default**, so a development build points at whatever `SUPABASE_URL`
/// was defined for it. Promising that changes do not affect members would be a claim this
/// layer cannot make, so the dev strip names the environment and says where the backend came
/// from instead.
///
/// 34px, per COMPONENTS.md's *"environment strip (34px)"*.
class AdminEnvironmentStrip extends StatelessWidget implements PreferredSizeWidget {
  const AdminEnvironmentStrip({required this.environment, super.key});

  final AppEnvironment environment;

  static const height = 34.0;

  /// The design's verbatim staging sentence.
  static const stagingText =
      'Staging environment — changes here do not affect members';

  /// Development names itself and makes no guarantee — see the class note.
  static const devText =
      'Development environment — the backend is whatever this build was configured with';

  /// Null in production: the design says there is no banner there.
  static String? textFor(AppEnvironment env) => switch (env) {
        AppEnvironment.prod => null,
        AppEnvironment.qa => stagingText,
        AppEnvironment.dev => devText,
      };

  @override
  Size get preferredSize =>
      Size.fromHeight(textFor(environment) == null ? 0 : height);

  @override
  Widget build(BuildContext context) {
    final text = textFor(environment);
    if (text == null) return const SizedBox.shrink();
    return Container(
      height: height,
      width: double.infinity,
      alignment: Alignment.center,
      // The AMBER is the generated token, and the foreground is the token made for it:
      // `--adm-color-status-warning` with `--adm-color-text-on-warning`. Using
      // `colorStatusWarningText` here instead would be amber-on-amber — that token is for
      // warning text on the page surface, not on the warning fill.
      color: AdminColors.colorStatusWarning,
      child: Text(text,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AdminColors.colorTextOnWarning,
            fontSize: AdminDims.typeCaptionSize,
            fontWeight: FontWeight.w600,
          )),
    );
  }
}
