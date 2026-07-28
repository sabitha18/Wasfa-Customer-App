import '../../core/utils/json_utils.dart';
import 'product.dart';

/// One category tile — originally just `GET /app/home`'s flat `cats[]`
/// (`{ id, name, arabic_name, slug, icon }`), now also used for the real
/// category tree from `GET /app/categories`, which nests subcategories
/// under each entry as `children[]` (confirmed live — same 5 fields per
/// node, recursively, e.g. Medicine -> Pain Relief -> Devices -> ...).
class HomeCategory {
  final int id;
  final String name;
  final String nameAr;
  final String slug;
  final String iconUrl;
  final List<HomeCategory> children;

  const HomeCategory({
    required this.id,
    required this.name,
    required this.nameAr,
    required this.slug,
    required this.iconUrl,
    this.children = const [],
  });

  String label(bool arabic) => arabic ? nameAr : name;
  bool get hasChildren => children.isNotEmpty;

  factory HomeCategory.fromJson(Map<String, dynamic> json) => HomeCategory(
        id: asInt(json, const ['id']),
        name: asString(json, const ['name']),
        nameAr: asString(json, const ['arabic_name', 'name_ar']),
        slug: asString(json, const ['slug']),
        iconUrl: asString(json, const ['icon']),
        children: asList(json, const ['children', 'subcategories'])
            .map((e) => HomeCategory.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// One button on a home banner — `{ text, link }`. `link` is a relative
/// path (e.g. `/website/shop?deals=1`) from the web version of this
/// content; the app maps it to an in-app route rather than opening a
/// browser — see `_HomeBody`'s banner-tap handling.
class HomeBannerButton {
  final String text;
  final String link;
  const HomeBannerButton({this.text = '', this.link = ''});

  factory HomeBannerButton.fromJson(Map<String, dynamic> json) => HomeBannerButton(
        text: asString(json, const ['text']),
        link: asString(json, const ['link']),
      );
}

/// ✅ Confirmed live on `GET /app/home`'s `banners[]` (2026-07-24):
/// `{ title, sub, buttons[], emoji, image, image_clickable, device }`.
/// `title`/`sub`/`buttons` can all be empty (image-only banners are valid —
/// see the third example in the confirmed response, which has empty
/// title/sub/buttons and just a full-bleed image). `device` isn't parsed
/// here since the app only ever receives its own `device=app` banners in
/// the first place.
class HomeBanner {
  final String title;
  final String sub;
  final List<HomeBannerButton> buttons;
  final String emoji;
  final String imageUrl;
  final bool imageClickable;

  const HomeBanner({
    this.title = '',
    this.sub = '',
    this.buttons = const [],
    this.emoji = '',
    this.imageUrl = '',
    this.imageClickable = false,
  });

  factory HomeBanner.fromJson(Map<String, dynamic> json) => HomeBanner(
        title: asString(json, const ['title']),
        sub: asString(json, const ['sub']),
        buttons: asList(json, const ['buttons']).map((e) => HomeBannerButton.fromJson(e as Map<String, dynamic>)).toList(),
        emoji: asString(json, const ['emoji']),
        imageUrl: asString(json, const ['image']),
        imageClickable: asBool(json, const ['image_clickable']),
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
  final List<HomeBanner> banners;

  const HomeFeed({
    required this.categories,
    required this.brands,
    required this.deals,
    required this.best,
    required this.recent,
    this.banners = const [],
  });

  static const empty = HomeFeed(categories: [], brands: [], deals: [], best: [], recent: [], banners: []);

  factory HomeFeed.fromJson(Map<String, dynamic> json) => HomeFeed(
        categories: asList(json, const ['cats', 'categories'])
            .map((e) => HomeCategory.fromJson(e as Map<String, dynamic>))
            .toList(),
        brands: _stringList(asList(json, const ['brands'])),
        deals: _products(asList(json, const ['deals']), fallbackFlag: 'offer'),
        best: _products(asList(json, const ['best']), fallbackFlag: 'best'),
        recent: _products(asList(json, const ['recent'])),
        banners: asList(json, const ['banners']).map((e) => HomeBanner.fromJson(e as Map<String, dynamic>)).toList(),
      );

  static List<String> _stringList(List<dynamic> raw) => raw
      .map((e) => e is Map ? (e['name'] ?? e['cat'] ?? e['label'] ?? '').toString() : e.toString())
      .where((s) => s.isNotEmpty)
      .toList();

  static List<Product> _products(List<dynamic> raw, {String? fallbackFlag}) => raw.map((e) {
        final p = Product.fromJson(e as Map<String, dynamic>);
        if (fallbackFlag != null && !p.flags.contains(fallbackFlag)) {
          return Product(
            id: p.id, sku: p.sku, apixSku: p.apixSku, nameEn: p.nameEn, nameAr: p.nameAr, brand: p.brand,
            category: p.category, concern: p.concern, form: p.form, scientificName: p.scientificName,
            emoji: p.emoji, imageUrl: p.imageUrl, photos: p.photos, apiSellerCount: p.apiSellerCount, rating: p.rating, reviews: p.reviews,
            flags: [...p.flags, fallbackFlag], tag: p.tag, tags: p.tags, sellers: p.sellers,
            wishlistStatus: p.wishlistStatus, cartStatus: p.cartStatus, offerStatus: p.offerStatus, discountPct: p.discountPct,
          );
        }
        return p;
      }).toList();
}
