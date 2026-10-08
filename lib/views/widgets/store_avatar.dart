import 'package:flutter/material.dart';
import '../../data/models/pharmacy_store.dart';

/// A store's logo: [PharmacyStore.logoUrl] (the `logo` field `/app/stores`
/// sends) when there is one, otherwise the gradient + monogram square. A
/// failed image load falls back the same way rather than showing a
/// broken-image icon, matching ProductImage's pattern elsewhere in the app.
///
/// Shared by the Home store cards/rows and the Store screen's header, so a
/// store looks the same everywhere. (Used to be private to home_screen.dart,
/// which is why the Store screen kept showing only the monogram.)
class StoreAvatar extends StatelessWidget {
  final PharmacyStore store;
  final double size;
  final double borderRadius;
  final double fontSize;
  final List<BoxShadow>? boxShadow;
  const StoreAvatar({super.key, required this.store, required this.size, required this.borderRadius, required this.fontSize, this.boxShadow});

  @override
  Widget build(BuildContext context) {
    final monogramBox = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: store.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: boxShadow,
      ),
      alignment: Alignment.center,
      child: Text(store.monogram, style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.w800)),
    );
    final logo = store.logoUrl;
    if (logo == null || logo.isEmpty) return monogramBox;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(borderRadius), boxShadow: boxShadow),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.network(
          logo,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => monogramBox,
        ),
      ),
    );
  }
}
