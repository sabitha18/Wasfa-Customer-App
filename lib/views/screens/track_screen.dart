import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/services/order_service.dart';
import '../../state/auth_state.dart';
import '../../state/locale_state.dart';
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
  String? _riderName;
  String? _riderPhone;
  String? _vehicleType;
  String? _plateNumber;
  String? _eta;
  double? _lat;
  double? _lng;
  Timer? _poll;
  GoogleMapController? _mapController;

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
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    final phone = context.read<AuthState>().user?.phone ?? '';
    try {
      final info = await _service.track(widget.orderId, mobile: phone);
      if (!mounted) return;
      setState(() {
        _liveStatus = info.status;
        _riderName = info.riderName;
        _riderPhone = info.riderPhone;
        _vehicleType = info.vehicleType;
        _plateNumber = info.plateNumber;
        _eta = info.eta;
        _lat = info.lat;
        _lng = info.lng;
        _error = null;
      });
      // Keep the shared OrdersState in sync so Orders/Order Detail screens
      // reflect the same status without a separate fetch.
      final o = context.read<OrdersState>().byId(widget.orderId);
      if (o != null) o.status = info.status;
      // Nudge the camera to the rider's latest position once we have one.
      if (_lat != null && _lng != null && _mapController != null) {
        _mapController!.animateCamera(CameraUpdate.newLatLng(LatLng(_lat!, _lng!)));
      }
    } catch (e) {
      if (!mounted) return;
      // Was hardcoded to a generic "couldn't refresh" message before,
      // which threw away real, specific, actionable server messages like
      // "Mobile number does not match this order" — the person had no way
      // to know THAT was the actual problem, just that tracking was
      // broken somehow. describeError surfaces what the server actually
      // said (ApiClient already throws with the real `msg`/`message`
      // field for any `{ok:false}` response, including this one).
      setState(() => _error = silent ? _error : describeError(e));
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = context.watch<LocaleState>().isArabic;
    String t(String en, String arabic) => ar ? arabic : en;
    // Was `orders.byId(widget.orderId) ?? orders.orders.first` — crashed
    // with "Bad state: No element" whenever OrdersState.orders was empty
    // (e.g. navigating here straight from a push notification tap, before
    // ever visiting the Orders list screen this session — nothing had
    // populated that list yet) AND, separately, ran on literally every
    // build including the very first frame before _fetch() had even
    // returned, so it could crash before there was any data at all. Worse,
    // even when non-empty, `.first` would silently show a random,
    // UNRELATED order rather than the one actually being tracked. Tracing
    // every use of `order.*` in this whole file shows only `.id` (always
    // just widget.orderId — this screen never needed a full cached Order
    // at all) and `.status` (already overridden by the fresher _liveStatus
    // from this screen's own /track fetch in nearly every real case) —
    // so there was never really a need to reach into OrdersState.orders
    // for rendering here in the first place.
    final status = _liveStatus ?? 'prep';
    final labels = [
      t('Order confirmed', 'تم تأكيد الطلب'),
      t('Preparing your order', 'جارٍ تحضير طلبك'),
      t('On the way', 'في الطريق'),
      t('Delivered', 'تم التوصيل'),
    ];
    final idx = {'conf': 0, 'prep': 1, 'way': 2, 'done': 3}[status] ?? 1;

    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
      backgroundColor: AppColors.bg,
      appBar: PageHeader(title: '${t("Track order", "تتبع الطلب")} · ${widget.orderId}'),
      body: _loading
          ? LoadingView(message: t('Loading tracking…', 'جارٍ تحميل التتبع…'))
          : RefreshIndicator(
        onRefresh: _fetch,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            if (_error != null) InlineErrorBanner(message: _error!, onRetry: _fetch),
            // ── .map — live rider location, only shown once the order is
            // actually on the way. Before that (and after delivery) there's
            // nothing real to show, so we show a status card instead of a
            // fake/static map.
            _TrackMapArea(status: status, lat: _lat, lng: _lng, onMapCreated: (c) => _mapController = c),

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
                  child: Text(_riderInitials(_riderName), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_riderName ?? (status == 'way' ? t('Rider', 'السائق') : t('Not assigned yet', 'لم يُعيَّن بعد')),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.navy)),
                      const SizedBox(height: 1),
                      // Real vehicle info (confirmed live on the driver
                      // object) — but only shown once a rider is actually
                      // known. Right after checkout, no driver is assigned
                      // yet at all, and this used to still show "Express
                      // Rider" here regardless — directly under "Not
                      // assigned yet" on the line above, reading like a
                      // contradiction (a specific rider sounds assigned
                      // when none is).
                      if (_riderName != null)
                        Text(
                          _vehicleLabel(ar),
                          style: const TextStyle(fontSize: 11.5, color: AppColors.sky, fontWeight: FontWeight.w600),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        _eta != null ? '${widget.orderId} · ${t("Arriving in ~$_eta", "يصل خلال ~$_eta")}' : widget.orderId,
                        style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _callRider(context),
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
                  child: Text(t('Home', 'الرئيسية'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  String _riderInitials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  /// e.g. "Motorbike · 123R", or just "Motorbike"/"123R" if only one of the
  /// two is known, falling back to a generic label if a rider is assigned
  /// but neither vehicle field came through.
  String _vehicleLabel(bool ar) {
    final type = _vehicleType?.trim();
    final plate = _plateNumber?.trim().toUpperCase();
    final hasType = type != null && type.isNotEmpty;
    final hasPlate = plate != null && plate.isNotEmpty;
    if (hasType && hasPlate) return '${type[0].toUpperCase()}${type.substring(1)} · $plate';
    if (hasType) return '${type[0].toUpperCase()}${type.substring(1)}';
    if (hasPlate) return plate;
    return ar ? 'سائق التوصيل' : 'Express Rider';
  }

  /// Was just `showToast(context, 'Calling rider…')` — a fake toast that
  /// never actually called anyone, regardless of whether a rider was even
  /// assigned. Now places a real call via `tel:` when there's a real
  /// number, and says so honestly when there isn't, instead of pretending
  /// to dial.
  ///
  /// NEEDS `url_launcher` ADDED TO pubspec.yaml — this file's session only
  /// has access to `lib/`, not the project root, so that dependency
  /// couldn't be added directly here. Run `flutter pub add url_launcher`.
  Future<void> _callRider(BuildContext context) async {
    final ar = context.read<LocaleState>().isArabic;
    final phone = _riderPhone;
    if (phone == null || phone.trim().isEmpty) {
      showToast(context, ar ? 'رقم هاتف السائق غير متوفر بعد.' : 'No rider phone number available yet.');
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final launched = await launchUrl(uri);
      if (!launched && context.mounted) showErrorToast(context, ar ? 'تعذر فتح تطبيق الاتصال.' : 'Couldn\'t open the phone dialer.');
    } catch (_) {
      if (context.mounted) showErrorToast(context, ar ? 'تعذر فتح تطبيق الاتصال.' : 'Couldn\'t open the phone dialer.');
    }
  }
}

// ── .map — live rider location once the order is on the way; a plain
// status card the rest of the time (nothing real to show before/after that
// window, so we don't fake it).
class _TrackMapArea extends StatelessWidget {
  final String status; // conf, prep, way, done
  final double? lat;
  final double? lng;
  final ValueChanged<GoogleMapController> onMapCreated;

  const _TrackMapArea({required this.status, required this.lat, required this.lng, required this.onMapCreated});

  @override
  Widget build(BuildContext context) {
    final ar = context.watch<LocaleState>().isArabic;
    if (status == 'way' && lat != null && lng != null) {
      return SizedBox(
        height: 210,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: LatLng(lat!, lng!), zoom: 15),
          onMapCreated: onMapCreated,
          markers: {
            Marker(
              markerId: const MarkerId('rider'),
              position: LatLng(lat!, lng!),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
              infoWindow: InfoWindow(title: ar ? 'سائقك' : 'Your rider'),
            ),
          },
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          liteModeEnabled: false,
        ),
      );
    }

    // status == 'way' but the backend hasn't sent a location yet, or the
    // order isn't on the way (yet, or anymore) — show a plain status card
    // instead of any map.
    final String message;
    final IconData icon;
    switch (status) {
      case 'way':
        message = ar ? 'بانتظار الموقع المباشر لسائقك…' : 'Waiting for your rider\'s live location…';
        icon = Icons.my_location_rounded;
        break;
      case 'done':
        message = ar ? 'تم التوصيل — شكراً لطلبك من وصفة!' : 'Delivered — thanks for ordering with WASFA!';
        icon = Icons.check_circle_rounded;
        break;
      default:
        message = ar ? 'سيظهر موقع السائق المباشر هنا بمجرد أن يكون طلبك في الطريق.' : 'Live driver location will appear here once your order is on the way.';
        icon = Icons.local_shipping_rounded;
    }

    return Container(
      height: 150,
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(15), border: Border.all(color: AppColors.line)),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.sky, size: 28),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w600)),
        ],
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
