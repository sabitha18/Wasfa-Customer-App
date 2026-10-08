import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/models/app_user.dart';
import '../../data/services/auth_service.dart';
import '../../state/auth_state.dart';
import '../../state/locale_state.dart';
import '../widgets/page_header.dart';
import '../widgets/toast.dart';

/// Matches the HTML's `rProfile()`:
/// - `.phead` — back + "Profile" title (t('profile_title')) → [PageHeader].
/// - `.prof-hero` — circular gradient avatar (✅ photo upload confirmed live
///   2026-09-28 — see the camera-button/[_pickPhoto] note below; falls back
///   to the initial-letter avatar until a real photo exists) + name +
///   "age · sex · blood type" subtitle.
/// - Three `.prof-card`s — "Personal information", "Health information",
///   "Emergency contact" — each a bordered white card with a section label
///   and `.afield`/`.arow` inputs.
/// - "Reset password" (`.btn-out`) opens the same 3-field bottom sheet as
///   `openResetPw()`/`doResetPw()` — client-side only in the HTML (no real
///   backend call), replicated the same way here since there's no password
///   concept in this app's OTP-based auth to begin with.
/// - "Save profile" (`.btn-primary`) → `saveProfileForm()`.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _civilId;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _nationality;
  late final TextEditingController _weight;
  late final TextEditingController _height;
  late final TextEditingController _emergName;
  late final TextEditingController _emergRel;
  late final TextEditingController _emergPhone;
  DateTime? _dob;
  String? _gender; // 'Male' | 'Female' | 'Other'
  String? _bloodType;
  bool _saving = false;
  // Local file, picked but not yet uploaded — uploads together with the
  // rest of the form on "Save profile" (see saveProfile's imagePath).
  File? _pickedImage;

  static const _bloodTypes = ['O+', 'O-', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-'];

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthState>().user;
    // One field, matching what the API actually stores/returns — a
    // single combined `name`, not separate first/last. Splitting that
    // into two boxes and re-splitting on every server refresh was lossy
    // and was silently wiping out whatever was typed as a last name.
    _name = TextEditingController(text: user?.name ?? '');
    _civilId = TextEditingController(text: user?.civilId ?? '');
    _email = TextEditingController(text: user?.email ?? '');
    _phone = TextEditingController(text: Formatters.localPhone(user?.phone ?? ''));
    _nationality = TextEditingController(text: user?.nationality ?? '');
    _weight = TextEditingController(text: user?.weight?.toString() ?? '');
    _height = TextEditingController(text: user?.height?.toString() ?? '');
    _emergName = TextEditingController(text: user?.emergName ?? '');
    _emergRel = TextEditingController(text: user?.emergRel ?? '');
    _emergPhone = TextEditingController(text: user?.emergPhone ?? '');
    _dob = user?.dob != null ? DateTime.tryParse(user!.dob!) : null;
    _gender = user?.gender;
    _bloodType = user?.bloodType;
    // The form is instantly populated from whatever's cached locally above;
    // this then fetches the real, current profile from the server (now
    // confirmed live) and refreshes everything once it lands, so the
    // screen doesn't just show stale on-device data indefinitely.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFromServer());
  }

  /// Fills the form from [user]. initState only does this once, at creation —
  /// so when someone signs in FROM this screen (it was opened signed out, so
  /// the fields were created empty), the form has to be filled again here.
  void _fillFromUser(AppUser? user) {
    if (user == null) return;
    setState(() {
      _name.text = user.name;
      _civilId.text = user.civilId ?? '';
      _email.text = user.email ?? '';
      _phone.text = Formatters.localPhone(user.phone);
      _nationality.text = user.nationality ?? '';
      _weight.text = user.weight?.toString() ?? '';
      _height.text = user.height?.toString() ?? '';
      _emergName.text = user.emergName ?? '';
      _emergRel.text = user.emergRel ?? '';
      _emergPhone.text = user.emergPhone ?? '';
      _dob = user.dob != null ? DateTime.tryParse(user.dob!) : null;
      _gender = user.gender;
      _bloodType = user.bloodType;
    });
  }

  Future<void> _loadFromServer() async {
    final auth = context.read<AuthState>();
    if (!auth.isSignedIn) return;
    try {
      final fresh = await AuthService.instance.fetchProfile(auth.userId!);
      if (!mounted) return;
      await auth.refreshUser(fresh);
      if (!mounted) return;
      setState(() {
        if (fresh.name.isNotEmpty) _name.text = fresh.name;
        if (fresh.civilId != null) _civilId.text = fresh.civilId!;
        if (fresh.email != null) _email.text = fresh.email!;
        if (fresh.phone.isNotEmpty) _phone.text = Formatters.localPhone(fresh.phone);
        if (fresh.nationality != null) _nationality.text = fresh.nationality!;
        if (fresh.weight != null) _weight.text = fresh.weight!.toString();
        if (fresh.height != null) _height.text = fresh.height!.toString();
        if (fresh.emergName != null) _emergName.text = fresh.emergName!;
        if (fresh.emergRel != null) _emergRel.text = fresh.emergRel!;
        if (fresh.emergPhone != null) _emergPhone.text = fresh.emergPhone!;
        if (fresh.dob != null) _dob = DateTime.tryParse(fresh.dob!) ?? _dob;
        if (fresh.gender != null) _gender = fresh.gender;
        if (fresh.bloodType != null) _bloodType = fresh.bloodType;
      });
    } catch (_) {
      // Best-effort — keep showing whatever was already cached locally.
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _civilId.dispose();
    _email.dispose();
    _phone.dispose();
    _nationality.dispose();
    _weight.dispose();
    _height.dispose();
    _emergName.dispose();
    _emergRel.dispose();
    _emergPhone.dispose();
    super.dispose();
  }

  int? get _age {
    if (_dob == null) return null;
    final now = DateTime.now();
    var age = now.year - _dob!.year;
    if (now.month < _dob!.month || (now.month == _dob!.month && now.day < _dob!.day)) age--;
    return age;
  }

  String _profInitial() {
    final auth = context.read<AuthState>().user;
    final n = auth?.name.trim() ?? '';
    return n.isNotEmpty ? n[0].toUpperCase() : '?';
  }

  /// Gallery, not camera directly — matches the existing pattern this app
  /// already uses for the same choice elsewhere (return-request photos),
  /// and avoids needing a separate camera permission prompt just for this.
  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1024);
    if (picked != null) setState(() => _pickedImage = File(picked.path));
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 110),
      lastDate: now,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    final ar = context.read<LocaleState>().isArabic;
    final auth = context.read<AuthState>();
    if (!auth.isSignedIn) return;
    if (_name.text.trim().isEmpty) {
      showErrorToast(context, ar ? 'يرجى إدخال اسمك.' : 'Please enter your name.');
      return;
    }
    // The save API still wants first_name/last_name as two separate keys
    // (confirmed in the Postman collection) — split only here, right at
    // the point of sending, so the UI itself stays a single field.
    final nameParts = _name.text.trim().split(RegExp(r'\s+'));
    final firstName = nameParts.first;
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
    setState(() => _saving = true);
    try {
      final updated = await AuthService.instance.saveProfile(
        userId: auth.userId!,
        firstName: firstName,
        lastName: lastName,
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : '+965${Formatters.localPhone(_phone.text.trim())}',
        civilId: _civilId.text.trim().isEmpty ? null : _civilId.text.trim(),
        dateOfBirth: _dob != null ? _dob!.toIso8601String().split('T').first : null,
        gender: _gender,
        nationality: _nationality.text.trim().isEmpty ? null : _nationality.text.trim(),
        weight: double.tryParse(_weight.text.trim()),
        height: double.tryParse(_height.text.trim()),
        bloodType: _bloodType,
        emergName: _emergName.text.trim().isEmpty ? null : _emergName.text.trim(),
        emergRel: _emergRel.text.trim().isEmpty ? null : _emergRel.text.trim(),
        emergPhone: _emergPhone.text.trim().isEmpty ? null : _emergPhone.text.trim(),
        imagePath: _pickedImage?.path,
      );
      if (!mounted) return;
      await auth.refreshUser(updated);
      if (!mounted) return;
      showToast(context, ar ? 'تم حفظ الملف الشخصي' : 'Profile saved');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      showErrorToast(context, describeError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openResetPw() {
    final ar = context.read<LocaleState>().isArabic;
    final current = TextEditingController();
    final newPw = TextEditingController();
    final confirm = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => Directionality(
        textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
        child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line, width: 1))),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(ar ? 'إعادة تعيين كلمة المرور' : 'Reset password', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.navy)),
                InkWell(
                  onTap: () => Navigator.pop(sheetContext),
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(9)),
                    alignment: Alignment.center,
                    child: const Icon(Icons.close_rounded, size: 18, color: AppColors.navy),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
              child: Column(children: [
                _afield(ar ? 'كلمة المرور الحالية' : 'Current password', current, obscure: true),
                _afield(ar ? 'كلمة المرور الجديدة' : 'New password', newPw, obscure: true),
                _afield(ar ? 'تأكيد كلمة المرور الجديدة' : 'Confirm new password', confirm, obscure: true),
              ]),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line, width: 1))),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  ),
                  // Client-side only, same as the HTML's doResetPw() — this
                  // app's auth is OTP-based with no password on the backend,
                  // so there's nothing to actually change here yet.
                  onPressed: () {
                    if (newPw.text.length < 6) {
                      showErrorToast(sheetContext, ar ? 'كلمة المرور قصيرة جداً' : 'Password too short');
                      return;
                    }
                    if (newPw.text != confirm.text) {
                      showErrorToast(sheetContext, ar ? 'كلمتا المرور غير متطابقتين' : "Passwords don't match");
                      return;
                    }
                    Navigator.pop(sheetContext);
                    showToast(context, ar ? 'تم تغيير كلمة المرور' : 'Password changed');
                  },
                  child: Text(ar ? 'حفظ' : 'Save', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ]),
        ),
        ),
      ),
    );
  }

  // .afield
  Widget _afield(String label, TextEditingController c, {TextInputType? type, bool obscure = false, bool readOnly = false, int? maxLength}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.navy)),
          const SizedBox(height: 5),
          TextField(
            controller: c,
            keyboardType: type,
            obscureText: obscure,
            readOnly: readOnly,
            maxLength: maxLength,
            textAlign: readOnly ? TextAlign.center : TextAlign.start,
            style: TextStyle(fontSize: 13.5, color: readOnly ? AppColors.muted : AppColors.ink),
            decoration: InputDecoration(
              counterText: '',
              filled: readOnly,
              fillColor: readOnly ? AppColors.bg : null,
              // Readonly fields here are only ever the short "+965" prefix box —
              // the default 11px all-around padding left barely any room for
              // the text at a fixed 58px width and was clipping the last digit.
              contentPadding: readOnly ? const EdgeInsets.symmetric(horizontal: 4, vertical: 11) : const EdgeInsets.all(11),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line, width: 1.5)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line, width: 1.5)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.sky, width: 1.5)),
            ),
          ),
        ],
      ),
    );
  }

  // .afield for a tap-to-pick field (date / dropdown) rendered as a bordered box
  Widget _apick(String label, String display, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.navy)),
          const SizedBox(height: 5),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(border: Border.all(color: AppColors.line, width: 1.5), borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(display, style: const TextStyle(fontSize: 13.5, color: AppColors.ink)),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.muted),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _pickOption(String title, List<String> options, String? current, ValueChanged<String> onPicked, {String Function(String)? labelFor}) {
    final ar = context.read<LocaleState>().isArabic;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => Directionality(
        textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
        child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(16), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.navy))),
          for (final o in options)
            ListTile(
              title: Text(labelFor?.call(o) ?? o),
              trailing: current == o ? const Icon(Icons.check_rounded, color: AppColors.sky) : null,
              onTap: () {
                onPicked(o);
                Navigator.pop(sheetContext);
              },
            ),
          const SizedBox(height: 8),
        ]),
        ),
      ),
    );
  }

  // .arow with the phone prefix fixed at 58px (HTML: flex:0 0 58px) instead
  // of an equal split, so the actual number field gets the rest of the row.
  Widget _phoneRow(TextEditingController phone) {
    final ar = context.read<LocaleState>().isArabic;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 64, child: _afield(ar ? 'رقم الهاتف' : 'Phone', TextEditingController(text: '+965'), readOnly: true)),
        const SizedBox(width: 10),
        Expanded(child: _afield('\u00A0', phone, type: TextInputType.phone)),
      ],
    );
  }

  // .arow
  Widget _arow(List<Widget> children) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: children[i])]]),
      );

  // .prof-card
  Widget _profCard(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.line, width: 1), borderRadius: BorderRadius.circular(16), boxShadow: AppColors.shSm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.navy)),
          const SizedBox(height: 12),
          ...children,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final isArabic = context.watch<LocaleState>().isArabic;
    String t(String en, String arabic) => isArabic ? arabic : en;

    // Signed out: this screen used to open an empty "WASFA customer" form
    // that couldn't be saved. Now it asks to sign in first, like Wallet,
    // My orders, My requests and the rest of the Account screen's rows.
    if (!context.watch<AuthState>().isSignedIn) {
      return Directionality(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          backgroundColor: AppColors.bg,
          appBar: PageHeader(title: t('Profile', 'الملف الشخصي')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('👤', style: TextStyle(fontSize: 34)),
                const SizedBox(height: 10),
                Text(t('Sign in to view and edit your profile', 'سجّل الدخول لعرض ملفك الشخصي وتعديله'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: () async {
                    final ok = await Navigator.of(context).pushNamed(Routes.login);
                    if (ok == true && mounted) {
                      _fillFromUser(context.read<AuthState>().user);
                      _loadFromServer();
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
                  child: Text(t('Sign in', 'تسجيل الدخول')),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    final genderLabel = _gender == 'Male'
        ? t('Male', 'ذكر')
        : _gender == 'Female'
            ? t('Female', 'أنثى')
            : _gender == 'Other'
                ? t('Other', 'أخرى')
                : null;
    final subtitleParts = <String>[
      if (_age != null) '$_age ${t("yrs", "سنة")}',
      if (genderLabel != null) genderLabel,
      if (_bloodType != null) _bloodType!,
    ];

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
      backgroundColor: AppColors.bg,
      appBar: PageHeader(title: t('Profile', 'الملف الشخصي')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 30),
        children: [
          // .prof-hero
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
            color: Colors.white,
            child: Column(children: [
              Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 92, height: 92,
                  decoration: BoxDecoration(
                    gradient: _pickedImage == null && (context.watch<AuthState>().user?.photoUrl == null)
                        ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.sky, AppColors.navy])
                        : null,
                    shape: BoxShape.circle,
                    boxShadow: AppColors.sh,
                    image: _pickedImage != null
                        ? DecorationImage(image: FileImage(_pickedImage!), fit: BoxFit.cover)
                        : (context.watch<AuthState>().user?.photoUrl != null
                            ? DecorationImage(image: NetworkImage(context.watch<AuthState>().user!.photoUrl!), fit: BoxFit.cover)
                            : null),
                  ),
                  alignment: Alignment.center,
                  // Only shown as a fallback — hidden the moment there's a
                  // real picked or server photo to display instead, since
                  // it'd otherwise sit underneath/behind the actual image.
                  child: (_pickedImage == null && context.watch<AuthState>().user?.photoUrl == null)
                      ? Text(_profInitial(), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w700))
                      : null,
                ),
                Positioned(
                  bottom: -2, right: -2,
                  child: InkWell(
                    // ✅ Confirmed live (2026-09-28): /acct/profile's save
                    // request now takes a real `image` file — this used to
                    // be a "not available yet" stub since no such field
                    // existed at all. Picks locally and shows it
                    // immediately (setState below) — actually uploading it
                    // happens together with the rest of the form on "Save
                    // profile", same as every other field here, rather
                    // than as a separate upload step.
                    onTap: _pickPhoto,
                    borderRadius: BorderRadius.circular(15),
                    child: Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(color: AppColors.rose, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                      alignment: Alignment.center,
                      child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Text(
                _name.text.trim().isEmpty ? t('WASFA customer', 'عميل وصفة') : _name.text,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.navy),
              ),
              if (subtitleParts.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(subtitleParts.join(' · '), style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
              ],
              const SizedBox(height: 8),
            ]),
          ),

          const SizedBox(height: 12),

          // Personal information
          _profCard(t('Personal information', 'المعلومات الشخصية'), [
            _afield(t('Name', 'الاسم'), _name),
            _afield(t('Civil ID', 'الرقم المدني'), _civilId, type: TextInputType.number, maxLength: 12),
            _afield(t('Email', 'البريد الإلكتروني'), _email, type: TextInputType.emailAddress),
            _phoneRow(_phone),
            _arow([
              _apick(t('Date of birth', 'تاريخ الميلاد'), _dob != null ? '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}' : t('Not set', 'غير محدد'), _pickDob),
              _apick(t('Sex', 'الجنس'), genderLabel ?? t('Not set', 'غير محدد'), () => _pickOption(
                    t('Sex', 'الجنس'),
                    ['Female', 'Male', 'Other'],
                    _gender,
                    (v) => setState(() => _gender = v),
                    labelFor: (v) => t(v, {'Female': 'أنثى', 'Male': 'ذكر', 'Other': 'أخرى'}[v] ?? v),
                  )),
            ]),
            _afield(t('Nationality', 'الجنسية'), _nationality),
          ]),

          // Health information
          _profCard(t('Health information', 'المعلومات الصحية'), [
            _arow([_afield(t('Weight (kg)', 'الوزن (كجم)'), _weight, type: TextInputType.number), _afield(t('Height (cm)', 'الطول (سم)'), _height, type: TextInputType.number)]),
            _apick(t('Blood type', 'فصيلة الدم'), _bloodType ?? t('Not set', 'غير محدد'), () => _pickOption(t('Blood type', 'فصيلة الدم'), _bloodTypes, _bloodType, (v) => setState(() => _bloodType = v))),
            const SizedBox(height: 2),
          ]),

          // Emergency contact
          _profCard(t('Emergency contact', 'جهة اتصال الطوارئ'), [
            _arow([_afield(t('Contact name', 'اسم جهة الاتصال'), _emergName), _afield(t('Relationship', 'صلة القرابة'), _emergRel)]),
            _phoneRow(_emergPhone),
          ]),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: OutlinedButton(
              onPressed: _openResetPw,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.navy, width: 1.5),
                foregroundColor: AppColors.navy,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.lock_outline_rounded, size: 17),
                const SizedBox(width: 8),
                Text(t('Reset password', 'إعادة تعيين كلمة المرور'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navy, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                minimumSize: const Size(double.infinity, 0),
              ),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Text(t('Save profile', 'حفظ الملف الشخصي'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
