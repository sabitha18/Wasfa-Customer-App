import '../../core/utils/json_utils.dart';

/// `GET /app/seller/{shop_id}/banners` — confirmed live (2026-09-17):
/// `{ banners: [{ id, image, title, description, button_show, button_text,
/// link_type, link_id, link_label }] }`. Closes a real gap — the Store
/// screen's promo carousel used to be 3 entirely hardcoded cards, identical
/// on every single seller's page, with no backend control at all.
///
/// [linkType]/[linkId]/[linkLabel] describe where a tap should navigate.
/// Confirmed live (2026-10-07, seller 18398): `"none"`; `"brand"`
/// (`link_id: 268, link_label: "Korff"`); `"product"`
/// (`link_id: 109803, link_label: "Korff Depigmeting Aa-Pe Face Serum"`).
/// store_screen.dart also handles `category` on the assumption it follows the
/// same shape (id in [linkId], name in [linkLabel]) — not yet seen in a real
/// seller-banner response — and falls back to opening this store's own Shop
/// listing for `"none"` and anything else.
class SellerBanner {
  final int id;
  final String image;
  final String title;
  final String description;
  final bool buttonShow;
  final String buttonText;
  final String linkType;
  final int? linkId;
  /// `link_id` exactly as sent, as text — for `product` banners, where it's a
  /// SKU that a whole-number parse would throw away.
  final String? linkIdText;
  final String? linkLabel;

  const SellerBanner({
    required this.id,
    required this.image,
    required this.title,
    required this.description,
    required this.buttonShow,
    required this.buttonText,
    required this.linkType,
    this.linkId,
    this.linkIdText,
    this.linkLabel,
  });

  factory SellerBanner.fromJson(Map<String, dynamic> json) => SellerBanner(
        id: asInt(json, const ['id']),
        image: asString(json, const ['image']),
        title: asString(json, const ['title']),
        description: asString(json, const ['description']),
        buttonShow: asBool(json, const ['button_show']),
        buttonText: asString(json, const ['button_text']),
        linkType: asString(json, const ['link_type'], fallback: 'none'),
        linkId: asIntOrNull(json, const ['link_id']),
        linkIdText: asNonEmptyStringOrNull(json, const ['link_id']),
        linkLabel: asStringOrNull(json, const ['link_label']),
      );
}
