import 'package:flutter/widgets.dart';

import '../domain/admin_metrics.dart';
import 'admin_tokens.dart';

/// V5 §164 — the Admin metric readout, and the `A11` states it must distinguish.
///
/// Anatomy is the published **Stat tile** and **Empty state** specs
/// (`COMPONENT-SPECS.md`, derived from the approved design): a `4px 1fr auto` row,
/// `--adm-space-7` gap, `14px 0` padding, with the empty treatment in
/// `--adm-color-text-muted` at the small type size. Every value comes from
/// [AdminColors] / [AdminDims], which are generated from the published
/// `admin.tokens.css` — no raw hex appears here, which is the Helix rule the older
/// admin screen's `const _brand = Color(0xFFA855F7)` breaks.
///
/// WHY THE CALLER MUST NAME THE REASON FOR AN ABSENT VALUE. There is no
/// `AdminMetricTile(value: someNullableInt)` constructor, on purpose. A tile that
/// accepts a bare null has to guess why it is null, and the only cheap guess is
/// "treat it as nothing", which renders `0`. For METRIC-02 that would tell a
/// `Users`-only operator that nobody signed in — a statement about the
/// Security-owned audit population that role may not query. So [AdminMetricTile.of]
/// requires `whenNull`, and the two states render differently:
///
///   * [MetricAbsence.notAuthorized] → "Not available to your role"
///   * [MetricAbsence.notRecorded]   → "Not recorded"
///
/// A MEASURED ZERO IS A VALUE, NOT AN ABSENCE. The approved design states the zero
/// copy explicitly — "None" · "none raised" · "none open", *not* an empty panel
/// (`STATE-SPECS-A11.md` §1) — so [zeroCopy] carries that wording where a card uses
/// it, and the tile still renders as a value.
class AdminMetricTile extends StatelessWidget {
  const AdminMetricTile.value({
    required this.label,
    required int this.value,
    this.zeroCopy,
    this.suffix,
    this.delta,
    super.key,
  })  : absence = null,
        display = null;

  const AdminMetricTile.absent({
    required this.label,
    required MetricAbsence this.absence,
    super.key,
  })  : value = null,
        zeroCopy = null,
        suffix = null,
        delta = null,
        display = null;

  /// For a figure that is not an integer — a percentage, a money amount — already
  /// formatted by the caller, who knows its units.
  const AdminMetricTile.text({
    required this.label,
    required String this.display,
    this.delta,
    super.key,
  })  : value = null,
        absence = null,
        zeroCopy = null,
        suffix = null;

  /// The only entry point that takes a nullable figure, and it will not compile
  /// without being told what a null means.
  static AdminMetricTile of(
    String label,
    int? value, {
    required MetricAbsence whenNull,
    String? zeroCopy,
    String? suffix,
    int? delta,
    Key? key,
  }) =>
      value == null
          ? AdminMetricTile.absent(label: label, absence: whenNull, key: key)
          : AdminMetricTile.value(
              label: label,
              value: value,
              zeroCopy: zeroCopy,
              suffix: suffix,
              delta: delta,
              key: key);

  final String label;
  final int? value;
  final String? display;
  final MetricAbsence? absence;

  /// The design's own wording for a measured zero, e.g. "None".
  final String? zeroCopy;
  final String? suffix;

  /// Month-on-month change. Null means unknown, and an unknown delta is NOT
  /// rendered as "0" — a flat month and an unmeasurable one are different claims.
  final int? delta;

  static const _absenceCopy = {
    MetricAbsence.notAuthorized: 'Not available to your role',
    MetricAbsence.notRecorded: 'Not recorded',
  };

  String get _valueText {
    if (display != null) return display!;
    if (value == 0 && zeroCopy != null) return zeroCopy!;
    return '${_grouped(value!)}${suffix ?? ''}';
  }

  static String _grouped(int n) {
    final s = n.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${n < 0 ? '-' : ''}$b';
  }

  bool get isAbsent => absence != null;

  @override
  Widget build(BuildContext context) {
    final absent = absence;
    return Padding(
      // Stat tile: `padding: 14px 0`.
      padding: const EdgeInsets.symmetric(vertical: AdminDims.space7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Stat tile: the leading `4px` rail.
          Container(
            width: AdminDims.space2,
            height: AdminDims.sizeIconMd,
            decoration: BoxDecoration(
              color: absent == null
                  ? AdminColors.colorBrandAccent
                  : AdminColors.colorLineStrong,
              borderRadius: BorderRadius.circular(AdminDims.radiusPill),
            ),
          ),
          const SizedBox(width: AdminDims.space7),
          // BOTH columns are Flexible, not `Expanded` + a fixed Text. The published
          // Stat tile is `4px 1fr auto`, and an `auto` column sized by the absence
          // copy overflows a narrow tile — which is exactly what the widget test
          // caught at 360px, a width RESPONSIVE.md's <=900px case makes ordinary.
          // The label yields first, because the figure is the point of the tile.
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AdminColors.colorTextSecondary,
                fontSize: AdminDims.typeSmallSize,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: AdminDims.space7),
          if (absent != null)
            // Empty state: `--adm-color-text-muted` at the small type size. Never a
            // number, and never a zero.
            Flexible(
              child: Text(
                _absenceCopy[absent]!,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: AdminColors.colorTextMuted,
                  fontSize: AdminDims.typeSmallSize,
                ),
              ),
            )
          else ...[
            // FLEXIBLE, like the absence branch beside it. §164.3 made the absence text
            // flexible and left this one fixed, so a long pre-formatted value — a
            // sentence passed to AdminMetricTile.text — overflowed by 288px the first
            // time the Trust page used one. A tile is a single row by design, so the
            // value ellipsises rather than wrapping; PROSE does not belong in a tile at
            // all, and the caller that triggered this was corrected too.
            Flexible(
              child: Text(
                _valueText,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: AdminColors.colorTextPrimary,
                  fontSize: AdminDims.typeCardTitleSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (delta != null) ...[
              const SizedBox(width: AdminDims.space4),
              Text(
                '${delta! >= 0 ? '+' : ''}${_grouped(delta!)}',
                style: TextStyle(
                  color: delta! >= 0
                      ? AdminColors.colorStatusSuccessText
                      : AdminColors.colorStatusDangerText,
                  fontSize: AdminDims.typeCaptionSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
