import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../vendor/presentation/event_agenda_screen.dart';
import '../../payments/data/payment_service.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _bg    = Color(0xFF030303);
const _card  = Color(0xFF0E0B16);
const _brd   = Color(0xFF1A1020);
const _brand = Color(0xFFA855F7);
const _pri   = Color(0xFFDDB7FF);
const _tert  = Color(0xFF6FFBBE);
const _wht   = Colors.white;
const _mut   = Color(0xFFCFC2D6);

// ── UC30: Event Registration + QR Ticket ─────────────────────────────────────
class EventTicketScreen extends StatefulWidget {
  final Map<String, dynamic> event;
  const EventTicketScreen({super.key, required this.event});
  @override
  State<EventTicketScreen> createState() => _EventTicketScreenState();
}

class _EventTicketScreenState extends State<EventTicketScreen> {
  final _db = Supabase.instance.client;
  bool _registered = false;
  bool _loading = false;
  String? _ticketCode;

  @override
  void initState() {
    super.initState();
    _checkRegistration();
  }

  Future<void> _checkRegistration() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final reg = await _db
          .from('event_registrations')
          .select('qr_code')
          .eq('event_id', widget.event['id'] as String)
          .eq('user_id', uid)
          .maybeSingle();
      if (reg != null) {
        if (!mounted) return;
        setState(() {
          _registered = true;
          _ticketCode = reg['qr_code'] as String?;
        });
      }
    } catch (_) {}
  }

  Future<void> _register() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    setState(() => _loading = true);
    try {
      final code = 'TKT-${uid.substring(0, 6).toUpperCase()}-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
      await _db.from('event_registrations').insert({
        'event_id': widget.event['id'],
        'user_id': uid,
        'qr_code': code,
        'status': 'confirmed',
      });
      if (!mounted) return;
      setState(() { _registered = true; _ticketCode = code; });
    } catch (_) {
      // I-COM-01 / DAT-4. This block used to invent a demo ticket code and set
      // `_registered = true`, so a failed write rendered the same _TicketView as
      // a real registration. QA_CLOSURE_STANDARD §9 invariant I-1 names that
      // exactly — "Not 'You're registered' on a failed registration" and "never
      // demo data presented as the user's own" — and PD-B27 requires the
      // fabricating catch deleted "regardless of the answer".
      //
      // The failure is now surfaced through the mechanism this screen already
      // uses for the paid path (_buyTicket, below): no state is invented, so
      // `_registered` stays false and the build falls through to the register
      // affordance. What becomes of the error object is ERR-1/EC-11 territory
      // and is deliberately NOT changed here.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not complete your registration. Try again.')));
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  /// Paid events go through Stripe Checkout; the webhook grants the registration.
  /// Uses in-app Embedded Checkout on web when configured, else hosted redirect.
  Future<void> _buyTicket() async {
    final eventId = widget.event['id'] as String;
    final svc = PaymentService();
    setState(() => _loading = true);

    // Hosted redirect only — Stripe Checkout can't run in an iframe.
    final ok = await svc.startCheckout(kind: 'event_ticket', eventId: eventId);
    if (!mounted) return;
    setState(() => _loading = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not start checkout. Try again.')));
    } else {
      _checkRegistration();
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final dt = DateTime.tryParse(event['event_date'] as String? ?? '') ?? DateTime.now();
    final isFree = event['is_free'] as bool? ?? true;
    final price = event['price'];

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _wht, size: 20),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context)),
        title: const Text('Event Ticket', style: TextStyle(color: _wht, fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          // Event card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _card, borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _brd),
              image: event['banner_url'] != null ? DecorationImage(
                image: NetworkImage(event['banner_url'] as String),
                fit: BoxFit.cover, opacity: 0.2) : null,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: _brand.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                child: const Text('RECHARGE EVENT', style: TextStyle(color: _brand, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1))),
              const SizedBox(height: 12),
              Text(event['title'] as String? ?? 'Event',
                style: const TextStyle(color: _wht, fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(event['description'] as String? ?? '',
                style: const TextStyle(color: _mut, fontSize: 13, height: 1.5)),
              const SizedBox(height: 16),
              _InfoRow(Icons.calendar_today_rounded, '${_day(dt)}, ${dt.day} ${_month(dt)} ${dt.year}'),
              const SizedBox(height: 6),
              _InfoRow(Icons.access_time_rounded, '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}'),
              if (event['location'] != null) ...[
                const SizedBox(height: 6),
                _InfoRow(Icons.location_on_rounded, event['location'] as String),
              ],
              if (event['price'] != null && event['price'] != 0) ...[
                const SizedBox(height: 6),
                _InfoRow(Icons.attach_money_rounded, '\$${event['price']}'),
              ],
            ]),
          ),
          const SizedBox(height: 24),
          if (_registered && _ticketCode != null) ...[
            _TicketView(code: _ticketCode!, eventName: event['title'] as String? ?? 'Event'),
          ] else ...[
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: _loading ? null : (isFree ? _register : _buyTicket),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brand, foregroundColor: _wht,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: _wht, strokeWidth: 2))
                  : Text(
                      isFree ? 'Register & Get Ticket' : 'Buy Ticket — \$$price',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            )),
          ],
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => EventAgendaScreen(event: event))),
            style: OutlinedButton.styleFrom(
              foregroundColor: _pri,
              side: const BorderSide(color: _brd),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            icon: const Icon(Icons.event_note_rounded, size: 18),
            label: const Text('View Agenda', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          )),
        ]),
      ),
    );
  }

  String _day(DateTime dt) => ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'][dt.weekday-1];
  String _month(DateTime dt) => ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][dt.month-1];
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: _brand, size: 16),
    const SizedBox(width: 8),
    Text(text, style: const TextStyle(color: _wht, fontSize: 13)),
  ]);
}

