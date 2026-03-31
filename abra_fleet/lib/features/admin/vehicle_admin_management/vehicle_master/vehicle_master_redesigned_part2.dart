// ============================================================================
// VEHICLE MASTER SCREEN - REDESIGNED - PART 2/5
// Main Widget, State Management, Lifecycle Methods
// ============================================================================
// APPEND THIS TO PART 1
// ============================================================================

class VehicleMasterScreenRedesigned extends StatefulWidget {
  const VehicleMasterScreenRedesigned({super.key});

  @override
  State<VehicleMasterScreenRedesigned> createState() => _VehicleMasterScreenRedesignedState();
}

class _VehicleMasterScreenRedesignedState extends State<VehicleMasterScreenRedesigned> 
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  
  // Services
  final VehicleService _vehicleService = VehicleService();
  final DocumentStorageService _documentStorageService = DocumentStorageService();
  
  // Data
  List<_VehicleData> _vehicleData = [];
  List<_VehicleData> _filteredVehicleData = [];
  
  // Loading states
  bool _isLoading = true;
  String? _errorMessage;
  
  // Basic filter states
  String _selectedStatusFilter = 'All';
  String _selectedDocumentFilter = 'All';
  String _selectedVendorFilter = 'All';
  String _selectedDriverFilter = 'All';
  String _selectedTypeFilter = 'All';
  
  // Location filters (from CountryStateCityFilter)
  String? _selectedCountry;
  String? _selectedState;
  String? _selectedCity;
  String? _selectedArea;
  DateTime? _startDate;
  DateTime? _endDate;
  
  // Search controller
  final TextEditingController _searchController = TextEditingController();
  
  // Advanced filters animation
  bool _showAdvancedFilters = false;
  late AnimationController _filterAnimationController;
  late Animation<double> _filterAnimation;
  
  // Horizontal scroll controller
  final ScrollController _horizontalScrollController = ScrollController();
  
  // Auto-refresh timer
  Timer? _refreshTimer;
  DateTime? _lastRefreshTime;

  // ============================================================================
  // LIFECYCLE METHODS
  // ============================================================================
  @override
  void initState() {
    super.initState();
    
    // Initialize filter animation
    _filterAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _filterAnimation = CurvedAnimation(
      parent: _filterAnimationController,
      curve: Curves.easeInOut,
    );
    
    _loadVehicles();
    _searchController.addListener(_applyFilters);
    WidgetsBinding.instance.addObserver(this);
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _filterAnimationController.dispose();
    _horizontalScrollController.dispose();
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print('🔄 Vehicle Master: App resumed, refreshing vehicles...');
      _loadVehicles();
    }
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && !_isLoading) {
        print('🔄 Vehicle Master: Auto-refresh triggered (every 30s)');
        _loadVehicles();
      }
    });
  }

  // ============================================================================
  // API METHODS
  // ============================================================================
  Future<void> _loadVehicles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _vehicleService.getVehicles(limit: 100);
      
      if (response['success'] == true) {
        final List<dynamic> vehiclesData = response['data'] ?? [];
        setState(() {
          _vehicleData = vehiclesData
              .map((vehicle) => _VehicleData.fromBackend(vehicle))
              .toList();
          _applyFilters();
          _isLoading = false;
          _lastRefreshTime = DateTime.now();
        });
      } else {
        setState(() {
          _errorMessage = response['message'] ?? 'Failed to load vehicles';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading vehicles: $e';
        _isLoading = false;
      });
    }
  }

  // ============================================================================
  // FILTER LOGIC
  // ============================================================================
  void _applyFilters() {
    final searchQuery = _searchController.text.toLowerCase().trim();
    
    _filteredVehicleData = _vehicleData.where((vehicle) {
      // Search filter
      if (searchQuery.isNotEmpty) {
        final seatCapacity = int.tryParse(vehicle.seatingCapacity) ?? 4;
        final driverSeats = vehicle.assignedDriverName != null ? 1 : 0;
        final assignedCustomers = vehicle.assignedCustomersCount;
        final availableSeats = seatCapacity - driverSeats - assignedCustomers;
        
        final matchesSearch = 
          vehicle.vehicleId.toLowerCase().contains(searchQuery) ||
          vehicle.registration.toLowerCase().contains(searchQuery) ||
          vehicle.type.toLowerCase().contains(searchQuery) ||
          vehicle.model.toLowerCase().contains(searchQuery) ||
          vehicle.status.toLowerCase().contains(searchQuery) ||
          vehicle.year.toLowerCase().contains(searchQuery) ||
          vehicle.engineType.toLowerCase().contains(searchQuery) ||
          vehicle.engineCapacity.toLowerCase().contains(searchQuery) ||
          vehicle.mileage.toLowerCase().contains(searchQuery) ||
          (vehicle.vendor?.toLowerCase().contains(searchQuery) ?? false) ||
          (vehicle.assignedDriverName?.toLowerCase().contains(searchQuery) ?? false) ||
          vehicle.seatingCapacity.contains(searchQuery) ||
          availableSeats.toString().contains(searchQuery) ||
          '$availableSeats/$seatCapacity'.contains(searchQuery) ||
          vehicle.lastServiceDate.toLowerCase().contains(searchQuery) ||
          vehicle.nextServiceDue.toLowerCase().contains(searchQuery);
        
        if (!matchesSearch) return false;
      }
      
      // Status filter
      if (_selectedStatusFilter != 'All' && 
          vehicle.status.toUpperCase() != _selectedStatusFilter.toUpperCase()) {
        return false;
      }
      
      // Type filter
      if (_selectedTypeFilter != 'All' && 
          vehicle.type.toUpperCase() != _selectedTypeFilter.toUpperCase()) {
        return false;
      }
      
      // Vendor filter
      if (_selectedVendorFilter == 'Own Fleet' && vehicle.vendor != null && vehicle.vendor!.isNotEmpty) {
        return false;
      } else if (_selectedVendorFilter == 'Vendor' && (vehicle.vendor == null || vehicle.vendor!.isEmpty)) {
        return false;
      }
      
      // Driver filter
      if (_selectedDriverFilter == 'Assigned' && vehicle.assignedDriverName == null) {
        return false;
      } else if (_selectedDriverFilter == 'Not Assigned' && vehicle.assignedDriverName != null) {
        return false;
      }
      
      // Document filter
      if (_selectedDocumentFilter == 'Expired Documents' && !vehicle.hasExpiredDocuments) {
        return false;
      } else if (_selectedDocumentFilter == 'Expiring Soon' && !vehicle.hasExpiringSoonDocuments) {
        return false;
      } else if (_selectedDocumentFilter == 'All Valid' && 
                 (vehicle.hasExpiredDocuments || vehicle.hasExpiringSoonDocuments)) {
        return false;
      } else if (_selectedDocumentFilter == 'No Documents' && vehicle.documents.isNotEmpty) {
        return false;
      }
      
      // Location filters (Country → State → City hierarchy)
      if (_selectedCountry != null && _selectedCountry!.isNotEmpty) {
        if (vehicle.country == null || 
            !vehicle.country!.toLowerCase().contains(_selectedCountry!.toLowerCase())) {
          return false;
        }
      }
      
      if (_selectedState != null && _selectedState!.isNotEmpty) {
        if (vehicle.state == null || 
            !vehicle.state!.toLowerCase().contains(_selectedState!.toLowerCase())) {
          return false;
        }
      }
      
      if (_selectedCity != null && _selectedCity!.isNotEmpty) {
        if (vehicle.city == null || 
            !vehicle.city!.toLowerCase().contains(_selectedCity!.toLowerCase())) {
          return false;
        }
      }
      
      // Date range filter
      if (_startDate != null && _endDate != null && vehicle.onboardedDate != null) {
        if (vehicle.onboardedDate!.isBefore(_startDate!) || 
            vehicle.onboardedDate!.isAfter(_endDate!)) {
          return false;
        }
      }
      
      return true;
    }).toList();
    
    setState(() {});
  }

  void _updateFilter(String filterType, String value) {
    setState(() {
      if (filterType == 'status') {
        _selectedStatusFilter = value;
      } else if (filterType == 'document') {
        _selectedDocumentFilter = value;
      } else if (filterType == 'vendor') {
        _selectedVendorFilter = value;
      } else if (filterType == 'driver') {
        _selectedDriverFilter = value;
      } else if (filterType == 'type') {
        _selectedTypeFilter = value;
      }
      _applyFilters();
    });
  }

  void _clearAllFilters() {
    setState(() {
      _selectedStatusFilter = 'All';
      _selectedDocumentFilter = 'All';
      _selectedVendorFilter = 'All';
      _selectedDriverFilter = 'All';
      _selectedTypeFilter = 'All';
      _selectedCountry = null;
      _selectedState = null;
      _selectedCity = null;
      _selectedArea = null;
      _startDate = null;
      _endDate = null;
      _searchController.clear();
      _applyFilters();
    });
  }

  void _toggleAdvancedFilters() {
    setState(() {
      _showAdvancedFilters = !_showAdvancedFilters;
      if (_showAdvancedFilters) {
        _filterAnimationController.forward();
      } else {
        _filterAnimationController.reverse();
      }
    });
  }

  int _getActiveFilterCount() {
    int count = 0;
    if (_selectedStatusFilter != 'All') count++;
    if (_selectedDocumentFilter != 'All') count++;
    if (_selectedVendorFilter != 'All') count++;
    if (_selectedDriverFilter != 'All') count++;
    if (_selectedTypeFilter != 'All') count++;
    if (_selectedCountry != null && _selectedCountry!.isNotEmpty) count++;
    if (_selectedState != null && _selectedState!.isNotEmpty) count++;
    if (_selectedCity != null && _selectedCity!.isNotEmpty) count++;
    if (_startDate != null && _endDate != null) count++;
    return count;
  }

  // ============================================================================
  // END OF PART 2
  // Continue with Part 3 (Export Methods)
  // ============================================================================
}
