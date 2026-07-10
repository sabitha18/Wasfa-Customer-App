import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../core/network/api_exception.dart';
import '../core/utils/auth_gate.dart';
import '../core/widgets/async_state_view.dart';
import '../data/models/cart_line.dart';
import '../data/models/product.dart';
import '../data/models/promo.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/services/account_service.dart';
import 'auth_state.dart';

/// Holds the shopping cart (CART), the prescription cart (RXCART), and the
/// wishlist. This is the Flutter analogue of the JS globals `CART`, `RXCART`,
/// `WISH` plus the pure functions `cartGroups/lineCharge/groupSub/phFee/
/// deliveryTotal/computeTotals` from the HTML prototype — kept together here
/// because in the source they all operate on the same cart state.
class CartState extends ChangeNotifier {
  final Map<String, CartLine> cart = {}; // "productId_seller" -> line
  final Map<String, CartLine> rxCart = {}; // "rxId#idx" -> line
  final Set<int> wishlist = {};

  String cartTab = 'my'; // 'my' | 'rx'
  bool deliverTogether = false;
  String? selectedPromoCode; // null = auto-best, '__none__' = explicitly none

  Map<String, CartLine> get activeStore => cartTab == 'rx' ? rxCart : cart;

  // ---------------------------------------------------------------- cart ops
  void addToCart(Product p, {required String seller, required double price, double? was, int? apiProductId}) {
    final key = '${p.id}_$seller';
    if (cart.containsKey(key)) {
      cart[key]!.qty++;
    } else {
      cart[key] = CartLine(key: key, productId: p.id, apiProductId: apiProductId, seller: seller, price: price, was: was);
    }
    notifyListeners();
  }

  void setQty(String key, int delta, {bool rx = false}) {
    final store = rx ? rxCart : cart;
    final line = store[key];
    if (line == null) return;
    line.qty += delta;
    if (line.qty <= 0) store.remove(key);
    notifyListeners();
  }

  void removeLine(String key, {bool rx = false}) {
    (rx ? rxCart : cart).remove(key);
    notifyListeners();
  }

  void clearCart() {
    cart.clear();
    notifyListeners();
  }

  void clearRxCart() {
    rxCart.clear();
    notifyListeners();
  }

  void setCartTab(String tab) {
    cartTab = tab;
    notifyListeners();
  }

  void toggleDeliverTogether() {
    deliverTogether = !deliverTogether;
    notifyListeners();
  }

  void toggleWish(int productId) {
    if (wishlist.contains(productId)) {
      wishlist.remove(productId);
    } else {
      wishlist.add(productId);
    }
    notifyListeners();
  }

  bool isWished(int productId) => wishlist.contains(productId);

  bool wishlistLoading = false;

  /// Replaces the local wishlist with the server's copy — call after login
  /// and whenever the Wishlist tab is opened, matching skus back to catalog
  /// product ids via [CatalogRepository]'s cache.
  Future<void> loadWishlistRemote(int userId) async {
    wishlistLoading = true;
    notifyListeners();
    try {
      final skus = await AccountService.instance.wishlist(userId);
      final repo = CatalogRepository.instance;
      wishlist
        ..clear()
        ..addAll(repo.products.where((p) => skus.contains(p.sku)).map((p) => p.id));
    } catch (_) {
      // Non-fatal — keep whatever was already there locally.
    } finally {
      wishlistLoading = false;
      notifyListeners();
    }
  }

  /// Toggles the wishlist optimistically, then syncs to the server —
  /// requires sign-in (per the `/acct/wish-toggle` endpoint). Reverts and
  /// shows an error toast if the request fails.
  Future<void> toggleWishRemote(BuildContext context, Product product) async {
    if (!await requireLogin(context)) return;
    if (!context.mounted) return;
    final auth = context.read<AuthState>();
    toggleWish(product.id);
    try {
      await AccountService.instance.toggleWish(auth.userId!, product.sku.isNotEmpty ? product.sku : product.id.toString());
    } catch (e) {
      toggleWish(product.id); // revert
      if (context.mounted) showErrorToast(context, describeError(e));
    }
  }

