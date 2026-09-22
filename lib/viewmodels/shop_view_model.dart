import 'package:flutter/foundation.dart';
import '../core/network/api_exception.dart';
import '../data/models/home_feed.dart';
import '../data/models/pharmacy_store.dart';
import '../data/models/product.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/services/catalog_service.dart';

/// Initial filter state a caller can seed the Shop (PLP) screen with —
/// e.g. opening from a storefront (pharmacy set), a category tile, or a
/// brand tile. Mirrors how JS mutates the global `SHOP` object before
/// calling `go('shop')`.
class ShopFilter {
  final String? pharmacy;
  final String? category;
  /// The real category id, when the caller already has one — e.g. a real
  /// banner's `link_ref` (confirmed live, 2026-09-22: `link_type:
  /// "category"`, `link_ref: 540`). Set this instead of relying on
  /// [category] alone to be name-matched against the top-level category
  /// chips (see ShopViewModel._resolveSelectedCategory) — that only ever
  /// searches the top-level list, so a deep subcategory name (which this
  /// can well be) would never resolve to an id that way at all.
  final int? categoryId;
  final String? brand;
  /// Store id (the shop's `user_id`) to filter the listing to a single store
  /// via `GET /app/products?shop=<id>`. Null = browse the whole catalogue.
  final int? shopId;
  /// Pre-apply the "Offers only" / best-sellers-only client-side filters —
  /// e.g. the Store screen's "Special offers"/"Best sellers" "See all"
  /// links use these so the Shop screen opens already narrowed to that
  /// section's products, instead of the full store catalogue.
  final bool offersOnly;
  final bool bestSellersOnly;
  const ShopFilter({this.pharmacy, this.category, this.categoryId, this.brand, this.shopId, this.offersOnly = false, this.bestSellersOnly = false});
}

class ShopViewModel extends ChangeNotifier {
  final CatalogRepository _repo = CatalogRepository.instance;
  final CatalogService _service = CatalogService.instance;

  bool isLoading = true;
  String? error;
  List<Product> _fetched = [];
  int _page = 1;
  int _totalPages = 1;
  bool isLoadingMore = false;

  /// Whether another page exists beyond what's already loaded — drives the
  /// infinite-scroll trigger and the "Loading more…" footer.
  bool get hasMore => _page < _totalPages;

  String? pharmacy;
  /// The real store id resolved from [pharmacy]'s name (see
  /// [_resolveShopId]) — what actually gets sent as `shop=` for the
  /// Pharmacy filter (confirmed 2026-09-17: same param already used for
  /// full-store browsing via [shopId]). Kept separate from [shopId]
  /// itself, which means "browsing exactly one store's whole catalogue"
  /// (set once, at construction, from a Store/Brand screen) — the two
  /// shouldn't clobber each other; [load]/[loadMore] send whichever is set,
  /// preferring [shopId] since that's the more deliberate, initial scope.
  int? _pharmacyShopId;
  int? shopId; // store filter -> GET /app/products?shop=<id>
  int? userId; // so wishlist_status/cart_status reflect this person, not a default
  String? category;
  /// Numeric id of [category] — this, not the name, is what the API
  /// actually filters on (confirmed with backend: `category` as a string
  /// doesn't reliably match). Set alongside [category] whenever the
  /// selection comes from the real tree ([selectParentCategory]/
  /// [selectSubCategory]) — and also backfilled by [_resolveSelectedCategory]
  /// for the name-only deep links (`ShopFilter.category` from store/
  /// pharmacy/brand screens), so those filter correctly server-side too
  /// once the real tree is loaded, not just the older name-string fallback.
  int? categoryId;
  /// Which top-level category is "expanded" in the Shop screen's first
  /// chip row — drives which subcategories show in the second row. Purely
  /// a UI concern; [category]/[categoryId] (the actual filter sent to the
  /// API) can independently be this parent's or one of its children's.
  HomeCategory? selectedParent;
  String? concern;
  String query = '';
  String view = 'grid'; // grid | list
  String sort = 'pop'; // pop | low | high | rated
  List<String> brands = [];
  bool inStock = false;
  bool offersOnly = false;
  /// "Show best-sellers first" — see [_apiSort]'s doc: there's no separate
  /// server-side boolean for this (confirmed 2026-09-17 only as a `sort`
  /// value, `sort=best`), so turning this on sends that sort instead of
  /// whatever the Sort picker had, rather than filtering the list down to
  /// ONLY best-sellers. There never was a real filter behind this anyway —
  /// it used to check Product.isBestSeller, which depends on a `flags`
  /// field no real `/app/products` response has ever actually included.
  bool bestSellersOnly = false;

