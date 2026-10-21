import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const _bg   = Color(0xFF0E0E0F);
const _surf = Color(0xFF201F20);
const _pri  = Color(0xFFDDB7FF);
const _priC = Color(0xFFB76DFF);
const _onS  = Color(0xFFE5E2E3);
const _onSV = Color(0xFFCDC3D0);
const _out  = Color(0xFF968E99);
const _outV = Color(0xFF4B444F);

class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});
  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  int? _expandedIndex;

  static const _faqs = [
    (
      q: 'How do I change my coaching mode?',
      a: 'Go to Profile → Settings → Coaching Mode. You can switch between Self-Guided, AI-Guided, and Coach-Guided at any time. Changes take effect immediately.',
    ),
    (
      q: 'How do I book a call with my coach?',
      a: 'Tap "Book a coaching call" from your Home screen or the Check-Ins tab. Your coach publishes available time slots and you can book directly from the calendar.',
    ),
    (
      q: 'How do I connect my fitness wearable?',
      a: 'Go to Profile → Integrations. Tap "Connect" next to your device or app. Health app integrations require the iOS or Android app — they are not available on web.',
    ),
    (
      q: 'How do I track my nutrition?',
      a: 'Tap the Nutrition tab in the bottom navigation. Log meals manually, use the food search, or connect MyFitnessPal to import nutrition data automatically.',
    ),
    (
      q: 'Can I change my fitness goals?',
      a: 'Yes. Go to Profile → Personal Info → Fitness Goal. You can update your primary goal, activity level, and nutrition preferences at any time.',
    ),
    (
      q: 'How do I delete my account?',
      a: 'Email privacy@12circle.app from the address on your account and we will delete it. Your data is permanently removed within 30 days and the deletion cannot be undone. Deleting your account from inside the app is not available yet.',
    ),
    (
      q: 'What is the AI Coach?',
      a: 'The AI Coach uses your workout history, check-in data, and goals to provide personalised insights and recommendations. It is available 24/7 in the AI Coach tab.',
    ),
    (
      q: 'How do I reset my password?',
      a: 'On the login screen tap "Forgot Password?" and enter your email. You will receive a reset link within a few minutes — check your spam folder if needed.',
    ),
    (
      q: 'My data is not syncing. What should I do?',
      a: 'Pull down to refresh. If data still does not update, go to Profile → Integrations, disconnect and reconnect the affected app. Contact support if the issue persists.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final top    = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _buildHeader(context, top),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 24, 20, bottom + 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildContactCard(),
                  const SizedBox(height: 28),
                  const Text('Frequently Asked Questions',
                    style: TextStyle(color: _onS, fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('Tap a question to see the answer.',
                    style: TextStyle(color: _out, fontSize: 12)),
                  const SizedBox(height: 16),
                  ...List.generate(_faqs.length, _buildFaqItem),
                  const SizedBox(height: 24),
                  const Text('Quick Links',
                    style: TextStyle(color: _onS, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  _QuickLinkRow(
                    icon: Icons.privacy_tip_outlined,
                    label: 'Privacy Policy',
                    onTap: () => context.push('/privacy-policy'),
                  ),
                  const SizedBox(height: 8),
                  _QuickLinkRow(
                    icon: Icons.description_outlined,
                    label: 'Terms of Service',
                    onTap: () => context.push('/terms-of-service'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, double top) {
    return Container(
      padding: EdgeInsets.only(left: 8, right: 20, top: top),
      decoration: const BoxDecoration(
        color: Color(0x99201F20),
        border: Border(bottom: BorderSide(color: Color(0x1A4B444F)))),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: _pri, size: 20),
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).pop()),
            const Expanded(
              child: Center(
                child: Text('HELP CENTER',
                  style: TextStyle(color: _pri, fontSize: 16,
                    fontWeight: FontWeight.w800, letterSpacing: 2)))),
            const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_priC.withValues(alpha: 0.12), _bg],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _priC.withValues(alpha: 0.25))),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _priC.withValues(alpha: 0.15),
              shape: BoxShape.circle),
            child: const Icon(Icons.support_agent_rounded, color: _pri, size: 26)),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Need more help?',
                  style: TextStyle(color: _onS, fontSize: 15, fontWeight: FontWeight.w700)),
                SizedBox(height: 2),
                Text('Email us at support@12circle.app',
                  style: TextStyle(color: _onSV, fontSize: 12)),
                Text('We reply within 24 hours.',
                  style: TextStyle(color: _out, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaqItem(int i) {
    final faq      = _faqs[i];
    final expanded = _expandedIndex == i;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => setState(() =>
            _expandedIndex = expanded ? null : i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: expanded ? _priC.withValues(alpha: 0.08) : _surf,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: expanded ? _priC.withValues(alpha: 0.3) : _outV.withValues(alpha: 0.3))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(faq.q,
                      style: TextStyle(
                        color: expanded ? _pri : _onS,
                        fontSize: 14,
                        fontWeight: FontWeight.w600))),
                  const SizedBox(width: 8),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: _out,
                    size: 20),
                ]),
              if (expanded) ...[
                const SizedBox(height: 10),
                Text(faq.a,
                  style: const TextStyle(color: _onSV, fontSize: 13, height: 1.55)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickLinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _QuickLinkRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _surf,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _outV.withValues(alpha: 0.3))),
        child: Row(
          children: [
            Icon(icon, color: _onSV, size: 20),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(color: _onS, fontSize: 14)),
            const Spacer(),
            const Icon(Icons.chevron_right, color: _out, size: 20),
          ],
        ),
      ),
    );
  }
}
