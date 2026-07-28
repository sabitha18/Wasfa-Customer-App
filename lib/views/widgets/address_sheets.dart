import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/models/address.dart';
import '../../state/address_state.dart';
import '../../state/auth_state.dart';
import '../../state/location_state.dart';
import 'toast.dart';

/// `.sh-h`/`.sh-b`/`.sh-f` — address picker sheet matching `openAddrPicker()`.
/// Originally private to the checkout screen; pulled out here so Account's
/// "Delivery addresses" row (and the Home header's "Deliver to ..." row) can
/// open the exact same sheet UI/flow instead of a separate full-page screen.
///
/// [locationState] powers the "Current location" tile at the top — tapping
/// it switches [AddressState.useCurrentLocation] back on instead of picking
/// one of the saved addresses below.
void showAddressPickerSheet(BuildContext context, AddressState addressState, LocationState locationState) {
  showModalBottomSheet(
    context: context,
    // Was missing before — without this, showModalBottomSheet caps the
    // sheet at roughly half the screen's height and gives its content no
    // scrolling ability at all. With more than ~4 saved addresses (or on a
    // shorter phone), everything past that cutoff — including "Add new
    // address" — became completely unreachable, with no scroll indicator
    // or any other sign there was more content below.
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (sheetContext) => SafeArea(
      // Caps the sheet at 85% of the screen so the drag-handle area at the
      // very top always stays visible, while letting the body underneath
      // scroll for however many addresses there are.
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // .sh-h — fixed header, stays put while the list below scrolls
            Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line, width: 1))),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Delivery addresses', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.navy)),
                InkWell(onTap: () => Navigator.pop(context), child: const Icon(Icons.close_rounded, size: 20, color: AppColors.muted)),
              ]),
            ),
            // .sh-b — address rows styled like .payopt — now scrollable
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
                child: Column(children: [
              // "Current location" — GPS-detected, selected by default until
              // the person explicitly picks a saved address below.
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: GestureDetector(
                  onTap: () {
                    addressState.selectCurrentLocation();
                    // Refresh the GPS fix/reverse-geocode, then try to match
                    // it against the real /areas catalog so "Current
                    // location" carries an actual governorate/area (not
                    // just a display label) for delivery-fee calculation
                    // and order placement.
                    locationState.retry().then((_) => addressState.syncFromLocation(
                          governorate: locationState.governorate,
                          area: locationState.area,
                          street: locationState.street,
                        ));
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: addressState.isCurrentLocationActive ? const Color(0xFFF2FAFE) : Colors.white,
                      border: Border.all(color: addressState.isCurrentLocationActive ? AppColors.sky : AppColors.line, width: 1.5),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(children: [
                      const Icon(Icons.my_location_rounded, size: 20, color: AppColors.navy),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Current location', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.navy)),
                            const SizedBox(height: 2),
                            Text(
                              // Once a real match attempt has confirmed this
                              // GPS location doesn't correspond to anywhere
                              // in the delivery area catalog, say so plainly
                              // instead of showing a location label that
                              // implies it's usable when it isn't — this is
                              // exactly the mismatch that used to show
                              // "Current location" selected here while
                              // Checkout quietly used a different address.
                              addressState.useCurrentLocation && addressState.currentLocationMatchFailed
                                  ? "Doesn't match a delivery area — using your saved address instead"
                                  : (locationState.formatted?.isNotEmpty == true ? locationState.formatted! : 'Detects your location automatically'),
                              style: TextStyle(
                                fontSize: 11,
                                color: (addressState.useCurrentLocation && addressState.currentLocationMatchFailed) ? AppColors.rose : AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 20, height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: addressState.isCurrentLocationActive ? AppColors.sky : AppColors.line, width: 2),
                        ),
                        child: addressState.isCurrentLocationActive
                            ? Center(child: Container(width: 12, height: 12, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.sky)))
                            : null,
                      ),
                    ]),
                  ),
                ),
              ),
              for (var i = 0; i < addressState.addresses.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: GestureDetector(
                    onTap: () {
                      addressState.select(i);
                      Navigator.pop(context);
                    },
                    onLongPress: () => showAddressFormSheet(context, addressState, i),
                    child: Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: (!addressState.isCurrentLocationActive && addressState.selectedIndex == i) ? const Color(0xFFF2FAFE) : Colors.white,
                        border: Border.all(color: (!addressState.isCurrentLocationActive && addressState.selectedIndex == i) ? AppColors.sky : AppColors.line, width: 1.5),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Row(children: [
                        const Icon(Icons.location_on_outlined, size: 20, color: AppColors.navy),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Text(addressState.addresses[i].title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.navy)),
                                if (addressState.addresses[i].isDefault) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: const Color(0xFFF2FAFE), borderRadius: BorderRadius.circular(6)),
                                    child: const Text('Default', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.sky)),
                                  ),
                                ],
                              ]),
                              const SizedBox(height: 2),
                              Text(addressState.addresses[i].formatted, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                            ],
                          ),
                        ),
                        // Edit — the HTML's checkout picker doesn't need this
                        // (editing happens via the separate pencil icon next
                        // to "Shipping address"), but Account needs full
                        // management from inside this same sheet.
                        InkWell(
                          onTap: () => showAddressFormSheet(context, addressState, i),
                          borderRadius: BorderRadius.circular(15),
                          child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.edit_outlined, size: 17, color: AppColors.sky)),
                        ),
                        Container(
                          width: 20, height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: (!addressState.isCurrentLocationActive && addressState.selectedIndex == i) ? AppColors.sky : AppColors.line, width: 2),
                          ),
                          child: (!addressState.isCurrentLocationActive && addressState.selectedIndex == i)
                              ? Center(child: Container(width: 12, height: 12, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.sky)))
                              : null,
                        ),
                      ]),
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.line, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    showAddressFormSheet(context, addressState, -1);
                  },
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.add, size: 16, color: AppColors.navy),
                    SizedBox(width: 6),
                    Text('Add new address', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy, fontSize: 13.5)),
                  ]),
                ),
              ),
            ]),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// `.sh-h`/`.sh-b`/`.sh-f` — address form sheet matching `openAddrForm()`.
