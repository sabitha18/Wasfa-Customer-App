import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:go_sell_sdk_flutter/go_sell_sdk_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:go_sell_sdk_flutter/model/models.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../../core/utils/json_utils.dart';

/// What Tap itself says about a charge, from [TapPaymentService.verifyCharge].
/// `captured` is the ONLY state where money has actually moved (Tap's own
/// docs); `pending` means it never reached a final state inside the wait
/// window — NOT the same as failed.
enum TapChargeOutcome { captured, failed, pending }

/// Outcome of a single [TapPaymentService.payWithKnet] attempt.
class TapPaymentResult {
  final bool success;
  final String? chargeId;
  final String? errorMessage;
  /// The SDK session ended via the plugin's `sessionCancelled()` callback
  /// (`sdk_result: "CANCELLED"`, no charge id in the map at all) — e.g.
  /// the customer backed out of the KNET page. NOT proof that nothing was
  /// charged: a KNET payment can complete at the bank/Tap while the
  /// session still ends this way, and with no charge id there's nothing
  /// to verify it against. See checkout_screen.dart for how that's handled.
  final bool cancelled;
  const TapPaymentResult({required this.success, this.chargeId, this.errorMessage, this.cancelled = false});
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

  /// Build-time switch for payment diagnostics on devices that can't be
  /// plugged into a PC (a client testing an APK): build the test APK with
  /// `--dart-define=PAYMENT_DEBUG=true` and the cancelled/failed/pending
  /// payment screens also show — and can copy — the raw SDK result and the
  /// Tap status check. Off in normal builds, so customers never see it.
  static const bool paymentDebug = bool.fromEnvironment('PAYMENT_DEBUG');

  /// Raw result of the most recent attempt + what Tap said about it. Only
  /// ever shown when [paymentDebug] is on.
  String lastDiagnostics = '';

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
    // Confirmed (2026-09-23): this app is now meant to process live
    // payments. Was hardcoded `= true`, meaning every KNET payment through
    // this app — including any real release build a customer actually
    // uses — went through Tap's sandbox unconditionally, regardless of
    // anything the server sent. Tied to the build mode instead: debug
    // builds (day-to-day development/testing) stay in sandbox
    // automatically, and any release build — including one just installed
    // for manual testing, not just a Play Store release — now goes
    // through Tap's LIVE mode and can charge a real card for real money.
    bool sandbox = kDebugMode,
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
      // Real incident (2026-09-28): a live KNET charge actually succeeded
      // (money left the customer's account, confirmed against their bank
      // statement) but this switch's old `default:` branch discarded
      // `charge_id` entirely and reported plain failure with NO
      // transaction id at all — leaving nothing on either side (this app
      // or the backend) to trace that specific charge back to what Tap
      // actually recorded. Logging the full raw result now so a repeat of
      // this is actually diagnosable instead of a guess, and every branch
      // below — including the catch-all — keeps whatever charge_id/message
      // is present rather than silently dropping it.
      debugPrint('goSellSDK result: $result');
      lastDiagnostics = '${DateTime.now().toIso8601String()} | ${sandbox ? 'SANDBOX' : 'LIVE'} | order ${orderCode ?? '-'}\nSDK result: $result';

