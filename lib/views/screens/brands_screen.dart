import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/pharmacy_store.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../viewmodels/shop_view_model.dart';
import '../widgets/page_header.dart';
import 'shop_screen.dart';

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

    return Scaffold(
      appBar: PageHeader(title: 'Top brands'),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 2.2),
        itemCount: list.length,
        itemBuilder: (context, i) => OutlinedButton(
          style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.line, width: 1.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              // `shopId` is what actually scopes the server listing to this
              // store (see StoreScreen._openShop) — omitting it here was
              // the bug: tapping a brand opened the full, unfiltered Shop.
              builder: (_) => ShopScreen(initialFilter: ShopFilter(pharmacy: store?.seller, shopId: store?.id, brand: list[i])),
            ),
          ),
          child: Text(list[i], style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy)),
        ),
      ),
    );
  }
}
