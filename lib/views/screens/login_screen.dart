import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../core/theme/app_colors.dart';
import '../../state/auth_state.dart';
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
  const LoginScreen({super.key});

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
    final local = _phoneCtrl.text.trim();
    if (local.length < 8) {
      showErrorToast(context, 'Enter a valid 8-digit phone number.');
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
        showToast(context, 'Dev code ${auth.devOtpCode} auto-filled below');
      } else {
        showToast(context, 'A verification code was sent to $_fullPhone');
      }
    } else {
      showErrorToast(context, auth.otpError ?? 'Couldn\'t send the code.');
    }
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length < 4) {
      showErrorToast(context, 'Enter the 4-digit code.');
      return;
    }
    final auth = context.read<AuthState>();
    final ok = await auth.verifyOtp(code: code, name: _nameCtrl.text.trim());
    if (!mounted) return;
    if (ok) {
      showToast(context, 'Welcome${auth.user?.name.isNotEmpty == true ? ', ${auth.user!.name}' : ''}!');
      Navigator.of(context).pop(true);
    } else {
      showErrorToast(context, auth.otpError ?? 'Incorrect code, please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
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
              Text(
                _codeSent ? 'Enter verification code' : 'Sign in to WASFA',
                style: const TextStyle(color: AppColors.navy, fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                _codeSent
                    ? 'We sent a 4-digit code to $_fullPhone'
                    : 'Enter your mobile number — we\'ll text you a one-time code.',
                style: const TextStyle(color: AppColors.muted, fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 28),
              if (!_codeSent) ..._phoneStep(auth) else ..._otpStep(auth),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _phoneStep(AuthState auth) => [
        _phoneField(),
        const SizedBox(height: 20),
        _primaryButton(
          label: 'Send code',
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

  List<Widget> _otpStep(AuthState auth) => [
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
                  'Testing mode — code is ${auth.devOtpCode}',
                  style: const TextStyle(color: Color(0xFF8A6D00), fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ]),
          ),
        _field(controller: _codeCtrl, hint: '1234', keyboardType: TextInputType.number, icon: Icons.lock_outline_rounded, maxLength: 4),
        const SizedBox(height: 14),
        _field(controller: _nameCtrl, hint: 'Your name (first time only)', icon: Icons.person_outline_rounded),
        const SizedBox(height: 20),
        _primaryButton(
          label: 'Verify & continue',
          loading: auth.otpVerifying,
          onTap: _verify,
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: _resendIn > 0 ? null : _sendCode,
            child: Text(
              _resendIn > 0 ? 'Resend code in ${_resendIn}s' : 'Resend code',
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
