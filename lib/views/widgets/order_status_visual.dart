import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Label + badge colors for one normalized order status (the values
/// [Order.status]/[TrackInfo.status] actually hold — see
/// `Order._normalizeStatus` in order.dart for the raw→normalized mapping).
class OrderStatusVisual {
  final String label;
  final Color bg;
  final Color fg;
  const OrderStatusVisual({required this.label, required this.bg, required this.fg});
}

const _deliveredBg = Color(0xFFE7F8F0);

/// [status] must already be normalized (e.g. `order.status`), NOT the raw
/// server string. Covers every bucket `Order._normalizeStatus` can
/// produce — confirmed against the admin panel's 11-value "Delivery
/// Status" dropdown (Pending, Confirmed, Processing, Picked up, On the
/// way, Delivered, Cancelled, Return requested, Return completed,
/// Refunded, Closed) — so a status showing up here that this app has
/// genuinely never seen before still falls back to the 'Preparing' look
/// rather than rendering nothing.
OrderStatusVisual orderStatusVisual(String status) {
  switch (status) {
    case 'pending':
      return const OrderStatusVisual(label: 'Pending', bg: AppColors.line, fg: AppColors.muted);
    case 'conf':
      return const OrderStatusVisual(label: 'Confirmed', bg: AppColors.blush, fg: AppColors.rose);
    case 'picked_up':
      return const OrderStatusVisual(label: 'Picked up', bg: AppColors.blush, fg: AppColors.rose);
    case 'collecting':
      return const OrderStatusVisual(label: 'Collecting', bg: AppColors.blush, fg: AppColors.rose);
    case 'way':
      return const OrderStatusVisual(label: 'On the way', bg: AppColors.blush, fg: AppColors.rose);
    case 'done':
      return const OrderStatusVisual(label: 'Delivered', bg: _deliveredBg, fg: AppColors.ok);
    case 'cancelled':
      return OrderStatusVisual(label: 'Cancelled', bg: AppColors.danger.withOpacity(.1), fg: AppColors.danger);
    case 'return_requested':
      return OrderStatusVisual(label: 'Return requested', bg: AppColors.warn.withOpacity(.14), fg: AppColors.warn);
    case 'return_completed':
      return const OrderStatusVisual(label: 'Return completed', bg: _deliveredBg, fg: AppColors.ok);
    case 'refunded':
      return const OrderStatusVisual(label: 'Refunded', bg: _deliveredBg, fg: AppColors.ok);
    case 'closed':
      return const OrderStatusVisual(label: 'Closed', bg: AppColors.line, fg: AppColors.muted);
    case 'prep':
    default:
      return const OrderStatusVisual(label: 'Preparing', bg: AppColors.blush, fg: AppColors.rose);
  }
}

/// True for the "side" outcomes — cancelled, either return step, refunded,
/// closed — that don't have a meaningful spot on the linear
/// confirmed→preparing→on the way→delivered timeline. Screens that render
/// that timeline should show [OrderStatusBanner] instead for these.
bool isTerminalSideStatus(String status) => const {'cancelled', 'return_requested', 'return_completed', 'refunded', 'closed'}.contains(status);

/// Small rounded pill — e.g. top-right of an order card/detail header.
/// Wraps [orderStatusVisual] so every screen renders the same status
/// identically instead of three near-identical hand-rolled Containers.
class OrderStatusBadge extends StatelessWidget {
  final String status;
  const OrderStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final v = orderStatusVisual(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: v.bg, borderRadius: BorderRadius.circular(20)),
      child: Text(v.label, style: TextStyle(color: v.fg, fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }
}

/// Plain banner used in place of the step timeline for [isTerminalSideStatus]
/// statuses, which have no meaningful position on that timeline.
class OrderStatusBanner extends StatelessWidget {
  final String status;
  const OrderStatusBanner({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final v = orderStatusVisual(status);
    String message;
    IconData icon;
    switch (status) {
      case 'cancelled':
        message = 'This order was cancelled.';
        icon = Icons.cancel_outlined;
        break;
      case 'return_requested':
        message = 'A return request is pending for this order.';
        icon = Icons.assignment_return_outlined;
        break;
      case 'return_completed':
        message = 'The returned item(s) have been received.';
        icon = Icons.assignment_return_outlined;
        break;
      case 'refunded':
        message = 'This order has been refunded.';
        icon = Icons.currency_exchange_rounded;
        break;
      case 'closed':
        message = 'This order has been closed.';
        icon = Icons.lock_outline_rounded;
        break;
      default:
        message = '${v.label}.';
        icon = Icons.info_outline_rounded;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: v.fg.withOpacity(.08), borderRadius: BorderRadius.circular(15), border: Border.all(color: v.fg.withOpacity(.25))),
      child: Row(children: [
        Icon(icon, color: v.fg, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: TextStyle(color: v.fg, fontWeight: FontWeight.w600, fontSize: 12.5))),
      ]),
    );
  }
}