// ── QR-style ticket (visual only — no external QR package needed) ─────────────
class _TicketView extends StatelessWidget {
  final String code;
  final String eventName;
  const _TicketView({required this.code, required this.eventName});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const Text('Your Ticket', style: TextStyle(color: _wht, fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      Container(
        decoration: BoxDecoration(
          color: _card, borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _tert.withValues(alpha: 0.4)),
          boxShadow: [BoxShadow(color: _tert.withValues(alpha: 0.1), blurRadius: 30, spreadRadius: 5)],
        ),
        child: Column(children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
            child: Column(children: [
              const Icon(Icons.confirmation_num_rounded, color: _brand, size: 40),
              const SizedBox(height: 8),
              Text(eventName,
                style: const TextStyle(color: _wht, fontSize: 18, fontWeight: FontWeight.w800),
                textAlign: TextAlign.center),
              const SizedBox(height: 4),
              const Text('CONFIRMED', style: TextStyle(color: _tert, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w700)),
            ]),
          ),
          // Dashed divider
          Row(children: [
            Container(width: 20, height: 20, decoration: const BoxDecoration(color: _bg, shape: BoxShape.circle)),
            Expanded(child: CustomPaint(painter: _DashedLinePainter())),
            Container(width: 20, height: 20, decoration: const BoxDecoration(color: _bg, shape: BoxShape.circle)),
          ]),
          // QR code visual
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Container(
                width: 180, height: 180,
                decoration: BoxDecoration(
                  color: _wht, borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: _brand.withValues(alpha: 0.3), blurRadius: 20)]),
                child: CustomPaint(
                  painter: _QRPainter(code),
                  child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.fitness_center_rounded, color: _brand, size: 28)),
                  ])),
                ),
              ),
              const SizedBox(height: 16),
              Text(code,
                style: const TextStyle(color: _pri, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 2)),
              const SizedBox(height: 4),
              const Text('Show this at the door for entry',
                style: TextStyle(color: _mut, fontSize: 12)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _brd)),
        child: const Row(children: [
          Icon(Icons.info_outline_rounded, color: _brand, size: 18),
          SizedBox(width: 10),
          Expanded(child: Text('Screenshot this ticket for offline access. Check-in staff will scan your code at the event.',
            style: TextStyle(color: _mut, fontSize: 12), maxLines: 3)),
        ]),
      ),
    ]);
  }
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF1A1020)..strokeWidth = 1.5;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, size.height / 2), Offset(x + 6, size.height / 2), paint);
      x += 12;
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _QRPainter extends CustomPainter {
  final String data;
  _QRPainter(this.data);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF1A1A1A);
    final seed = data.hashCode;
    final rng = _LCG(seed);
    final cellSize = size.width / 21;

    // Draw finder patterns (corners)
    _drawFinder(canvas, paint, 0, 0, cellSize);
    _drawFinder(canvas, paint, 14, 0, cellSize);
    _drawFinder(canvas, paint, 0, 14, cellSize);

    // Draw random data cells
    for (int row = 0; row < 21; row++) {
      for (int col = 0; col < 21; col++) {
        if ((row < 9 && col < 9) || (row < 9 && col > 11) || (row > 11 && col < 9)) continue;
        if (rng.next() > 0.45) {
          canvas.drawRect(
            Rect.fromLTWH(col * cellSize, row * cellSize, cellSize - 0.5, cellSize - 0.5),
            paint);
        }
      }
    }
  }

  void _drawFinder(Canvas canvas, Paint paint, int col, int row, double cell) {
    canvas.drawRect(Rect.fromLTWH(col * cell, row * cell, 7 * cell, 7 * cell), paint);
    canvas.drawRect(Rect.fromLTWH((col + 1) * cell, (row + 1) * cell, 5 * cell, 5 * cell),
      paint..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH((col + 2) * cell, (row + 2) * cell, 3 * cell, 3 * cell),
      paint..color = const Color(0xFF1A1A1A));
    paint.color = const Color(0xFF1A1A1A);
  }

  @override bool shouldRepaint(_) => false;
}

// Simple pseudo-random number generator
class _LCG {
  int _state;
  _LCG(this._state);
  double next() {
    _state = (_state * 1664525 + 1013904223) & 0xFFFFFFFF;
    return (_state & 0xFFFF) / 0xFFFF;
  }
}
