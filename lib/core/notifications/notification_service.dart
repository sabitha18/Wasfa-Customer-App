import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../routing/app_routes.dart';
import '../../data/services/account_service.dart';
import '../../data/services/notification_history_store.dart';

/// Must be a top-level (or static) function annotated exactly like this —
/// FCM invokes it in a separate background isolate when a message arrives
/// while the app is fully backgrounded or terminated, so it can't be a
/// method on [NotificationService] or close over any app state.
///
/// If [message] has a `notification` block (title+body), the OS already
/// shows that automatically in this state — nothing to do here except
/// record it into the local history list, so it still shows up on the
/// in-app notifications page later. If it's DATA-ONLY (just a `data` map,
/// no `notification` block — common when a push needs to carry custom
/// fields like an order code or Rx id), the OS does NOT auto-display
/// anything at all, in any app state, and this used to genuinely do
/// nothing about that despite the comment here once claiming it was "a
/// hook for future... handling" — meaning any data-only push sent while
/// the app was backgrounded or terminated was silently dropped with zero
/// visible sign anything had gone wrong on either side. This constructs
/// and shows a local notification from the message's own `data` fields in
/// that case, same as the foreground handler already does for real
/// `notification` pushes.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // ═══ Grep logcat for "WASFA_PUSH" to see exactly what backend actually
  // sends, in every app state — this is the single most useful thing to
  // check if tapping a notification isn't navigating anywhere: the code
  // below only recognizes `data['type']`/`data['id']` (see
  // NotificationService._handleDeepLink) — if the real payload uses
  // different key names, or nests them differently, this log line will
  // show that immediately, without needing to guess again.
  debugPrint('WASFA_PUSH [background] notification=${message.notification != null ? '{title: ${message.notification!.title}, body: ${message.notification!.body}}' : 'null'} data=${message.data}');
  final n = message.notification;
  if (n != null) {
    // OS already displays this — this instance of NotificationHistoryStore
    // lives in a separate background isolate from the running app (if any),
    // but both read/write the SAME underlying SharedPreferences file, so
    // this is still picked up correctly the next time the app itself calls
    // NotificationHistoryStore.refresh() (see main.dart / notifications
    // screen).
    await NotificationHistoryStore.instance.add(title: n.title ?? 'WASFA', body: n.body ?? '', data: message.data);
    return;
  }
  // Field names here are a best-effort guess (`title`/`body`, matching the
  // structure a `notification` block would have) — confirm the actual data
  // keys backend sends for a data-only push and adjust if they differ.
  final title = message.data['title']?.toString() ?? 'WASFA';
  final body = message.data['body']?.toString() ?? message.data['message']?.toString() ?? '';
  if (body.isEmpty) return; // nothing meaningful to show
  final local = FlutterLocalNotificationsPlugin();
  // Background isolates don't share the main isolate's already-initialized
  // plugin instance — this needs its own lightweight init.
  await local.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  ));
  await local.show(
    message.hashCode,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails('wasfa_default', 'WASFA notifications', channelDescription: 'Order status and prescription updates', importance: Importance.high),
      iOS: DarwinNotificationDetails(),
    ),
    payload: jsonEncode(message.data),
  );
  await NotificationHistoryStore.instance.add(title: title, body: body, data: message.data);
}

