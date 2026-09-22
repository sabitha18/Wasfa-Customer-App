import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../state/locale_state.dart';
import '../../viewmodels/shop_view_model.dart';
import '../widgets/page_header.dart';
import 'shop_screen.dart';

class PharmaciesScreen extends StatelessWidget {
  const PharmaciesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final list = CatalogRepository.instance.pharmacyList();
    const logos = ['🟢', '🔵', '🟣', '🟠', '🔴', '🟡'];
    final ar = context.watch<LocaleState>().isArabic;

    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
      appBar: PageHeader(title: ar ? 'الصيدليات' : 'Pharmacies'),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final ph = list[i];
          return ListTile(
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: CircleAvatar(backgroundColor: AppColors.bg, child: Text(logos[i % logos.length])),
            title: Text(ph['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(ar
                ? '${ph['n']} منتج · ابتداءً من ${Formatters.money(ph['min'] as double)}'
                : '${ph['n']} products · from ${Formatters.money(ph['min'] as double)}'),
            trailing: Icon(ar ? Icons.chevron_left_rounded : Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ShopScreen(initialFilter: ShopFilter(pharmacy: ph['name'] as String))),
            ),
          );
        },
      ),
      ),
    );
  }
}
