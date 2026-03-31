// ============================================================================
// HRM EMPLOYEE FILTERS
// ============================================================================
// Complete filter widget with all filters in ONE ROW
// Matching Country/State/City filter design pattern
// ============================================================================

import 'package:flutter/material.dart';
import 'package:country_state_city/country_state_city.dart' as csc;
import '../../../core/services/hrm_employee_service.dart';

// ── Top-level colors ──────────────────────────────────────────────────────
const Color _kPrimary    = Color(0xFF2563EB);
const Color _kBorder     = Color(0xFFE2E8F0);
const Color _kBg         = Color(0xFFF8FAFC);
const Color _kText       = Color(0xFF1E293B);
const Color _kHint       = Color(0xFF94A3B8);
const Color _kActiveBg   = Color(0xFFEFF6FF);
const Color _kDisabledBg = Color(0xFFF1F5F9);

class HRMEmployeeFilters extends StatefulWidget {
  final Function(Map<String, dynamic>) onFilterApplied;

  const HRMEmployeeFilters({
    Key? key,
    required this.onFilterApplied,
  }) : super(key: key);

  @override
  State<HRMEmployeeFilters> createState() => _HRMEmployeeFiltersState();
}

class _HRMEmployeeFiltersState extends State<HRMEmployeeFilters> {
  final HRMEmployeeService _service = HRMEmployeeService();
  
  // ── Search ─────────────────────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();
  
  // ── Selected values ─────────────────────────────────────────────────────
  DateTime? _fromDate;
  DateTime? _toDate;
  String? _status;
  String? _department;
  String? _position;
  String? _employeeType;
  String? _workLocation;
  String? _companyName;
  String? _countryName;
  String? _countryIso;
  String? _stateName;
  String? _stateIso;
  
  // ── Data lists ──────────────────────────────────────────────────────────
  List<csc.Country> _countries = [];
  List<csc.State>   _states    = [];
  List<String> _departments = [];
  List<String> _positions = [];
  List<String> _workLocations = [];
  List<String> _companies = [];
  
  // ── Loading states ──────────────────────────────────────────────────────
  bool _loadingCountries = true;
  bool _loadingStates    = false;
  bool _loadingDepartments = true;
  bool _loadingPositions = true;
  bool _loadingLocations = true;
  bool _loadingCompanies = true;
  
  // ── Overlay anchors ─────────────────────────────────────────────────────
  final LayerLink _lkStatus = LayerLink();
  final LayerLink _lkDepartment = LayerLink();
  final LayerLink _lkPosition = LayerLink();
  final LayerLink _lkEmployeeType = LayerLink();
  final LayerLink _lkWorkLocation = LayerLink();
  final LayerLink _lkCompany = LayerLink();
  final LayerLink _lkCountry = LayerLink();
  final LayerLink _lkState = LayerLink();
  
  OverlayEntry? _ovStatus;
  OverlayEntry? _ovDepartment;
  OverlayEntry? _ovPosition;
  OverlayEntry? _ovEmployeeType;
  OverlayEntry? _ovWorkLocation;
  OverlayEntry? _ovCompany;
  OverlayEntry? _ovCountry;
  OverlayEntry? _ovState;
  
  // ── Search controllers for dropdowns ───────────────────────────────────
  final TextEditingController _scStatus = TextEditingController();
  final TextEditingController _scDepartment = TextEditingController();
  final TextEditingController _scPosition = TextEditingController();
  final TextEditingController _scEmployeeType = TextEditingController();
  final TextEditingController _scWorkLocation = TextEditingController();
  final TextEditingController _scCompany = TextEditingController();
  final TextEditingController _scCountry = TextEditingController();
  final TextEditingController _scState = TextEditingController();
  
