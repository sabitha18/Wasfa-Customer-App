import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/pharmacy_store.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../state/locale_state.dart';
import '../../viewmodels/shop_view_model.dart';
import '../widgets/page_header.dart';
import 'shop_screen.dart';
import '../widgets/content_grid.dart';

class BrandsScreen extends StatelessWidget {
  final PharmacyStore? store;
  /// The store's real, server-scoped brand list (StoreViewModel.brandsInStore),
  /// passed in by the caller when available. Preferred over recomputing from
  /// the mock cache below, which only ever matched local seed data and went
  /// empty as soon as real store products replaced it.
  final List<String>? brands;
  const BrandsScreen({super.key, this.store, this.brands});

  @override
  Widget build(BuildContext context) {
    final repo = CatalogRepository.instance;
    final list = brands ??
        (store != null
            ? repo.productsByPharmacy(store!.seller).map((p) => p.brand).toSet().toList()
            : repo.products.map((p) => p.brand).where((b) => b.isNotEmpty).toSet().toList());
    final ar = context.watch<LocaleState>().isArabic;

    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
      appBar: PageHeader(title: ar ? 'أفضل العلامات التجارية' : 'Top brands'),
      // Rows sized to their content (see content_grid.dart) instead of a
      // fixed-ratio grid (cell height followed screen width).
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: contentGridRowCount(list.length, 2),
        itemBuilder: (context, row) => contentGridRow(
          context: context,
          row: row,
          itemCount: list.length,
          columns: 2,
          itemBuilder: (context, i) => OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.line, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 28),
          ),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              // `shopId` is what actually scopes the server listing to this
              // store (see StoreScreen._openShop) — omitting it here was
              // the bug: tapping a brand opened the full, unfiltered Shop.
              builder: (_) => ShopScreen(initialFilter: ShopFilter(pharmacy: store?.seller, shopId: store?.id, brand: list[i])),
            ),
          ),
          child: Text(list[i], textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy)),
        ),
        ),
      ),
      ),
    );
  }
}
