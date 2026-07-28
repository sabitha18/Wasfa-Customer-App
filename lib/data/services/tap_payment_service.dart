import 'package:go_sell_sdk_flutter/go_sell_sdk_flutter.dart';
import 'package:go_sell_sdk_flutter/model/models.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../../core/utils/json_utils.dart';

/// Outcome of a single [TapPaymentService.payWithKnet] attempt.
class TapPaymentResult {
  final bool success;
  final String? chargeId;
  final String? errorMessage;
  const TapPaymentResult({required this.success, this.chargeId, this.errorMessage});
}

/// Ports the native Android app's Tap `goSellSDK` payment flow
/// (`CheckOutActivity.kt`/`MyApplication.kt`) to Flutter using the official
/// `go_sell_sdk_flutter` plugin. The overall shape mirrors the native code
/// closely on purpose — same currency, same 3D-Secure requirement, same
/// "order created first, then paid" sequencing — so behavior stays
/// consistent between platforms.
///
/// KEY SOURCE: unlike the earlier version of this file (which tried to
/// fetch the key from this app's own backend, mirroring the OLD app's
/// `getPaymentkeys` proxy), these are the REAL Tap dashboard keys, supplied
/// directly — hardcoding them here matches Tap's own official usage
/// pattern for every one of their SDKs (Android/iOS/React
/// Native/Flutter all show the secret key hardcoded in `configureApp`
/// directly in their own docs). This is NOT the same risk category as the
/// raw CBK `client_id`/`secret`/`encrp_key` — those encrypt a request your
/// OWN server should be building; this key exists specifically to
/// initialize Tap's mobile SDK client-side.
///
/// ✅ Registered correctly against `kw.wasfa.customer` (2026-07-27) —
/// resolves the earlier bundle-id mismatch (the previous keys were
/// registered against `com.wasfa.app`, the OLD native app's package name).
///
/// STILL NOT CONFIRMED:
/// 1. Whether `knet_config` (`client_id`/`secret`/`encrp_key`/`base_url`)
///    from the checkout-init response has anything to do with this Tap
///    flow at all — it's a different credential shape entirely (see
///    above), so it's most likely unrelated/leftover. Confirm with Soumya.
/// 2. The old app also calls Tap's own REST API directly
///    (`https://api.tap.company/v2/charges/{id}`) using the secret key as
///    a Bearer token, to poll charge status as a resilience fallback. This
///    port intentionally does NOT replicate that direct call —
///    [reportPaymentResponse] instead tells YOUR backend the outcome and
///    lets it verify with Tap server-side if it needs to.
class TapPaymentService {
  TapPaymentService._();
  static final TapPaymentService instance = TapPaymentService._();
  final ApiClient _client = ApiClient.instance;

  // Real Tap dashboard keys, correctly registered against this app's own
  // bundle id (kw.wasfa.customer) — confirmed 2026-07-27.
  static const String _bundleId = 'kw.wasfa.customer';
  static const String _sandboxSecretKey = 'sk_test_gpiIta3fbMAue478DwNQ5HCG';
  static const String _liveSecretKey = 'sk_live_ioIXbOK85AzLyZaRpGseFfHq';

  bool _configured = false;

  /// Call before the first payment attempt. Safe to call repeatedly —
  /// only actually configures the SDK once per app run.
  void configureIfNeeded() {
    if (_configured) return;
    // Confirmed against the ACTUAL installed 2.4.29 source (not the stale
    // README, which shows different — wrong — param names):
    // `configureApp({required productionSecretKey, required
    // sandBoxSecretKey, required bundleId, required lang})`.
    GoSellSdkFlutter.configureApp(
      bundleId: _bundleId,
      productionSecretKey: _liveSecretKey,
      sandBoxSecretKey: _sandboxSecretKey,
      lang: 'en',
    );
    _configured = true;
  }