/// Push notifications for order status changes and Rx submission/pricing
/// updates.
///
/// ✅ Confirmed live (2026-07-28, real logcat output) — the actual payload
/// shapes:
/// ```json
/// // Order status change:
/// { "notification": {...}, "data": { "type": "order", "order_code": "APM169", "order_id": 183, "status": "collecting" } }
/// // New prescription:
/// { "notification": {...}, "data": { "type": "prescription", "prescription_id": "ADM119-1785215450" } }
/// ```
/// Earlier versions of this file guessed at `order_status`/`new_rx`/a
/// generic `id` field — all wrong. See [_handleDeepLink] for the routing
/// itself.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  /// Attach this to `MaterialApp.navigatorKey` — notification taps happen
  /// outside any screen's own `BuildContext`, so navigating in response to
  /// one needs a app-wide key rather than a context passed in normally.
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  static const _channel = AndroidNotificationChannel(
    'wasfa_default',
    'WASFA notifications',
    description: 'Order status and prescription updates',
    importance: Importance.high,
  );

  bool _initialized = false;
  int? _pendingUserId; // re-sent on token refresh, once known

  /// Call once at app start, after `Firebase.initializeApp()` — see
  /// main.dart. Requests notification permission, wires up foreground/
  /// background/terminated message handling, and checks whether the app
  /// was opened directly from a notification tap.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await NotificationHistoryStore.instance.ensureLoaded();

    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (details) {
        final payload = details.payload;
        debugPrint('WASFA_PUSH [tapped: local notification] payload=$payload');
        if (payload == null || payload.isEmpty) return;
        _handleDeepLink(jsonDecode(payload) as Map<String, dynamic>);
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);

    // Foreground: FCM does NOT show a system notification on its own while
    // the app is open (on either platform) — show one via
    // flutter_local_notifications so a push isn't silently invisible just
    // because the app happened to be in the foreground when it arrived.
    // Handles BOTH shapes: a real `notification` block (title/body used
    // directly), and a data-only push (no `notification` block at all —
    // this used to just `return` and show nothing for that case, silently
    // dropping any data-only push that arrived while the app was open).
    FirebaseMessaging.onMessage.listen((message) {
      // ═══ Same WASFA_PUSH log as the background handler — grep logcat
      // for this while the app is OPEN and a push arrives, to see the
      // real payload shape in this app state too.
      debugPrint('WASFA_PUSH [foreground] notification=${message.notification != null ? '{title: ${message.notification!.title}, body: ${message.notification!.body}}' : 'null'} data=${message.data}');
      final n = message.notification;
      final title = n?.title ?? message.data['title']?.toString() ?? 'WASFA';
      final body = n?.body ?? message.data['body']?.toString() ?? message.data['message']?.toString() ?? '';
      if (body.isEmpty) return; // nothing meaningful to show either way
      _local.show(
        message.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(_channel.id, _channel.name, channelDescription: _channel.description, importance: Importance.high),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: jsonEncode(message.data),
      );
      NotificationHistoryStore.instance.add(title: title, body: body, data: message.data);
    });

    // Tapped while the app was backgrounded (not terminated).
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('WASFA_PUSH [tapped: was backgrounded] data=${message.data}');
      _handleDeepLink(message.data);
    });

    // App was fully terminated and got opened by tapping the notification.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      debugPrint('WASFA_PUSH [tapped: was terminated] data=${initial.data}');
      _handleDeepLink(initial.data);
    }

    // The OS can rotate the token at any time (not just once) — re-send it
    // whenever that happens, for whichever user was last registered.
    FirebaseMessaging.instance.onTokenRefresh.listen((_) {
      final uid = _pendingUserId;
      if (uid != null) registerTokenForUser(uid);
    });
  }

  /// Call after login and after restoring a saved session (see
  /// AuthState.verifyOtp/.restore) so this device's FCM token is associated
  /// with the signed-in user — without this, the backend has no way to
  /// target a push at them. Best-effort: swallows failures (e.g. the
  /// endpoint not existing yet) since push setup should never block sign-in
  /// or app usage.
  Future<void> registerTokenForUser(int userId) async {
    _pendingUserId = userId;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await AccountService.instance.registerFcmToken(userId, token);
    } catch (_) {
      // Non-fatal — see doc above.
    }
  }

  /// Call on sign-out so a stale user id doesn't get re-attached to a
  /// refreshed token for whoever's using the device next.
  void clearRegisteredUser() => _pendingUserId = null;

  /// ✅ Confirmed live (2026-07-28, real logcat output) — the actual
  /// payload shapes, finally not a guess:
  /// ```
  /// order:       {order_code: "APM169", type: "order", order_id: 183, status: "collecting"}
  /// prescription: {prescription_id: "ADM119-1785215450", type: "prescription"}
  /// ```
  /// Both `type` values and both reference field names (`order_code`,
  /// `prescription_id`) were wrong before (`order_status`/`new_rx`/generic
  /// `id`) — fixed to match exactly. `order_id` (183, a numeric internal
  /// id) is NOT what `Routes.track` wants — that route needs the order's
  /// CODE (`order_code`, "APM169"), same as everywhere else in this app.
  void _handleDeepLink(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    debugPrint('WASFA_PUSH [_handleDeepLink] type="$type" data=$data');
    final nav = navigatorKey.currentState;
    if (nav == null) {
      debugPrint('WASFA_PUSH [_handleDeepLink] NOT navigating — navigatorKey.currentState is null (app not fully attached yet).');
      return;
    }
    switch (type) {
      case 'order':
        final orderCode = data['order_code'] as String?;
        if (orderCode == null || orderCode.isEmpty) {
          debugPrint('WASFA_PUSH [_handleDeepLink] NOT navigating — type="order" but order_code missing/empty.');
          return;
        }
        debugPrint('WASFA_PUSH [_handleDeepLink] → Routes.track, arguments: $orderCode');
        nav.pushNamed(Routes.track, arguments: orderCode);
        break;
      case 'prescription':
        final prescriptionId = data['prescription_id'] as String?;
        if (prescriptionId == null || prescriptionId.isEmpty) {
          debugPrint('WASFA_PUSH [_handleDeepLink] NOT navigating — type="prescription" but prescription_id missing/empty.');
          return;
        }
        debugPrint('WASFA_PUSH [_handleDeepLink] → Routes.rxDetail, arguments: $prescriptionId');
        nav.pushNamed(Routes.rxDetail, arguments: prescriptionId);
        break;
      default:
        // Unknown type — nothing to navigate to yet; the notification's
        // own title/body still showed, so this is a silent no-op rather
        // than an error.
        debugPrint('WASFA_PUSH [_handleDeepLink] NOT navigating — type="$type" doesn\'t match "order" or "prescription".');
        break;
    }
  }
}
