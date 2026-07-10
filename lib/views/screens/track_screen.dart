import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/services/order_service.dart';
import '../../state/orders_state.dart';
import '../widgets/page_header.dart';
import '../widgets/toast.dart';

class TrackScreen extends StatefulWidget {
  final String orderId;
  const TrackScreen({super.key, required this.orderId});

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  final OrderService _service = OrderService.instance;
  bool _loading = true;
  String? _error;
  String? _liveStatus; // normalized prep/way/done from the server, if reachable
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _fetch();
    // Live tracking refreshes every 15s while the screen is open.
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _fetch(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _fetch({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final info = await _service.track(widget.orderId);
      if (!mounted) return;
      setState(() {
        _liveStatus = info.status;
        _error = null;
      });
      // Keep the shared OrdersState in sync so Orders/Order Detail screens
      // reflect the same status without a separate fetch.
      final o = context.read<OrdersState>().byId(widget.orderId);
      if (o != null) o.status = info.status;
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = silent ? _error : 'Couldn\'t refresh tracking. Showing the last known status.');
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrdersState>();
    final order = orders.byId(widget.orderId) ?? orders.orders.first;
    final status = _liveStatus ?? order.status;
    const labels = ['Order confirmed', 'Preparing your order', 'On the way', 'Delivered'];
    final idx = {'conf': 0, 'prep': 1, 'way': 2, 'done': 3}[status] ?? 1;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: PageHeader(title: 'Track order · ${order.id}'),
      body: _loading
          ? const LoadingView(message: 'Loading tracking…')
          : RefreshIndicator(
        onRefresh: _fetch,
        child: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (_error != null) InlineErrorBanner(message: _error!, onRetry: _fetch),
          // ── .map — gradient bg, grid lines, dashed route, teardrop pins ──
          const _TrackMap(),

          // ── .ridercard ──
          Container(
            margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: AppColors.shSm),
            child: Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.sky, AppColors.navy], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: const Text('AR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ahmad R.', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.navy)),
                    const SizedBox(height: 1),
                    const Text('Express Rider', style: TextStyle(fontSize: 11.5, color: AppColors.sky, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('${order.id} · Arriving in ~25 min', style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => showToast(context, 'Calling rider…'),
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: AppColors.ok, borderRadius: BorderRadius.circular(13)),
                  alignment: Alignment.center,
                  child: const Icon(Icons.call_rounded, color: Colors.white, size: 18),
                ),
              ),
            ]),
          ),

          // ── .timeline ──
          Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: AppColors.shSm),
            child: Column(
              children: [
                for (var i = 0; i < labels.length; i++)
                  _TimelineStep(
                    label: labels[i],
                    done: i < idx,
                    current: i == idx,
                    isLast: i == labels.length - 1,
                  ),
              ],
            ),
          ),

          // ── .btn-ghost — full-width "Home" button ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.bg,
                  foregroundColor: AppColors.navy,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  elevation: 0,
                ),
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('Home', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

// ── .map — matches HTML's stylized delivery map exactly ──
class _TrackMap extends StatelessWidget {
  const _TrackMap();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: ClipRect(
        child: Stack(children: [
          // Gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFFdCEef7), Color(0xFFeaf4fa)],
              ),
            ),
          ),
          // Grid lines
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          // Dashed curved route
          Positioned(
            left: 0, top: 0, right: 0, bottom: 0,
            child: CustomPaint(painter: _RoutePainter()),
          ),
          // Rider pin (rose, top-left area)
          Positioned(
            left: MediaQuery.of(context).size.width * 0.24 - 19,
            top: 210 * 0.30 - 19,
            child: _TeardropPin(color: AppColors.rose, icon: Icons.local_shipping_rounded),
          ),
          // Destination pin (navy, bottom-right area)
          Positioned(
            right: MediaQuery.of(context).size.width * 0.22 - 19,
            bottom: 210 * 0.22 - 19,
            child: _TeardropPin(color: AppColors.navy, icon: Icons.location_on_rounded),
          ),
        ]),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.navy.withOpacity(0.05)
      ..strokeWidth = 1;
    const step = 30.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(size.width * 0.20, size.height * 0.32, size.width * 0.55, size.height * 0.40);
    final path = Path()
      ..addArc(rect, -2.0, 2.4); // approximates the HTML's asymmetric rounded arc

    final dashed = _dashPath(path, dashLength: 6, gapLength: 5);
    final paint = Paint()
      ..color = AppColors.sky.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawPath(dashed, paint);
  }

  Path _dashPath(Path source, {required double dashLength, required double gapLength}) {
    final dest = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0;
      bool draw = true;
      while (distance < metric.length) {
        final len = draw ? dashLength : gapLength;
        final next = (distance + len).clamp(0, metric.length).toDouble(); // ← added .toDouble()
        if (draw) dest.addPath(metric.extractPath(distance, next), Offset.zero);
        distance = next;
        draw = !draw;
      }
    }
    return dest;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Teardrop map pin — rounded square rotated 45°, matching HTML's .mpin
class _TeardropPin extends StatelessWidget {
  final Color color;
  final IconData icon;
  const _TeardropPin({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -45 * 3.1415926 / 180,
      child: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(19),
            topRight: Radius.circular(19),
            bottomLeft: Radius.circular(19),
            bottomRight: Radius.zero,
          ),
          boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Center(
          child: Transform.rotate(
            angle: 45 * 3.1415926 / 180,
            child: Icon(icon, color: Colors.white, size: 16),
          ),
        ),
      ),
    );
  }
}

// ── .tstep — done (green) / current (sky glow) / pending (gray) ──
class _TimelineStep extends StatelessWidget {
  final String label;
  final bool done;
  final bool current;
  final bool isLast;
  const _TimelineStep({required this.label, required this.done, required this.current, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final dotColor = done ? AppColors.ok : (current ? AppColors.sky : AppColors.bg);
    final borderColor = done ? AppColors.ok : (current ? AppColors.sky : AppColors.line);
    final lineColor = done ? AppColors.ok : AppColors.line;
    final textColor = done || current ? AppColors.navy : AppColors.muted;

    return IntrinsicHeight(
      child: Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(clipBehavior: Clip.none, children: [
              // Connector line (drawn behind the dot, matches .tstep::before)
              if (!isLast)
                Positioned(
                  left: 11, top: 24,
                  child: Container(width: 2, height: 44, color: lineColor),
                ),
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 2),
                  boxShadow: current
                      ? [BoxShadow(color: AppColors.sky.withOpacity(0.18), blurRadius: 0, spreadRadius: 4)]
                      : null,
                ),
                child: done ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
              ),
            ]),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: textColor)),
            ),
          ],
        ),
      ),
    );
  }
}