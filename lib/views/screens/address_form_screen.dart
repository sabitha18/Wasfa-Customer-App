import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/models/address.dart';
import '../../data/models/area_catalog.dart';
import '../../state/address_state.dart';
import '../../state/auth_state.dart';
import '../../state/location_state.dart';
import '../widgets/page_header.dart';
import '../widgets/toast.dart';

class AddressFormScreen extends StatefulWidget {
  final int index; // -1 to add new
  const AddressFormScreen({super.key, required this.index});

  @override
  State<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends State<AddressFormScreen> {
  late Address _draft;
  final List<String> _titles = const ['Home/Apartment', 'Work', 'Other'];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AddressState>();
    _draft = widget.index >= 0 ? _copy(state.addresses[widget.index]) : Address();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAreasAndAutofill(state));
  }

  /// New addresses only — prefills governorate/area/street from the
  /// device's current location (best-effort name match against the real
  /// `/areas` list; the person can still change anything before saving).
  Future<void> _loadAreasAndAutofill(AddressState state) async {
    await state.loadAreas();
    if (!mounted || widget.index >= 0) return;

    final location = context.read<LocationState>();
    if (!location.isReady) return;

    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    final govGuess = location.governorate;
    final areaGuess = location.area;
    if (govGuess == null && areaGuess == null) return;

    for (final g in state.areaCatalog.governorates) {
      final govMatches = govGuess != null && (norm(g.name).contains(norm(govGuess)) || norm(govGuess).contains(norm(g.name)));
      for (final a in g.areas) {
        final areaMatches = areaGuess != null && (norm(a.name).contains(norm(areaGuess)) || norm(areaGuess).contains(norm(a.name)));
        if (areaMatches || (govMatches && areaGuess == null)) {
          setState(() {
            _draft.governorateId = g.id;
            _draft.areaId = a.id;
            if (location.street != null && location.street!.isNotEmpty) _draft.street = location.street!;
          });
          return;
        }
      }
    }
  }

  Address _copy(Address a) => Address(
        id: a.id,
        title: a.title, first: a.first, last: a.last, email: a.email, phone: a.phone, alt: a.alt,
        governorateId: a.governorateId, areaId: a.areaId,
        gov: a.gov, area: a.area, block: a.block, street: a.street, building: a.building, apt: a.apt, floor: a.floor,
      );

  Widget _field(String label, String value, void Function(String) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        onChanged: onChanged,
      ),
    );
  }

  Future<void> _save() async {
    if (_draft.governorateId == null || _draft.areaId == null) {
      showErrorToast(context, 'Please choose your governorate and area.');
      return;
    }
    if (!await requireLogin(context)) return;
    if (!mounted) return;

    setState(() => _saving = true);
    try {
      final auth = context.read<AuthState>();
      final addressState = context.read<AddressState>();
      await addressState.saveRemote(auth.userId!, _draft, index: widget.index >= 0 ? widget.index : null);
      if (!mounted) return;
      Navigator.pop(context);
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
    final addressState = context.watch<AddressState>();
    final catalog = addressState.areaCatalog;
    final selectedGov = _draft.governorateId != null ? catalog.findGov(_draft.governorateId!) : null;
    final areasForGov = selectedGov?.areas ?? const <AreaInfo>[];

    return Scaffold(
      appBar: PageHeader(title: widget.index >= 0 ? 'Edit address' : 'Add address'),
      body: addressState.areasLoading && catalog.governorates.isEmpty
          ? const LoadingView(message: 'Loading areas…')
          : (addressState.areasError != null && catalog.governorates.isEmpty)
              ? ErrorRetryView(message: addressState.areasError!, onRetry: addressState.loadAreas)
              : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (addressState.areasError != null && catalog.governorates.isNotEmpty)
            InlineErrorBanner(message: addressState.areasError!, onRetry: addressState.loadAreas),
          DropdownButtonFormField<String>(
            initialValue: _titles.contains(_draft.title) ? _draft.title : _titles.first,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Title'),
            items: _titles.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (v) => setState(() => _draft.title = v ?? _draft.title),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _field('First name', _draft.first, (v) => _draft.first = v)),
            const SizedBox(width: 10),
            Expanded(child: _field('Last name', _draft.last, (v) => _draft.last = v)),
          ]),
          _field('Email', _draft.email, (v) => _draft.email = v),
          _field('Phone', _draft.phone, (v) => _draft.phone = v),
          DropdownButtonFormField<int>(
            initialValue: selectedGov?.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Governorate'),
            items: catalog.governorates.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() {
              _draft.governorateId = v;
              _draft.areaId = null; // reset dependent area choice
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: areasForGov.any((a) => a.id == _draft.areaId) ? _draft.areaId : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Area',
              helperText: selectedGov == null ? 'Pick a governorate first' : null,
            ),
            items: areasForGov.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: selectedGov == null ? null : (v) => setState(() => _draft.areaId = v),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _field('Block', _draft.block, (v) => _draft.block = v)),
            const SizedBox(width: 10),
            Expanded(child: _field('Street', _draft.street, (v) => _draft.street = v)),
          ]),
          Row(children: [
            Expanded(child: _field('Building', _draft.building, (v) => _draft.building = v)),
            const SizedBox(width: 10),
            Expanded(child: _field('Apartment', _draft.apt, (v) => _draft.apt = v)),
          ]),
          _field('Floor', _draft.floor, (v) => _draft.floor = v),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Text(widget.index >= 0 ? 'Save address' : 'Add address'),
          ),
        ],
      ),
    );
  }
}
