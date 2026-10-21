import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/admin_metrics.dart';
import '../domain/admin_provider.dart';
import 'admin_chrome.dart';
import 'admin_tokens.dart';

/// `DESIGN-01` §1 — the `critical-incident` state, implemented.
///
/// `STATE-SPECS-A11.md` §1 records **"No dependency. Every element exists"** for this
/// state: `audit_incidents.severity` already ships `Critical`, and `admin_incidents`
/// (migration 160) already projects `severity` to the Admin layer. So this is
/// implementation of an approved design, not a new product decision.
///
/// WHAT THE SPECIFICATION REQUIRES, AND IS IMPLEMENTED HERE.
///   * severity label `Critical` in **title case** — the shipped `A2` enum (`143:70`).
///     METRIC-12 established by evidence that an uppercase `CRITICAL` appears nowhere,
///     so nothing upper-cases it;
///   * the card container — `--adm-color-bg-surface`, `--adm-radius-xl`, hairline ring;
///   * a status pill badge — `--adm-radius-pill`, `--adm-font-weight-semibold`, tracked;
///   * the zero state as the **literal copy the design uses** — "none raised" — and
///     explicitly *not* an empty panel;
///   * **a single primary action per item, never bulk**;
///   * the read-only footer, verbatim: *"Actions open the item. Nothing is changed
///     from this screen."*;
///   * a 44px touch target (`--adm-size-control`) per `RESPONSIVE.md`.
///
/// ON THE TOKENS THIS USES, AND A CORRECTION (V5 §176).
///
/// `COMPONENT-SPECS` › Severity badge observes `#f08a9b` with no token, and
/// `admin.tokens.css` publishes `#f07a8c`. §168 recorded using the token as a
/// **deviation** from the design. Measuring the published package shows that was wrong,
/// and the opposite is true:
///
///   * the approved screens contain **zero `var(--adm-*)` references** and 447 literal
///     hex values, so `admin.tokens.css` is DERIVED FROM them, not consumed by them;
///   * `#f07a8c` appears **80×** across Trust and Operations and `#f08a9b` **15×**;
///   * the danger TINT collapses **six** screen alphas into one token;
///   * the overline SIZE picks `11px` (2 uses) over `11.5px` (11 uses), because 11 is a
///     round step on a type scale.
///
/// So the token set is a deliberate NORMALISATION of ad-hoc literals, and reading from it
/// is conformance to the design authority's own intent — matching a raw literal would be
/// conformance to pre-normalisation noise. `admin.contrast.md` also publishes a measured
/// **7.4:1** for the token and measures none of the literals. Hence
/// [AdminColors.colorStatusDangerText], [AdminDims.typeOverlineSize] and the danger tint,
/// with no hex here at all.
///
/// ONE GENUINE SUBSTITUTION REMAINS. The specification names `ph-fill ph-warning-circle`
/// from the Phosphor set, and **the app does not depend on Phosphor** — `pubspec.yaml`
/// carries only `cupertino_icons` — so a Material fill-weight equivalent stands in. That
/// is a substitution, not fidelity, and adding an icon dependency is not a decision to
/// take in passing. The badge's `0.08em` tracking is also not the `0.12em` overline
/// token, so it is expressed as the exact `0.08em` the design specifies, computed from
/// the token font size.
class AdminAttentionQueue extends ConsumerWidget {
  const AdminAttentionQueue({super.key});

  /// The design's own wording for the zero case, on three separate pages.
  static const zeroCopy = 'none raised';

  /// `CONF-D5` README, quoted exactly.
  static const readOnlyFooter =
      'Actions open the item. Nothing is changed from this screen.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminIncidentsProvider);
    return AdminCard(
      title: 'Needs your attention',
      child: async.when(
        loading: () => const AdminNote('Loading…'),
        error: (_, __) => const AdminNote('Unavailable'),
        data: (items) {
          // Null and empty are different facts, and the service distinguishes them by
          // asking admin_can rather than inferring a permission from an empty list.
          if (items == null) return const AdminNote('Not available to your role');
          if (items.isEmpty) return const AdminNote(zeroCopy);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final i in items) _IncidentRow(incident: i),
              const SizedBox(height: AdminDims.space6),
              const Text(readOnlyFooter,
                  style: TextStyle(
                    color: AdminColors.colorTextSubtle,
                    fontSize: AdminDims.typeCaptionSize,
                  )),
            ],
          );
        },
      ),
    );
  }
}

