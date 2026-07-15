import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../state/auth_state.dart';
import '../../state/locale_state.dart';
import '../../state/orders_state.dart';
import 'coming_soon_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrdersState>();
    final locale = context.watch<LocaleState>();
    final auth = context.watch<AuthState>();
    final signedIn = auth.isSignedIn;

    final rows = <List<dynamic>>[
      [Icons.person_outline_rounded, 'View profile', () => Navigator.pushNamed(context, Routes.profile)],
      [Icons.inventory_2_outlined, 'My orders', () => Navigator.pushNamed(context, Routes.orders)],
      [Icons.assignment_return_outlined, 'My requests${orders.pendingRequestCount > 0 ? ' · ${orders.pendingRequestCount}' : ''}', () => Navigator.pushNamed(context, Routes.requests)],
      [Icons.medication_outlined, 'My prescriptions', () => Navigator.pushNamed(context, Routes.myRx)],
      [Icons.account_balance_wallet_outlined, 'Wallet', () => Navigator.pushNamed(context, Routes.wallet)],
      [Icons.location_on_outlined, 'Addresses', () => Navigator.pushNamed(context, Routes.addresses)],
      [Icons.favorite_border_rounded, 'Wishlist', () => Navigator.pushNamed(context, Routes.wishlist)],
      [Icons.credit_card_outlined, 'Payments', () {}],
      [Icons.language_rounded, 'Language · ${locale.isArabic ? "العربية" : "English"}', () => locale.toggle()],
    ];

    final infoRows = <List<dynamic>>[
      [Icons.help_outline_rounded, 'About WASFA', () {}],
      [Icons.quiz_outlined, 'FAQ', () {}],
      [Icons.description_outlined, 'Terms of service', () {}],
      [Icons.privacy_tip_outlined, 'Privacy policy', () {}],
      [Icons.support_agent_rounded, 'Help', () {}],
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppColors.shSm),
          child: InkWell(
            onTap: signedIn ? () => Navigator.pushNamed(context, Routes.profile) : () => Navigator.pushNamed(context, Routes.login),
            child: Row(children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.navy,
                child: Text(
                  signedIn && auth.user!.name.isNotEmpty ? auth.user!.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: signedIn
                      ? [
                          Text(auth.user!.name.isNotEmpty ? auth.user!.name : 'WASFA customer', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          Text(auth.user!.phone, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                        ]
                      : const [
                          Text('Sign in', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          Text('Tap to sign in with your phone number', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                        ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ]),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppColors.shSm),
          child: Column(children: [for (final r in rows) _Row(icon: r[0], label: r[1], onTap: r[2])]),
        ),
        const Padding(padding: EdgeInsets.fromLTRB(16, 18, 16, 6), child: Text('Legal', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted, fontSize: 12))),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppColors.shSm),
          child: Column(children: [for (final r in infoRows) _Row(icon: r[0], label: r[1], onTap: r[2])]),
        ),
        if (signedIn)
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Log out?'),
                    content: const Text('You\'ll need to verify your phone number again to sign back in.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log out')),
                    ],
                  ),
                );
                if (confirm == true) await context.read<AuthState>().logout();
              },
              child: const Text('Log out'),
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Row({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.navy, size: 21),
      title: Text(label, style: const TextStyle(fontSize: 13.5)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 20),
      onTap: onTap,
    );
  }
}