  int get cartCount => cart.values.fold(0, (s, l) => s + l.qty);
  int get rxCartCount => rxCart.values.fold(0, (s, l) => s + l.qty);

  // ------------------------------------------------------------ pure totals
  /// Free-of-charge units for BOGO ("1+1") lines.
  int _freeUnits(CartLine line) {
    if (line.productId == null) return 0;
    final p = CatalogRepository.instance.findProduct(line.productId!);
    if (p == null || !p.isBogo) return 0;
    return line.qty ~/ 2;
  }

  double lineCharge(CartLine line) => line.price * (line.qty - _freeUnits(line));

  /// Groups a store's lines by seller/pharmacy name.
  Map<String, List<CartLine>> groupsFor(Map<String, CartLine> store) {
    final g = <String, List<CartLine>>{};
    for (final line in store.values) {
      g.putIfAbsent(line.seller, () => []).add(line);
    }
    return g;
  }

  double groupSubtotal(List<CartLine> items) =>
      items.fold(0.0, (s, l) => s + lineCharge(l));

  double pharmacyFee(double sub) => sub >= 3 ? 0 : 0.750;

  double cartSubtotal(Map<String, CartLine> store) =>
      store.values.fold(0.0, (s, l) => s + lineCharge(l));

  double deliveryTotal(Map<String, List<CartLine>> groups) {
    if (deliverTogether && groups.keys.length > 1) return 1.250;
    return groups.values.fold(0.0, (s, items) => s + pharmacyFee(groupSubtotal(items)));
  }

  List<Promo> applicablePromos(double sub) =>
      CatalogRepository.instance.promos.where((p) => sub >= p.min).toList();

  Promo? bestPromo(double sub, double fee) {
    Promo? best;
    double bestSave = 0;
    for (final p in applicablePromos(sub)) {
      final s = p.savings(sub, fee);
      if (s > bestSave) {
        bestSave = s;
        best = p;
      }
    }
    return best;
  }

  Promo? activePromo(double sub, double fee) {
    if (selectedPromoCode == '__none__') return null;
    if (selectedPromoCode != null) {
      final p = CatalogRepository.instance.promos
          .where((p) => p.code == selectedPromoCode)
          .cast<Promo?>()
          .firstWhere((p) => p != null, orElse: () => null);
      if (p != null && sub >= p.min) return p;
    }
    return bestPromo(sub, fee);
  }

  /// Full checkout totals — mirrors JS `computeTotals()`.
  CheckoutTotals computeTotals() {
    final store = cartTab == 'rx' ? rxCart : cart;
    final groups = groupsFor(store);
    final before = store.values.fold(0.0, (s, l) => s + l.lineTotalBeforeDiscount);
    final sub = cartSubtotal(store);
    final itemDiscount = double.parse((before - sub).toStringAsFixed(3));
    final fee = deliveryTotal(groups);
    final promo = activePromo(sub, fee);
    final promoDiscount = promo?.savings(sub, fee) ?? 0;
    final total = (promo?.type == PromoType.freeDelivery)
        ? sub
        : double.parse((sub + fee - promoDiscount).toStringAsFixed(3));
    return CheckoutTotals(
      groups: groups,
      before: before,
      subtotal: sub,
      itemDiscount: itemDiscount,
      deliveryFee: fee,
      promo: promo,
      promoDiscount: promoDiscount,
      total: total,
      due: total,
    );
  }
}

class CheckoutTotals {
  final Map<String, List<CartLine>> groups;
  final double before;
  final double subtotal;
  final double itemDiscount;
  final double deliveryFee;
  final Promo? promo;
  final double promoDiscount;
  final double total;
  final double due;

  const CheckoutTotals({
    required this.groups,
    required this.before,
    required this.subtotal,
    required this.itemDiscount,
    required this.deliveryFee,
    required this.promo,
    required this.promoDiscount,
    required this.total,
    required this.due,
  });
}
