import '../../core/utils/json_utils.dart';

/// One entry in a product's real `reviews[]` array — confirmed live on
/// `GET /app/product/{sku}` (2026-09-17): `{ id, name, rating, comment,
/// date }`. Not present on the PLP's list items, only after a full PDP
/// fetch — same pattern as [Product.photos].
class ProductReview {
  final int? id;
  final String name;
  final int rating;
  final String comment;
  final DateTime? date;

  const ProductReview({this.id, required this.name, required this.rating, required this.comment, this.date});

  factory ProductReview.fromJson(Map<String, dynamic> json) => ProductReview(
        id: asIntOrNull(json, const ['id']),
        name: asString(json, const ['name']),
        rating: asInt(json, const ['rating']),
        comment: asString(json, const ['comment']),
        date: DateTime.tryParse(asString(json, const ['date'])),
      );
}
