import 'package:flutter/material.dart';
import '../../core/utils/json_utils.dart';

class PharmacyStore {
  /// Backend store id from `GET /app/stores` — this is the shop's `user_id`,
  /// and the value the product listing expects as `?shop=<id>` to filter to
  /// just this store's catalogue. Null for the local mock stores.
  final int? id;
  final String name;
  final String nameAr;
  final String area;
  final String category; // pharmacy, beauty, eyecare, nutrition
  final String eta; // "20-30"
  final bool fast;
  final bool pro;
  final bool freeDelivery;
  final String? offer; // non-null = "has an offer" (UI just checks null vs not, never reads the text)
  final String seller; // maps to Seller.name used across PRODUCTS
  final int? productCount; // `products` count from GET /app/stores, if the card ever wants to show it
  /// Not part of the confirmed live `/app/stores` shape yet — every known
  /// response only has {id, name, name_ar, area, category, products, eta,
  /// free, pro, offers, seller}, no image field at all. Parsed
  /// speculatively against a few likely key names so store cards pick it
  /// up the moment backend adds one, with zero code changes needed here.
  /// Null today for every real store — see _StoreAvatar in home_screen.dart
  /// for the gradient+monogram fallback every store currently shows.
  final String? logoUrl;
  final List<Color> gradient;
  final String monogram;

  const PharmacyStore({
    this.id,
    required this.name,
    required this.nameAr,
    required this.area,
    required this.category,
    required this.eta,
    required this.fast,
    required this.pro,
    required this.freeDelivery,
    this.offer,
    required this.seller,
    this.productCount,
    this.logoUrl,
    required this.gradient,
    required this.monogram,
  });

  String label(bool arabic) => arabic ? nameAr : name;

  /// From `GET /app/stores` list items — shape confirmed against a live
  /// Postman response:
  /// `{ id, name, name_ar, area, category, products, eta, free, pro, offers, seller }`.
  ///
  /// Visual-only fields the API doesn't carry (a brand `gradient` and a
  /// `monogram`) are derived locally so the existing store cards render
  /// without any server-side design metadata.
  factory PharmacyStore.fromJson(Map<String, dynamic> json) {
    final name = asString(json, const ['name', 'store_name', 'title']);
    final monogram = asString(json, const ['monogram']);
    final eta = asString(json, const ['eta', 'delivery_eta']);
    final area = asString(json, const ['area', 'area_name']);
    return PharmacyStore(
      // The shop's `user_id` — sent back as `?shop=<id>` to filter products.
      id: asIntOrNull(json, const ['id', 'user_id', 'store_id', 'seller_id']),
      name: name,
      nameAr: asString(json, const ['name_ar', 'arabic_name'], fallback: name),
      area: area,
      category: asString(json, const ['category', 'type'], fallback: 'pharmacy'),
      // The live endpoint sends '' rather than omitting the key when there's
      // no ETA yet — used to substitute a fake "30-45" placeholder here,
      // which looked exactly like a real estimate. Left genuinely empty
      // now; callers show "ETA unavailable" instead (see home_screen.dart).
      eta: eta,
      fast: asBool(json, const ['fast']),
      pro: asBool(json, const ['pro']),
      // Real key is `free` (bool). Kept the old candidates too in case an
      // older/alternate response shape is ever hit. Defaults to false (not
      // true) if none of these keys exist at all — claiming delivery is
      // free when that's genuinely unconfirmed could mislead someone about
      // cost, which is worse than just not showing the "Free delivery" badge.
      freeDelivery: (json.containsKey('free') || json.containsKey('free_delivery') || json.containsKey('freeDelivery'))
          ? asBool(json, const ['free', 'free_delivery', 'freeDelivery'])
          : false,
      // Real key is `offers` (bool: does this store have any offers right
      // now), not a text label — the UI only ever checks offer != null, so
      // map true -> a non-null marker, false/absent -> null.
      offer: asBool(json, const ['offers', 'has_offers']) ? 'offers' : asStringOrNull(json, const ['offer', 'offer_label']),
      seller: asString(json, const ['seller', 'seller_name', 'name']),
      productCount: asIntOrNull(json, const ['products', 'product_count']),
      logoUrl: asStringOrNull(json, const ['logo', 'logo_url', 'image', 'image_url', 'store_logo', 'avatar']),
      gradient: _gradientFor(name),
      monogram: monogram.isNotEmpty ? monogram : (name.isNotEmpty ? name[0].toUpperCase() : '℞'),
    );
  }

  static const List<List<Color>> _paletteGradients = [
    [Color(0xFF7C5CFF), Color(0xFF1E9CD7)],
    [Color(0xFF023B60), Color(0xFF1E9CD7)],
    [Color(0xFF0B6B4F), Color(0xFF23B487)],
    [Color(0xFF7A1F1F), Color(0xFFB34B4B)],
    [Color(0xFF0E3554), Color(0xFF1E9CD7)],
    [Color(0xFFE7609F), Color(0xFFF6A5C0)],
  ];

  /// Deterministic gradient per store so the same store always looks the same.
  static List<Color> _gradientFor(String key) {
    if (key.isEmpty) return _paletteGradients.first;
    return _paletteGradients[key.hashCode.abs() % _paletteGradients.length];
  }
}

class StoreCategory {
  final String key;
  final String emoji;
  final String labelEn;
  final String labelAr;
  const StoreCategory(this.key, this.emoji, this.labelEn, this.labelAr);
}