      switch (result['sdk_result']) {
        case 'SUCCESS':
          return TapPaymentResult(success: true, chargeId: result['charge_id']?.toString());
        case 'FAILED':
          return TapPaymentResult(success: false, chargeId: result['charge_id']?.toString(), errorMessage: result['message']?.toString());
        case 'SDK_ERROR':
          return TapPaymentResult(success: false, chargeId: result['charge_id']?.toString(), errorMessage: result['sdk_error_message']?.toString() ?? 'Payment error occurred.');
        // Documented by Tap as a real, distinct SDK result (not something
        // this app's own logic can trigger) — e.g. a payment method the
        // current platform doesn't support. Kept separate from the
        // catch-all below since it's a confirmed, named case, not an
        // unknown one.
        // Confirmed against the plugin's own source (go_sell_sdk_flutter
        // 2.4.29, GoSellSdKDelegate.sessionCancelled): this is exactly what
        // it reports when the session is cancelled, with NO charge_id. The
        // app had no case for it, so it fell into the catch-all below and
        // showed "Payment was not completed." — the text the customer saw
        // in the real incident where Tap's dashboard showed the charge
        // Captured.
        case 'CANCELLED':
          return const TapPaymentResult(success: false, cancelled: true);
        case 'NOT_IMPLEMENTED':
          return TapPaymentResult(success: false, chargeId: result['charge_id']?.toString(), errorMessage: result['message']?.toString() ?? 'This payment method isn\'t available.');
        default:
          // An sdk_result value this app has never seen documented or
          // encountered before — genuinely unclear, NOT the same as a
          // confirmed failure. Still keeps charge_id/message if either is
          // present, since a real charge can exist even when the result
          // shape itself is unrecognized.
          return TapPaymentResult(
            success: false,
            chargeId: result['charge_id']?.toString(),
            errorMessage: result['message']?.toString() ?? 'Payment status unclear — check your bank/Tap dashboard before retrying.',
          );
      }
    } catch (e) {
      return TapPaymentResult(success: false, errorMessage: e.toString());
    }
  }

  /// Only these two end the wait early — matching the old native app
  /// (CheckOutActivity.verifyKnetTransaction), which treated everything
  /// else (INITIATED, ABANDONED, CANCELLED, ...) as "keep polling". More
  /// conservative than declaring other non-captured states final: the
  /// failure mode being guarded against is telling a customer a payment
  /// failed when it actually went through.
  static const _definitiveFailureStatuses = {'FAILED', 'DECLINED'};

  /// Asks Tap directly what actually happened to [chargeId] — the same
  /// resilience check the old native app did (see the class doc, item 2),
  /// which this port had dropped on the assumption the backend would
  /// verify instead. Real incident (2026-10-03): Tap's dashboard showed the
  /// charge as Captured / Paid successfully while the SDK's own result
  /// reached the app as a non-success, so the app reported failure for
  /// money that had genuinely moved. For redirect-based methods like KNET,
  /// Tap's docs say the final status is available via webhook or the
  /// retrieve-charge API — the SDK's immediate result isn't guaranteed to
  /// reflect it yet — so this polls briefly (it can lag the redirect by a
  /// few seconds) instead of trusting a single reading.
  ///
  /// Uses the same secret key the SDK is already configured with, in the
  /// same mode as the attempt it's verifying ([sandbox] must match).
  /// Read-only. Longer term, the backend verifying this itself (and a Tap
  /// webhook) is the more robust place for it — this is the app-side net.
  Future<TapChargeOutcome> verifyCharge(
    String chargeId, {
    bool sandbox = kDebugMode,
    // The old native app polled every 5s for up to 24 tries (~2 min).
    // 12 × 5s here: shorter because this only starts after the SDK has
    // already returned, not while the customer is still on the bank page.
    int attempts = 12,
    Duration interval = const Duration(seconds: 5),
  }) async {
    final key = sandbox ? _sandboxSecretKey : _liveSecretKey;
    for (var i = 0; i < attempts; i++) {
      try {
        final res = await http
            .get(Uri.parse('https://api.tap.company/v2/charges/$chargeId'), headers: {'Authorization': 'Bearer $key', 'accept': 'application/json'})
            .timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          final status = (body is Map ? body['status'] : null)?.toString().toUpperCase();
          debugPrint('Tap charge $chargeId status: $status');
          lastDiagnostics += '\nTap check ($chargeId): $status';
          if (status == 'CAPTURED') return TapChargeOutcome.captured;
          if (status != null && _definitiveFailureStatuses.contains(status)) return TapChargeOutcome.failed;
          // INITIATED / IN_PROGRESS / UNKNOWN — not final yet, keep waiting.
        } else {
          debugPrint('Tap charge $chargeId lookup returned HTTP ${res.statusCode}');
        }
      } catch (e) {
        debugPrint('Tap charge $chargeId lookup error: $e'); // network blip — try again
      }
      if (i < attempts - 1) await Future.delayed(interval);
    }
    lastDiagnostics += '\nTap check gave no final status after $attempts tries';
    return TapChargeOutcome.pending;
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
