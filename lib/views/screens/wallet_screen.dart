import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_state_view.dart';
import '../../state/auth_state.dart';
import '../../state/locale_state.dart';
import '../../state/orders_state.dart';
import '../widgets/page_header.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthState>();
      if (auth.isSignedIn) context.read<OrdersState>().loadWallet(auth.userId!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final orders = context.watch<OrdersState>();
    final ar = context.watch<LocaleState>().isArabic;
    String t(String en, String arabic) => ar ? arabic : en;

    if (!auth.isSignedIn) {
      return Directionality(
        textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
        appBar: PageHeader(title: t('Wallet', 'المحفظة')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('👛', style: TextStyle(fontSize: 34)),
              const SizedBox(height: 10),
              Text(t('Sign in to see your wallet', 'سجّل الدخول لعرض محفظتك'), style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () async {
                  final ok = await Navigator.of(context).pushNamed('login');
                  if (ok == true && context.mounted) context.read<OrdersState>().loadWallet(context.read<AuthState>().userId!);
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

    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
      appBar: PageHeader(title: t('Wallet', 'المحفظة')),
      body: (orders.walletLoading && orders.transactions.isEmpty)
          ? LoadingView(message: t('Loading wallet…', 'جارٍ تحميل المحفظة…'))
          : (orders.walletError != null && orders.transactions.isEmpty)
              ? ErrorRetryView(message: orders.walletError!, onRetry: () => orders.loadWallet(auth.userId!))
              : RefreshIndicator(
        onRefresh: () => orders.loadWallet(auth.userId!),
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (orders.walletError != null) InlineErrorBanner(message: orders.walletError!, onRetry: () => orders.loadWallet(auth.userId!)),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: AppColors.promo1, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('Balance', 'الرصيد'), style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                const SizedBox(height: 4),
                Text(Formatters.money(orders.wallet), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                Text('⭐ ${orders.rewards} ${t("points", "نقطة")}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(t('Transactions', 'المعاملات'), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted, fontSize: 12.5))),
          if (orders.transactions.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Center(child: Text(t('No transactions yet', 'لا توجد معاملات بعد'), style: const TextStyle(color: AppColors.muted)))),
          for (final tx in orders.transactions)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: AppColors.shSm),
              child: Row(children: [
                Text(tx.amount >= 0 ? '⬇️' : '⬆️', style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tx.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(tx.dateDisplay, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                  ]),
                ),
                Text('${tx.amount >= 0 ? '+' : '−'}${Formatters.money(tx.amount.abs())}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: tx.amount >= 0 ? AppColors.ok : AppColors.danger)),
              ]),
            ),
        ],
        ),
      ),
      ),
    );
  }
}
