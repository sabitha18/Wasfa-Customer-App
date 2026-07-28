import '../../core/utils/json_utils.dart';

/// One notification from the confirmed `GET /app/acct/notifications` list.
///
/// ⚠️ There's no saved EXAMPLE RESPONSE for this LIST endpoint anywhere in
/// the Postman collection — only the request shape is confirmed
/// (`?user_id=&page=&per_page=`). [title]/[body]/[read]/[date] below are
/// still best-effort guesses at field names for that reason.
///
/// [type]/[orderCode]/[prescriptionId] are NOT guesses, though — these
/// match the CONFIRMED real push payload shape (2026-07-28 logcat output —
/// see NotificationService._handleDeepLink's doc), on the reasonable bet
/// that the list endpoint reuses the same field names for the same data.
/// Confirm that assumption once a real list response can be captured.
class ServerNotification {
  final int id; // the notification's own row id — this, not orderCode/prescriptionId, is what /read wants
  final String title;
  final String body;
  final String? type; // "order" | "prescription" — confirmed values
  final String? orderCode; // present when type == "order", e.g. "APM169"
  final String? prescriptionId; // present when type == "prescription", e.g. "ADM119-1785215450"
  final bool read;
  final DateTime date;

  const ServerNotification({
    required this.id,
    required this.title,
    required this.body,
    this.type,
    this.orderCode,
    this.prescriptionId,
    this.read = false,
    required this.date,
  });

  factory ServerNotification.fromJson(Map<String, dynamic> json) => ServerNotification(
        id: asInt(json, const ['id', 'notification_id']),
        title: asString(json, const ['title', 'subject'], fallback: 'WASFA'),
        body: asString(json, const ['body', 'message', 'text']),
        type: asStringOrNull(json, const ['type']),
        orderCode: asStringOrNull(json, const ['order_code']),
        prescriptionId: asStringOrNull(json, const ['prescription_id']),
        read: asBool(json, const ['read', 'is_read', 'seen']),
        date: DateTime.tryParse(asString(json, const ['date', 'created_at', 'sent_at'])) ?? DateTime.now(),
      );
}

/// Page wrapper — field names for total/page/per_page are guesses at the
/// same pagination shape confirmed elsewhere in this app (`/app/products`),
/// since this endpoint's own response isn't confirmed.
class NotificationPage {
  final List<ServerNotification> items;
  final int page;
  final int perPage;
  final int total;
  final int unread;

  const NotificationPage({required this.items, required this.page, required this.perPage, required this.total, this.unread = 0});

  bool get hasMore => items.isNotEmpty && page * perPage < total;

  factory NotificationPage.fromJson(dynamic res, {required int requestedPage, required int requestedPerPage}) {
    if (res is List) {
      // Bare array, no pagination wrapper at all.
      final items = res.map((e) => ServerNotification.fromJson(e as Map<String, dynamic>)).toList();
      return NotificationPage(items: items, page: requestedPage, perPage: requestedPerPage, total: items.length);
    }
    final map = res as Map<String, dynamic>;
    final rawList = asList(map, const ['notifications', 'items', 'data']);
    final items = rawList.map((e) => ServerNotification.fromJson(e as Map<String, dynamic>)).toList();
    return NotificationPage(
      items: items,
      page: asInt(map, const ['page', 'current_page'], fallback: requestedPage),
      perPage: asInt(map, const ['per_page', 'perPage'], fallback: requestedPerPage),
      total: asInt(map, const ['total'], fallback: items.length),
      unread: asInt(map, const ['unread']),
    );
  }
}
