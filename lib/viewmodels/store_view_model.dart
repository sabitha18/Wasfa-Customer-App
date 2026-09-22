import 'package:flutter/foundation.dart';
import '../core/network/api_exception.dart';
import '../data/models/home_feed.dart';
import '../data/models/pharmacy_store.dart';
import '../data/models/product.dart';
import '../data/models/seller_banner.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/services/catalog_service.dart';

class StoreViewModel extends ChangeNotifier {
  final PharmacyStore store;
  final int? userId; // so wishlist_status/cart_status reflect this person, not a default
  final CatalogRepository _repo = CatalogRepository.instance;
  final CatalogService _service = CatalogService.instance;

  bool isLoading = false;
  String? error;
  List<Product>? _fetched;

  /// Real per-store promo carousel content (see SellerBanner's doc) —
  /// replaces the 3 hardcoded PromoCards that used to show identically on
  /// every seller's page. Empty (not a fallback to those old cards) until
  /// this loads or if the store has no banners configured — store_screen.dart
  /// simply shows nothing in that case rather than reverting to fake ones.
  List<SellerBanner> banners = [];

  StoreViewModel(this.store, {this.userId}) {
    // When the store carries a backend id, load its catalogue from the server
    // (`GET /app/products?shop=<id>`). Mock/local stores (no id) fall back to
    // the seller-name match against the shared product cache.
    if (store.id != null) {
      _load();
      _loadBanners();
    }
    // Safety net so "Shop by category" still works when a store is opened
    // via a deep link, before Home/Shop has ever cached the real tree.
    if (_repo.liveProductCategories.isEmpty) _loadCategories();
  }

  Future<void> _load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final page = await _service.products(shop: store.id, perPage: 100, userId: userId);
      _fetched = page.items;
      _repo.cacheProducts(page.items);
    } catch (e) {
      error = describeError(e);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadBanners() async {
    try {
      banners = await _service.sellerBanners(store.id!);
      notifyListeners();
    } catch (_) {
      // Best-effort — the carousel just shows nothing rather than a fake
      // placeholder if this fails.
    }
  }

  Future<void> _loadCategories() async {
    try {
      final tree = await _service.categories();
      _repo.cacheProductCategories(tree);
      notifyListeners();
    } catch (_) {
      // Best-effort — falls back to the static placeholder list.
    }
  }

  /// Products in this store: the server-scoped fetch when we have a store id,
  /// otherwise the seller-name match against the shared cache (mock stores).
  List<Product> get products => _fetched ?? _repo.productsByPharmacy(store.seller);

  List<Product> get offers =>
      products.where((p) => p.isOffer || p.sellers.any((s) => s.name == store.seller && s.was != null)).toList();

  /// Confirmed live (2026-09-17): real per-product `sold`/`total_sold`
  /// counts, sorted descending — this is genuinely what `sort=best` orders
  /// by server-side (a real page came back in strict descending
  /// `total_sold` order). Was `products.where((p) => p.isBestSeller)`,
  /// which could never show anything at all — see that getter's doc.
  /// Filters out anything with no real sold count (0 or unknown) rather
  /// than showing arbitrarily-ordered zero-sales products as if they were
  /// best sellers.
  List<Product> get bestSellers {
    final withSales = products.where((p) => (p.sold ?? 0) > 0).toList();
    withSales.sort((a, b) => (b.sold ?? 0).compareTo(a.sold ?? 0));
    return withSales;
  }

  /// Categories actually present in this store's catalogue. Prefers the real
  /// backend taxonomy ([CatalogRepository.liveProductCategories], populated
  /// from `GET /app/categories` once Home or Shop has loaded it) — matching
  /// [ShopViewModel.categories]'s fallback pattern.
  ///
  /// Confirmed against a live `/app/products?shop=<id>` response: `category`
  /// comes back as a granular leaf value (e.g. `"Acne"`), not one of the
  /// ~7 top-level names ('Medicine', 'Skin care', ...) the design's category
  /// tiles expect — "Acne" is a descendant of "Skin care" a few levels down
  /// the real tree. So this walks the whole tree once, maps every
  /// descendant name to its top-level ancestor, and buckets each product
  /// under that ancestor — which is what actually lets a real leaf value
  /// like "Acne" surface as the "Skin care" tile instead of matching
  /// nothing. The static [CatalogRepository.productCategories] placeholder
  /// list is only used as a last-resort fallback before the real tree has
  /// loaded at all.
  ///
  /// Each entry carries `icon` — the real category image from
  /// `/app/categories`' `icon` field — alongside `emoji` as a fallback for
  /// when `icon` is empty or fails to load, and `cat` as the label.
  List<Map<String, String>> get categoriesInStore {
    if (_repo.liveProductCategories.isNotEmpty) {
      final leafToTop = _flattenToTopLevel(_repo.liveProductCategories);
      final matched = <String, HomeCategory>{};
      for (final p in products) {
        final top = leafToTop[p.category];
        if (top != null) matched[top.name] = top;
      }
      return matched.values.map((c) => {'emoji': _emojiFor(c.name), 'cat': c.name, 'icon': c.iconUrl}).toList();
    }
    return CatalogRepository.productCategories
        .where((c) => products.any((p) => p.category == c['cat']))
        .map((c) => {...c, 'icon': ''})
        .toList();
  }

  /// Walks a category tree and maps every node's name (at any depth) to its
  /// top-level ancestor, so a leaf like "Acne" resolves to "Skin care".
  static Map<String, HomeCategory> _flattenToTopLevel(List<HomeCategory> tree) {
    final map = <String, HomeCategory>{};
    void walk(HomeCategory top, HomeCategory node) {
      map[node.name] = top;
      for (final child in node.children) {
        walk(top, child);
      }
    }
    for (final top in tree) {
      walk(top, top);
    }
    return map;
  }

  /// Best-effort icon for a top-level category name — reuses the same
  /// mapping the static placeholder list uses, since real top-level names
  /// are expected to line up with those (only the leaf values underneath
  /// them, like "Acne", don't). Falls back to a generic folder icon for any
  /// top-level name the map doesn't recognise.
  static String _emojiFor(String name) {
    const map = {
      'Medicine': '💊', 'Hair care': '💇', 'Skin care': '🧴', 'Vitamins': '🟡',
      'Mom & baby': '🍼', 'Personal care': '🪥', 'Health': '❤️',
    };
    return map[name] ?? '🗂️';
  }

  // Empty-string brands (a product with no brand set at all) were sneaking
  // into this list as an actual entry — a real store had one, showing up
  // as a completely blank pill with no text in "Top brands" (screenshot,
  // 2026-09-16). Filtered out here rather than leaving it to whatever
  // widget renders the chip to silently do nothing useful with an empty
  // label.
  List<String> get brandsInStore => products.map((p) => p.brand).where((b) => b.trim().isNotEmpty).toSet().toList();

  /// Brand name -> logo URL, for whichever brands in [brandsInStore]
  /// actually have one (see Product.brandLogo's doc — speculative, always
  /// null today). A brand can appear on several products; the first
  /// non-null logo found for that name wins. store_screen.dart's "Top
  /// brands" row falls back to today's plain text-only pill for any brand
  /// missing an entry here, which right now is every brand.
  Map<String, String> get brandLogosInStore {
    final map = <String, String>{};
    for (final p in products) {
      final name = p.brand.trim();
      final logo = p.brandLogo;
      if (name.isNotEmpty && logo != null && logo.isNotEmpty && !map.containsKey(name)) {
        map[name] = logo;
      }
    }
    return map;
  }
}