  /// Maps the UI sort keys (pop/low/high/rated) to the API's expected
  /// values. [bestSellersOnly] overrides this entirely when on (see its
  /// own doc) — this only matters when it's off.
  String get _apiSort {
    if (bestSellersOnly) return 'best';
    switch (sort) {
      case 'low':
        return 'plow';
      case 'high':
        return 'phigh';
      // ✅ Confirmed live (2026-09-17): sort=rating now exists server-side —
      // this used to fetch as plain 'pop' and re-sort the already-loaded
      // page by rating client-side instead.
      case 'rated':
        return 'rating';
      default:
        return 'pop';
    }
  }

  ShopViewModel({ShopFilter? initial, this.userId}) {
    if (initial != null) {
      pharmacy = initial.pharmacy;
      _pharmacyShopId = _resolveShopId(initial.pharmacy);
      shopId = initial.shopId;
      category = initial.category;
      // Set BEFORE _resolveSelectedCategory() below runs — that method
      // only ever overwrites this when it finds a matching TOP-LEVEL
      // category chip by name; it never nulls this out if no match is
      // found, so a real id passed in directly (see ShopFilter.categoryId's
      // doc) survives even when the name is a deep subcategory the
      // top-level-only search could never have resolved on its own.
      categoryId = initial.categoryId;
      if (initial.brand != null) brands = [initial.brand!];
      offersOnly = initial.offersOnly;
      bestSellersOnly = initial.bestSellersOnly;
    }
    // A caller (Store screen's category tile, a deep link, etc.) only ever
    // hands us a category *name* — resolve it against the chip list so the
    // matching chip highlights, not just the underlying filter. Without
    // this, `category`/products were filtered correctly but no chip ever
    // showed as selected, since the chip row checks `selectedParent`/
    // `categoryId`, not the plain name string.
    _resolveSelectedCategory();
    if (_repo.liveProductCategories.isEmpty) _loadCategories();
    if (_repo.stores.isEmpty) _loadStores();
    load();
  }

  /// Fetches `/app/stores` if Home hasn't cached it yet this session (e.g.
  /// Shop opened directly, or from a deep link, before ever visiting Home)
  /// — needed so [_resolveShopId] has real id/name pairs to match a
  /// Pharmacy filter chip against. Called with no location — this only
  /// needs id+name per store, not a distance-sorted list. Best-effort: on
  /// failure the Pharmacy filter simply can't resolve to a real id yet,
  /// same as if the list were still empty.
  Future<void> _loadStores() async {
    try {
      final list = await _service.stores();
      _repo.cacheStores(list);
      // A pharmacy name passed in at construction (e.g. from the
      // standalone Pharmacies list, which has no shopId of its own) may
      // not have resolved yet if this cache was still empty back then —
      // re-resolve now that real data is in, and reload so the filter
      // actually takes effect server-side instead of silently never
      // applying.
      if (pharmacy != null && _pharmacyShopId == null) {
        _pharmacyShopId = _resolveShopId(pharmacy);
        if (_pharmacyShopId != null) load();
      }
    } catch (_) {
      // Ignore — Pharmacy filter just won't resolve an id until some other
      // path (e.g. visiting Home) populates the cache.
    }
  }

