import 'package:flutter/foundation.dart';
import '../data/services/catalog_service.dart';

/// Drives which payment methods show at Checkout, meant to be controlled
/// from the dashboard's "App settings" (see `ApiConfig.appSettings` — this
/// is PROPOSED, not a confirmed live endpoint; there is currently no
/// backend support for this at all). Defaults to all four methods enabled
/// so Checkout doesn't silently lose payment options while that endpoint
/// doesn't exist yet, hasn't loaded, or fails.
///
/// CURRENTLY DISABLED: `.load()` is intentionally not called anywhere
/// (main.dart just constructs this without it) — the team's checkout API
/// is being built separately and will provide payment-method details once
/// ready. Wire `.load()` back in (or point it at whatever that real
/// endpoint turns out to be) then; until that happens this only ever
/// reports the default of all 4 methods enabled.
class AppSettingsState extends ChangeNotifier {
  final CatalogService _service = CatalogService.instance;

  static const List<String> allPaymentMethods = ['knet', 'card', 'wallet', 'cod'];

  List<String> enabledPaymentMethods = allPaymentMethods;
  bool _loaded = false;

  /// Feeds in payment-method availability from the checkout-init endpoint
  /// (`GET /app/checkout`), which is a real, confirmed source — unlike
  /// `/app/settings` above. Called from the Checkout screen once that
  /// fetch succeeds; falls back to all 4 enabled if the list comes back
  /// empty, same safety net as [load].
  void applyFromCheckout(List<String> keys) {
    enabledPaymentMethods = keys.isNotEmpty ? keys : allPaymentMethods;
    notifyListeners();
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final methods = await _service.paymentMethods();
      // Ignore unknown keys the dashboard might send, and never end up with
      // zero payment methods even if the response is malformed/empty.
      final filtered = methods.where(allPaymentMethods.contains).toList();
      if (filtered.isNotEmpty) {
        enabledPaymentMethods = filtered;
        notifyListeners();
      }
    } catch (_) {
      // Endpoint doesn't exist yet / failed — keep all four enabled.
    }
  }
}
