import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One received push, kept for the in-app notification list.
class AppNotification {
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime receivedAt;
  bool read;

  AppNotification({required this.title, required this.body, this.data = const {}, DateTime? receivedAt, this.read = false})
      : receivedAt = receivedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'title': title,
        'body': body,
        'data': data,
        'receivedAt': receivedAt.toIso8601String(),
        'read': read,
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        data: (json['data'] is Map) ? Map<String, dynamic>.from(json['data'] as Map) : const {},
        receivedAt: DateTime.tryParse(json['receivedAt'] as String? ?? '') ?? DateTime.now(),
        read: json['read'] as bool? ?? false,
      );
}

/// Persisted, on-device notification history — the "notification listing
/// page" the person taps the bell icon to see.
///
/// IMPORTANT — what this is and isn't: there's no confirmed backend
/// endpoint anywhere in this project that returns a person's past
/// notifications (nothing in the Postman collection shows this), so this
/// is built entirely client-side: every push this device actually
/// receives (foreground or background/terminated) gets appended here and
/// persisted locally. That means:
/// - It only shows notifications received AFTER this feature ships on a
///   given device — nothing sent before that, and nothing sent while the
///   app was uninstalled, can ever appear.
/// - It's per-device, not synced across a person's devices, and doesn't
///   survive an uninstall/reinstall (SharedPreferences is cleared with the
///   app's own data).
/// If backend ever adds a real "list my notifications" endpoint, this
/// should be replaced with a real fetch — flag that possibility to Soumya
/// rather than treating this as the permanent design.
class NotificationHistoryStore extends ChangeNotifier {
  NotificationHistoryStore._();
  static final NotificationHistoryStore instance = NotificationHistoryStore._();

  static const _key = 'wasfa_notifications_v1';
  static const _maxStored = 50; // keeps SharedPreferences small; oldest silently drop off

  List<AppNotification> _items = [];
  List<AppNotification> get items => List.unmodifiable(_items);
  int get unreadCount => _items.where((n) => !n.read).length;

  bool _loaded = false;

  /// Call once at app start (see main.dart) — also safe to call again
  /// (e.g. on app resume) to pick up anything a background-isolate push
  /// persisted while this app instance wasn't watching it live.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await refresh();
  }

  /// Unconditionally re-reads from disk, unlike [ensureLoaded]. Needed
  /// because a push received while the app was backgrounded/terminated is
  /// handled in a SEPARATE background isolate (see
  /// firebaseMessagingBackgroundHandler in notification_service.dart) with
  /// its own completely separate instance of this class — the only thing
  /// the two isolates actually share is the underlying SharedPreferences
  /// file, not this object's in-memory state.
  Future<void> refresh() async {
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _items = list.map((e) => AppNotification.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {
        // Corrupt/old-shape data — start fresh rather than crash the app
        // over what's ultimately just a "nice to have" history list.
        _items = [];
      }
    }
    notifyListeners();
  }

  Future<void> add({required String title, required String body, Map<String, dynamic> data = const {}}) async {
    await ensureLoaded();
    _items.insert(0, AppNotification(title: title, body: body, data: data));
    if (_items.length > _maxStored) _items = _items.sublist(0, _maxStored);
    await _persist();
    notifyListeners();
  }

  Future<void> markAllRead() async {
    await ensureLoaded();
    if (_items.every((n) => n.read)) return; // avoid a pointless write+notify
    for (final n in _items) {
      n.read = true;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_items.map((n) => n.toJson()).toList()));
  }
}
