import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/widgets/async_state_view.dart';
import '../../state/address_state.dart';
import '../../state/auth_state.dart';
import '../widgets/page_header.dart';
import '../widgets/toast.dart';
import 'address_form_screen.dart';

/// Account → "Addresses": lists the customer's saved delivery addresses with
/// Add / Edit / Delete, backed by [AddressState] (which talks to
/// `/acct/addresses`, `/acct/address-save`, `/acct/address-delete`).
///
/// Previously the Account row jumped straight into Checkout — this is the
/// dedicated management screen it should have opened instead.
class AddressListScreen extends StatefulWidget {
  const AddressListScreen({super.key});

  @override
  State<AddressListScreen> createState() => _AddressListScreenState();
}

class _AddressListScreenState extends State<AddressListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final addressState = context.read<AddressState>();
      addressState.loadAreas();
      final auth = context.read<AuthState>();
      if (auth.isSignedIn) addressState.loadAddresses(auth.userId!);
    });
  }

  Future<void> _openForm(int index) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddressFormScreen(index: index)),
    );
    // AddressState notifies on save, so the watched list rebuilds on return.
  }

  Future<void> _delete(int index) async {
    final addressState = context.read<AddressState>();
    final auth = context.read<AuthState>();
    if (!auth.isSignedIn) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete address?'),
        content: const Text('This address will be removed from your account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await addressState.deleteRemote(auth.userId!, index);
      if (mounted) showToast(context, 'Address deleted');
    } catch (e) {
      if (mounted) showErrorToast(context, describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final addressState = context.watch<AddressState>();
    final auth = context.watch<AuthState>();
    final addresses = addressState.addresses;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: PageHeader(title: 'Delivery addresses'),
      body: addressState.addressesLoading && addresses.isEmpty
          ? const LoadingView(message: 'Loading addresses…')
          : (addressState.addressesError != null && addresses.isEmpty)
              ? ErrorRetryView(
                  message: addressState.addressesError!,
                  onRetry: () => auth.isSignedIn ? addressState.loadAddresses(auth.userId!) : null,
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    if (addressState.addressesError != null)
                      InlineErrorBanner(
                        message: addressState.addressesError!,
                        onRetry: () => auth.isSignedIn ? addressState.loadAddresses(auth.userId!) : null,
                      ),
                    for (var i = 0; i < addresses.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 11),
                        child: _AddressRow(
                          title: addresses[i].title,
                          detail: addresses[i].formatted,
                          onEdit: () => _openForm(i),
                          onDelete: () => _delete(i),
                        ),
                      ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.navy, width: 1.5),
                          foregroundColor: AppColors.navy,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                        ),
                        onPressed: () async {
                          if (!await requireLogin(context)) return;
                          if (!mounted) return;
                          _openForm(-1);
                        },
                        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.add, size: 18),
                          SizedBox(width: 6),
                          Text('Add new address', style: TextStyle(fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  final String title;
  final String detail;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _AddressRow({required this.title, required this.detail, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.line, width: 1.5),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.location_on_outlined, size: 20, color: AppColors.navy),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.navy)),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(detail, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
                ],
              ],
            ),
          ),
          InkWell(
            onTap: onEdit,
            borderRadius: BorderRadius.circular(15),
            child: const SizedBox(width: 34, height: 34, child: Icon(Icons.edit_outlined, size: 18, color: AppColors.sky)),
          ),
          InkWell(
            onTap: onDelete,
            borderRadius: BorderRadius.circular(15),
            child: const SizedBox(width: 34, height: 34, child: Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.rose)),
          ),
        ],
      ),
    );
  }
}
