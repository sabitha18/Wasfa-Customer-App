import '../../core/utils/json_utils.dart';
import 'product_review.dart';
import 'seller.dart';

class Product {
  final int id;
  /// A separate internal catalog code (e.g. `"a16346"`) — kept for display/
  /// reference, but NOT what the PDP fetch or order-line resolution should
  /// use. See [apixSku] for that.
  final String sku;
  /// The identifier the single-product endpoint actually needs —
  /// `GET /app/product/{apix_sku}` — confirmed against a real `/app/products`
  /// response where `sku` and `apix_sku` were two different values on the
  /// same item (e.g. `sku: "a16346"`, `apix_sku: "10078"`). The class doc
  /// used to claim these were interchangeable/the same field under two
  /// names — that was wrong; they're genuinely separate codes, and using
  /// `sku` for a PDP fetch or checkout's order-line resolution was sending
  /// the wrong identifier.
  final String apixSku;
  final String nameEn;
  final String nameAr;
  final String brand;
  final String category; // Medicine, Skin care, Vitamins, Mom & baby, ...
  final String concern; // pain, skin, energy, hair, baby, oral
  final String form; // "24 tablets"
  final String scientificName;
  final String emoji; // placeholder "photo" (emoji) — swap for real asset later
  final String? imageUrl; // real product photo, once the API returns one
  /// PROPOSED — NOT a confirmed live field. No `/app/products` response
  /// seen so far includes a per-brand logo/image of any kind — every
  /// product only ever carries its own plain `brand` name string, nothing
  /// else about the brand. Parsed speculatively against a few likely
  /// brand-specific key names (deliberately excluding 'image'/'image_url'/
  /// 'photo' — those are already [imageUrl]'s own keys, and reusing them
  /// here would wrongly show a product's own photo as if it were the
  /// brand's logo) so this picks up automatically the moment backend adds
  /// one, with zero code changes needed here. Null for every real product
  /// today — see StoreViewModel.brandLogosInStore for the graceful
  /// text-only fallback every brand tile currently shows.
  final String? brandLogo;
  /// ✅ Confirmed live on the PDP (`GET /app/product/{sku}`): a gallery of
  /// additional photos beyond the single [imageUrl] hero shot. Not present
  /// on the PLP's list items — only ever populated after a full PDP fetch.
  final List<String> photos;
  /// `seller_count` from the PLP — the listing endpoint only ever gives us
  /// a single synthesized [Seller] (see [Product.fromJson]), so this is what
  /// the "🏪 N pharmacies" UI should show instead of `sellers.length`. Null
  /// once a full PDP fetch has replaced [sellers] with the real list.
  final int? apiSellerCount;
  final double rating;
  /// Was `asInt(json, const ['reviews', 'reviews_count'])` — but a real PDP
  /// response has `reviews` holding the actual array of review OBJECTS
  /// (see [reviewList]), not a count at all. Since that key still exists
  /// (just with the wrong type), it got picked over `reviews_count` every
  /// time, asInt couldn't make a number out of a List, and silently fell
  /// back to 0 — every product with real reviews showed "0 reviews".
  /// Fixed by checking the definitively-numeric field first.
  final int reviews;
  /// The product's own real review entries — confirmed live on the PDP
  /// (2026-09-17), `reviews[]`: `{ id, name, rating, comment, date }`. Not
  /// present on the PLP's list items. See product_screen.dart for where
  /// this replaced a fake, hardcoded 5-star percentage breakdown
  /// (70/20/7/2/1 on every product regardless of its real distribution).
  final List<ProductReview> reviewList;
  /// Real product description HTML — confirmed live on the PDP
  /// (2026-09-17). The PDP's "Description" and "How to use" accordions
  /// used to show entirely fabricated text (a synthesized sentence built
  /// from the product's own name/scientific-name, and a generic
  /// boilerplate dosage warning) instead of this. A real response shows
  /// "how to use" content isn't even a separate field — it's just more
  /// prose inside this same HTML blob (e.g. "...</p>How To Use:<p>Use
  /// Twice aday</p>") — so the fabricated separate "How to use" section
  /// was removed rather than trying to split this apart to feed it.
  final String description;
  /// PROPOSED — confirmed present on the PDP (2026-09-17: `brand_id: 94`),
  /// not yet confirmed on the PLP (`/app/products`) list items. This is
  /// what ShopViewModel's brand filter would need to move server-side
  /// (`/app/products`'s own `brand` param takes comma-separated brand
  /// IDs, confirmed in the Postman Params tab) instead of the current
  /// client-side name matching — holding off on that rewire until the
  /// API team confirms the other open filter questions (see
  /// area file), so this is just captured for when that's ready.
  final int? brandId;
  /// Same status as [brandId] — confirmed on the PDP (`category_id: 781`),
  /// could make StoreViewModel's leaf-category-to-top-level matching
  /// (currently by name string) more reliable if also confirmed on the PLP.
  final int? categoryId;
  /// Real units-sold counter. Confirmed on the PDP as `sold`; a real PLP
  /// response (`/app/products`, 2026-09-17) uses a DIFFERENT key for the
  /// same thing — `total_sold` — and confirms it's exactly what `sort=best`
  /// orders by (items came back in strict descending `total_sold` order).
  /// This is the real "best seller" signal StoreViewModel.bestSellers now
  /// uses, replacing [isBestSeller] there (see its doc for why that was
  /// never usable — no real response has ever included the `flags` field
  /// it depends on).
  final int? sold;
  /// Confirmed live (2026-09-17) — exactly the verified-purchase signal
  /// asked for after finding "Write a review" had zero eligibility check
  /// at all (any signed-in person could review any product, whether they'd
  /// ever ordered it or not). `true` only when this user has a delivered
  /// order containing this product. See [alreadyReviewed] for the other
  /// reason the button might not apply — the two need different UI (no
  /// review option at all vs. "you already reviewed this").
  final bool canReview;
  /// Confirmed live alongside [canReview] (2026-09-17) — this user has
  /// already left a review for this product. `reviewList` already
  /// contains it if so; this just flags "don't offer to submit another".
  final bool alreadyReviewed;
  final List<String> flags; // offer, best, new
  /// Guessed field names (`tag`/`promo_tag`) that never actually matched a
  /// real response — kept only for [isBogo]'s fallback and any content
  /// that already set this directly (e.g. the Rx flow's synthesized
  /// entries). [bogoStatus]/[bogoLabel] below are the confirmed-live
  /// fields; prefer those.
  final String? tag; // "1+1"
  /// Confirmed live on `/app/products` (2026-07-29): whether this exact
  /// product+seller row is a real "Buy 1 Get 1" (or similar) promotion,
  /// and the exact label the backend wants shown for it (e.g. "Buy 1 Get
  /// 1") — NOT a guess like [tag] was. See [isBogo]/[bogoDisplayLabel].
  final bool bogoStatus;
  final String? bogoLabel;
  /// The dashboard's product "tags" field — confirmed by the client as the
  /// actual intended source for the PDP's "Key benefits" chips (e.g. "Female
  /// care"). This is distinct from [flags] ('offer'/'best'/'new' — UI
  /// behaviour flags) and from [tag] (the "1+1" promo badge) — `tags` here
  /// is free-form editorial content set per-product in the dashboard.
  final List<String> tags;
  final List<Seller> sellers;
  /// Confirmed live on `/app/products` list items — whether the *signed-in*
  /// user already has this wished/carted, straight from the server rather
  /// than something the app has to infer from local state. `offerStatus`/
  /// `discountPct` are the real discount signal (see [isOffer]) — replacing
  /// the old approach of guessing from a `was`/`compare_price` value being
  /// merely present.
  final bool wishlistStatus;
  final bool cartStatus;
  /// Real quantity already in this signed-in person's cart for this exact
  /// product+seller row — confirmed added by the backend team alongside
  /// `cart_status` (2026-07-29). Null on any response that predates this
  /// field; [CartState.syncQtyFromListing] falls back to a 1-unit guess
  /// from [cartStatus] only in that case. Once this is reliably present,
  /// [cartStatus] itself becomes redundant (kept for now, harmless).
  final int? cartQty;
  final bool offerStatus;
  final int? discountPct;