  /// The real store id for a Pharmacy filter chip's name — see
  /// [_pharmacyShopId]'s doc. Null if [_repo.stores] hasn't loaded yet, or
  /// genuinely has no store by this exact name.
  int? _resolveShopId(String? name) {
    if (name == null) return null;
    for (final s in _repo.stores) {
      if (s.name == name) return s.id;
    }
    return null;
  }

  /// Resolves selected brand NAMES (what the chips show/toggle) to real
  /// brand ids — confirmed live (2026-09-18): `brand_id` is on every
  /// product already, so unlike [_resolveShopId] this needs no separate
  /// fetch, just a lookup against whatever's already loaded. A name that
  /// doesn't resolve (or resolves to id 0 — seen on real products with no
  /// brand at all, though [realBrands] already excludes empty-name brands
  /// so this shouldn't come up in practice) is dropped rather than sent as
  /// a bogus id.
  List<int> _resolveBrandIds() {
    if (brands.isEmpty) return const [];
    final ids = <int>{};
    for (final p in [..._fetched, ..._repo.products]) {
      if (brands.contains(p.brand) && p.brandId != null && p.brandId! > 0) ids.add(p.brandId!);
    }
    return ids.toList();
  }

  /// Fetches the real category tree (see [CatalogRepository.liveProductCategories])
  /// if nothing has cached it yet — e.g. the person opened Shop directly
  /// without visiting Home first. Best-effort: on failure the screen just
  /// keeps using the static placeholder list.
  Future<void> _loadCategories() async {
    try {
      final tree = await _service.categories();
      _repo.cacheProductCategories(tree);
      // Re-resolve now that the real tree (with real ids) is in — if the
      // constructor only had the id:0 placeholder list to match against,
      // this upgrades `selectedParent`/`categoryId` to the real entry.
      _resolveSelectedCategory();
      notifyListeners();
    } catch (_) {
      // Ignore — falls back to the static placeholder list.
    }
  }

  /// Finds the chip-list entry matching [category]'s name (case-insensitive)
  /// and sets [selectedParent]/[categoryId] to it, so the top chip row
  /// highlights correctly for a category that arrived as a plain string
  /// rather than through [selectParentCategory]. No-op if [category] is
  /// null or nothing matches.
  void _resolveSelectedCategory() {
    if (category == null) return;
    for (final c in categories) {
      if (c.name.toLowerCase() == category!.toLowerCase()) {
        selectedParent = c;
        categoryId = c.id == 0 ? categoryId : c.id;
        return;
      }
    }
  }

  /// Real, server-driven categories when available; falls back to the
  /// static placeholder list (see [CatalogRepository.productCategories])
  /// only until the real list has loaded.
  List<HomeCategory> get categories {
    if (_repo.liveProductCategories.isNotEmpty) return _repo.liveProductCategories;
    return CatalogRepository.productCategories
        .where((c) => c['cat'] != 'Health')
        .map((c) => HomeCategory(id: 0, name: c['cat']!, nameAr: c['cat']!, slug: c['cat']!, iconUrl: ''))
        .toList();
  }

