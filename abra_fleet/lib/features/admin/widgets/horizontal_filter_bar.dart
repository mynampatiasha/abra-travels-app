// lib/features/admin/widgets/alternative_filter_bar.dart
// Using country_picker package for better customization and control

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:country_picker/country_picker.dart';
// import 'package:csc_picker/csc_picker.dart'; // TEMPORARILY DISABLED - Incompatible with Flutter 3.35.2

/// Enhanced Filter Bar with Country-State-City hierarchy and improved UI
class AlternativeFilterBar extends StatefulWidget {
  final Function(Map<String, dynamic>) onFilterApplied;
  final VoidCallback? onFilterCleared;
  final Map<String, dynamic>? initialFilters;
  final bool showDateFilter;
  final bool showDateRangeFilter;
  final bool showCountryFilter;
  final bool showStateFilter;
  final bool showCityFilter;
  final bool showAreaFilter;

  const AlternativeFilterBar({
    super.key,
    required this.onFilterApplied,
    this.onFilterCleared,
    this.initialFilters,
    this.showDateFilter = true,
    this.showDateRangeFilter = true,
    this.showCountryFilter = true,
    this.showStateFilter = true,
    this.showCityFilter = true,
    this.showAreaFilter = true,
  });

  @override
  State<AlternativeFilterBar> createState() => _AlternativeFilterBarState();
}