  const Product({
    required this.id,
    this.sku = '',
    this.apixSku = '',
    required this.nameEn,
    required this.nameAr,
    required this.brand,
    required this.category,
    required this.concern,
    required this.form,
    required this.scientificName,
    required this.emoji,
    this.imageUrl,
    this.brandLogo,
    this.photos = const [],
    this.apiSellerCount,
    required this.rating,
    required this.reviews,
    this.reviewList = const [],
    this.description = '',
    this.brandId,
    this.categoryId,
    this.sold,
    this.canReview = false,
    this.alreadyReviewed = false,
    this.flags = const [],
    this.tag,
    this.bogoStatus = false,
    this.bogoLabel,
    this.tags = const [],
    required this.sellers,
    this.wishlistStatus = false,
    this.cartStatus = false,
    this.cartQty,
    this.offerStatus = false,
    this.discountPct,
  });

  String name(bool arabic) => arabic ? nameAr : nameEn;

  /// Prefers the confirmed `offer_status` field; falls back to the older
  /// flags/compare-price-based guess for anything that doesn't send it
  /// (e.g. a Product built before this field existed, like the Rx flow's
  /// synthesized entries).
  bool get isOffer => offerStatus || flags.contains('offer') || sellers.any((s) => s.was != null);
  /// Never true in practice — depends on a `flags` field no real
  /// `/app/products` or `/app/product/{sku}` response has ever included.
  /// Superseded by [sold]: StoreViewModel.bestSellers sorts by that
  /// directly now (confirmed live, 2026-09-17) instead of checking this.
  /// Kept only in case some other response shape does send `flags` one day.
  bool get isBestSeller => flags.contains('best');

