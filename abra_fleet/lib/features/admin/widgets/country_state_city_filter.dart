// File: lib/features/admin/widgets/country_state_city_filter.dart
//
// ✅ ZERO ERRORS — All colors defined at top-level
// ✅ ALL FILTERS IN ONE ROW — wraps on small screens
// ✅ SEARCH BAR INSIDE EACH DROPDOWN popup
// ✅ Country → State → City hierarchy
// ✅ Live update + Apply Filter button
// ✅ UPDATED TEXT SIZES — Company standards applied
//
// pubspec.yaml → add:  country_state_city: ^2.0.1
// then run:            flutter pub get

import 'package:flutter/material.dart';
import 'package:country_state_city/country_state_city.dart' as csc;

// ── Top-level colors (accessible everywhere, no const issues) ──────────────
const Color _kPrimary    = Color(0xFF0D1B2A); // Deep Navy Black
const Color _kBorder     = Color(0xFFE2E8F0);
const Color _kBg         = Color(0xFFF8FAFC);
const Color _kText       = Color(0xFF0D1B2A); // Deep Navy Black
const Color _kHint       = Color(0xFF4A5568);
const Color _kActiveBg   = Color(0xFFE2E8F0); // Navy-tinted active background
const Color _kDisabledBg = Color(0xFFF1F5F9);

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class CountryStateCityFilter extends StatefulWidget {
  /// Called on every filter change (live) AND when Apply Filter is pressed.
  /// Keys: 'fromDate', 'toDate', 'country', 'state', 'city', 'localArea'
  final Function(Map<String, dynamic>) onFilterApplied;

  final DateTime? initialFromDate;
  final DateTime? initialToDate;
  final String?   initialCountry;
  final String?   initialState;
  final String?   initialCity;
  final String?   initialLocalArea;

  const CountryStateCityFilter({
    Key? key,
    required this.onFilterApplied,
    this.initialFromDate,
    this.initialToDate,
    this.initialCountry,
    this.initialState,
    this.initialCity,
    this.initialLocalArea,
  }) : super(key: key);

  @override
  State<CountryStateCityFilter> createState() => _CSCFilterState();
}

class _CSCFilterState extends State<CountryStateCityFilter> {
  // ── Selected values ─────────────────────────────────────────────────────
  DateTime? _fromDate;
  DateTime? _toDate;
  String?   _countryName;
  String?   _countryIso;
  String?   _stateName;
  String?   _stateIso;
  String?   _cityName;
  final TextEditingController _localCtrl = TextEditingController();

  // ── Data ─────────────────────────────────────────────────────────────────
  List<csc.Country> _countries = [];
  List<csc.State>   _states    = [];
  List<csc.City>    _cities    = [];

  // ── Loading ───────────────────────────────────────────────────────────────
  bool _loadingCountries = true;
  bool _loadingStates    = false;
  bool _loadingCities    = false;

  // ── Overlay anchors ───────────────────────────────────────────────────────
  final LayerLink _lkCountry = LayerLink();
  final LayerLink _lkState   = LayerLink();
  final LayerLink _lkCity    = LayerLink();

  OverlayEntry? _ovCountry;
  OverlayEntry? _ovState;
  OverlayEntry? _ovCity;

  // ── Search controllers ────────────────────────────────────────────────────
  final TextEditingController _scCountry = TextEditingController();
  final TextEditingController _scState   = TextEditingController();
  final TextEditingController _scCity    = TextEditingController();