/// Returns `true` if a new/edited address was actually saved, `null` if the
/// sheet was dismissed without saving (back button, tapping outside, the
/// close icon) — lets a caller like Checkout's "please complete your
/// address" flow know whether to proceed or not.
Future<bool?> showAddressFormSheet(BuildContext context, AddressState addressState, int index) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => _AddressFormSheet(addressState: addressState, index: index),
  );
}

class _AddressFormSheet extends StatefulWidget {
  final AddressState addressState;
  final int index; // -1 = add new
  const _AddressFormSheet({required this.addressState, required this.index});

  @override
  State<_AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends State<_AddressFormSheet> {
  static const titles = ['Home/Apartment', 'Work', 'Other'];

  late String _title;
  int? _govId;
  int? _areaId;
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _alt;
  late final TextEditingController _block;
  late final TextEditingController _street;
  late final TextEditingController _building;
  late final TextEditingController _apt;
  late final TextEditingController _floor;
  late final TextEditingController _note;
  bool _isDefault = false;
  bool _saving = false;

  // Bounds-checked, not just non-negative — the list can change size
  // between when this sheet is requested (capturing widget.index) and
  // when it actually builds, e.g. if an in-flight loadAddresses() call
  // replaces the list with a different-length one in the meantime. An
  // index that's merely >= 0 but now out of range would otherwise crash
  // with a RangeError the moment initState tries to read addresses[index].
  bool get _isEdit => widget.index >= 0 && widget.index < widget.addressState.addresses.length;

  @override
  void initState() {
    super.initState();
    final existing = _isEdit ? widget.addressState.addresses[widget.index] : null;
    _title = titles.contains(existing?.title) ? existing!.title : titles.first;
    _govId = existing?.governorateId;
    _areaId = existing?.areaId;
    _first = TextEditingController(text: existing?.first ?? '');
    _last = TextEditingController(text: existing?.last ?? '');
    _email = TextEditingController(text: existing?.email ?? '');
    _phone = TextEditingController(text: existing?.phone ?? '');
    _alt = TextEditingController(text: existing?.alt ?? '');
    _block = TextEditingController(text: existing?.block ?? '');
    _street = TextEditingController(text: existing?.street ?? '');
    _building = TextEditingController(text: existing?.building ?? '');
    _apt = TextEditingController(text: existing?.apt ?? '');
    _floor = TextEditingController(text: existing?.floor ?? '');
    _note = TextEditingController(text: existing?.note ?? '');
    // New addresses default to "set as default" when it's the very first
    // one on the account (nothing to compare against yet); otherwise
    // reflect whatever the server already has for an existing address.
    _isDefault = existing?.isDefault ?? widget.addressState.addresses.isEmpty;
    if (widget.addressState.areaCatalog.governorates.isEmpty) {
      widget.addressState.loadAreas().then((_) => _autofillFromLocation());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autofillFromLocation());
    }
  }