  /// What to actually pass to `GET /app/product/{..}` — ✅ confirmed live
  /// (2026-07-24): this endpoint wants [sku], NOT [apixSku] — passing
  /// apix_sku here 404s. Falls back to [apixSku] then [id] only if [sku]
  /// is genuinely empty, so a PDP fetch is at least attempted rather than
  /// skipped outright. (Note this is the OPPOSITE priority from the
  /// wishlist-toggle endpoint, which wants the real [sku] too, but for a
  /// different confirmed reason — see [AccountService.toggleWish]'s doc.
  /// Different endpoints on this backend genuinely want different
  /// identifiers; there's no one universal rule here.)
  String get pdpIdentifier => sku.isNotEmpty ? sku : (apixSku.isNotEmpty ? apixSku : id.toString());
  bool get isNew => flags.contains('new');
  bool get isBogo => bogoStatus || tag == '1+1';
  /// What the badge/label should actually say — the backend's own
  /// [bogoLabel] when present, falling back to a generic "Buy 1 Get 1"
  /// only if [bogoStatus] is true but the label itself is missing for some
  /// reason.
  String? get bogoDisplayLabel => isBogo ? (bogoLabel ?? 'Buy 1 Get 1') : null;

  /// Lowest in-stock price across sellers (falls back to any seller).
  double get bestPrice {
    if (sellers.isEmpty) return 0;
    final inStock = sellers.where((s) => s.stock).toList();
    final pool = inStock.isNotEmpty ? inStock : sellers;
    return pool.map((s) => s.price).reduce((a, b) => a < b ? a : b);
  }

  /// Strike-through price associated with the best-price seller, if any.
  double? get bestWasPrice {
    if (sellers.isEmpty) return null;
    final s = sellers.firstWhere(
      (s) => s.price == bestPrice,
      orElse: () => sellers.first,
    );
    return s.was;
  }

  Seller sellerByName(String name) =>
      sellers.firstWhere((s) => s.name == name, orElse: () => sellers.first);

  /// Cheapest in-stock seller, matching JS `selSeller()` default behaviour.
  Seller get defaultSeller {
    final inStock = sellers.where((s) => s.stock).toList()
      ..sort((a, b) => a.price.compareTo(b.price));
    return inStock.isNotEmpty ? inStock.first : sellers.first;
  }

  int get sellerCount => apiSellerCount ?? sellers.length;

  static const Map<String, String> _categoryEmoji = {
    'Medicine': '💊',
    'Hair care': '💇',
    'Skin care': '🧴',
    'Vitamins': '🟡',
    'Mom & baby': '🍼',
    'Personal care': '🪥',
    'Health': '❤️',
  };