  // ════════════════════════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();
    _fromDate  = widget.initialFromDate;
    _toDate    = widget.initialToDate;
    _countryName = widget.initialCountry;
    _stateName   = widget.initialState;
    _cityName    = widget.initialCity;
    _localCtrl.text = widget.initialLocalArea ?? '';
    _fetchCountries();
  }

  @override
  void dispose() {
    _closeAll();
    _localCtrl.dispose();
    _scCountry.dispose();
    _scState.dispose();
    _scCity.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // DATA FETCHING
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _fetchCountries() async {
    try {
      final list = await csc.getAllCountries();
      if (!mounted) return;
      setState(() {
        _countries = list..sort((a, b) => a.name.compareTo(b.name));
        _loadingCountries = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCountries = false);
    }
  }

  Future<void> _fetchStates(String iso) async {
    setState(() {
      _loadingStates = true;
      _states    = [];
      _cities    = [];
      _stateName = null;
      _stateIso  = null;
      _cityName  = null;
    });
    try {
      final list = await csc.getStatesOfCountry(iso);
      if (!mounted) return;
      setState(() {
        _states = list..sort((a, b) => a.name.compareTo(b.name));
        _loadingStates = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingStates = false);
    }
  }

  Future<void> _fetchCities(String countryIso, String stateIso) async {
    setState(() {
      _loadingCities = true;
      _cities   = [];
      _cityName = null;
    });
    try {
      final list = await csc.getStateCities(countryIso, stateIso);
      if (!mounted) return;
      setState(() {
        _cities = list..sort((a, b) => a.name.compareTo(b.name));
        _loadingCities = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCities = false);
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // OVERLAY
  // ════════════════════════════════════════════════════════════════════════════

  void _closeAll() {
    _ovCountry?.remove(); _ovCountry = null;
    _ovState?.remove();   _ovState   = null;
    _ovCity?.remove();    _ovCity    = null;
    _scCountry.clear();
    _scState.clear();
    _scCity.clear();
  }

  void _openCountry() {
    _closeAll();
    _ovCountry = _buildOverlay<csc.Country>(
      link:     _lkCountry,
      items:    _countries,
      selLabel: _countryName,
      ctrl:     _scCountry,
      loading:  _loadingCountries,
      empty:    'No countries found',
      label:    (c) => c.name,
      onPick:   (c) {
        _closeAll();
        setState(() { _countryName = c.name; _countryIso = c.isoCode; });
        _fetchStates(c.isoCode);
        _notify();
      },
      onClose:  () { _closeAll(); if (mounted) setState(() {}); },
    );
    Overlay.of(context).insert(_ovCountry!);
    setState(() {});
  }

  void _openState() {
    _closeAll();
    _ovState = _buildOverlay<csc.State>(
      link:     _lkState,
      items:    _states,
      selLabel: _stateName,
      ctrl:     _scState,
      loading:  _loadingStates,
      empty:    'No states found',
      label:    (s) => s.name,
      onPick:   (s) {
        _closeAll();
        setState(() { _stateName = s.name; _stateIso = s.isoCode; });
        _fetchCities(_countryIso!, s.isoCode);
        _notify();
      },
      onClose:  () { _closeAll(); if (mounted) setState(() {}); },
    );
    Overlay.of(context).insert(_ovState!);
    setState(() {});
  }

  void _openCity() {
    _closeAll();
    _ovCity = _buildOverlay<csc.City>(
      link:     _lkCity,
      items:    _cities,
      selLabel: _cityName,
      ctrl:     _scCity,
      loading:  _loadingCities,
      empty:    'No cities found',
      label:    (c) => c.name,
      onPick:   (c) {
        _closeAll();
        setState(() => _cityName = c.name);
        _notify();
      },
      onClose:  () { _closeAll(); if (mounted) setState(() {}); },
    );
    Overlay.of(context).insert(_ovCity!);
    setState(() {});
  }

  OverlayEntry _buildOverlay<T>({
    required LayerLink link,
    required List<T> items,
    required String? selLabel,
    required TextEditingController ctrl,
    required bool loading,
    required String empty,
    required String Function(T) label,
    required void Function(T) onPick,
    required VoidCallback onClose,
  }) {
    late OverlayEntry ov;
    ov = OverlayEntry(builder: (_) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onClose,
        child: Stack(children: [
          Positioned.fill(child: Container(color: Colors.transparent)),
          CompositedTransformFollower(
            link: link,
            showWhenUnlinked: false,
            offset: const Offset(0, 42),
            child: GestureDetector(
              onTap: () {}, // stop propagation
              child: Material(
                elevation: 10,
                borderRadius: BorderRadius.circular(10),
                shadowColor: Colors.black26,
                child: Container(
                  width: 240,
                  constraints: const BoxConstraints(maxHeight: 300),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Search bar ──────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: TextField(
                          controller: ctrl,
                          autofocus: true,
                          style: const TextStyle(fontSize: 14, color: _kText),
                          decoration: InputDecoration(
                            hintText: 'Search...',
                            hintStyle: const TextStyle(fontSize: 14, color: _kHint),
                            prefixIcon: const Icon(Icons.search, size: 18, color: _kHint),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            filled: true,
                            fillColor: _kBg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: _kBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: _kBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: _kPrimary, width: 1.5),
                            ),
                          ),
                          onChanged: (_) => ov.markNeedsBuild(),
                        ),
                      ),
                      const Divider(height: 1),
                      // ── List ──────────────────────────────────────────
                      if (loading)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: SizedBox(
                            width: 24, height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        )
                      else
                        Flexible(
                          child: Builder(builder: (_) {
                            final q = ctrl.text.toLowerCase().trim();
                            final filtered = q.isEmpty
                                ? items
                                : items.where((i) => label(i).toLowerCase().contains(q)).toList();
                            if (filtered.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text(empty,
                                    style: const TextStyle(fontSize: 14, color: _kHint)),
                              );
                            }
                            return ListView.builder(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final item = filtered[i];
                                final lbl  = label(item);
                                final isSel = lbl == selLabel;
                                return InkWell(
                                  onTap: () => onPick(item),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    color: isSel ? _kActiveBg : Colors.transparent,
                                    child: Row(children: [
                                      Expanded(
                                        child: Text(lbl,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: _kText,
                                              fontWeight: isSel
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                            )),
                                      ),
                                      if (isSel)
                                        const Icon(Icons.check, size: 16, color: _kPrimary),
                                    ]),
                                  ),
                                );
                              },
                            );
                          }),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ]),
      );
    });
    return ov;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> _filterMap() => {
    'fromDate'  : _fromDate,
    'toDate'    : _toDate,
    'country'   : _countryName,
    'state'     : _stateName,
    'city'      : _cityName,
    'localArea' : _localCtrl.text.trim().isEmpty ? null : _localCtrl.text.trim(),
  };

  void _notify() => widget.onFilterApplied(_filterMap());

  void _clearAll() {
    _closeAll();
    setState(() {
      _fromDate    = null;
      _toDate      = null;
      _countryName = null;
      _countryIso  = null;
      _stateName   = null;
      _stateIso    = null;
      _cityName    = null;
      _states      = [];
      _cities      = [];
      _localCtrl.clear();
    });
    widget.onFilterApplied(_filterMap());
  }

  bool get _hasFilters =>
      _fromDate != null ||
      _toDate != null ||
      (_countryName?.isNotEmpty ?? false) ||
      (_stateName?.isNotEmpty ?? false) ||
      (_cityName?.isNotEmpty ?? false) ||
      _localCtrl.text.trim().isNotEmpty;

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_fromDate ?? now) : (_toDate ?? _fromDate ?? now),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _kPrimary),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
        if (_toDate != null && _fromDate!.isAfter(_toDate!)) _toDate = null;
      } else {
        _toDate = picked;
      }
    });
    _notify();
  }

  BoxDecoration _boxDec({required bool active, bool disabled = false}) =>
      BoxDecoration(
        color: disabled ? _kDisabledBg : active ? _kActiveBg : _kBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: disabled ? _kBorder : active ? _kPrimary : _kBorder,
          width: active && !disabled ? 1.5 : 1.0,
        ),
      );

  // ════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(children: [
            const Icon(Icons.filter_list, size: 18, color: _kPrimary),
            const SizedBox(width: 8),
            const Text('Filters',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _kText)),
            if (_hasFilters) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _clearAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close, size: 12, color: Color(0xFFF87171)),
                      SizedBox(width: 4),
                      Text('Clear All',
                          style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFF87171),
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ],
          ]),

          const SizedBox(height: 14),

          // ── ONE ROW — wraps on small screens ─────────────────────────────
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              // 1 ─ FROM DATE ──────────────────────────────────────────────
              _fieldWrap(
                label: 'From Date',
                width: 145,
                child: GestureDetector(
                  onTap: () => _pickDate(true),
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: _boxDec(active: _fromDate != null),
                    child: Row(children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 15, color: _fromDate != null ? _kPrimary : _kHint),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _fromDate != null ? _fmt(_fromDate!) : 'Select',
                          style: TextStyle(
                            fontSize: 14,
                            color: _fromDate != null ? _kText : _kHint,
                            fontWeight: _fromDate != null ? FontWeight.w500 : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_fromDate != null)
                        GestureDetector(
                          onTap: () { setState(() => _fromDate = null); _notify(); },
                          child: const Icon(Icons.close, size: 15, color: _kHint),
                        ),
                    ]),
                  ),
                ),
              ),

              // 2 ─ TO DATE ────────────────────────────────────────────────
              _fieldWrap(
                label: 'To Date',
                width: 145,
                child: GestureDetector(
                  onTap: () => _pickDate(false),
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: _boxDec(active: _toDate != null),
                    child: Row(children: [
                      Icon(Icons.event_outlined,
                          size: 15, color: _toDate != null ? _kPrimary : _kHint),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _toDate != null ? _fmt(_toDate!) : 'Select',
                          style: TextStyle(
                            fontSize: 14,
                            color: _toDate != null ? _kText : _kHint,
                            fontWeight: _toDate != null ? FontWeight.w500 : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_toDate != null)
                        GestureDetector(
                          onTap: () { setState(() => _toDate = null); _notify(); },
                          child: const Icon(Icons.close, size: 15, color: _kHint),
                        ),
                    ]),
                  ),
                ),
              ),

              // 3 ─ COUNTRY ────────────────────────────────────────────────
              _fieldWrap(
                label: 'Country',
                width: 170,
                child: CompositedTransformTarget(
                  link: _lkCountry,
                  child: GestureDetector(
                    onTap: () {
                      if (_ovCountry != null) { _closeAll(); setState(() {}); }
                      else { _openCountry(); }
                    },
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: _boxDec(
                          active: _countryName != null || _ovCountry != null),
                      child: _dropRow(
                        value: _countryName ?? 'All Countries',
                        hasValue: _countryName != null,
                        isOpen: _ovCountry != null,
                        isLoading: _loadingCountries,
                        onClear: _countryName != null
                            ? () {
                                setState(() {
                                  _countryName = null;
                                  _countryIso  = null;
                                  _stateName   = null;
                                  _stateIso    = null;
                                  _cityName    = null;
                                  _states = [];
                                  _cities = [];
                                });
                                _notify();
                              }
                            : null,
                      ),
                    ),
                  ),
                ),
              ),

              // 4 ─ STATE ──────────────────────────────────────────────────
              _fieldWrap(
                label: 'State',
                width: 170,
                child: CompositedTransformTarget(
                  link: _lkState,
                  child: GestureDetector(
                    onTap: _countryName == null
                        ? null
                        : () {
                            if (_ovState != null) { _closeAll(); setState(() {}); }
                            else { _openState(); }
                          },
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: _boxDec(
                        active: _stateName != null || _ovState != null,
                        disabled: _countryName == null,
                      ),
                      child: _dropRow(
                        value: _stateName ??
                            (_countryName == null ? 'Select Country first' : 'All States'),
                        hasValue: _stateName != null,
                        isOpen: _ovState != null,
                        isLoading: _loadingStates,
                        isDisabled: _countryName == null,
                        onClear: _stateName != null
                            ? () {
                                setState(() {
                                  _stateName = null;
                                  _stateIso  = null;
                                  _cityName  = null;
                                  _cities    = [];
                                });
                                _notify();
                              }
                            : null,
                      ),
                    ),
                  ),
                ),
              ),

              // 5 ─ CITY ───────────────────────────────────────────────────
              _fieldWrap(
                label: 'City',
                width: 170,
                child: CompositedTransformTarget(
                  link: _lkCity,
                  child: GestureDetector(
                    onTap: _stateName == null
                        ? null
                        : () {
                            if (_ovCity != null) { _closeAll(); setState(() {}); }
                            else { _openCity(); }
                          },
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: _boxDec(
                        active: _cityName != null || _ovCity != null,
                        disabled: _stateName == null,
                      ),
                      child: _dropRow(
                        value: _cityName ??
                            (_stateName == null ? 'Select State first' : 'All Cities'),
                        hasValue: _cityName != null,
                        isOpen: _ovCity != null,
                        isLoading: _loadingCities,
                        isDisabled: _stateName == null,
                        onClear: _cityName != null
                            ? () {
                                setState(() => _cityName = null);
                                _notify();
                              }
                            : null,
                      ),
                    ),
                  ),
                ),
              ),

              // 6 ─ LOCAL AREA ─────────────────────────────────────────────
              _fieldWrap(
                label: 'Local Area / Landmark',
                width: 190,
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _localCtrl,
                    onChanged: (_) { setState(() {}); _notify(); },
                    style: const TextStyle(fontSize: 14, color: _kText),
                    decoration: InputDecoration(
                      hintText: 'Enter area...',
                      hintStyle: const TextStyle(fontSize: 14, color: _kHint),
                      prefixIcon: const Icon(Icons.pin_drop_outlined,
                          size: 16, color: _kHint),
                      suffixIcon: _localCtrl.text.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                setState(() => _localCtrl.clear());
                                _notify();
                              },
                              child: const Icon(Icons.close, size: 15, color: _kHint),
                            )
                          : null,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      filled: true,
                      fillColor: _kBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _kBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _kBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _kPrimary, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ),

              // 7 ─ APPLY BUTTON ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _closeAll();
                      widget.onFilterApplied(_filterMap());
                    },
                    icon: const Icon(Icons.search, size: 16),
                    label: const Text('Apply Filter',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SMALL HELPER WIDGETS
  // ════════════════════════════════════════════════════════════════════════════

  /// Wraps a field with a label on top
  Widget _fieldWrap({
    required String label,
    required Widget child,
    double? width,
  }) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: _kHint)),
          const SizedBox(height: 5),
          child,
        ],
      ),
    );
  }

  /// Inner row content for dropdown buttons
  Widget _dropRow({
    required String value,
    required bool hasValue,
    required bool isOpen,
    required bool isLoading,
    bool isDisabled = false,
    VoidCallback? onClear,
  }) {
    return Row(children: [
      if (isLoading)
        const SizedBox(
            width: 15, height: 15,
            child: CircularProgressIndicator(strokeWidth: 2))
      else
        Icon(Icons.location_on_outlined,
            size: 15,
            color: isDisabled ? _kHint : hasValue ? _kPrimary : _kHint),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          value,
          style: TextStyle(
            fontSize: 14,
            color: isDisabled ? _kHint : hasValue ? _kText : _kHint,
            fontWeight: hasValue ? FontWeight.w500 : FontWeight.normal,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (hasValue && onClear != null)
        GestureDetector(
            onTap: onClear,
            child: const Icon(Icons.close, size: 15, color: _kHint))
      else if (!isDisabled)
        Icon(
          isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          size: 18,
          color: _kHint,
        ),
    ]);
  }
}