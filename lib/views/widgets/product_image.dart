import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/product.dart';

/// Renders [Product.imageUrl] when the API provided one. Shows a plain empty
/// box — no emoji, no stand-in icon of any kind — when there's no photo or
/// the photo fails to load, per explicit request: nothing that could look
/// like placeholder/dummy content should ever show in the app.
class ProductImage extends StatelessWidget {
  final Product product;
  final double height;
  final double? width; // null = fill available width (grid card); set for a fixed square (list card thumbnail)
  final double emojiSize; // kept for call-site compatibility; unused now that the emoji fallback is gone
  const ProductImage({super.key, required this.product, required this.height, this.width, this.emojiSize = 40});

  @override
  Widget build(BuildContext context) {
    final url = product.imageUrl;
    if (url == null || url.isEmpty) {
      return Container(
        height: height,
        width: width ?? double.infinity,
        color: AppColors.blush,
      );
    }
    return SizedBox(
      height: height,
      width: width ?? double.infinity,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            color: AppColors.blush,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.sky),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => Container(color: AppColors.blush),
      ),
    );
  }
}