  /// PLP item: confirmed live shape includes `product_id`, `sku`,
  /// `apix_sku`, `name`, `name_ar`, `brand`, `category`, `image`, `price`,
  /// `seller_count`, `pharmacy_name`, `wishlist_status`, `cart_status`,
  /// `cart_qty`, `bogo_status`, `bogo_label`, `in_stock`, `rating`, `unit`,
  /// `min_qty`, `compare_price`, `offer_status`, `discount_pct` — each PLP
  /// row is already scoped to one
  /// specific seller's listing (hence `pharmacy_name`/`price` sitting at
  /// the top level, not nested); `seller_count` just hints there may be
  /// more sellers to see via the PDP, which is where a real `sellers[]`
  /// array replaces the single synthesized one built below.
  factory Product.fromJson(Map<String, dynamic> json) {
    final sku = asString(json, const ['sku']);
    final apixSku = asString(json, const ['apix_sku']);
    // Some identifier to key the product on internally even if neither of
    // the above is present for some reason.
    final anyId = sku.isNotEmpty ? sku : (apixSku.isNotEmpty ? apixSku : asString(json, const ['id']));
    final category = asString(json, const ['category']);
    final sellersJson = asList(json, const ['sellers']);
    final sellers = sellersJson.isNotEmpty
        ? sellersJson.map((e) => Seller.fromJson(e as Map<String, dynamic>)).toList()
        : <Seller>[
            if (json.containsKey('price'))
              Seller(
                productId: asIntOrNull(json, const ['product_id']),
                name: asString(json, const ['pharmacy_name', 'seller', 'pharmacy'], fallback: 'WASFA'),
                price: asDouble(json, const ['price']),
                // `compare_price` confirmed live as the real discount field —
                // kept the old guessed names after it as a fallback only.
                was: asDoubleOrNull(json, const [
                  'compare_price', 'was', 'old_price', 'compare_at_price', 'original_price', 'list_price', 'mrp', 'regular_price', 'strike_price',
                ]),
                eta: asString(json, const ['eta', 'delivery_eta']),
                stock: asBool(json, const ['in_stock', 'stock'], fallback: true),
              ),
          ];
    return Product(
      id: asInt(json, const ['id'], fallback: int.tryParse(anyId) ?? anyId.hashCode),
      sku: sku,
      apixSku: apixSku,
      nameEn: asString(json, const ['name_en', 'name']),
      nameAr: asString(json, const ['name_ar', 'nameAr']),
      brand: asString(json, const ['brand']),
      category: category,
      concern: asString(json, const ['concern']),
      form: asString(json, const ['form', 'pack_size']),
      scientificName: asString(json, const ['scientific_name', 'generic_name']),
      emoji: asStringOrNull(json, const ['emoji']) ?? _categoryEmoji[category] ?? '💊',
      imageUrl: asStringOrNull(json, const ['image', 'image_url', 'photo']),
      brandLogo: asStringOrNull(json, const ['brand_logo', 'brand_image', 'brand_icon', 'brand_photo', 'brand_logo_url']),
      photos: asList(json, const ['photos']).map((e) => e.toString()).where((s) => s.isNotEmpty).toList(),
      // Only trust `seller_count` as a display hint when this came from the
      // PLP (no full `sellers[]` array) — a PDP response's own sellers list
      // is the real, authoritative count.
      apiSellerCount: sellersJson.isEmpty ? asIntOrNull(json, const ['seller_count']) : null,
      rating: asDouble(json, const ['rating', 'avg_rating', 'reviews_avg']),
      // Fixed order — see [reviews]'s doc for why 'reviews' (an array of
      // review objects on a real PDP response) can't be checked first.
      reviews: asInt(json, const ['reviews_count', 'reviews']),
      reviewList: asList(json, const ['reviews'])
          .whereType<Map<String, dynamic>>()
          .map((e) => ProductReview.fromJson(e))
          .toList(),
      description: asString(json, const ['description']),
      brandId: asIntOrNull(json, const ['brand_id']),
      categoryId: asIntOrNull(json, const ['category_id']),
      sold: asIntOrNull(json, const ['sold', 'total_sold']),
      canReview: asBool(json, const ['can_review']),
      alreadyReviewed: asBool(json, const ['already_reviewed']),
      flags: asList(json, const ['flags']).map((e) => e.toString()).toList(),
      tag: asStringOrNull(json, const ['tag', 'promo_tag']),
      bogoStatus: asBool(json, const ['bogo_status']),
      bogoLabel: asStringOrNull(json, const ['bogo_label']),
      // Dashboard-authored "tags" field driving the PDP's "Key benefits"
      // chips — field name is a best guess ('tags') per the client's
      // description; confirm against a real response and adjust if the
      // backend uses a different key.
      tags: asList(json, const ['tags']).map((e) => e.toString()).where((s) => s.isNotEmpty).toList(),
      sellers: sellers,
      wishlistStatus: asBool(json, const ['wishlist_status']),
      cartStatus: asBool(json, const ['cart_status']),
      cartQty: asIntOrNull(json, const ['cart_qty']),
      offerStatus: asBool(json, const ['offer_status']),
      discountPct: asIntOrNull(json, const ['discount_pct']),
    );
  }
}
