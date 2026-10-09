import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/auth_state.dart';
import '../routing/app_routes.dart';

/// Call before any account-gated action (checkout, wishlist, addresses,
/// orders, wallet, rx). If already signed in, resolves immediately with
/// `true`. Otherwise pushes the login flow and resolves with whatever the
/// person did there.
///
/// ```dart
/// if (!await requireLogin(context)) return;
/// // proceed with the signed-in-only action
/// ```
///
/// [message] (optional) is shown at the top of the login screen to explain
/// why it opened — e.g. from the cart's Checkout button.
Future<bool> requireLogin(BuildContext context, {String? message}) async {
  final auth = context.read<AuthState>();
  if (auth.isSignedIn) return true;
  final result = await Navigator.of(context).pushNamed(Routes.login, arguments: message);
  return result == true;
}