  /// Runs one KNET payment attempt through Tap's hosted SDK UI and returns
  /// once the person has completed, failed, or cancelled it. Mirrors
  /// `configureSDKSession`/`getCustomer` in the native Kotlin file — but the
  /// param list below is built against the REAL 2.4.29 source
  /// (`sessionConfigurations`), which requires far more than the README
  /// shows (almost every param is `required`, not optional).
  Future<TapPaymentResult> payWithKnet({
    required int userId,
    required double amount,
    required String customerFirstName,
    required String customerEmail,
    required String customerPhone, // local number, no country code — ISD is added separately below
    String customerId = '',
    String? orderCode, // ties the Tap `Reference.order` back to this app's own order, once one exists
    bool sandbox = true, // flip to false once this is confirmed ready for production
  }) async {
    try {
      configureIfNeeded();
      GoSellSdkFlutter.sessionConfigurations(
        trxMode: TransactionMode.PURCHASE,
        transactionCurrency: 'kwd',
        amount: amount, // double, not String — the README's example was wrong for this version
        customer: Customer(
          customerId: customerId,
          email: customerEmail,
          isdNumber: '965',
          number: customerPhone,
          firstName: customerFirstName,
          middleName: '',
          lastName: '',
          // Customer.metaData is a plain String? here, NOT a Map — matches
          // the native app's own `.metadata("external_id=${custId}")`
          // format exactly.
          metaData: 'external_id=$userId',
        ),
        // A single line item standing in for the whole order total, since
        // this checkout doesn't break the order down per-product at the
        // Tap level — it's for the receipt Tap shows, not the amount
        // actually charged (that's `amount` above, exact to 3 decimals).
        // NOTE: PaymentItem.totalAmount is an int (whole KWD, rounded) —
        // a quirk of this SDK version's model, not something this app
        // controls; the real, precise charge is `amount` above regardless.
        paymentItems: [
          PaymentItem(
            name: orderCode != null && orderCode.isNotEmpty ? 'Order $orderCode' : 'WASFA order',
            amountPerUnit: amount,
            quantity: Quantity(value: 1),
            totalAmount: amount.round(),
          ),
        ],
        taxes: const [],
        shippings: const [],
        postURL: '', // no server-side webhook confirmed for this flow yet — payment result is reported via reportPaymentResponse instead
        paymentDescription: orderCode != null && orderCode.isNotEmpty ? 'Payment for order $orderCode' : 'WASFA order payment',
        paymentMetaData: {'external_id': userId.toString()},
        paymentReference: Reference(order: orderCode),
        paymentStatementDescriptor: 'WASFA',
        isUserAllowedToSaveCard: false,
        isRequires3DSecure: true,
        // No receipt SMS/email from Tap directly — this app sends its own
        // order confirmation once `reportPaymentResponse` succeeds.
        receipt: Receipt(false, false),
        // Irrelevant for TransactionMode.PURCHASE, but the SDK still
        // requires a value regardless of trxMode.
        authorizeAction: AuthorizeAction(type: AuthorizeActionType.CAPTURE, timeInHours: 0),
        merchantID: '',
        allowedCadTypes: CardType.ALL,
        cardHolderName: customerFirstName,
        allowsToEditCardHolderName: true,
        allowsToSaveSameCardMoreThanOnce: false,
        // Restricts the SDK's own payment-method list to KNET only, since
        // this app already has its own separate UI for choosing
        // cod/knet/wallet — the native app does the equivalent by only
        // starting this session at all when `paymentTypeStatus == "KNET"`.
        supportedPaymentMethods: const ['knet'],
        paymentType: PaymentType.ALL,
        sdkMode: sandbox ? SDKMode.Sandbox : SDKMode.Production,
      );

      final Map result = await GoSellSdkFlutter.startPaymentSDK;

      switch (result['sdk_result']) {
        case 'SUCCESS':
          return TapPaymentResult(success: true, chargeId: result['charge_id']?.toString());
        case 'FAILED':
          return TapPaymentResult(success: false, chargeId: result['charge_id']?.toString(), errorMessage: result['message']?.toString());
        case 'SDK_ERROR':
          return TapPaymentResult(success: false, errorMessage: result['sdk_error_message']?.toString() ?? 'Payment error occurred.');
        default:
          return const TapPaymentResult(success: false, errorMessage: 'Payment was not completed.');
      }
    } catch (e) {
      return TapPaymentResult(success: false, errorMessage: e.toString());
    }
  }

  /// Tells the backend how the payment went, so it can mark the order
  /// paid/failed. Confirmed live via Postman (2026-07-24):
  /// `POST /order/payment` — form-data `code`, `status` ("success"|
  /// "failed"), `transaction_id`, `payment_id` (optional), `ref_id`
  /// (optional) — returns `{ok, confirmed, msg}`.
  Future<bool> reportPaymentResponse({
    required String orderCode,
    required bool success,
    String? transactionId,
    String? paymentId,
    String? refId,
  }) async {
    final res = await _client.post(ApiConfig.orderPayment, body: {
      'code': orderCode,
      'status': success ? 'success' : 'failed',
      'transaction_id': transactionId ?? '',
      if (paymentId != null && paymentId.isNotEmpty) 'payment_id': paymentId,
      if (refId != null && refId.isNotEmpty) 'ref_id': refId,
    });
    if (res is! Map) return false;
    final map = res.cast<String, dynamic>();
    return asBool(map, const ['ok']) && asBool(map, const ['confirmed']);
  }
}
