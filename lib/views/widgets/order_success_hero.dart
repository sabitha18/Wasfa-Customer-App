import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// "Order placed successfully" hero — Flutter version of the client's
/// design (order-success-hero.html). Shown at the top of Track order right
/// after an order is placed, in place of the map / truck banner.
///
/// Same look and motion as the design: two soft rings grow, the green badge
/// pops, the check draws, confetti and text fade in (once, < 1 s). With the
/// system "Reduce motion" setting on, it's shown without animation.
class OrderSuccessHero extends StatefulWidget {
  final bool isArabic;
  const OrderSuccessHero({super.key, required this.isArabic});

  @override
  State<OrderSuccessHero> createState() => _OrderSuccessHeroState();
}

class _OrderSuccessHeroState extends State<OrderSuccessHero> with SingleTickerProviderStateMixin {
  // Design colours.
  static const _accent = Color(0xFF16A34A); // Success Green
  static const _bg = Color(0xFFEEF7FC);
  static const _navy = Color(0xFF023B60);
  static const _sub = Color(0xFF4F6273);
  static const _rose = Color(0xFFE7609F);
  static const _aqua = Color(0xFF58C4E4);
  static const _sky = Color(0xFF1E9CD7);

  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _c.value = 1; // Reduce motion → final state, no animation
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // Timings mirror the CSS (delays/durations over an ~1.1 s timeline).
  Animation<double> _iv(double begin, double end, [Curve curve = Curves.easeOut]) =>
      CurvedAnimation(parent: _c, curve: Interval(begin, end, curve: curve));

  @override
  Widget build(BuildContext context) {
    final ar = widget.isArabic;
    final ring = _iv(0.0, 0.55, const Cubic(.2, .8, .2, 1));
    final pop = _iv(0.09, 0.59, const Cubic(.2, .8, .2, 1));
    final draw = _iv(0.45, 0.86);
    final confetti = _iv(0.50, 0.95);
    final text = _iv(0.55, 0.96);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // ── confetti, positioned around the badge (relative to centre) ──
          Positioned.fill(
            child: LayoutBuilder(builder: (context, box) {
              final cx = box.maxWidth / 2;
              Widget dot(double dx, double top, double w, double h, Color color, {double rot = 0, bool round = true}) {
                return Positioned(
                  left: cx + dx,
                  top: top,
                  child: AnimatedBuilder(
                    animation: confetti,
                    builder: (_, child) => Opacity(
                      opacity: confetti.value,
                      child: Transform.translate(
                        offset: Offset(0, 8 * (1 - confetti.value)),
                        child: Transform.scale(scale: 0.3 + 0.7 * confetti.value, child: child),
                      ),
                    ),
                    child: Transform.rotate(
                      angle: rot * math.pi / 180,
                      child: Container(
                        width: w,
                        height: h,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(round ? 99 : 3),
                        ),
                      ),
                    ),
                  ),
                );
              }

              return Stack(children: [
                dot(-136, 46, 10, 10, _rose),
                dot(-110, 128, 14, 5, _aqua, rot: -30, round: false),
                dot(-160, 96, 6, 6, _navy),
                dot(108, 40, 14, 5, _rose, rot: 35, round: false),
                dot(138, 112, 9, 9, _aqua),
                dot(100, 150, 6, 6, _rose),
                dot(-80, 30, 6, 6, _sky),
                dot(72, 78, 5, 5, _navy),
              ]);
            }),
          ),

          // ── badge + text ──
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: SizedBox(
                    width: 132,
                    height: 132,
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (_, __) {
                        final r = ring.value;
                        final p = pop.value;
                        // Pop: 0.4 → 1.08 → 1 (like the CSS keyframes)
                        final scale = p < 0.6 ? 0.4 + (1.08 - 0.4) * (p / 0.6) : 1.08 - 0.08 * ((p - 0.6) / 0.4);
                        return Stack(alignment: Alignment.center, children: [
                          Opacity(
                            opacity: r,
                            child: Transform.scale(
                              scale: 0.6 + 0.4 * r,
                              child: Container(
                                decoration: BoxDecoration(shape: BoxShape.circle, color: _accent.withValues(alpha: 0.10)),
                              ),
                            ),
                          ),
                          Opacity(
                            opacity: r,
                            child: Transform.scale(
                              scale: 0.6 + 0.4 * r,
                              child: Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(shape: BoxShape.circle, color: _accent.withValues(alpha: 0.18)),
                              ),
                            ),
                          ),
                          Opacity(
                            opacity: p.clamp(0.0, 1.0),
                            child: Transform.scale(
                              scale: scale,
                              child: Container(
                                width: 76,
                                height: 76,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _accent,
                                  boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))],
                                ),
                                alignment: Alignment.center,
                                child: CustomPaint(size: const Size(40, 40), painter: _CheckPainter(draw.value)),
                              ),
                            ),
                          ),
                        ]);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                AnimatedBuilder(
                  animation: text,
                  builder: (_, child) => Opacity(
                    opacity: text.value,
                    child: Transform.translate(offset: Offset(0, 6 * (1 - text.value)), child: child),
                  ),
                  child: Column(children: [
                    Text(
                      ar ? 'تم تأكيد طلبك بنجاح' : 'Order placed successfully',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: _navy),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      ar ? 'شكراً لك! استلمنا طلبك والصيدلي يعمل عليه الآن.' : "Thank you! We've received your order and our pharmacist is on it.",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, height: 1.55, color: _sub),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// White check mark (path M10 21 L17.5 28.5 L31 13 in a 40×40 box), drawn
/// from start to end as [progress] goes 0 → 1.
class _CheckPainter extends CustomPainter {
  final double progress;
  _CheckPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final s = size.width / 40;
    final path = Path()
      ..moveTo(10 * s, 21 * s)
      ..lineTo(17.5 * s, 28.5 * s)
      ..lineTo(31 * s, 13 * s);
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final out = Path();
    for (final ui.PathMetric m in path.computeMetrics()) {
      out.addPath(m.extractPath(0, m.length * progress.clamp(0.0, 1.0)), Offset.zero);
    }
    canvas.drawPath(out, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}
