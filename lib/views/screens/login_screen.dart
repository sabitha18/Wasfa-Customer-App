import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../core/theme/app_colors.dart';
import '../../state/auth_state.dart';
import '../../state/locale_state.dart';
import '../widgets/toast.dart';
import '../../core/widgets/async_state_view.dart';

/// Two-step phone + OTP login. Pushed with `Navigator.pushNamed(Routes.login)`
/// and pops `true` on success, `false`/null if the user backs out — callers
/// that gate an action on being signed in should check the result:
///
/// ```dart
/// final ok = await Navigator.pushNamed(context, Routes.login);
/// if (ok == true) { /* proceed */ }
/// ```
class LoginScreen extends StatefulWidget {
  /// Optional line shown at the top explaining why login is needed — e.g.
  /// "Log in to complete your order" when opened from the cart's Checkout.
  /// Null everywhere else, so other entry points look the same as before.
  final String? message;
  const LoginScreen({super.key, this.message});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Kuwaiti numbers need the country code for the SMS gateway to route
  // correctly — the person only ever types their local 8-digit number.
  static const _countryCode = '+965';

  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _codeSent = false;
  int _resendIn = 0;
  Timer? _timer;

  String get _fullPhone => '$_countryCode${_phoneCtrl.text.trim()}';

  @override
  void dispose() {
    _timer?.cancel();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _resendIn = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _sendCode() async {
    final ar = context.read<LocaleState>().isArabic;
    final local = _phoneCtrl.text.trim();
    if (local.length < 8) {
      showErrorToast(context, ar ? 'أدخل رقم هاتف صحيح مكوّن من 8 أرقام.' : 'Enter a valid 8-digit phone number.');
      return;
    }
    final auth = context.read<AuthState>();
    final ok = await auth.requestOtp(_fullPhone);
    if (!mounted) return;
    if (ok) {
      setState(() => _codeSent = true);
      _startResendTimer();
      if (auth.devOtpCode != null && kDebugMode) {
        _codeCtrl.text = auth.devOtpCode!;
        showToast(context, ar ? 'تم تعبئة رمز الاختبار ${auth.devOtpCode} تلقائياً أدناه' : 'Dev code ${auth.devOtpCode} auto-filled below');
      } else {
        showToast(context, ar ? 'تم إرسال رمز التحقق إلى $_fullPhone' : 'A verification code was sent to $_fullPhone');
      }
    } else {
      showErrorToast(context, auth.otpError ?? (ar ? 'تعذر إرسال الرمز.' : 'Couldn\'t send the code.'));
    }
  }

  Future<void> _verify() async {
    final ar = context.read<LocaleState>().isArabic;
    final code = _codeCtrl.text.trim();
    if (code.length < 6) {
      showErrorToast(context, ar ? 'أدخل الرمز المكوّن من 6 أرقام.' : 'Enter the 6-digit code.');
      return;
    }
    final auth = context.read<AuthState>();
    final ok = await auth.verifyOtp(code: code, name: _nameCtrl.text.trim());
    if (!mounted) return;
    if (ok) {
      final hasName = auth.user?.name.isNotEmpty == true;
      showToast(context, ar ? 'مرحباً${hasName ? '، ${auth.user!.name}' : ''}!' : 'Welcome${hasName ? ', ${auth.user!.name}' : ''}!');
      Navigator.of(context).pop(true);
    } else {
      showErrorToast(context, auth.otpError ?? (ar ? 'رمز غير صحيح، حاول مرة أخرى.' : 'Incorrect code, please try again.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final ar = context.watch<LocaleState>().isArabic;
    String t(String en, String arabic) => ar ? arabic : en;
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(ar ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded, color: AppColors.navy),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              if (widget.message != null && !_codeSent)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: AppColors.benefitPillBg, borderRadius: BorderRadius.circular(12)),
                  child: Text(widget.message!, style: const TextStyle(color: AppColors.navy, fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
              Text(
                _codeSent ? t('Enter verification code', 'أدخل رمز التحقق') : t('Sign in to WASFA', 'تسجيل الدخول إلى وصفة'),
                style: const TextStyle(color: AppColors.navy, fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                _codeSent
                    ? t('We sent a 6-digit code to $_fullPhone', 'أرسلنا رمزاً مكوّناً من 6 أرقام إلى $_fullPhone')
                    : t('Enter your mobile number — we\'ll text you a one-time code.', 'أدخل رقم هاتفك — سنرسل لك رمزاً لمرة واحدة عبر رسالة نصية.'),
                style: const TextStyle(color: AppColors.muted, fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 28),
              if (!_codeSent) ..._phoneStep(auth, t) else ..._otpStep(auth, t),
            ],
          ),
        ),
      ),
      ),
    );
  }

  List<Widget> _phoneStep(AuthState auth, String Function(String, String) t) => [
        _phoneField(),
        const SizedBox(height: 20),
        _primaryButton(
          label: t('Send code', 'إرسال الرمز'),
          loading: auth.otpSending,
          onTap: _sendCode,
        ),
      ];

  Widget _phoneField() {
    return Container(
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(_countryCode, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 14.5)),
          ),
          Container(margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 12), width: 1.2, height: 20, color: AppColors.line),
          Expanded(
            child: TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                counterText: '',
                hintText: '5000 0000',
                hintStyle: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w500),
                filled: false,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _otpStep(AuthState auth, String Function(String, String) t) => [
        if (auth.devOtpCode != null && kDebugMode)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF6D9),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: const Color(0xFFE8CE5C)),
            ),
            child: Row(children: [
              const Icon(Icons.bug_report_outlined, size: 17, color: Color(0xFF8A6D00)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t('Testing mode — code is ${auth.devOtpCode}', 'وضع الاختبار — الرمز هو ${auth.devOtpCode}'),
                  style: const TextStyle(color: Color(0xFF8A6D00), fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ]),
          ),
        _field(controller: _codeCtrl, hint: '123456', keyboardType: TextInputType.number, icon: Icons.lock_outline_rounded, maxLength: 6),
        const SizedBox(height: 14),
        // Only ask for a name if this looks like a first-time signup, or
        // the backend hasn't told us otherwise yet (auth.isNewUser
        // defaults to true) — an existing person with a known name never
        // sees this field, so there's nothing here to overwrite their
        // saved name with (verifyOtp only sends `name` when it's
        // non-empty, and this controller stays empty when the field is
        // never shown).
        if (auth.isNewUser || (auth.knownName?.isEmpty ?? true))
          _field(controller: _nameCtrl, hint: t('Your name (first time only)', 'اسمك (لأول مرة فقط)'), icon: Icons.person_outline_rounded)
        else
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
            decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Icon(Icons.waving_hand_rounded, color: AppColors.sky, size: 20),
                const SizedBox(width: 10),
                Text(t('Welcome back, ${auth.knownName}', 'مرحباً بعودتك، ${auth.knownName}'), style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 14.5)),
              ],
            ),
          ),
        const SizedBox(height: 20),
        _primaryButton(
          label: t('Verify & continue', 'تحقق ومتابعة'),
          loading: auth.otpVerifying,
          onTap: _verify,
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: _resendIn > 0 ? null : _sendCode,
            child: Text(
              _resendIn > 0 ? t('Resend code in ${_resendIn}s', 'إعادة الإرسال خلال $_resendIn ثانية') : t('Resend code', 'إعادة إرسال الرمز'),
              style: TextStyle(
                color: _resendIn > 0 ? AppColors.muted : AppColors.sky,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ];

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w500),
        prefixIcon: Icon(icon, color: AppColors.muted, size: 20),
        filled: true,
        fillColor: AppColors.bg,
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.sky, width: 1.5)),
        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.danger)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.danger, width: 1.5)),
      ),
    );
  }

  Widget _primaryButton({required String label, required bool loading, required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.navy,
          disabledBackgroundColor: AppColors.navy.withOpacity(.6),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: loading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ),
    );
  }
}