  /// New addresses only — best-effort name match against `/areas`.
  void _autofillFromLocation() {
    if (!mounted || _isEdit) return;
    final location = context.read<LocationState>();
    if (!location.isReady) return;

    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    final govGuess = location.governorate;
    final areaGuess = location.area;
    if (govGuess == null && areaGuess == null) return;

    for (final g in widget.addressState.areaCatalog.governorates) {
      final govMatches = govGuess != null && (norm(g.name).contains(norm(govGuess)) || norm(govGuess).contains(norm(g.name)));
      for (final a in g.areas) {
        final areaMatches = areaGuess != null && (norm(a.name).contains(norm(areaGuess)) || norm(areaGuess).contains(norm(a.name)));
        if (areaMatches || (govMatches && areaGuess == null)) {
          setState(() {
            _govId = g.id;
            _areaId = a.id;
            if (location.street != null && location.street!.isNotEmpty && _street.text.isEmpty) _street.text = location.street!;
          });
          return;
        }
      }
    }
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    _phone.dispose();
    _alt.dispose();
    _block.dispose();
    _street.dispose();
    _building.dispose();
    _apt.dispose();
    _floor.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_govId == null || _areaId == null) {
      showErrorToast(context, 'Please choose your governorate and area.');
      return;
    }
    if (!await requireLogin(context)) return;
    if (!mounted) return;

    final address = Address(
      id: _isEdit ? widget.addressState.addresses[widget.index].id : null,
      title: _title,
      first: _first.text,
      last: _last.text,
      email: _email.text,
      phone: _phone.text,
      alt: _alt.text,
      governorateId: _govId,
      areaId: _areaId,
      block: _block.text,
      street: _street.text,
      building: _building.text,
      apt: _apt.text,
      floor: _floor.text,
      note: _note.text,
      isDefault: _isDefault,
    );

    setState(() => _saving = true);
    try {
      final auth = context.read<AuthState>();
      await widget.addressState.saveRemote(auth.userId!, address, index: _isEdit ? widget.index : null);
      if (!mounted) return;
      Navigator.pop(context, true);
      showToast(context, 'Address saved');
    } catch (e) {
      if (!mounted) return;
      showErrorToast(context, describeError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Available height once the keyboard is up — this is what was missing:
    // the old code capped the field list at 60% of the *full* screen height,
    // which doesn't shrink when the keyboard eats another 40-50% of it, so
    // header + a still-60%-tall body + footer no longer fit and overflowed.
    final maxSheetHeight = media.size.height - media.viewInsets.bottom - media.padding.top - 24;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxSheetHeight > 200 ? maxSheetHeight : media.size.height * 0.5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // .sh-h
              Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line, width: 1))),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(_isEdit ? 'Edit address' : 'Add new address', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.navy)),
                  InkWell(onTap: () => Navigator.pop(context), child: const Icon(Icons.close_rounded, size: 20, color: AppColors.muted)),
                ]),
              ),
              // .sh-b — scrollable field list; Flexible (not a fixed-height
              // ConstrainedBox) so it shrinks to whatever room is actually
              // left after the header/footer/keyboard, instead of a
              // hardcoded percentage that ignores the keyboard entirely.
              Flexible(
                child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
                child: Column(children: [
                  _AField(
                    label: 'Title',
                    required: true,
                    child: _ADropdown(value: _title, options: titles, onChanged: (v) => setState(() => _title = v)),
                  ),
                  _ARow(children: [
                    _AField(label: 'First name', required: true, child: _AInput(controller: _first)),
                    _AField(label: 'Last name', required: true, child: _AInput(controller: _last)),
                  ]),
                  _AField(label: 'Email', required: true, child: _AInput(controller: _email, keyboard: TextInputType.emailAddress)),
                  _ARow(children: [
                    SizedBox(
                      width: 64,
                      child: _AField(label: 'Phone', required: true, child: _AInput(controller: TextEditingController(text: '+965'), readOnly: true)),
                    ),
                    Expanded(
                      child: _AField(label: '\u00A0', required: false, child: _AInput(controller: _phone, hint: 'Enter phone number', keyboard: TextInputType.phone)),
                    ),
                  ]),
                  _ARow(children: [
                    SizedBox(
                      width: 64,
                      child: _AField(label: 'Alt. phone', required: false, child: _AInput(controller: TextEditingController(text: '+965'), readOnly: true)),
                    ),
                    Expanded(
                      child: _AField(label: '\u00A0', required: false, child: _AInput(controller: _alt, keyboard: TextInputType.phone)),
                    ),
                  ]),
                  _AField(
                    label: 'Governorate',
                    required: true,
                    child: _AreaIdDropdown(
                      value: _govId,
                      hint: 'Select governorate',
                      options: [for (final g in widget.addressState.areaCatalog.governorates) (id: g.id, label: g.name)],
                      onChanged: (v) => setState(() { _govId = v; _areaId = null; }),
                    ),
                  ),
                  _AField(
                    label: 'Area',
                    required: true,
                    child: _AreaIdDropdown(
                      value: _areaId,
                      hint: 'Select area',
                      options: [
                        for (final g in widget.addressState.areaCatalog.governorates)
                          if (g.id == _govId)
                            for (final a in g.areas) (id: a.id, label: a.name),
                      ],
                      onChanged: (v) => setState(() => _areaId = v),
                    ),
                  ),
                  _ARow(children: [
                    _AField(label: 'Block', required: true, child: _AInput(controller: _block)),
                    _AField(label: 'Street name', required: true, child: _AInput(controller: _street)),
                  ]),
                  _ARow(children: [
                    _AField(label: 'Building', required: true, child: _AInput(controller: _building)),
                    _AField(label: 'Apartment', required: false, child: _AInput(controller: _apt)),
                  ]),
                  _AField(label: 'Floor', required: false, child: _AInput(controller: _floor)),
                  _AField(label: 'Delivery note (optional)', required: false, child: _AInput(controller: _note, hint: 'e.g. gate code, landmark…')),
                  InkWell(
                    onTap: () => setState(() => _isDefault = !_isDefault),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Container(
                          width: 20, height: 20,
                          decoration: BoxDecoration(
                            color: _isDefault ? AppColors.sky : Colors.white,
                            border: Border.all(color: _isDefault ? AppColors.sky : AppColors.line, width: 2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: _isDefault ? const Icon(Icons.check_rounded, size: 13, color: Colors.white) : null,
                        ),
                        const SizedBox(width: 10),
                        const Text('Set as default address', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.navy)),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
            // .sh-f
            Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line, width: 1))),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    elevation: 0,
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : Text(_isEdit ? 'Save address' : 'Add address', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

// ── .afield — label + input/dropdown wrapper ──
class _AField extends StatelessWidget {
  final String label;
  final bool required;
  final Widget child;
  const _AField({required this.label, required this.required, required this.child});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(required ? '$label *' : label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.navy)),
        const SizedBox(height: 5),
        child,
      ]),
    );
  }
}