  // ── Static options ──────────────────────────────────────────────────────
  final List<String> _statusOptions = ['Active', 'Inactive', 'Terminated'];
  final List<String> _employeeTypeOptions = ['Probation period', 'Permanent Employee'];
  
  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }
  
  @override
  void dispose() {
    _closeAll();
    _searchCtrl.dispose();
    _scStatus.dispose();
    _scDepartment.dispose();
    _scPosition.dispose();
    _scEmployeeType.dispose();
    _scWorkLocation.dispose();
    _scCompany.dispose();
    _scCountry.dispose();
    _scState.dispose();
    super.dispose();
  }
  
  // ═══════════════════════════════════════════════════════════════════════
  // DATA LOADING
  // ═══════════════════════════════════════════════════════════════════════
  
  Future<void> _loadInitialData() async {
    await Future.wait([
      _fetchCountries(),
      _fetchDepartments(),
      _fetchPositions(),
      _fetchWorkLocations(),
      _fetchCompanies(),
    ]);
  }
  
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
      _states = [];
      _stateName = null;
      _stateIso = null;
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
  
  Future<void> _fetchDepartments() async {
    try {
      final list = await _service.getDepartments();
      if (!mounted) return;
      setState(() {
        _departments = list;
        _loadingDepartments = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDepartments = false);
    }
  }
  
  Future<void> _fetchPositions() async {
    try {
      final list = await _service.getPositions();
      if (!mounted) return;
      setState(() {
        _positions = list;
        _loadingPositions = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPositions = false);
    }
  }
  
  Future<void> _fetchWorkLocations() async {
    try {
      final list = await _service.getWorkLocations();
      if (!mounted) return;
      setState(() {
        _workLocations = list;
        _loadingLocations = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingLocations = false);
    }
  }
  
  Future<void> _fetchCompanies() async {
    try {
      final list = await _service.getCompanies();
      if (!mounted) return;
      setState(() {
        _companies = list;
        _loadingCompanies = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCompanies = false);
    }
  }
  
  // ═══════════════════════════════════════════════════════════════════════
  // OVERLAY MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════
  
  void _closeAll() {
    _ovStatus?.remove(); _ovStatus = null;
    _ovDepartment?.remove(); _ovDepartment = null;
    _ovPosition?.remove(); _ovPosition = null;
    _ovEmployeeType?.remove(); _ovEmployeeType = null;
    _ovWorkLocation?.remove(); _ovWorkLocation = null;
    _ovCompany?.remove(); _ovCompany = null;
    _ovCountry?.remove(); _ovCountry = null;
    _ovState?.remove(); _ovState = null;
    _scStatus.clear();
    _scDepartment.clear();
    _scPosition.clear();
    _scEmployeeType.clear();
    _scWorkLocation.clear();
    _scCompany.clear();
    _scCountry.clear();
    _scState.clear();
  }
  
  void _openStatus() {
    _closeAll();
    _ovStatus = _buildSimpleOverlay(
      link: _lkStatus,
      items: _statusOptions,
      selected: _status,
      ctrl: _scStatus,
      onPick: (val) {
        _closeAll();
        setState(() => _status = val);
        _notify();
      },
      onClose: () { _closeAll(); if (mounted) setState(() {}); },
    );
    Overlay.of(context).insert(_ovStatus!);
    setState(() {});
  }
  
  void _openDepartment() {
    _closeAll();
    _ovDepartment = _buildSimpleOverlay(
      link: _lkDepartment,
      items: _departments,
      selected: _department,
      ctrl: _scDepartment,
      loading: _loadingDepartments,
      onPick: (val) {
        _closeAll();
        setState(() => _department = val);
        _notify();
      },
      onClose: () { _closeAll(); if (mounted) setState(() {}); },
    );
    Overlay.of(context).insert(_ovDepartment!);
    setState(() {});
  }
  
  void _openPosition() {
    _closeAll();
    _ovPosition = _buildSimpleOverlay(
      link: _lkPosition,
      items: _positions,
      selected: _position,
      ctrl: _scPosition,
      loading: _loadingPositions,
      onPick: (val) {
        _closeAll();
        setState(() => _position = val);
        _notify();
      },
      onClose: () { _closeAll(); if (mounted) setState(() {}); },
    );
    Overlay.of(context).insert(_ovPosition!);
    setState(() {});
  }
  
  void _openEmployeeType() {
    _closeAll();
    _ovEmployeeType = _buildSimpleOverlay(
      link: _lkEmployeeType,
      items: _employeeTypeOptions,
      selected: _employeeType,
      ctrl: _scEmployeeType,
      onPick: (val) {
        _closeAll();
        setState(() => _employeeType = val);
        _notify();
      },
      onClose: () { _closeAll(); if (mounted) setState(() {}); },
    );
    Overlay.of(context).insert(_ovEmployeeType!);
    setState(() {});
  }
  
  void _openWorkLocation() {
    _closeAll();
    _ovWorkLocation = _buildSimpleOverlay(
      link: _lkWorkLocation,
      items: _workLocations,
      selected: _workLocation,
      ctrl: _scWorkLocation,
      loading: _loadingLocations,
      onPick: (val) {
        _closeAll();
        setState(() => _workLocation = val);
        _notify();
      },
      onClose: () { _closeAll(); if (mounted) setState(() {}); },
    );
    Overlay.of(context).insert(_ovWorkLocation!);
    setState(() {});
  }
  
  void _openCompany() {
    _closeAll();
    _ovCompany = _buildSimpleOverlay(
      link: _lkCompany,
      items: _companies,
      selected: _companyName,
      ctrl: _scCompany,
      loading: _loadingCompanies,
      onPick: (val) {
        _closeAll();
        setState(() => _companyName = val);
        _notify();
      },
      onClose: () { _closeAll(); if (mounted) setState(() {}); },
    );
    Overlay.of(context).insert(_ovCompany!);
    setState(() {});
  }
  
  void _openCountry() {
    _closeAll();
    _ovCountry = _buildOverlay<csc.Country>(
      link: _lkCountry,
      items: _countries,
      selLabel: _countryName,
      ctrl: _scCountry,
      loading: _loadingCountries,
      empty: 'No countries found',
      label: (c) => c.name,
      onPick: (c) {
        _closeAll();
        setState(() {
          _countryName = c.name;
          _countryIso = c.isoCode;
        });
        _fetchStates(c.isoCode);
        _notify();
      },
      onClose: () { _closeAll(); if (mounted) setState(() {}); },
    );
    Overlay.of(context).insert(_ovCountry!);
    setState(() {});
  }
  
  void _openState() {
    _closeAll();
    _ovState = _buildOverlay<csc.State>(
      link: _lkState,
      items: _states,
      selLabel: _stateName,
      ctrl: _scState,
      loading: _loadingStates,
      empty: 'No states found',
      label: (s) => s.name,
      onPick: (s) {
        _closeAll();
        setState(() {
          _stateName = s.name;
          _stateIso = s.isoCode;
        });
        _notify();
      },
      onClose: () { _closeAll(); if (mounted) setState(() {}); },
    );
    Overlay.of(context).insert(_ovState!);
    setState(() {});
  }
  
  // ═══════════════════════════════════════════════════════════════════════
  // OVERLAY BUILDERS
  // ═══════════════════════════════════════════════════════════════════════
  
  OverlayEntry _buildSimpleOverlay({
    required LayerLink link,
    required List<String> items,
    required String? selected,
    required TextEditingController ctrl,
    bool loading = false,
    required void Function(String) onPick,
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
              onTap: () {},
              child: Material(
                elevation: 10,
                borderRadius: BorderRadius.circular(10),
                shadowColor: Colors.black26,
                child: Container(
                  width: 220,
                  constraints: const BoxConstraints(maxHeight: 280),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: TextField(
                          controller: ctrl,
                          autofocus: true,
                          style: const TextStyle(fontSize: 13, color: _kText),
                          decoration: InputDecoration(
                            hintText: 'Search...',
                            hintStyle: const TextStyle(fontSize: 13, color: _kHint),
                            prefixIcon: const Icon(Icons.search, size: 16, color: _kHint),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                      if (loading)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        Flexible(
                          child: Builder(builder: (_) {
                            final q = ctrl.text.toLowerCase().trim();
                            final filtered = q.isEmpty
                                ? items
                                : items.where((i) => i.toLowerCase().contains(q)).toList();
                            if (filtered.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('No items found',
                                    style: TextStyle(fontSize: 12, color: _kHint)),
                              );
                            }
                            return ListView.builder(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final item = filtered[i];
                                final isSel = item == selected;
                                return InkWell(
                                  onTap: () => onPick(item),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    color: isSel ? _kActiveBg : Colors.transparent,
                                    child: Row(children: [
                                      Expanded(
                                        child: Text(item,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: _kText,
                                              fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                                            )),
                                      ),
                                      if (isSel)
                                        const Icon(Icons.check, size: 14, color: _kPrimary),
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
              onTap: () {},
              child: Material(
                elevation: 10,
                borderRadius: BorderRadius.circular(10),
                shadowColor: Colors.black26,
                child: Container(
                  width: 220,
                  constraints: const BoxConstraints(maxHeight: 280),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: TextField(
                          controller: ctrl,
                          autofocus: true,
                          style: const TextStyle(fontSize: 13, color: _kText),
                          decoration: InputDecoration(
                            hintText: 'Search...',
                            hintStyle: const TextStyle(fontSize: 13, color: _kHint),
                            prefixIcon: const Icon(Icons.search, size: 16, color: _kHint),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                      if (loading)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
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
                                padding: const EdgeInsets.all(16),
                                child: Text(empty,
                                    style: const TextStyle(fontSize: 12, color: _kHint)),
                              );
                            }
                            return ListView.builder(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final item = filtered[i];
                                final lbl = label(item);
                                final isSel = lbl == selLabel;
                                return InkWell(
                                  onTap: () => onPick(item),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    color: isSel ? _kActiveBg : Colors.transparent,
                                    child: Row(children: [
                                      Expanded(
                                        child: Text(lbl,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: _kText,
                                              fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                                            )),
                                      ),
                                      if (isSel)
                                        const Icon(Icons.check, size: 14, color: _kPrimary),
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
  
  // ═══════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════
  
  Map<String, dynamic> _filterMap() => {
    'search': _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
    'fromDate': _fromDate,
    'toDate': _toDate,
    'status': _status,
    'department': _department,
    'position': _position,
    'employeeType': _employeeType,
    'workLocation': _workLocation,
    'companyName': _companyName,
    'country': _countryName,
    'state': _stateName,
  };
  
  void _notify() => widget.onFilterApplied(_filterMap());
  
  void _clearAll() {
    _closeAll();
    setState(() {
      _searchCtrl.clear();
      _fromDate = null;
      _toDate = null;
      _status = null;
      _department = null;
      _position = null;
      _employeeType = null;
      _workLocation = null;
      _companyName = null;
      _countryName = null;
      _countryIso = null;
      _stateName = null;
      _stateIso = null;
      _states = [];
    });
    widget.onFilterApplied(_filterMap());
  }
  
  bool get _hasFilters =>
      _searchCtrl.text.trim().isNotEmpty ||
      _fromDate != null ||
      _toDate != null ||
      _status != null ||
      _department != null ||
      _position != null ||
      _employeeType != null ||
      _workLocation != null ||
      _companyName != null ||
      _countryName != null ||
      _stateName != null;
  
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
  
  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════
  
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(children: [
            const Icon(Icons.filter_list, size: 16, color: _kPrimary),
            const SizedBox(width: 6),
            const Text('Filters',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kText)),
            if (_hasFilters) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _clearAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close, size: 11, color: Color(0xFFF87171)),
                      SizedBox(width: 3),
                      Text('Clear All',
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFFF87171),
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ],
          ]),
          
          const SizedBox(height: 12),
          
          // ── ALL FILTERS IN ONE ROW ─────────────────────────────────────
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              // 1 ─ SEARCH BOX ──────────────────────────────────────────
              _fieldWrap(
                label: 'Search',
                width: 200,
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) { setState(() {}); _notify(); },
                    style: const TextStyle(fontSize: 12, color: _kText),
                    decoration: InputDecoration(
                      hintText: 'Employee ID, Name, Email, Phone...',
                      hintStyle: const TextStyle(fontSize: 12, color: _kHint),
                      prefixIcon: const Icon(Icons.search, size: 14, color: _kHint),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                setState(() => _searchCtrl.clear());
                                _notify();
                              },
                              child: const Icon(Icons.close, size: 13, color: _kHint),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
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
              
              // 2 ─ FROM DATE ──────────────────────────────────────────
              _fieldWrap(
                label: 'From Date',
                width: 130,
                child: GestureDetector(
                  onTap: () => _pickDate(true),
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: _boxDec(active: _fromDate != null),
                    child: Row(children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 13, color: _fromDate != null ? _kPrimary : _kHint),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _fromDate != null ? _fmt(_fromDate!) : 'Select',
                          style: TextStyle(
                            fontSize: 12,
                            color: _fromDate != null ? _kText : _kHint,
                            fontWeight: _fromDate != null ? FontWeight.w500 : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_fromDate != null)
                        GestureDetector(
                          onTap: () { setState(() => _fromDate = null); _notify(); },
                          child: const Icon(Icons.close, size: 13, color: _kHint),
                        ),
                    ]),
                  ),
                ),
              ),
              
              // 3 ─ TO DATE ────────────────────────────────────────────
              _fieldWrap(
                label: 'To Date',
                width: 130,
                child: GestureDetector(
                  onTap: () => _pickDate(false),
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: _boxDec(active: _toDate != null),
                    child: Row(children: [
                      Icon(Icons.event_outlined,
                          size: 13, color: _toDate != null ? _kPrimary : _kHint),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _toDate != null ? _fmt(_toDate!) : 'Select',
                          style: TextStyle(
                            fontSize: 12,
                            color: _toDate != null ? _kText : _kHint,
                            fontWeight: _toDate != null ? FontWeight.w500 : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_toDate != null)
                        GestureDetector(
                          onTap: () { setState(() => _toDate = null); _notify(); },
                          child: const Icon(Icons.close, size: 13, color: _kHint),
                        ),
                    ]),
                  ),
                ),
              ),
              
              // 4 ─ STATUS ──────────────────────────────────────────────
              _fieldWrap(
                label: 'Status',
                width: 140,
                child: CompositedTransformTarget(
                  link: _lkStatus,
                  child: GestureDetector(
                    onTap: () {
                      if (_ovStatus != null) { _closeAll(); setState(() {}); }
                      else { _openStatus(); }
                    },
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: _boxDec(active: _status != null || _ovStatus != null),
                      child: _dropRow(
                        value: _status ?? 'All Status',
                        hasValue: _status != null,
                        isOpen: _ovStatus != null,
                        onClear: _status != null
                            ? () { setState(() => _status = null); _notify(); }
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
              
              // 5 ─ DEPARTMENT ──────────────────────────────────────────
              _fieldWrap(
                label: 'Department',
                width: 155,
                child: CompositedTransformTarget(
                  link: _lkDepartment,
                  child: GestureDetector(
                    onTap: () {
                      if (_ovDepartment != null) { _closeAll(); setState(() {}); }
                      else { _openDepartment(); }
                    },
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: _boxDec(active: _department != null || _ovDepartment != null),
                      child: _dropRow(
                        value: _department ?? 'All Departments',
                        hasValue: _department != null,
                        isOpen: _ovDepartment != null,
                        isLoading: _loadingDepartments,
                        onClear: _department != null
                            ? () { setState(() => _department = null); _notify(); }
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
              
              // 6 ─ POSITION ────────────────────────────────────────────
              _fieldWrap(
                label: 'Position',
                width: 155,
                child: CompositedTransformTarget(
                  link: _lkPosition,
                  child: GestureDetector(
                    onTap: () {
                      if (_ovPosition != null) { _closeAll(); setState(() {}); }
                      else { _openPosition(); }
                    },
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: _boxDec(active: _position != null || _ovPosition != null),
                      child: _dropRow(
                        value: _position ?? 'All Positions',
                        hasValue: _position != null,
                        isOpen: _ovPosition != null,
                        isLoading: _loadingPositions,
                        onClear: _position != null
                            ? () { setState(() => _position = null); _notify(); }
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
              
              // 7 ─ EMPLOYEE TYPE ───────────────────────────────────────
              _fieldWrap(
                label: 'Employee Type',
                width: 160,
                child: CompositedTransformTarget(
                  link: _lkEmployeeType,
                  child: GestureDetector(
                    onTap: () {
                      if (_ovEmployeeType != null) { _closeAll(); setState(() {}); }
                      else { _openEmployeeType(); }
                    },
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: _boxDec(active: _employeeType != null || _ovEmployeeType != null),
                      child: _dropRow(
                        value: _employeeType ?? 'All Types',
                        hasValue: _employeeType != null,
                        isOpen: _ovEmployeeType != null,
                        onClear: _employeeType != null
                            ? () { setState(() => _employeeType = null); _notify(); }
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
              
              // 8 ─ WORK LOCATION ───────────────────────────────────────
              _fieldWrap(
                label: 'Work Location',
                width: 155,
                child: CompositedTransformTarget(
                  link: _lkWorkLocation,
                  child: GestureDetector(
                    onTap: () {
                      if (_ovWorkLocation != null) { _closeAll(); setState(() {}); }
                      else { _openWorkLocation(); }
                    },
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: _boxDec(active: _workLocation != null || _ovWorkLocation != null),
                      child: _dropRow(
                        value: _workLocation ?? 'All Locations',
                        hasValue: _workLocation != null,
                        isOpen: _ovWorkLocation != null,
                        isLoading: _loadingLocations,
                        onClear: _workLocation != null
                            ? () { setState(() => _workLocation = null); _notify(); }
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
              
              // 9 ─ COMPANY ─────────────────────────────────────────────
              _fieldWrap(
                label: 'Company',
                width: 155,
                child: CompositedTransformTarget(
                  link: _lkCompany,
                  child: GestureDetector(
                    onTap: () {
                      if (_ovCompany != null) { _closeAll(); setState(() {}); }
                      else { _openCompany(); }
                    },
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: _boxDec(active: _companyName != null || _ovCompany != null),
                      child: _dropRow(
                        value: _companyName ?? 'All Companies',
                        hasValue: _companyName != null,
                        isOpen: _ovCompany != null,
                        isLoading: _loadingCompanies,
                        onClear: _companyName != null
                            ? () { setState(() => _companyName = null); _notify(); }
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
              
              // 10 ─ COUNTRY ────────────────────────────────────────────
              _fieldWrap(
                label: 'Country',
                width: 155,
                child: CompositedTransformTarget(
                  link: _lkCountry,
                  child: GestureDetector(
                    onTap: () {
                      if (_ovCountry != null) { _closeAll(); setState(() {}); }
                      else { _openCountry(); }
                    },
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: _boxDec(active: _countryName != null || _ovCountry != null),
                      child: _dropRow(
                        value: _countryName ?? 'All Countries',
                        hasValue: _countryName != null,
                        isOpen: _ovCountry != null,
                        isLoading: _loadingCountries,
                        onClear: _countryName != null
                            ? () {
                                setState(() {
                                  _countryName = null;
                                  _countryIso = null;
                                  _stateName = null;
                                  _stateIso = null;
                                  _states = [];
                                });
                                _notify();
                              }
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
              
              // 11 ─ STATE ──────────────────────────────────────────────
              _fieldWrap(
                label: 'State',
                width: 155,
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
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
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
                                  _stateIso = null;
                                });
                                _notify();
                              }
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
              
              // 12 ─ APPLY BUTTON ───────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(top: 15),
                child: SizedBox(
                  height: 38,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _closeAll();
                      widget.onFilterApplied(_filterMap());
                    },
                    icon: const Icon(Icons.search, size: 15),
                    label: const Text('Apply Filter',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
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
  
  // ═══════════════════════════════════════════════════════════════════════
  // SMALL HELPER WIDGETS
  // ═══════════════════════════════════════════════════════════════════════
  
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
                  fontSize: 11, fontWeight: FontWeight.w500, color: _kHint)),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
  
  Widget _dropRow({
    required String value,
    required bool hasValue,
    required bool isOpen,
    bool isLoading = false,
    bool isDisabled = false,
    VoidCallback? onClear,
  }) {
    return Row(children: [
      if (isLoading)
        const SizedBox(
            width: 13, height: 13,
            child: CircularProgressIndicator(strokeWidth: 1.5))
      else
        Icon(Icons.filter_alt_outlined,
            size: 13,
            color: isDisabled ? _kHint : hasValue ? _kPrimary : _kHint),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          value,
          style: TextStyle(
            fontSize: 12,
            color: isDisabled ? _kHint : hasValue ? _kText : _kHint,
            fontWeight: hasValue ? FontWeight.w500 : FontWeight.normal,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (hasValue && onClear != null)
        GestureDetector(
            onTap: onClear,
            child: const Icon(Icons.close, size: 13, color: _kHint))
      else if (!isDisabled)
        Icon(
          isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          size: 16,
          color: _kHint,
        ),
    ]);
  }
}