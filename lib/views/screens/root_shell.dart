import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/cart_state.dart';
import 'account_screen.dart';
import 'home_screen.dart';
import 'shop_screen.dart';
import 'wishlist_screen.dart';
import '../widgets/app_top_bar.dart';

/// The persistent 4-tab shell — Home / Shop / Wishlist / Account — matching
/// `renderBnav()` in the HTML prototype. The Home tab also carries the
/// `.appbar` (location row + search bar) from `renderAppbar()`, since that
/// appbar is only shown on home/store/shop/wishlist/account in the HTML.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartState>();

    final pages = [
      Scaffold(appBar: const AppTopBar(), body: const HomeScreen()),
      const ShopScreen(),
      Scaffold(appBar: AppBar(title: const Text('Wishlist')), body: const WishlistScreen()),
      Scaffold(appBar: AppBar(title: const Text('Account')), body: const AccountScreen()),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
          const BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: 'Shop'),
          BottomNavigationBarItem(
            icon: Badge(
              label: Text('${cart.wishlist.length}'),
              isLabelVisible: cart.wishlist.isNotEmpty,
              child: const Icon(Icons.favorite_border_rounded),
            ),
            label: 'Wishlist',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded), label: 'Account'),
        ],
      ),
    );
  }
}

