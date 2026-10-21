import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/admin_provider.dart';
import 'admin_chrome.dart';
import 'admin_metrics_panel.dart';
import 'admin_tokens.dart';

/// V5 §167 — the host for [AdminMetricsPanel]: the owner-approved Admin metrics.
///
/// A NEW ROUTE RATHER THAN A CHANGE TO THE LEGACY CONSOLE. `/admin-dashboard` is the
/// pre-token screen, styled from its own private palette. Mounting a token-styled
/// panel inside it would produce a screen in two visual languages, and restyling that
/// screen is a product decision, not something to do in passing. §12's rule is to
/// extend additively, so this is additive: nothing about the legacy console changes.
///
/// WHY NO CLIENT-SIDE ROLE GUARD IS ADDED HERE. The admin routes in `app_router.dart`
/// are not role-gated, and the enforcement that matters is server-side — every surface
/// this page reads gates on `admin_can` inside the view's own `WHERE`, so a caller
/// without the capability receives no row no matter how they arrived. Adding a client
/// check would be defence in depth, but it would also be the only check a reader
/// sees, and a client-side gate that *looks* like the boundary is worse than none.
/// What a non-admin sees here is every card saying "Not available to your role",
/// which is both true and the correct `A11` state.
class AdminMetricsScreen extends ConsumerWidget {
  const AdminMetricsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AdminColors.colorBgCanvas,
      appBar: AppBar(
        backgroundColor: AdminColors.colorBgCanvas,
        surfaceTintColor: AdminColors.colorBgCanvas,
        elevation: 0,
        iconTheme: const IconThemeData(color: AdminColors.colorTextPrimary),
        title: const Text(
          'Metrics',
          style: TextStyle(
            color: AdminColors.colorTextPrimary,
            fontSize: AdminDims.typeSectionTitleSize,
            fontWeight: FontWeight.w500,
          ),
        ),
        // COMPONENTS.md · the 34px environment strip. Production shows NOTHING,
        // which is the design's own rule and the arm that matters most.
        bottom: AdminEnvironmentStrip(
            environment: ref.watch(adminEnvironmentProvider)),
      ),
      body: RefreshIndicator(
        color: AdminColors.colorBrandAccent,
        backgroundColor: AdminColors.colorBgSurface,
        onRefresh: () async {
          ref.invalidate(adminActivityOverviewProvider);
          ref.invalidate(adminUserOverviewProvider);
          ref.invalidate(adminEventsOverviewProvider);
          ref.invalidate(adminCommunityOverviewProvider);
          ref.invalidate(adminRevenueOverviewProvider);
          ref.invalidate(adminReleaseStatusProvider);
        },
        child: ListView(
          // The panel is a Column and does not own scrolling; the host provides it.
          padding: const EdgeInsets.fromLTRB(
            AdminDims.space8,
            AdminDims.space6,
            AdminDims.space8,
            AdminDims.space20,
          ),
          children: const [AdminMetricsPanel()],
        ),
      ),
    );
  }
}