// ── .arow — two fields side by side with 10px gap ──
class _ARow extends StatelessWidget {
  final List<Widget> children;
  const _ARow({required this.children});
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (children[i] is _AField) Expanded(child: children[i]) else children[i],
          if (i != children.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

// ── .afield input ──
class _AInput extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final bool readOnly;
  final TextInputType? keyboard;
  const _AInput({required this.controller, this.hint, this.readOnly = false, this.keyboard});
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboard,
      textAlign: readOnly ? TextAlign.center : TextAlign.start,
      style: TextStyle(fontSize: 13.5, color: readOnly ? AppColors.muted : AppColors.ink),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: readOnly ? AppColors.bg : Colors.white,
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.muted, fontSize: 13.5),
        contentPadding: const EdgeInsets.all(11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line, width: 1.5)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.sky, width: 1.5)),
      ),
    );
  }
}

// ── governorate/area select (id-based, from the /areas API) ──
class _AreaIdDropdown extends StatelessWidget {
  final int? value;
  final String? hint;
  final List<({int id, String label})> options;
  final ValueChanged<int?> onChanged;
  const _AreaIdDropdown({required this.value, this.hint, required this.options, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final validValue = options.any((o) => o.id == value) ? value : null;
    return DropdownButtonFormField<int>(
      value: validValue,
      hint: hint != null ? Text(hint!, style: const TextStyle(color: AppColors.muted, fontSize: 13.5)) : null,
      items: options.map((o) => DropdownMenuItem(value: o.id, child: Text(o.label, style: const TextStyle(fontSize: 13.5, color: AppColors.ink)))).toList(),
      onChanged: options.isEmpty ? null : onChanged,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line, width: 1.5)),
      ),
    );
  }
}

// ── .afield select ──
class _ADropdown extends StatelessWidget {
  final String? value;
  final String? hint;
  final List<String> options;
  final ValueChanged<String> onChanged;
  const _ADropdown({required this.value, this.hint, required this.options, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value != null && options.contains(value) ? value : null,
      hint: hint != null ? Text(hint!, style: const TextStyle(color: AppColors.muted, fontSize: 13.5)) : null,
      items: options.map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 13.5, color: AppColors.ink)))).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line, width: 1.5)),
      ),
    );
  }
}
