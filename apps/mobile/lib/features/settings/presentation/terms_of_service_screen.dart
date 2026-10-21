import 'package:flutter/material.dart';

const _bg   = Color(0xFF0E0E0F);
const _pri  = Color(0xFFDDB7FF);
const _onS  = Color(0xFFE5E2E3);
const _onSV = Color(0xFFCDC3D0);
const _out  = Color(0xFF968E99);

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final top    = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
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
            const Expanded(child: Center(child: Text('TERMS OF SERVICE',
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

            _intro('Welcome to 12 Circle. By accessing or using our app and services, '
              'you agree to be bound by these Terms of Service. Please read them carefully '
              'before using the platform.'),
            const SizedBox(height: 28),

            _section('1. Acceptance of Terms',
              'By creating an account or using 12 Circle, you confirm that you are at '
              'least 18 years of age (or have parental consent if under 18) and agree '
              'to these Terms and our Privacy Policy.'),
            _section('2. Health & Safety Disclaimer',
              'The fitness content, workout plans, and nutritional guidance provided '
              'through 12 Circle are for informational purposes only and do not constitute '
              'medical advice. Always consult a qualified healthcare professional before '
              'starting any new exercise or diet programme, especially if you have a '
              'pre-existing health condition.'),
            _section('3. Account Responsibilities',
              'You are responsible for maintaining the confidentiality of your account '
              'credentials. You agree not to share your account with others or use another '
              "person's account without permission. Notify us immediately of any unauthorised "
              'use of your account.'),
            _section('4. Permitted Use',
              'You may use the app for personal, non-commercial fitness and wellness '
              'purposes. You may not reproduce, distribute, or create derivative works '
              'from any content without written permission from 12 Circle.'),
            _section('5. Subscriptions & Payments',
              'Certain features require a paid subscription. Subscriptions auto-renew '
              'unless cancelled at least 24 hours before the renewal date. Refunds are '
              'subject to the refund policy in effect at the time of purchase and the '
              'policies of the applicable app store.'),
            _section('6. Coach Services',
              'Coaches on the platform are independent contractors, not employees of '
              '12 Circle. We do not guarantee specific results from coaching. Any '
              'coaching relationship is between you and your selected coach.'),
            _section('7. Data & Privacy',
              'We collect and process data as described in our Privacy Policy. By using '
              '12 Circle you consent to this data processing. Health data (including '
              'PAR-Q responses and body metrics) is stored securely and never sold '
              'to third parties.'),
            _section('8. Limitation of Liability',
              '12 Circle is not liable for any indirect, incidental, or consequential '
              'damages arising from your use of the app or any injury sustained while '
              'following a workout programme. Our total liability is limited to the '
              'amount you paid in the 12 months preceding the claim.'),
            _section('9. Termination',
              'We may suspend or terminate your account for violation of these Terms '
              'without prior notice. You may request deletion of your account at any '
              'time by emailing privacy@12circle.app from the address on your account. '
              'Deleting your account from inside the app is not available yet.'),
            _section('10. Changes to Terms',
              'We may update these Terms periodically. Continued use of the app after '
              'changes are posted constitutes acceptance. We will notify you of material '
              'changes via email or in-app notification.'),
            _section('11. Governing Law',
              'These Terms are governed by the laws of the jurisdiction in which '
              '12 Circle operates. Any disputes shall be resolved through binding '
              'arbitration unless prohibited by applicable law.'),
            const SizedBox(height: 16),
            _meta('Questions? Contact us at legal@12circle.app'),
          ]))),
      ]),
    );
  }

  Widget _meta(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: const TextStyle(color: _out, fontSize: 12)));

  Widget _intro(String text) => Text(text,
    style: const TextStyle(color: _onSV, fontSize: 14, height: 1.6));

  Widget _section(String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(
        color: _onS, fontSize: 15, fontWeight: FontWeight.w700, height: 1.4)),
      const SizedBox(height: 6),
      Text(body, style: const TextStyle(
        color: _onSV, fontSize: 13, height: 1.65)),
    ]));
}
