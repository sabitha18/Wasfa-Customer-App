import '../../core/utils/json_utils.dart';
import 'product.dart';

/// One category tile from `GET /app/home`'s `cats[]`:
/// `{ id, name, arabic_name, slug, icon }` — confirmed against a real
/// response (icon is a real photo URL on their CDN).
class HomeCategory {
  final int id;
  final String name;
  final String nameAr;
  final String slug;
  final String iconUrl;

  const HomeCategory({required this.id, required this.name, required this.nameAr, required this.slug, required this.iconUrl});

  String label(bool arabic) => arabic ? nameAr : name;

  factory HomeCategory.fromJson(Map<String, dynamic> json) => HomeCategory(
        id: asInt(json, const ['id']),
        name: asString(json, const ['name']),
        nameAr: asString(json, const ['arabic_name', 'name_ar']),
        slug: asString(json, const ['slug']),
        iconUrl: asString(json, const ['icon']),
      );
}

/// From `GET /app/home`: `{ cats[], brands[], deals[], best[], recent[] }`.
///
/// `brands` comes through as either plain strings or small objects — see
/// [_stringList]. `deals`/`best`/`recent` are product rails in the same
/// shape as the PLP's `items[]`.
class HomeFeed {
  final List<HomeCategory> categories;
  final List<String> brands;
  final List<Product> deals;
  final List<Product> best;
  final List<Product> recent;

  const HomeFeed({
    required this.categories,
    required this.brands,
    required this.deals,
    required this.best,
    required this.recent,
  });

  static const empty = HomeFeed(categories: [], brands: [], deals: [], best: [], recent: []);

  factory HomeFeed.fromJson(Map<String, dynamic> json) => HomeFeed(
        categories: asList(json, const ['cats', 'categories'])
            .map((e) => HomeCategory.fromJson(e as Map<String, dynamic>))
            .toList(),
        brands: _stringList(asList(json, const ['brands'])),
        deals: _products(asList(json, const ['deals']), fallbackFlag: 'offer'),
        best: _products(asList(json, const ['best']), fallbackFlag: 'best'),
        recent: _products(asList(json, const ['recent'])),
      );

  static List<String> _stringList(List<dynamic> raw) => raw
      .map((e) => e is Map ? (e['name'] ?? e['cat'] ?? e['label'] ?? '').toString() : e.toString())
      .where((s) => s.isNotEmpty)
      .toList();

  static List<Product> _products(List<dynamic> raw, {String? fallbackFlag}) => raw.map((e) {
        final p = Product.fromJson(e as Map<String, dynamic>);
        if (fallbackFlag != null && !p.flags.contains(fallbackFlag)) {
          return Product(
            id: p.id, sku: p.sku, nameEn: p.nameEn, nameAr: p.nameAr, brand: p.brand,
            category: p.category, concern: p.concern, form: p.form, scientificName: p.scientificName,
            emoji: p.emoji, imageUrl: p.imageUrl, apiSellerCount: p.apiSellerCount, rating: p.rating, reviews: p.reviews,
            flags: [...p.flags, fallbackFlag], tag: p.tag, sellers: p.sellers,
          );
        }
        return p;
      }).toList();
}