class _AlternativeFilterBarState extends State<AlternativeFilterBar>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _animation;

  // Filter values
  DateTime? _selectedDate;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedCountry;
  String? _selectedState;
  String? _selectedCity;
  String? _selectedArea;

  // Controllers
  final TextEditingController _areaController = TextEditingController();

  // CSC Data - You'll need to populate these based on CSC package or custom data
  List<String> _availableStates = [];
  List<String> _availableCities = [];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    if (widget.initialFilters != null) {
      _loadInitialFilters();
    }
  }

  void _loadInitialFilters() {
    final filters = widget.initialFilters!;
    _selectedDate = filters['date'];
    _startDate = filters['startDate'];
    _endDate = filters['endDate'];
    _selectedCountry = filters['country'];
    _selectedState = filters['state'];
    _selectedCity = filters['city'];
    _selectedArea = filters['area'];

    if (_selectedArea != null) _areaController.text = _selectedArea!;
  }

  @override
  void dispose() {
    _animationController.dispose();
    _areaController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  // Date Picker
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue.shade700,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  // Enhanced Date Range Picker with Calendar Overlay
  Future<void> _selectDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue.shade700,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue.shade700,
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  void _onCountryChanged(String? country) {
    setState(() {
      _selectedCountry = country;
      _selectedState = null;
      _selectedCity = null;
      _availableStates = [];
      _availableCities = [];
    });
  }

  void _onStateChanged(String? state) {
    setState(() {
      _selectedState = state;
      _selectedCity = null;
      _availableCities = [];
    });
  }

  void _onCityChanged(String? city) {
    setState(() {
      _selectedCity = city;
    });
  }

  void _applyFilters() {
    final filters = <String, dynamic>{};

    if (_selectedDate != null) filters['date'] = _selectedDate;
    if (_startDate != null) filters['startDate'] = _startDate;
    if (_endDate != null) filters['endDate'] = _endDate;
    if (_selectedCountry != null && _selectedCountry!.isNotEmpty) {
      filters['country'] = _selectedCountry;
    }
    if (_selectedState != null && _selectedState!.isNotEmpty) {
      filters['state'] = _selectedState;
    }
    if (_selectedCity != null && _selectedCity!.isNotEmpty) {
      filters['city'] = _selectedCity;
    }
    if (_areaController.text.isNotEmpty) {
      filters['area'] = _areaController.text.trim();
      _selectedArea = _areaController.text.trim();
    }

    widget.onFilterApplied(filters);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text('Filters applied: ${filters.length} active filter(s)'),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _clearFilters() {
    setState(() {
      _selectedDate = null;
      _startDate = null;
      _endDate = null;
      _selectedCountry = null;
      _selectedState = null;
      _selectedCity = null;
      _selectedArea = null;
      _areaController.clear();
      _availableStates = [];
      _availableCities = [];
    });

    widget.onFilterCleared?.call();
    widget.onFilterApplied({});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.refresh, color: Colors.white),
            SizedBox(width: 8),
            Text('All filters cleared'),
          ],
        ),
        backgroundColor: Colors.orange.shade600,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  int _getActiveFilterCount() {
    int count = 0;
    if (_selectedDate != null) count++;
    if (_startDate != null && _endDate != null) count++;
    if (_selectedCountry != null && _selectedCountry!.isNotEmpty) count++;
    if (_selectedState != null && _selectedState!.isNotEmpty) count++;
    if (_selectedCity != null && _selectedCity!.isNotEmpty) count++;
    if (_areaController.text.isNotEmpty) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final activeFilterCount = _getActiveFilterCount();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            spreadRadius: 0,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Filter Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade700, Colors.blue.shade600],
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.filter_alt,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Advanced Filters',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (activeFilterCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$activeFilterCount',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (activeFilterCount > 0)
                  TextButton.icon(
                    onPressed: _clearFilters,
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text('Clear All'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withOpacity(0.2),
                    ),
                  ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _toggleExpanded,
                  icon: AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: const Icon(Icons.expand_more, size: 20),
                  ),
                  label: Text(_isExpanded ? 'Hide' : 'Show'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.blue.shade700,
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),

          // Expandable Filter Content
          SizeTransition(
            sizeFactor: _animation,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Date and Date Range
                  if (widget.showDateFilter || widget.showDateRangeFilter)
                    Row(
                      children: [
                        if (widget.showDateFilter)
                          Expanded(child: _buildDateFilter()),
                        if (widget.showDateFilter && widget.showDateRangeFilter)
                          const SizedBox(width: 16),
                        if (widget.showDateRangeFilter)
                          Expanded(child: _buildDateRangeFilter()),
                      ],
                    ),
                  if (widget.showDateFilter || widget.showDateRangeFilter)
                    const SizedBox(height: 16),

                  // Row 2: Country and State
                  if (widget.showCountryFilter || widget.showStateFilter)
                    Row(
                      children: [
                        if (widget.showCountryFilter)
                          Expanded(child: _buildCountryDropdown()),
                        if (widget.showCountryFilter && widget.showStateFilter)
                          const SizedBox(width: 16),
                        if (widget.showStateFilter)
                          Expanded(child: _buildStateDropdown()),
                      ],
                    ),
                  if (widget.showCountryFilter || widget.showStateFilter)
                    const SizedBox(height: 16),

                  // Row 3: City and Area
                  if (widget.showCityFilter || widget.showAreaFilter)
                    Row(
                      children: [
                        if (widget.showCityFilter)
                          Expanded(child: _buildCityDropdown()),
                        if (widget.showCityFilter && widget.showAreaFilter)
                          const SizedBox(width: 16),
                        if (widget.showAreaFilter)
                          Expanded(child: _buildAreaFilter()),
                      ],
                    ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _clearFilters,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Reset'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                          side: BorderSide(color: Colors.grey.shade400),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _applyFilters,
                        icon: const Icon(Icons.check_circle, size: 18),
                        label: const Text('Apply Filters'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              'Single Date',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _selectDate(context),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: _selectedDate != null
                    ? Colors.blue.shade300
                    : Colors.grey.shade300,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(10),
              color: Colors.white,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.event,
                  size: 18,
                  color: _selectedDate != null
                      ? Colors.blue.shade700
                      : Colors.grey.shade600,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _selectedDate != null
                        ? DateFormat('dd/MM/yyyy').format(_selectedDate!)
                        : 'Select Date',
                    style: TextStyle(
                      color: _selectedDate != null
                          ? Colors.black87
                          : Colors.grey.shade500,
                      fontSize: 14,
                      fontWeight: _selectedDate != null
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ),
                if (_selectedDate != null)
                  GestureDetector(
                    onTap: () => setState(() => _selectedDate = null),
                    child: Icon(
                      Icons.cancel,
                      size: 18,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateRangeFilter() {
    String displayText = 'Select Date Range';
    if (_startDate != null && _endDate != null) {
      displayText =
          '${DateFormat('dd/MM/yyyy').format(_startDate!)} - ${DateFormat('dd/MM/yyyy').format(_endDate!)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.date_range, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              'Date Range',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _selectDateRange(context),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: _startDate != null && _endDate != null
                    ? Colors.blue.shade300
                    : Colors.grey.shade300,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(10),
              color: Colors.white,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_month,
                  size: 18,
                  color: _startDate != null && _endDate != null
                      ? Colors.blue.shade700
                      : Colors.grey.shade600,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    displayText,
                    style: TextStyle(
                      color: _startDate != null && _endDate != null
                          ? Colors.black87
                          : Colors.grey.shade500,
                      fontSize: 14,
                      fontWeight: _startDate != null && _endDate != null
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ),
                if (_startDate != null && _endDate != null)
                  GestureDetector(
                    onTap: () => setState(() {
                      _startDate = null;
                      _endDate = null;
                    }),
                    child: Icon(
                      Icons.cancel,
                      size: 18,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCountryDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.public, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              'Country',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // TEMPORARY FIX: Using simple button instead of CSCPicker
        InkWell(
          onTap: () {
            showCountryPicker(
              context: context,
              showPhoneCode: false,
              onSelect: (Country country) {
                setState(() {
                  _selectedCountry = country.name;
                  _selectedState = null;
                  _selectedCity = null;
                });
              },
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: _selectedCountry != null
                    ? Colors.blue.shade300
                    : Colors.grey.shade300,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(10),
              color: Colors.white,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.public,
                  size: 18,
                  color: _selectedCountry != null
                      ? Colors.blue.shade700
                      : Colors.grey.shade600,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _selectedCountry ?? 'Select Country',
                    style: TextStyle(
                      color: _selectedCountry != null
                          ? Colors.black87
                          : Colors.grey.shade500,
                      fontSize: 14,
                      fontWeight: _selectedCountry != null
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ),
                if (_selectedCountry != null)
                  GestureDetector(
                    onTap: () => setState(() {
                      _selectedCountry = null;
                      _selectedState = null;
                      _selectedCity = null;
                    }),
                    child: Icon(
                      Icons.cancel,
                      size: 18,
                      color: Colors.grey.shade600,
                    ),
                  )
                else
                  Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStateDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.location_city, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              'State / Province',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: _selectedCountry != null
                ? Colors.white
                : Colors.grey.shade100,
          ),
          child: IgnorePointer(
            ignoring: _selectedCountry == null,
            child: Opacity(
              opacity: _selectedCountry != null ? 1.0 : 0.6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _selectedState != null
                        ? Colors.blue.shade300
                        : Colors.grey.shade300,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.place,
                      size: 18,
                      color: _selectedState != null
                          ? Colors.blue.shade700
                          : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _selectedState ?? 'Select State',
                        style: TextStyle(
                          color: _selectedState != null
                              ? Colors.black87
                              : Colors.grey.shade500,
                          fontSize: 14,
                          fontWeight: _selectedState != null
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCityDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.apartment, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              'City / District',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: _selectedState != null ? Colors.white : Colors.grey.shade100,
          ),
          child: IgnorePointer(
            ignoring: _selectedState == null,
            child: Opacity(
              opacity: _selectedState != null ? 1.0 : 0.6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _selectedCity != null
                        ? Colors.blue.shade300
                        : Colors.grey.shade300,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 18,
                      color: _selectedCity != null
                          ? Colors.blue.shade700
                          : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _selectedCity ?? 'Select City',
                        style: TextStyle(
                          color: _selectedCity != null
                              ? Colors.black87
                              : Colors.grey.shade500,
                          fontSize: 14,
                          fontWeight: _selectedCity != null
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAreaFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.place_outlined, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              'Area / Locality',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _areaController,
          decoration: InputDecoration(
            hintText: 'Enter area or locality',
            hintStyle: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 14,
            ),
            prefixIcon: Icon(
              Icons.my_location,
              color: Colors.grey.shade600,
              size: 18,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.blue.shade300, width: 1.5),
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
  }
}