/// One queue item. Opening it reveals what is already recorded and changes nothing —
/// there is no write path on this widget at all, which is the cheapest way to honour
/// "nothing is changed from this screen".
class _IncidentRow extends StatefulWidget {
  const _IncidentRow({required this.incident});

  final AdminIncident incident;

  @override
  State<_IncidentRow> createState() => _IncidentRowState();
}

class _IncidentRowState extends State<_IncidentRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final i = widget.incident;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AdminDims.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                // See the class doc: a Material substitution for ph-fill
                // ph-warning-circle, because Phosphor is not a dependency.
                Icons.error_rounded,
                size: AdminDims.sizeIconMd,
                color: _severityColor(i.severity),
              ),
              const SizedBox(width: AdminDims.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (i.severity != null) _SeverityBadge(severity: i.severity!),
                    if (i.severity != null) const SizedBox(height: AdminDims.space2),
                    Text(
                      i.summary ?? 'Incident',
                      style: const TextStyle(
                        color: AdminColors.colorTextPrimary,
                        fontSize: AdminDims.typeSmallSize,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: AdminDims.space1),
                    Text(
                      [
                        if (i.scope != null) i.scope!,
                        if (i.occurredAt != null)
                          i.occurredAt!.toIso8601String().split('T').first,
                      ].join(' · '),
                      style: const TextStyle(
                        color: AdminColors.colorTextMuted,
                        fontSize: AdminDims.typeCaptionSize,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AdminDims.space4),
              // A SINGLE primary action per item. There is deliberately no select-all,
              // no multi-select and no bulk control: the specification says "never
              // bulk", and a bulk affordance on a read-only surface would also imply a
              // mutation that does not exist.
              if (i.hasDetail)
                SizedBox(
                  height: AdminDims.sizeControl, // 44px touch target, RESPONSIVE.md
                  child: TextButton(
                    onPressed: () => setState(() => _open = !_open),
                    style: TextButton.styleFrom(
                      foregroundColor: AdminColors.colorBrandAccent,
                      minimumSize: const Size(
                          AdminDims.sizeControl, AdminDims.sizeControl),
                    ),
                    child: Text(_open ? 'Close' : 'Investigate',
                        style: const TextStyle(
                          fontSize: AdminDims.typeCaptionSize,
                          fontWeight: FontWeight.w500,
                        )),
                  ),
                ),
            ],
          ),
          if (_open) ...[
            const SizedBox(height: AdminDims.space4),
            for (final row in <(String, String?)>[
              ('Suspected cause', i.suspectedCause),
              ('Recommended action', i.recommendedAction),
              ('Action taken', i.actionTaken),
              ('Resolution', i.resolution),
            ])
              if (row.$2 != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AdminDims.space3),
                  child: Text('${row.$1}: ${row.$2}',
                      style: const TextStyle(
                        color: AdminColors.colorTextSecondary,
                        fontSize: AdminDims.typeCaptionSize,
                      )),
                ),
          ],
        ],
      ),
    );
  }
}

/// `COMPONENT-SPECS` › Severity badge, over the shipped `A2` scale.
class _SeverityBadge extends StatelessWidget {
  const _SeverityBadge({required this.severity});

  final String severity;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AdminDims.space4, vertical: AdminDims.space1),
          decoration: BoxDecoration(
            color: _severityTint(severity),
            borderRadius: BorderRadius.circular(AdminDims.radiusPill),
          ),
          child: Text(
            // Title case, exactly as the shipped enum stores it.
            severity,
            style: TextStyle(
              color: _severityColor(severity),
              // typeOverlineSize (11px) is the token the design set NORMALISED the
              // screens' 11.5px to — see the class doc and V5 §176. Not a deviation.
              fontSize: AdminDims.typeOverlineSize,
              fontWeight: FontWeight.w600, // --adm-font-weight-semibold
              letterSpacing: AdminDims.typeOverlineSize * 0.08, // the spec's 0.08em
            ),
          ),
        ),
      );
}

Color _severityColor(String? severity) => switch (severity) {
      'Critical' => AdminColors.colorStatusDangerText,
      'High' => AdminColors.colorStatusWarningText,
      'Warning' => AdminColors.colorStatusWarningText,
      // Informational, and anything the enum gains later. An unrecognised severity
      // is rendered neutrally rather than guessed into a danger colour.
      _ => AdminColors.colorTextMuted,
    };

Color _severityTint(String? severity) => switch (severity) {
      'Critical' => AdminColors.colorStatusDangerTint,
      'High' => AdminColors.colorStatusWarningTint,
      'Warning' => AdminColors.colorStatusWarningTint,
      _ => AdminColors.colorBgInset,
    };


