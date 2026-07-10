import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/services/auth_service.dart';
import '../../state/auth_state.dart';
import '../widgets/page_header.dart';
import '../widgets/toast.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _first;
  late final TextEditingController _last;
  final _email = TextEditingController();
  late final TextEditingController _phone;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthState>().user;
    final parts = (user?.name ?? '').split(' ');
    _first = TextEditingController(text: parts.isNotEmpty ? parts.first : '');
    _last = TextEditingController(text: parts.length > 1 ? parts.sublist(1).join(' ') : '');
    _phone = TextEditingController(text: user?.phone ?? '');
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final auth = context.read<AuthState>();
    if (!auth.isSignedIn) return;
    if (_first.text.trim().isEmpty) {
      showErrorToast(context, 'Please enter your first name.');
      return;
    }
    setState(() => _saving = true);
    try {
      await AuthService.instance.saveProfile(
        userId: auth.userId!,
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      );
      if (!mounted) return;
      showToast(context, 'Profile saved');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      showErrorToast(context, describeError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, TextEditingController c, {TextInputType? type}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: type,
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PageHeader(title: 'Profile'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field('First name', _first),
          _field('Last name', _last),
          _field('Email', _email, type: TextInputType.emailAddress),
          _field('Phone', _phone, type: TextInputType.phone),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 48)),
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : const Text('Save changes', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
