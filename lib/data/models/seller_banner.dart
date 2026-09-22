import '../../core/utils/json_utils.dart';

/// `GET /app/seller/{shop_id}/banners` — confirmed live (2026-09-17):
/// `{ banners: [{ id, image, title, description, button_show, button_text,
/// link_type, link_id, link_label }] }`. Closes a real gap — the Store
/// screen's promo carousel used to be 3 entirely hardcoded cards, identical
/// on every single seller's page, with no backend control at all.
///
/// [linkType]/[linkId] describe where the button should navigate — only
/// `"none"` has been seen in a real response so far, so store_screen.dart's
/// button falls back to just opening this store's own Shop listing for
/// `"none"` AND for any other value, rather than guessing a mapping for
/// link types that haven't been confirmed yet.
class SellerBanner {
  final int id;
  final String image;
  final String title;
  final String description;
  final bool buttonShow;
  final String buttonText;
  final String linkType;
  final int? linkId;
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
        linkLabel: asStringOrNull(json, const ['link_label']),
      );
}
