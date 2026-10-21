import 'package:flutter/material.dart';

const _bg   = Color(0xFF0E0E0F);
const _surf = Color(0xFF201F20);
const _pri  = Color(0xFFDDB7FF);
const _onS  = Color(0xFFE5E2E3);
const _onSV = Color(0xFFCDC3D0);
const _out  = Color(0xFF968E99);
const _outV = Color(0xFF4B444F);

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final top    = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        // Header
        Container(
          padding: EdgeInsets.only(left: 8, right: 20, top: top),
          decoration: const BoxDecoration(
            color: Color(0x99201F20),
            border: Border(bottom: BorderSide(color: Color(0x1A4B444F)))),
          child: SizedBox(height: 56, child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: _pri, size: 20),
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).pop()),
            const Expanded(child: Center(child: Text('PRIVACY POLICY',
              style: TextStyle(color: _pri, fontSize: 16,
                fontWeight: FontWeight.w800, letterSpacing: 2)))),
            const SizedBox(width: 40),
          ])),
        ),

        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 24, 20, bottom + 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            _meta('Effective Date: January 1, 2025'),
            _meta('Last Updated: June 1, 2025'),
            const SizedBox(height: 24),

            _intro('12 Circle ("we", "us", or "our") is committed to protecting your privacy. '
              'This Privacy Policy explains how we collect, use, and safeguard your information '
              'when you use the 12 Circle fitness application and related services.'),
            const SizedBox(height: 28),

            _section('1. Information We Collect', [
              _subsection('Account Information', 'When you register, we collect your name, email address, password, and optional profile details including fitness goals, body measurements, and profile photo.'),
              _subsection('Health & Fitness Data', 'With your explicit permission, we collect workout logs, nutrition entries, body weight and composition data, step counts, and heart rate data synced from connected wearables or health platforms.'),
              _subsection('Coaching Data', 'If you engage with a human coach, we store messages, session notes, check-in responses, and progress updates shared between you and your coach.'),
              _subsection('Usage Data', 'We automatically collect app interaction data, device identifiers, operating system version, and crash reports to improve app performance.'),
              _subsection('Third-Party Integrations', 'If you connect apps like Strava, Apple Health, Google Fit, WHOOP, Garmin, Polar, MyFitnessPal, or Spotify, we receive data from those services only as permitted by your authorization.'),
            ]),

            _section('2. How We Use Your Information', [
              _bullet('Provide, personalise, and improve our fitness coaching services'),
              _bullet('Match you with appropriate coaches and generate AI-powered recommendations'),
              _bullet('Track and display your fitness progress over time'),
              _bullet('Send workout reminders, coaching messages, and progress updates'),
              _bullet('Diagnose technical issues and prevent fraud'),
              _bullet('Comply with legal obligations'),
            ]),

            _section('3. Data Sharing', [
              _para('We do not sell your personal data. We may share data in these limited circumstances:'),
              _subsection('With Your Coach', 'Coaches you are matched with can view your profile, check-in history, workout logs, and progress data to provide personalised coaching.'),
              _subsection('Service Providers', 'We use Supabase (database and authentication), Expo (mobile deployment), and selected analytics providers who are contractually bound to protect your data.'),
              _subsection('Legal Requirements', 'We may disclose data if required by law, court order, or to protect the rights and safety of our users.'),
            ]),

            _section('4. Health Data', [
              _para('Health and fitness data is sensitive. We store it encrypted at rest using AES-256. '
                'We never share identifiable health data with third parties for advertising. '
                'Data synced from Apple Health or Google Fit is stored only on your account and is '
                'not accessible to coaches unless you explicitly share a report.'),
            ]),

            _section('5. Your Rights', [
              _subsection('Access', 'You may request a full export of your data at any time from Profile → Settings → Account.'),
              _subsection('Correction', 'You may update your personal information directly within the app.'),
              _subsection('Deletion', 'You may request deletion of your account by emailing privacy@12circle.app from the address on your account. Account deletion permanently removes all your data within 30 days. Deleting your account from inside the app is not available yet.'),
              _subsection('Data Portability', 'We provide data exports in JSON or CSV format on request.'),
              _subsection('Opt-Out', 'You may disable marketing notifications from Profile → Settings → Notification Preferences at any time.'),
            ]),

            _section('6. Data Retention', [
              _para('We retain your data for as long as your account is active. If you delete your account, '
                'we purge personal data within 30 days. Aggregate, anonymised fitness statistics may be '
                'retained indefinitely to improve our AI models.'),
            ]),

            _section('7. Security', [
              _para('We implement industry-standard security practices including TLS 1.3 in transit, '
                'AES-256 encryption at rest, row-level security policies on all database tables, '
                'and regular security audits. No method of transmission over the internet is 100% secure; '
                'we encourage you to use a strong, unique password.'),
            ]),

            _section('8. Children\'s Privacy', [
              _para('12 Circle is not intended for users under 13 years of age. We do not knowingly collect '
                'personal information from children. If you believe a child has provided us with data, '
                'please contact us immediately.'),
            ]),

            _section('9. International Users', [
              _para('12 Circle operates from Jamaica and stores data on servers provided by Supabase. '
                'By using the app, users outside Jamaica consent to the transfer of their data to these servers. '
                'We comply with applicable data protection regulations including GDPR for EU users.'),
            ]),

            _section('10. Changes to This Policy', [
              _para('We may update this policy from time to time. We will notify you of material changes '
                'via in-app notification or email at least 14 days before the change takes effect.'),
            ]),

            _section('11. Contact Us', [
              _para('If you have questions or concerns about this Privacy Policy or how we handle your data, '
                'please contact us at:'),
              const SizedBox(height: 8),
              _contactRow(Icons.email_outlined, 'privacy@12circle.app'),
              const SizedBox(height: 4),
              _contactRow(Icons.language_outlined, '12circle.app'),
            ]),

            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _surf,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _outV.withValues(alpha: 0.3))),
              child: const Row(children: [
                Icon(Icons.shield_outlined, color: _pri, size: 20),
                SizedBox(width: 12),
                Expanded(child: Text(
                  'Your data belongs to you. We are committed to transparency and will never use your health information for advertising.',
                  style: TextStyle(color: _onSV, fontSize: 12, height: 1.5))),
              ])),
          ]),
        )),
      ]),
    );
  }

  Widget _meta(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: const TextStyle(color: _out, fontSize: 12)));

  Widget _intro(String text) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _pri.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _pri.withValues(alpha: 0.15))),
    child: Text(text, style: const TextStyle(color: _onSV, fontSize: 13, height: 1.6)));

  Widget _section(String title, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(title, style: const TextStyle(
          color: _onS, fontSize: 16, fontWeight: FontWeight.w700))),
      ...children,
      const SizedBox(height: 24),
    ]);

  Widget _subsection(String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(
        color: _pri, fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 3),
      Text(body, style: const TextStyle(color: _onSV, fontSize: 13, height: 1.55)),
    ]));

  Widget _para(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(color: _onSV, fontSize: 13, height: 1.55)));

  Widget _bullet(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(top: 7),
        child: SizedBox(width: 4, height: 4,
          child: DecoratedBox(decoration: BoxDecoration(
            shape: BoxShape.circle, color: _pri)))),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(
        color: _onSV, fontSize: 13, height: 1.55))),
    ]));

  Widget _contactRow(IconData icon, String text) => Row(children: [
    Icon(icon, color: _out, size: 16),
    const SizedBox(width: 8),
    Text(text, style: const TextStyle(color: _pri, fontSize: 13)),
  ]);
}
