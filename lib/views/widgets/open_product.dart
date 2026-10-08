import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_routes.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/models/product.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/services/catalog_service.dart';
import '../../state/locale_state.dart';

/// Opens the product a BANNER points at (`link_type: "product"`).
///
/// [ref] is the banner's `link_ref` (Home) / `link_id` (seller), read as TEXT:
/// the product's SKU. [name] is the banner's `link_target` / `link_label`.
///
/// The product page loads by SKU — `GET /app/product/<product id>` does NOT
/// work (tested 2026-10-07: `/app/product/109803` -> 404 "Not found") — so:
///   1. try [ref] as a SKU (`GET /app/product/<ref>`);
///   2. if that finds nothing, look the product up by NAME through the
///      products listing and open it on an exact id (when [ref] is a number)
///      or exact name match. This is for older banners still saved with a
///      product id instead of a SKU; once every product banner carries a SKU
///      it never runs;
///   3. otherwise say it's unavailable rather than open a wrong product.
///
/// Guard: a purely numeric [ref] could be a product id that happens to equal
/// some OTHER product's numeric SKU (the collection has SKUs like "11785"), so
/// in that case a SKU hit is only accepted if its name matches the banner's.
/// A ref with letters can't be an id, so it's trusted as the SKU it is.
Future<void> openProductFromBanner(BuildContext context, String ref, String name) async {
  final ar = context.read<LocaleState>().isArabic;
  final nav = Navigator.of(context);
  final code = ref.trim();
  final wanted = name.trim();

  showBusyOverlay(context, message: ar ? 'جارٍ فتح المنتج…' : 'Opening product…');
  final hit = await _bySku(code, wanted) ?? await _byNameSearch(code, wanted);
  if (context.mounted) hideBusyOverlay(context);

  if (hit != null && context.mounted) {
    CatalogRepository.instance.cacheProducts([hit]);
    nav.pushNamed(Routes.product, arguments: hit.id);
    return;
  }
  if (context.mounted) {
    showErrorToast(context, ar ? 'هذا المنتج غير متاح حاليًا' : 'This product isn\'t available right now');
  }
}

bool _sameName(Product p, String name) {
  final wanted = name.trim();
  return p.nameEn.trim().toLowerCase() == wanted.toLowerCase() || p.nameAr.trim() == wanted;
}

Future<Product?> _bySku(String code, String name) async {
  if (code.isEmpty) return null;
  try {
    final fresh = await CatalogService.instance.product(code);
    final numeric = RegExp(r'^\d+$').hasMatch(code);
    if (numeric && name.isNotEmpty && !_sameName(fresh, name)) return null;
    return fresh;
  } catch (_) {
    return null; // not a SKU (e.g. an old banner's product id) — try the name search
  }
}

Future<Product?> _byNameSearch(String code, String name) async {
  if (name.isEmpty) return null;
  try {
    final page = await CatalogService.instance.products(query: name, perPage: 48);
    final id = int.tryParse(code);
    if (id != null) {
      for (final p in page.items) {
        if (p.id == id) return p;
      }
    }
    for (final p in page.items) {
      if (_sameName(p, name)) return p;
    }
  } catch (_) {
    // fall through to null
  }
  return null;
}
