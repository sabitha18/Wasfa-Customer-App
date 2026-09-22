import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/notification_history_store.dart';
import '../../state/address_state.dart';
import '../../state/cart_state.dart';
import '../../state/locale_state.dart';
import '../../state/location_state.dart';
import 'address_sheets.dart';

/// Matches `.appbar` — top location row (`.ab-top`/`.ab-loc`/`.ab-act`) plus
/// the `.search` bar underneath, in a single `PreferredSize` widget so it
/// slots into `Scaffold.appBar`. Per the HTML's `renderAppbar()`, this shows
/// on home/store/shop/wishlist/account — not on every screen.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartState>();
    final location = context.watch<LocationState>();
    final addressState = context.watch<AddressState>();
    final notifications = context.watch<NotificationHistoryStore>();
    final ar = context.watch<LocaleState>().isArabic;
    String t(String en, String arabic) => ar ? arabic : en;

    // "Deliver to ..." follows the device's GPS location by default; once
    // the person explicitly picks a saved address from the picker sheet,
    // it switches to showing that address instead (see AddressState.select
    // / .selectCurrentLocation).
    final usingSavedAddress = !addressState.isCurrentLocationActive && addressState.selected != null;
    final areaLabel = usingSavedAddress
        ? addressState.selected!.title
        : (location.area?.isNotEmpty == true ? location.area! : t('Current location', 'الموقع الحالي'));
    final detailLabel = usingSavedAddress
        ? addressState.selected!.formatted
        : [location.street, location.governorate].where((s) => s != null && s!.isNotEmpty).join(' · ');

    void openPicker() => showAddressPickerSheet(context, addressState, location);

    // Scoped to just this bar's own content — Scaffold.appBar is a sibling
    // slot to Scaffold.body, not a descendant of it, so a Directionality
    // wrapped around a screen's body (see AccountScreen/HomeScreen) never
    // reaches this; it needs its own, same as a bottom sheet or dialog does.
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: AppBar(
      backgroundColor: AppColors.white,
      elevation: 0,
      automaticallyImplyLeading: false,
      toolbarHeight: preferredSize.height,
      titleSpacing: 16,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: openPicker,
                child: Row(children: [
                  // .ab-loc .pin
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: AppColors.blush, borderRadius: BorderRadius.circular(11)),
                    alignment: Alignment.center,
                    child: const Icon(Icons.location_on_rounded, color: AppColors.rose, size: 18),
                  ),
                  const SizedBox(width: 8),
                ]),
              ),
              // .ab-loc .tx — current selection: GPS area, or a picked saved address
              Expanded(
                child: GestureDetector(
                  onTap: openPicker,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${t("Deliver to", "التوصيل إلى")} $areaLabel', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.navy, height: 1.15)),
                      const SizedBox(height: 1),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              detailLabel.isNotEmpty ? detailLabel : t('Tap to choose your delivery address', 'اضغط لاختيار عنوان التوصيل'),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: AppColors.muted),
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, size: 14, color: AppColors.muted),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // .ab-act
              IconBtn(
                icon: Icons.notifications_none_rounded,
                badge: notifications.unreadCount > 0 ? notifications.unreadCount : null,
                onTap: () => Navigator.pushNamed(context, Routes.notifications),
              ),
              const SizedBox(width: 7),
              IconBtn(icon: Icons.medication_outlined, onTap: () => Navigator.pushNamed(context, Routes.myRx)),
              const SizedBox(width: 7),
              IconBtn(
                icon: Icons.shopping_bag_outlined,
                badge: cart.cartCount > 0 ? cart.cartCount : null,
                onTap: () => Navigator.pushNamed(context, Routes.cart),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // .search
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, Routes.shop),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, size: 18, color: AppColors.muted),
                  const SizedBox(width: 9),
                  Text(t('Search for products or stores', 'ابحث عن منتجات أو متاجر'), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(126);
}

class IconBtn extends StatelessWidget {
  final IconData icon;
  final int? badge;
  final VoidCallback onTap;
  const IconBtn({super.key, required this.icon, required this.onTap, this.badge});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(10)),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(child: Icon(icon, size: 18, color: AppColors.navy)),
            if (badge != null)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  decoration: const BoxDecoration(color: AppColors.rose, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
