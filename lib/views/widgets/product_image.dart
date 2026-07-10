import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/product.dart';

/// Renders [Product.imageUrl] when the API provided one, falling back to the
/// emoji placeholder (used for mock data, or if the photo fails to load).
class ProductImage extends StatelessWidget {
  final Product product;
  final double height;
  final double emojiSize;
  const ProductImage({super.key, required this.product, required this.height, this.emojiSize = 40});

  @override
  Widget build(BuildContext context) {
    final url = product.imageUrl;
    if (url == null || url.isEmpty) {
      return Container(
        height: height,
        width: double.infinity,
        color: AppColors.blush,
        alignment: Alignment.center,
        child: Text(product.emoji, style: TextStyle(fontSize: emojiSize)),
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
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
        errorBuilder: (context, error, stackTrace) => Container(
          color: AppColors.blush,
          alignment: Alignment.center,
          child: Text(product.emoji, style: TextStyle(fontSize: emojiSize)),
        ),
      ),
    );
  }
}
