import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:abra_fleet/core/services/roster_service.dart';
import 'package:abra_fleet/core/services/backend_connection_manager.dart';

class TripsClientPage extends StatefulWidget {
  const TripsClientPage({Key? key}) : super(key: key);

  @override
  State<TripsClientPage> createState() => _TripsClientPageState();
}

class _TripsClientPageState extends State<TripsClientPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToTop = false;
  
  late RosterService _rosterService;
  List<Map<String, dynamic>> _allTrips = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  
  // Filter variables
  String _searchQuery = '';
  String _selectedCompany = 'All';
  DateTimeRange? _dateRange;
  
  // Stats
  int _assignedCount = 0;
  int _ongoingCount = 0;
  int _completedCount = 0;
  int _cancelledCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _rosterService = RosterService(apiService: BackendConnectionManager().apiService);
    
    _scrollController.addListener(() {
      if (_scrollController.offset > 200 && !_showScrollToTop) {
        setState(() => _showScrollToTop = true);
      } else if (_scrollController.offset <= 200 && _showScrollToTop) {
        setState(() => _showScrollToTop = false);
      }
    });
    
    _loadTrips();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// Helper method to safely extract string values from JSON
  String _safeGetString(Map<String, dynamic> data, String key, String defaultValue) {
    final value = data[key];
    if (value == null) return defaultValue;
    if (value is String) return value;
    if (value is Map || value is List) {
      // If it's a complex object, try to extract a meaningful string
      if (value is Map<String, dynamic>) {
        // Try common string fields
        final stringValue = value['name'] ?? value['value'] ?? value['text'] ?? value.toString();
        return stringValue is String ? stringValue : defaultValue;
      }
      return defaultValue;
    }
    return value.toString();
  }

  Future<void> _loadTrips() async {
    setState(() => _isLoading = true);
    
    try {
      final response = await _rosterService.getAssignedTrips();
      
      if (response['success'] == true) {
        final trips = List<Map<String, dynamic>>.from(response['data'] ?? []);
        
        setState(() {
          _allTrips = trips;
          _calculateStats();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading trips: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshData() async {
    if (_isRefreshing) return;
    
    setState(() => _isRefreshing = true);
    
    try {
      await _loadTrips();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Data refreshed successfully'),
              ],
            ),
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refresh failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  void _calculateStats() {
    _assignedCount = _allTrips.where((t) => t['status'] == 'assigned').length;
    _ongoingCount = _allTrips.where((t) => t['status'] == 'ongoing').length;
    _completedCount = _allTrips.where((t) => t['status'] == 'completed').length;
    _cancelledCount = _allTrips.where((t) => t['status'] == 'cancelled').length;
  }

  List<Map<String, dynamic>> _getFilteredTrips(String status) {
    return _allTrips.where((trip) {
      // Status filter
      if (status != 'all' && _safeGetString(trip, 'status', '') != status) return false;
      
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final name = _safeGetString(trip, 'customerName', '').toLowerCase();
        final email = _safeGetString(trip, 'customerEmail', '').toLowerCase();
        final vehicle = _safeGetString(trip, 'vehicleNumber', '').toLowerCase();
        final driver = _safeGetString(trip, 'driverName', '').toLowerCase();
        
        if (!name.contains(query) && 
            !email.contains(query) && 
            !vehicle.contains(query) && 
            !driver.contains(query)) {
          return false;
        }
      }
      
      // Company filter
      if (_selectedCompany != 'All') {
        final company = _safeGetString(trip, 'companyName', '');
        if (company != _selectedCompany) return false;
      }
      
      // Date range filter
      if (_dateRange != null) {
        final assignedAt = trip['assignedAt'];
        if (assignedAt != null) {
          try {
            final date = DateTime.parse(assignedAt.toString());
            if (date.isBefore(_dateRange!.start) || date.isAfter(_dateRange!.end)) {
              return false;
            }
          } catch (e) {
            // If date parsing fails, skip this filter
            debugPrint('Date parsing error: $e');
          }
        }
      }
      
      return true;
    }).toList();
  }

  List<String> _getUniqueCompanies() {
    final companies = _allTrips
        .map((t) => _safeGetString(t, 'companyName', 'Unknown'))
        .where((c) => c.isNotEmpty && c != 'Unknown')
        .toSet()
        .toList();
    companies.sort();
    return ['All', ...companies];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Stack(
          children: [
            NestedScrollView(
              controller: _scrollController,
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        _buildStatsSection(),
                        _buildSearchAndFilters(),
                        if (_hasActiveFilters()) _buildActiveFiltersChips(),
                        _buildTabBar(),
                      ],
                    ),
                  ),
                ];
              },
              body: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildTripsList('assigned'),
                        _buildTripsList('ongoing'),
                        _buildTripsList('completed'),
                        _buildTripsList('cancelled'),
                      ],
                    ),
            ),
            if (_isRefreshing) _buildRefreshOverlay(),
          ],
        ),
      ),
      floatingActionButton: _showScrollToTop
          ? FloatingActionButton(
              mini: true,
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF2563EB),
              elevation: 4,
              onPressed: _scrollToTop,
              child: const Icon(Icons.keyboard_arrow_up),
            )
          : null,
    );
  }

  Widget _buildStatsSection() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _tabController.animateTo(0),
              borderRadius: BorderRadius.circular(12),
              child: _buildStatCard(
                icon: Icons.assignment,
                color: const Color(0xFF2563EB),
                value: _assignedCount.toString(),
                label: 'Assigned',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () => _tabController.animateTo(1),
              borderRadius: BorderRadius.circular(12),
              child: _buildStatCard(
                icon: Icons.directions_car,
                color: const Color(0xFFF59E0B),
                value: _ongoingCount.toString(),
                label: 'Ongoing',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () => _tabController.animateTo(2),
              borderRadius: BorderRadius.circular(12),
              child: _buildStatCard(
                icon: Icons.check_circle,
                color: const Color(0xFF10B981),
                value: _completedCount.toString(),
                label: 'Completed',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () => _tabController.animateTo(3),
              borderRadius: BorderRadius.circular(12),
              child: _buildStatCard(
                icon: Icons.cancel,
                color: const Color(0xFFEF4444),
                value: _cancelledCount.toString(),
                label: 'Cancelled',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: InputDecoration(
                    hintText: 'Search by name, email, vehicle, driver...',
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Color(0xFF64748B)),
                            onPressed: () => setState(() => _searchQuery = ''),
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.2)),
                ),
                child: IconButton(
                  icon: _isRefreshing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
                          ),
                        )
                      : const Icon(Icons.refresh, color: Color(0xFF8B5CF6)),
                  onPressed: _isRefreshing ? null : _refreshData,
                  tooltip: "Refresh Data",
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCompany,
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B)),
                      items: _getUniqueCompanies().toSet().toList().map((company) {
                        return DropdownMenuItem(
                          value: company,
                          child: Text(
                            company,
                            style: const TextStyle(fontSize: 14),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedCompany = value);
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.2)),
                ),
                child: IconButton(
                  icon: const Icon(Icons.date_range, color: Color(0xFF2563EB)),
                  onPressed: _showDateRangePicker,
                  tooltip: "Date Range",
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: const Color(0xFF2563EB),
        unselectedLabelColor: const Color(0xFF64748B),
        indicatorColor: const Color(0xFF2563EB),
        indicatorWeight: 3,
        isScrollable: false,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
        tabs: [
          Tab(text: 'Assigned ($_assignedCount)'),
          Tab(text: 'Ongoing ($_ongoingCount)'),
          Tab(text: 'Completed ($_completedCount)'),
          Tab(text: 'Cancelled ($_cancelledCount)'),
        ],
      ),
    );
  }

  bool _hasActiveFilters() {
    return _searchQuery.isNotEmpty || 
           _selectedCompany != 'All' || 
           _dateRange != null;
  }

  Widget _buildActiveFiltersChips() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Text(
              'Active Filters: ',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 8),
            if (_selectedCompany != 'All')
              _buildFilterChip('Company: $_selectedCompany', () {
                setState(() => _selectedCompany = 'All');
              }),
            if (_dateRange != null)
              _buildFilterChip(
                'Date: ${DateFormat('MMM dd').format(_dateRange!.start)} - ${DateFormat('MMM dd').format(_dateRange!.end)}',
                () {
                  setState(() => _dateRange = null);
                },
              ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _clearAllFilters,
              icon: const Icon(Icons.clear_all, size: 16),
              label: const Text('Clear All'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, VoidCallback onRemove) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB).withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF2563EB),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(
              Icons.close,
              size: 14,
              color: Color(0xFF2563EB),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripsList(String status) {
    final trips = _getFilteredTrips(status);

    if (trips.isEmpty) {
      return _buildEmptyState(
        _hasActiveFilters()
            ? 'No trips match your filters'
            : 'No ${status} trips found',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: trips.length,
      itemBuilder: (context, index) {
        return _buildTripCard(trips[index]);
      },
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF64748B),
            ),
          ),
          if (_hasActiveFilters()) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _clearAllFilters,
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear Filters'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF2563EB),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTripCard(Map<String, dynamic> trip) {
    final status = _safeGetString(trip, 'status', 'unknown');
    final statusColor = _getStatusColor(status);
    final customerName = _safeGetString(trip, 'customerName', 'Unknown');
    final customerEmail = _safeGetString(trip, 'customerEmail', '');
    final companyName = _safeGetString(trip, 'companyName', 'Unknown');
    final vehicleNumber = _safeGetString(trip, 'vehicleNumber', 'Not Assigned');
    final driverName = _safeGetString(trip, 'driverName', 'Not Assigned');
    final driverPhone = _safeGetString(trip, 'driverPhone', 'N/A');
    final rosterType = _safeGetString(trip, 'rosterType', _safeGetString(trip, 'tripType', 'BOTH'));
    final pickupLocation = _safeGetString(trip, 'pickupLocation', '');
    final dropLocation = _safeGetString(trip, 'dropLocation', '');
    final pickupTime = _safeGetString(trip, 'pickupTime', '');
    final dropTime = _safeGetString(trip, 'dropTime', '');
    final assignedAt = trip['assignedAt'];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _showTripDetails(trip),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.person,
                      color: statusColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customerName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        if (customerEmail.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            customerEmail,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _buildStatusChip(status),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildInfoRow(
                      icon: Icons.business,
                      label: 'Company',
                      value: companyName,
                      color: const Color(0xFF8B5CF6),
                    ),
                  ),
                  Expanded(
                    child: _buildInfoRow(
                      icon: Icons.sync_alt,
                      label: 'Type',
                      value: rosterType.toUpperCase(),
                      color: const Color(0xFF06B6D4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildInfoRow(
                      icon: Icons.directions_car,
                      label: 'Vehicle',
                      value: vehicleNumber,
                      color: const Color(0xFF2563EB),
                    ),
                  ),
                  Expanded(
                    child: _buildInfoRow(
                      icon: Icons.person_outline,
                      label: 'Driver',
                      value: driverName,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
              if (driverPhone.isNotEmpty && driverPhone != 'N/A') ...[
                const SizedBox(height: 8),
                _buildInfoRow(
                  icon: Icons.phone,
                  label: 'Driver Phone',
                  value: driverPhone,
                  color: const Color(0xFF10B981),
                ),
              ],
              if (pickupLocation.isNotEmpty || dropLocation.isNotEmpty) ...[
                const SizedBox(height: 8),
                if (pickupLocation.isNotEmpty)
                  _buildInfoRow(
                    icon: Icons.location_on,
                    label: 'Pickup',
                    value: pickupLocation,
                    color: const Color(0xFFEF4444),
                  ),
                if (pickupLocation.isNotEmpty && dropLocation.isNotEmpty)
                  const SizedBox(height: 8),
                if (dropLocation.isNotEmpty)
                  _buildInfoRow(
                    icon: Icons.location_on_outlined,
                    label: 'Drop',
                    value: dropLocation,
                    color: const Color(0xFFEF4444),
                  ),
              ],
              if (pickupTime.isNotEmpty || dropTime.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (pickupTime.isNotEmpty)
                      Expanded(
                        child: _buildInfoRow(
                          icon: Icons.access_time,
                          label: 'Pickup Time',
                          value: pickupTime,
                          color: const Color(0xFFF59E0B),
                        ),
                      ),
                    if (dropTime.isNotEmpty)
                      Expanded(
                        child: _buildInfoRow(
                          icon: Icons.access_time_filled,
                          label: 'Drop Time',
                          value: dropTime,
                          color: const Color(0xFFF59E0B),
                        ),
                      ),
                  ],
                ),
              ],
              // ✅ ADD DISTANCE INFORMATION
              if (_hasDistanceData(trip)) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoRow(
                        icon: Icons.straighten,
                        label: 'Total Distance',
                        value: '${_getDistanceValue(trip)} km',
                        color: const Color(0xFF059669),
                      ),
                    ),
                    if (_getDurationValue(trip) > 0)
                      Expanded(
                        child: _buildInfoRow(
                          icon: Icons.schedule,
                          label: 'Est. Duration',
                          value: '${_getDurationValue(trip)} min',
                          color: const Color(0xFF059669),
                        ),
                      ),
                  ],
                ),
              ],
              if (assignedAt != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 14,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Assigned: ${_formatDateTime(assignedAt.toString())}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF1E293B),
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String status) {
    final color = _getStatusColor(status);
    final label = status.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'assigned':
        return const Color(0xFF2563EB);
      case 'ongoing':
        return const Color(0xFFF59E0B);
      case 'completed':
        return const Color(0xFF10B981);
      case 'cancelled':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF64748B);
    }
  }

  String _formatDateTime(String dateTimeStr) {
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      return DateFormat('MMM dd, yyyy HH:mm').format(dateTime);
    } catch (e) {
      return dateTimeStr;
    }
  }

  void _showTripDetails(Map<String, dynamic> trip) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _getStatusColor(trip['status'] ?? 'unknown').withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: _getStatusColor(trip['status'] ?? 'unknown'),
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Trip Details',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow('Status', trip['status'] ?? 'Unknown', Icons.flag),
                      _buildDetailRow('Customer Name', trip['customerName'] ?? 'Unknown', Icons.person),
                      _buildDetailRow('Email', trip['customerEmail'] ?? 'N/A', Icons.email),
                      _buildDetailRow('Phone', trip['customerPhone'] ?? 'N/A', Icons.phone_android),
                      _buildDetailRow('Company', trip['companyName'] ?? 'Unknown', Icons.business),
                      const Divider(height: 24),
                      _buildDetailRow('Vehicle Number', trip['vehicleNumber'] ?? 'Not Assigned', Icons.directions_car),
                      _buildDetailRow('Driver Name', trip['driverName'] ?? 'Not Assigned', Icons.person_outline),
                      _buildDetailRow(
                        'Driver Phone', 
                        (trip['driverPhone'] != null && trip['driverPhone'].toString().isNotEmpty) 
                            ? trip['driverPhone'].toString() 
                            : 'Not Available', 
                        Icons.phone
                      ),
                      const Divider(height: 24),
                      _buildDetailRow('Trip Type', (trip['rosterType'] ?? trip['tripType'] ?? 'BOTH').toString().toUpperCase(), Icons.sync_alt),
                      if (trip['pickupLocation'] != null && trip['pickupLocation'].toString().isNotEmpty)
                        _buildDetailRow('Pickup Location', trip['pickupLocation'].toString(), Icons.location_on),
                      if (trip['dropLocation'] != null && trip['dropLocation'].toString().isNotEmpty)
                        _buildDetailRow('Drop Location', trip['dropLocation'].toString(), Icons.location_on_outlined),
                      if (trip['pickupTime'] != null && trip['pickupTime'].toString().isNotEmpty)
                        _buildDetailRow('Pickup Time', trip['pickupTime'].toString(), Icons.access_time),
                      if (trip['dropTime'] != null && trip['dropTime'].toString().isNotEmpty)
                        _buildDetailRow('Drop Time', trip['dropTime'].toString(), Icons.access_time_filled),
                      if (trip['assignedAt'] != null)
                        _buildDetailRow('Assigned At', _formatDateTime(trip['assignedAt'].toString()), Icons.schedule),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF64748B)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF1E293B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRefreshOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.3),
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                const Text(
                  'Refreshing...',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Fetching latest data',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  void _clearAllFilters() {
    setState(() {
      _searchQuery = '';
      _selectedCompany = 'All';
      _dateRange = null;
    });
  }

  Future<void> _showDateRangePicker() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
    }
  }

  // ✅ Helper methods for distance data
  bool _hasDistanceData(Map<String, dynamic> trip) {
    final distance = _getDistanceValue(trip);
    return distance > 0;
  }

  double _getDistanceValue(Map<String, dynamic> trip) {
    // Try multiple fields for distance data
    if (trip['totalDistanceKm'] != null) {
      return (trip['totalDistanceKm'] as num).toDouble();
    }
    if (trip['distance'] != null) {
      return (trip['distance'] as num).toDouble();
    }
    if (trip['distanceData'] != null && trip['distanceData']['totalDistanceKm'] != null) {
      return (trip['distanceData']['totalDistanceKm'] as num).toDouble();
    }
    return 0.0;
  }

  int _getDurationValue(Map<String, dynamic> trip) {
    // Try multiple fields for duration data
    if (trip['totalDurationMin'] != null) {
      return (trip['totalDurationMin'] as num).toInt();
    }
    if (trip['estimatedDuration'] != null) {
      return (trip['estimatedDuration'] as num).toInt();
    }
    if (trip['distanceData'] != null && trip['distanceData']['totalDurationMin'] != null) {
      return (trip['distanceData']['totalDurationMin'] as num).toInt();
    }
    return 0;
  }
}
