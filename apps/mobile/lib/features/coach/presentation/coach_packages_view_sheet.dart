import 'package:flutter/material.dart';
import '../../../core/observability/app_failure.dart';
import '../../workout/presentation/widgets/section_load_failure.dart';
import '../data/package_service.dart';

const _card  = Color(0xFF0E0B16);
const _panel = Color(0xFF171026);
const _brand = Color(0xFFB76DFF);
const _white = Color(0xFFEDE7F3);
const _muted = Color(0xFFB6A9C4);
const _gold  = Color(0xFFFFD479);

/// Read-only view of a coach's published packages, for clients. Lets a
/// coach-guided client see what their coach offers without leaving the plan
/// screen. Editing lives in the coach's own pricing sheet.
void showCoachPackagesSheet(
    BuildContext context, String coachId, String coachName) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: _card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _CoachPackagesSheet(coachId: coachId, coachName: coachName),
  );
}

class _CoachPackagesSheet extends StatefulWidget {
  final String coachId;
  final String coachName;
  const _CoachPackagesSheet({required this.coachId, required this.coachName});
  @override
  State<_CoachPackagesSheet> createState() => _CoachPackagesSheetState();
}

class _CoachPackagesSheetState extends State<_CoachPackagesSheet> {
  List<Map<String, dynamic>>? _packages;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// One read per opening (the read was started in `build`, so it ran again
  /// whenever the sheet was rebuilt — a rotation, the keyboard), recorded and
  /// retryable when it fails (P0-FL-56b).
  Future<void> _load() async {
    if (_busy) return;
    _busy = true;
    try {
      final rows = await PackageService().getCoachPackages(widget.coachId);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = null;
        _packages = rows;
      });
    } catch (e, st) {
      reportError('CoachPackagesViewSheet._load', e, st);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e;
      });
    }
  }

  String _priceLabel(Map<String, dynamic> p) {
    final type = p['type'] as String? ?? '';
    final price = (p['price'] as num?)?.toDouble() ?? 0;
    final sessions = (p['sessions'] as num?)?.toInt() ?? 0;
    final amount = '\$${price.toStringAsFixed(price % 1 == 0 ? 0 : 2)}';
    return switch (type) {
      'monthly' => '$amount/mo',
      'bulk' => '$amount · $sessions sessions',
      _ => '$amount/session',
    };
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.coachName.trim().isEmpty ? 'Coach' : widget.coachName.trim();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (context, scrollCtrl) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: _muted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text("$title's Packages",
              style: const TextStyle(color: _white, fontSize: 20,
                fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('What your coach offers. Tap a coach in the marketplace to purchase.',
              style: TextStyle(color: _muted, fontSize: 13)),
            const SizedBox(height: 16),
            Expanded(
              child: Builder(
                builder: (context) {
                  final packages = _packages;
                  if (packages == null) {
                    if (_error == null) {
                      return const Center(
                        child: CircularProgressIndicator(color: _brand));
                    }
                    return SingleChildScrollView(
                      controller: scrollCtrl,
                      child: SectionLoadFailure(
                        what: 'packages',
                        error: _error,
                        busy: _busy,
                        onRetry: () => setState(() { _load(); }),
                        accent: _brand,
                        textColor: _white,
                        mutedColor: _muted,
                      ));
                  }
                  if (packages.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Text(
                          "$title hasn't published any packages yet.",
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _muted, fontSize: 14, height: 1.5)),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scrollCtrl,
                    itemCount: packages.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final p = packages[i];
                      final name = p['name'] as String? ?? 'Package';
                      final desc = p['description'] as String? ?? '';
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _panel,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _brand.withValues(alpha: 0.18)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(name,
                                    style: const TextStyle(color: _white, fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                                ),
                                Text(_priceLabel(p),
                                  style: const TextStyle(color: _gold, fontSize: 14,
                                    fontWeight: FontWeight.w800)),
                              ],
                            ),
                            if (desc.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(desc,
                                style: const TextStyle(color: _muted, fontSize: 13, height: 1.4)),
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