  /// `concern` still isn't filtered server-side — applied client-side
  /// against whatever's been fetched so far (see [loadMore] for how more
  /// gets appended page by page). `offers`/`shop`(pharmacy)/`sort`
  /// (including `best`/`rating`) and now `brand` (comma-separated real
  /// ids, confirmed 2026-09-18) are all real server params; see
  /// [_apiSort]/[_pharmacyShopId]/[_resolveBrandIds]'s docs.
  Future<void> load() async {
    isLoading = true;
    error = null;
    _page = 1;
    notifyListeners();
    try {
      final page = await _service.products(
        query: query,
        category: category,
        categoryId: categoryId,
        sort: _apiSort, // map UI sort -> API sort (plow/phigh/pop/best/rating)
        inStock: inStock,
        offersOnly: offersOnly,
        brandIds: _resolveBrandIds(),
        page: 1,
        perPage: 100,
        shop: shopId ?? _pharmacyShopId, // shopId (browsing one store) takes priority over a Pharmacy filter chip
        userId: userId,
      );
      _fetched = page.items;
      _totalPages = page.pages;
      _repo.cacheProducts(_fetched);
    } catch (e) {
      error = describeError(e);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Fetches the next page and appends it — this is what was missing
  /// before: [load] always requested `page: 1` and nothing after it ever
  /// got fetched, so anything past the first 100 matches was permanently
  /// unreachable. Called from the Shop screen's scroll listener once the
  /// person nears the bottom of the (already client-filtered) list.
  Future<void> loadMore() async {
    if (isLoadingMore || isLoading || !hasMore) return;
    isLoadingMore = true;
    notifyListeners();
    try {
      final next = _page + 1;
      final page = await _service.products(
        query: query,
        category: category,
        categoryId: categoryId,
        sort: _apiSort,
        inStock: inStock,
        offersOnly: offersOnly,
        brandIds: _resolveBrandIds(),
        page: next,
        perPage: 100,
        shop: shopId ?? _pharmacyShopId,
        userId: userId,
      );
      _fetched = [..._fetched, ...page.items];
      _page = next;
      _totalPages = page.pages;
      _repo.cacheProducts(page.items);
    } catch (_) {
      // Silent — keep showing whatever's already loaded; the person can
      // just scroll again to retry.
    } finally {
      isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Top always-visible category chip row — matches HTML's `setCat()`:
  /// plain set, never toggles off by tapping the same chip again. Also
  /// expands this category's children into the second row so the person
  /// can narrow further (null clears both — the "All" chip).
  void selectParentCategory(HomeCategory? c) {
    selectedParent = c;
    category = c?.name;
    categoryId = c?.id;
    // Brand/pharmacy chips are scoped to the category (see realBrands/
    // sellerNames) — a selection from a different category no longer even
    // shows as a chip here, so leaving it active would silently filter
    // everything out with nothing on screen to explain why.
    brands = [];
    pharmacy = null;
    _pharmacyShopId = null;
    load();
  }

  /// Second row's subcategory chips — narrows the filter to this specific
  /// child without collapsing the row (so the person can flip between
  /// siblings under the same parent).
  void selectSubCategory(HomeCategory c) {
    category = c.name;
    categoryId = c.id;
    brands = [];
    pharmacy = null;
    _pharmacyShopId = null;
    load();
  }

  /// Top always-visible category chip row — matches HTML's `setCat()`:
  /// plain set, never toggles off by tapping the same chip again.
  void setCategory(String? c) {
    category = c;
    load();
  }

  /// Filter sheet's Categories section — matches HTML's `setFilterCat()`:
  /// tapping the already-selected category clears it back to "All".
  void toggleFilterCategory(String? c) {
    category = category == c ? null : c;
    brands = [];
    pharmacy = null;
    _pharmacyShopId = null;
    load();
  }

  void setPharmacy(String? nm) {
    pharmacy = nm;
    _pharmacyShopId = _resolveShopId(nm);
    load();
  }

  void setConcern(String? c) {
    concern = concern == c ? null : c;
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    load();
  }

  void setView(String v) {
    view = v;
    notifyListeners();
  }

  void setSort(String s) {
    sort = s;
    load();
  }

  void toggleBrand(String b) {
    if (brands.contains(b)) {
      brands.remove(b);
    } else {
      brands.add(b);
    }
    load();
  }

  void toggleInStock() {
    inStock = !inStock;
    load();
  }

  void toggleOffersOnly() {
    offersOnly = !offersOnly;
    load();
  }

  void toggleBestSellersOnly() {
    bestSellersOnly = !bestSellersOnly;
    load();
  }

  /// Full drill-down chain from [selectedParent] to whichever node
  /// [categoryId] currently points at — e.g. [Skin care, Face care] once
  /// Face care is picked, or [Skin care, Face care, Cleansers] one level
  /// deeper still. The Filter sheet renders one "Subcategories of X" row
  /// per element that has children, which is what lets drilling continue
  /// past the first level — previously the sheet only ever showed
  /// [selectedParent]'s direct children with no way to go further, even
  /// when the tapped subcategory had its own children (e.g. Face care's
  /// own sub-list never appeared).
  List<HomeCategory> get selectedCategoryPath {
    if (selectedParent == null) return const [];
    if (categoryId == null) return [selectedParent!];
    return _findPath(selectedParent!, categoryId!) ?? [selectedParent!];
  }

  List<HomeCategory>? _findPath(HomeCategory node, int targetId) {
    if (node.id == targetId) return [node];
    for (final child in node.children) {
      final sub = _findPath(child, targetId);
      if (sub != null) return [node, ...sub];
    }
    return null;
  }

  void clearFilters() {
    brands = [];
    inStock = false;
    offersOnly = false;
    bestSellersOnly = false;
    pharmacy = null;
    _pharmacyShopId = null;
    category = null;
    categoryId = null;
    selectedParent = null;
    load();
  }

  void clearPharmacy() {
    pharmacy = null;
    _pharmacyShopId = null;
    load();
  }

  bool get hasActiveFilters => brands.isNotEmpty || inStock || offersOnly || bestSellersOnly || category != null || pharmacy != null;

  /// Matches HTML's `sellerNames()` — unique seller names for the Filter
  /// sheet's Pharmacy chips. Scoped to [_fetched] (the current category/
  /// sort's loaded products) first — was previously built from
  /// [CatalogRepository]'s whole-app product cache regardless of which
  /// category was selected, which offered chips (brands/stores from
  /// completely unrelated categories) that could never actually match
  /// anything once picked, silently producing an empty or wrong-looking
  /// result. Falls back to the full cross-session cache only when
  /// [_fetched] has nothing yet, so the sheet still isn't empty with no
  /// way out but "Clear all" on a genuinely empty first load.
  List<String> get sellerNames {
    final scoped = <String>{};
    for (final p in _fetched) {
      for (final s in p.sellers) {
        if (s.name.isNotEmpty) scoped.add(s.name);
      }
    }
    if (scoped.isNotEmpty) return scoped.toList()..sort();
    final names = <String>{};
    for (final p in _repo.products) {
      for (final s in p.sellers) {
        if (s.name.isNotEmpty) names.add(s.name);
      }
    }
    return names.toList()..sort();
  }

  /// Real brands for the Filter sheet — see [sellerNames] for why this is
  /// scoped to [_fetched] first, with the whole-app cache only as a
  /// fallback when nothing's loaded yet for the current category.
  List<String> get realBrands {
    final scoped = <String>{};
    for (final p in _fetched) {
      if (p.brand.isNotEmpty) scoped.add(p.brand);
    }
    if (scoped.isNotEmpty) return scoped.toList()..sort();
    final names = <String>{};
    for (final p in _repo.products) {
      if (p.brand.isNotEmpty) names.add(p.brand);
    }
    return names.toList()..sort();
  }

  List<Product> get results {
    // Pharmacy (shop=<id>), offers (offers=1), sort (including best/
    // rating), and brand (comma-separated real ids) are all real
    // server-side params now (confirmed 2026-09-17/18) — the server
    // already returns exactly the right page for all four, so none of
    // them need a second client-side pass here anymore. concern still
    // does — no server param confirmed for it yet.
    var list = List<Product>.from(_fetched);
    if (concern != null) list = list.where((p) => p.concern == concern).toList();
    return list;
  }
}
