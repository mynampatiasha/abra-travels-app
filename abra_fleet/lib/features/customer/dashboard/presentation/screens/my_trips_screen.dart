// lib/features/customer/trips/presentation/screens/my_trips_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:abra_fleet/features/customer/dashboard/data/repositories/roster_repository.dart';
import 'package:abra_fleet/features/customer/dashboard/presentation/screens/roster_screen.dart'; // or wherever your CreateRosterScreen is located
import 'package:abra_fleet/features/customer/dashboard/presentation/screens/address_change_request_screen.dart';
import 'package:abra_fleet/features/customer/dashboard/presentation/screens/my_address_requests_screen.dart';
import 'package:abra_fleet/core/services/backend_connection_manager.dart';
import 'package:abra_fleet/core/services/geocoding_service.dart';
import 'package:abra_fleet/core/services/my_trips_service.dart';

class MyTripsScreen extends StatefulWidget {
  final VoidCallback? onRefresh;
  final Key? key;

  const MyTripsScreen({
    this.onRefresh,
    this.key,
  }) : super(key: key);

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

// Add a GlobalKey to access the state
final GlobalKey<_MyTripsScreenState> _key = GlobalKey<_MyTripsScreenState>();

class _MyTripsScreenState extends State<MyTripsScreen> {
  late final RosterRepository _rosterRepository;
  Future<List<Map<String, dynamic>>>? _myRostersFuture;
  
  // Filter state
  String _selectedFilter = 'all';
  List<Map<String, dynamic>> _allRosters = [];
  List<Map<String, dynamic>> _filteredRosters = [];

  @override
  void initState() {
    super.initState();
    // Fix: Initialize RosterRepository with ApiService from BackendConnectionManager
    _rosterRepository = RosterRepository(
      apiService: BackendConnectionManager().apiService,
    );
    _fetchMyRosters();
    
    // Call the refresh callback if provided
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onRefresh?.call();
    });
  }
  
  // ✅ ADD: Handle route returns and refresh data
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Check if we're returning from another screen
    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent) {
      // Small delay to ensure we're fully loaded, then refresh
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          debugPrint('🔄 Screen became active - refreshing data');
          _fetchMyRosters();
        }
      });
    }
  }

  // Helper to fetch rosters, used for initial load and refresh
  void _fetchMyRosters() {
    if (mounted) {
      debugPrint('🔄 Fetching my rosters...');
      setState(() {
        _myRostersFuture = _rosterRepository.getMyRosters().then((rosters) {
          debugPrint('📋 Successfully fetched ${rosters.length} rosters');
          _allRosters = rosters;
          _applyFilter();
          return rosters;
        }).catchError((error) {
          debugPrint('❌ Error fetching rosters: $error');
          throw error;
        });
      });
    }
  }

  // ✅ ADD: Manual refresh method
  Future<void> _refreshData() async {
    debugPrint('🔄 Manual refresh triggered');
    _fetchMyRosters();
  }

  // Apply filter to rosters
  void _applyFilter() {
    if (_selectedFilter == 'all') {
      _filteredRosters = List.from(_allRosters);
    } else {
      _filteredRosters = _allRosters.where((roster) {
        final status = roster['status']?.toString().toLowerCase() ?? '';
        switch (_selectedFilter) {
          case 'pending':
            return status.contains('pending') || status == 'created';
          case 'assigned':
            return status == 'assigned';
          case 'ongoing':
            return status == 'in_progress' || status == 'ongoing';
          case 'completed':
            return status == 'completed' || status == 'delivered';
          case 'cancelled':
            return status == 'cancelled';
          default:
            return true;
        }
      }).toList();
    }
  }

  // Show filter dialog
  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Filter Trips'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFilterOption('all', 'All Trips'),
              _buildFilterOption('pending', 'Pending'),
              _buildFilterOption('assigned', 'Assigned'),
              _buildFilterOption('ongoing', 'Ongoing'),
              _buildFilterOption('completed', 'Completed'),
              _buildFilterOption('cancelled', 'Cancelled'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterOption(String value, String label) {
    return RadioListTile<String>(
      title: Text(label),
      value: value,
      groupValue: _selectedFilter,
      onChanged: (String? newValue) {
        if (newValue != null) {
          setState(() {
            _selectedFilter = newValue;
            _applyFilter();
          });
          Navigator.of(context).pop();
        }
      },
    );
  }

  // --- LOGIC TO HANDLE ROSTER DELETION ---
  Future<void> _handleDeleteRoster(String rosterId) async {
    // Show a confirmation dialog before deleting
    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: const Text('Are you sure you want to cancel this roster request?'),
          actions: <Widget>[
            TextButton(
              child: const Text('No'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Yes, Cancel'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    // If the user confirmed the deletion
    if (confirmDelete == true) {
      try {
        final success = await _rosterRepository.cancelRoster(rosterId);
        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Roster cancelled successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          // Refresh the list to show the change
          _fetchMyRosters();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to cancel roster: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // Handle update roster - navigate to CreateRosterScreen with existing data
  void _handleUpdateRoster(Map<String, dynamic> roster) async {
    // ✅ Check if roster can be edited
    final status = roster['status']?.toString() ?? '';
    final editableStatuses = ['pending_assignment', 'pending', 'created'];
    
    if (!editableStatuses.contains(status.toLowerCase())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cannot edit roster that is already ${status.replaceAll('_', ' ')}. '
              'Please contact admin if changes are needed.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }
    
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateRosterScreen(existingRoster: roster),
      ),
    );
    
    // ✅ IMPROVED: Always refresh if we get any result (including true)
    if (result != null) {
      debugPrint('🔄 Returned from roster edit - refreshing data');
      _fetchMyRosters();
    }
  }



  // Navigate to address change request screen
  void _navigateToAddressChangeRequest() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddressChangeRequestScreen(),
      ),
    );
    
    // ✅ IMPROVED: Always refresh if we get any result
    if (result != null) {
      debugPrint('🔄 Returned from address change - refreshing data');
      _fetchMyRosters();
    }
  }

  // Navigate to my address requests screen
  void _navigateToMyAddressRequests() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MyAddressRequestsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('My Trips'),
            const SizedBox(width: 8),
            if (_selectedFilter != 'all')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  (_selectedFilter ?? 'all').toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'Filter Trips',
          ),
          // ✅ ADD: Manual refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Refresh',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (String value) {
              switch (value) {
                case 'address_change':
                  _navigateToAddressChangeRequest();
                  break;
                case 'my_address_requests':
                  _navigateToMyAddressRequests();
                  break;
                case 'refresh':
                  _fetchMyRosters();
                  break;
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'address_change',
                child: Row(
                  children: [
                    Icon(Icons.location_on, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Change Address'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'my_address_requests',
                child: Row(
                  children: [
                    Icon(Icons.location_history, color: Colors.purple),
                    SizedBox(width: 8),
                    Text('My Address Requests'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, color: Colors.grey),
                    SizedBox(width: 8),
                    Text('Refresh'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: _myRostersFuture == null 
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<List<Map<String, dynamic>>>(
              future: _myRostersFuture!,
              builder: (context, snapshot) {
              // --- LOADING STATE ---
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              // --- ERROR STATE ---
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      const Text(
                        'Failed to load your trips.',
                        style: TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        snapshot.error.toString(),
                        style: TextStyle(color: Colors.grey.shade600),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                        onPressed: _fetchMyRosters,
                      ),
                    ],
                  ),
                );
              }

              // --- EMPTY STATE ---
              final rosters = snapshot.data;
              if (rosters == null || rosters.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.map_outlined, color: Colors.grey.shade400, size: 64),
                      const SizedBox(height: 16),
                      const Text(
                        'No Trips Found',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You haven\'t created any trips yet.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                );
              }

              // Update the rosters list for filtering
              _allRosters = rosters;
              _applyFilter();

              // Show filtered results
              if (_filteredRosters.isEmpty && _selectedFilter != 'all') {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.filter_list_off, color: Colors.grey.shade400, size: 64),
                      const SizedBox(height: 16),
                      Text(
                        'No ${(_selectedFilter ?? 'all').toUpperCase()} Trips',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Try changing the filter or create a new trip.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _selectedFilter = 'all';
                            _applyFilter();
                          });
                        },
                        child: const Text('Show All Trips'),
                      ),
                    ],
                  ),
                );
              }
              
              // --- SUCCESS STATE ---
              return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _filteredRosters.length,
                      itemBuilder: (context, index) {
                        final roster = _filteredRosters[index];
                        return RosterCard(
                          roster: roster,
                          onUpdate: () => _handleUpdateRoster(roster),
                          onDelete: () => _handleDeleteRoster(roster['id']),
                        );
                      },
                    );
            },
          ),
      ),
    );
  }
}

// A dedicated widget for displaying a single roster card with expandable trips
class RosterCard extends StatefulWidget {
  final Map<String, dynamic> roster;
  final VoidCallback onUpdate;
  final VoidCallback onDelete;

  const RosterCard({
    super.key,
    required this.roster,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  State<RosterCard> createState() => _RosterCardState();
}

class _RosterCardState extends State<RosterCard> {
  final _geocodingService = GeocodingService();
  final _tripsService = MyTripsService(); // ✅ ADD THIS LINE
  String? _address;
  bool _isExpanded = false;
  List<Map<String, dynamic>> _dailyTrips = [];
  bool _isLoadingTrips = false;

  // Helper to format dates nicely
  String _formatDate(String dateString) {
    if (dateString.isEmpty || dateString == 'null') return '';
    
    try {
      // Handle different date formats
      DateTime date;
      
      if (dateString.contains('T')) {
        // ISO format: 2024-03-15T00:00:00.000Z
        date = DateTime.parse(dateString);
      } else if (dateString.contains('-')) {
        // Simple format: 2024-03-15
        date = DateTime.parse(dateString);
      } else {
        // Fallback - try to parse as is
        date = DateTime.parse(dateString);
      }
      
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (e) {
      print('❌ Error formatting date: $dateString - $e');
      // Try to extract just the date part if it's an ISO string
      if (dateString.contains('T')) {
        try {
          final datePart = dateString.split('T')[0];
          final date = DateTime.parse(datePart);
          return DateFormat('MMM dd, yyyy').format(date);
        } catch (e2) {
          print('❌ Error formatting date part: ${dateString.split('T')[0]} - $e2');
        }
      }
      return dateString; // Return original if all parsing fails
    }
  }

  // Helper to get color based on status
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending_assignment':
        return Colors.orange;
      case 'assigned':
        return Colors.blue;
      case 'in_progress':
        return Colors.purple;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // Helper to capitalize strings
  String _titleCase(String? text) {
    if (text == null || text.isEmpty) return '';
    return text.replaceAll('_', ' ').split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  // Check if trip can be edited
  // ✅ FIX: Only allow editing rosters that are NOT assigned/in_progress/completed
  bool _canEditTrip(String status) {
    final editableStatuses = ['pending_assignment', 'pending', 'created'];
    return editableStatuses.contains(status.toLowerCase());
  }

  // Check if trip can be cancelled
  // ✅ FIX: Only allow cancelling rosters that are NOT in_progress/completed
  bool _canCancelTrip(String status) {
    final cancellableStatuses = ['pending_assignment', 'assigned', 'pending', 'created'];
    return cancellableStatuses.contains(status.toLowerCase());
  }

  // Get readable location address from roster data
  String _getLocationAddress(String locationType) {
    // This method is deprecated - use _getLocationDetails instead
    return _getLocationDetails(locationType);
  }

  @override
  void initState() {
    super.initState();
    _loadAddress();
  }

  Future<void> _loadAddress() async {
    final location = widget.roster['officeLocation'] ?? '';
    if (location.isNotEmpty) {
      final address = await _geocodingService.getAddressFromLocation(location);
      if (mounted) {
        setState(() {
          _address = address;
        });
      }
    }
  }

// ✅ FIXED: Load daily trips with proper status handling
Future<void> _loadDailyTrips() async {
  if (_isLoadingTrips) return;
  
  setState(() {
    _isLoadingTrips = true;
  });

  try {
    final rosterId = widget.roster['rosterId'] ?? widget.roster['id'];
    
    debugPrint('\n📋 Loading daily trips for roster: $rosterId');
    
    // Call API service
    final result = await _tripsService.getDailyTrips(
      rosterId: rosterId?.toString(),
    );
    
    debugPrint('📊 API Response: ${result['success']}');
    
    if (result['success'] == true) {
      final List<dynamic> tripsData = result['data'] ?? [];
      debugPrint('   ✅ Retrieved ${tripsData.length} trip(s) from API');
      
      // Transform API response to local format
      final trips = tripsData.map((trip) {
        final status = trip['status']?.toString() ?? 'scheduled';
        
        debugPrint('   🔍 Trip: ${trip['dateString']} - Status: $status');
        
        return {
          'tripId': trip['tripId'] ?? '',
          'rosterId': trip['rosterId'] ?? rosterId,
          'date': trip['date'] != null ? DateTime.parse(trip['date']) : DateTime.now(),
          'dateString': trip['dateString'] ?? '',
          'status': status, // ✅ Use status directly from API
          'pickupTime': trip['pickupTime'] ?? '',
          'readyByTime': trip['readyByTime'] ?? '',
          'officeArrivalTime': trip['officeArrivalTime'] ?? '',
          'distanceToOffice': (trip['distanceToOffice'] ?? 0).toDouble(),
          'estimatedTravelTime': trip['estimatedTravelTime'] ?? 0,
          'vehicleNumber': trip['vehicleNumber'] ?? 'To be assigned',
          'driverName': trip['driverName'] ?? 'To be assigned',
          'driverPhone': trip['driverPhone'] ?? 'N/A',
          'pickupSequence': trip['pickupSequence'] ?? 1,
          'pickupLocation': trip['pickupLocation'] ?? 'Pickup location',
          'officeLocation': trip['officeLocation'] ?? 'Office',
          'actualPickupTime': trip['actualPickupTime'],
          'actualDropTime': trip['actualDropTime'],
          'actualDistance': trip['actualDistance'] != null ? trip['actualDistance'].toDouble() : null,
          'canCancel': trip['canCancel'] ?? false,
          'cancelledAt': trip['cancelledAt'],
          'cancellationReason': trip['cancellationReason'],
        };
      }).toList();
      
      debugPrint('   ✅ Transformed ${trips.length} trips');
      debugPrint('   📊 Status breakdown:');
      final statusCounts = <String, int>{};
      for (var trip in trips) {
        final status = trip['status'] as String;
        statusCounts[status] = (statusCounts[status] ?? 0) + 1;
      }
      debugPrint('   $statusCounts');
      
      if (mounted) {
        setState(() {
          _dailyTrips = trips;
          _isLoadingTrips = false;
        });
      }
    } else {
      // If API fails, fall back to generating from roster data
      debugPrint('   ⚠️ API failed: ${result['message']}');
      debugPrint('   Using fallback generation');
      List<Map<String, dynamic>> trips = _generateDailyTripsFromRoster();
      
      if (mounted) {
        setState(() {
          _dailyTrips = trips;
          _isLoadingTrips = false;
        });
      }
    }
  } catch (e) {
    debugPrint('❌ Error loading daily trips: $e');
    
    // Fallback to local generation on error
    try {
      List<Map<String, dynamic>> trips = _generateDailyTripsFromRoster();
      if (mounted) {
        setState(() {
          _dailyTrips = trips;
          _isLoadingTrips = false;
        });
      }
    } catch (fallbackError) {
      debugPrint('❌ Fallback generation also failed: $fallbackError');
      if (mounted) {
        setState(() {
          _isLoadingTrips = false;
        });
      }
    }
  }
}


  // Generate daily trips from roster date range and working days
  List<Map<String, dynamic>> _generateDailyTripsFromRoster() {
    List<Map<String, dynamic>> trips = [];
    
    try {
      // Get date range from roster
      final dateRange = widget.roster['dateRange'] ?? {};
      String fromDateStr = '';
      String toDateStr = '';
      
      if (dateRange['from'] != null) {
        fromDateStr = dateRange['from'].toString();
      } else if (widget.roster['startDate'] != null) {
        fromDateStr = widget.roster['startDate'].toString();
      } else if (widget.roster['fromDate'] != null) {
        fromDateStr = widget.roster['fromDate'].toString();
      }
      
      if (dateRange['to'] != null) {
        toDateStr = dateRange['to'].toString();
      } else if (widget.roster['endDate'] != null) {
        toDateStr = widget.roster['endDate'].toString();
      } else if (widget.roster['toDate'] != null) {
        toDateStr = widget.roster['toDate'].toString();
      }
      
      if (fromDateStr.isEmpty || toDateStr.isEmpty) {
        return trips;
      }
      
      // Parse dates
      DateTime startDate = _parseDate(fromDateStr);
      DateTime endDate = _parseDate(toDateStr);
      
      // Get working days
      final weekdays = widget.roster['weekdays'] ?? 
                      widget.roster['weeklyOffDays'] ?? 
                      widget.roster['workingDays'] ?? 
                      [];
      
      // Convert weekdays to numbers (Monday = 1, Sunday = 7)
      Set<int> workingDayNumbers = {};
      if (weekdays.isEmpty) {
        // If no specific days, assume all weekdays (Mon-Fri)
        workingDayNumbers = {1, 2, 3, 4, 5};
      } else {
        for (var day in weekdays) {
          switch (day.toString().toLowerCase()) {
            case 'monday': workingDayNumbers.add(1); break;
            case 'tuesday': workingDayNumbers.add(2); break;
            case 'wednesday': workingDayNumbers.add(3); break;
            case 'thursday': workingDayNumbers.add(4); break;
            case 'friday': workingDayNumbers.add(5); break;
            case 'saturday': workingDayNumbers.add(6); break;
            case 'sunday': workingDayNumbers.add(7); break;
          }
        }
      }
      
      // Generate trips for each day in the range
      DateTime currentDate = startDate;
      while (currentDate.isBefore(endDate.add(const Duration(days: 1)))) {
        // Check if this day is a working day
        if (workingDayNumbers.contains(currentDate.weekday)) {
          trips.add({
            'date': currentDate,
            'dateString': DateFormat('EEE, MMM dd, yyyy').format(currentDate),
            'status': _getTripStatusForDate(currentDate),
            'distance': 0.0,
            'driverName': widget.roster['driverName']?.toString() ?? 'To be assigned',
            'driverPhone': widget.roster['driverPhone']?.toString() ?? 'N/A',
            'vehicleNumber': widget.roster['vehicleNumber']?.toString() ?? 'To be assigned',
            'tripId': '${widget.roster['id']}_${DateFormat('yyyyMMdd').format(currentDate)}',
            'pickupTime': widget.roster['timeRange']?['from'] ?? widget.roster['startTime'] ?? widget.roster['fromTime'] ?? '',
            'dropoffTime': widget.roster['timeRange']?['to'] ?? widget.roster['endTime'] ?? widget.roster['toTime'] ?? '',
            'canCancel': _canCancelTripForDate(currentDate),
          });
        }
        currentDate = currentDate.add(const Duration(days: 1));
      }
    } catch (e) {
      print('Error generating daily trips: $e');
    }
    
    return trips;
  }

  // Parse date string with multiple format support
  DateTime _parseDate(String dateString) {
    try {
      if (dateString.contains('T')) {
        return DateTime.parse(dateString);
      } else if (dateString.contains('-')) {
        return DateTime.parse(dateString);
      } else {
        return DateTime.parse(dateString);
      }
    } catch (e) {
      print('Error parsing date: $dateString - $e');
      return DateTime.now();
    }
  }

  // Determine trip status based on date
  String _getTripStatusForDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tripDate = DateTime(date.year, date.month, date.day);
    
    if (tripDate.isBefore(today)) {
      return 'completed'; // Past dates are completed
    } else if (tripDate.isAtSameMomentAs(today)) {
      return 'ongoing'; // Today's trip
    } else {
      return 'scheduled'; // Future trips are scheduled
    }
  }

  // Check if trip can be cancelled for a specific date
  bool _canCancelTripForDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tripDate = DateTime(date.year, date.month, date.day);
    
    // Can only cancel future trips (not today or past)
    return tripDate.isAfter(today);
  }

  // Handle trip expansion
  void _toggleExpansion() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
    
    if (_isExpanded && _dailyTrips.isEmpty) {
      _loadDailyTrips();
    }
  }

 Future<void> _cancelTrip(Map<String, dynamic> trip) async {
  // Check if trip can be cancelled
  if (trip['canCancel'] != true) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This trip cannot be cancelled (past date or same day)'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return;
  }

  final bool? confirmCancel = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Cancel Trip'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to cancel the trip scheduled for:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip['dateString'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (trip['pickupTime'] != null && trip['pickupTime'].toString().isNotEmpty)
                    Text('Time: ${trip['pickupTime']}'),
                  if (trip['vehicleNumber'] != null && trip['vehicleNumber'] != 'To be assigned')
                    Text('Vehicle: ${trip['vehicleNumber']}'),
                  if (trip['driverName'] != null && trip['driverName'] != 'To be assigned')
                    Text('Driver: ${trip['driverName']}'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Note: The driver will be notified. This action can be undone.',
              style: TextStyle(
                color: Colors.orange,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            child: const Text('No, Keep Trip'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Yes, Cancel Trip'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      );
    },
  );

  if (confirmCancel == true) {
    try {
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 12),
                Text('Cancelling trip...'),
              ],
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // ✅ FIX: Safely get tripDate from trip data
      DateTime tripDate;
      if (trip['date'] is DateTime) {
        tripDate = trip['date'] as DateTime;
      } else if (trip['date'] is String) {
        tripDate = DateTime.parse(trip['date']);
      } else {
        throw Exception('Invalid trip date format');
      }

      // Format date for API
      final tripDateString = _tripsService.formatDateForApi(tripDate);
      
      // ✅ FIX: Safely get tripId - handle both String and dynamic types
      String tripId;
      if (trip['tripId'] != null) {
        tripId = trip['tripId'].toString();
      } else if (trip['_id'] != null) {
        tripId = trip['_id'].toString();
      } else {
        throw Exception('Trip ID not found');
      }
      
      // ✅ FIX: Safely get rosterId
      String? rosterId;
      if (trip['rosterId'] != null) {
        rosterId = trip['rosterId'].toString();
      }

      debugPrint('🚫 Cancelling trip:');
      debugPrint('   Trip ID: $tripId');
      debugPrint('   Trip Date: $tripDateString');
      debugPrint('   Roster ID: ${rosterId ?? "N/A"}');
      
      // Call API to cancel trip
      final result = await _tripsService.cancelSingleTrip(
        tripId: tripId,
        tripDate: tripDateString,
        rosterId: rosterId,
        reason: 'Customer cancelled individual trip',
      );

      debugPrint('📊 Cancel result: ${result['success']}');
      debugPrint('   Message: ${result['message']}');

      if (result['success'] == true) {
        // ✅ FIX: Update local state immediately
        if (mounted) {
          setState(() {
            trip['status'] = 'cancelled';
            trip['canCancel'] = false;
            trip['cancelledAt'] = DateTime.now().toIso8601String();
          });
        }
        
        // ✅ NEW: Force reload the daily trips from API to refresh UI
        await _loadDailyTrips();
        
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Trip for ${trip['dateString'] ?? tripDateString} has been cancelled'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: 'Undo',
                textColor: Colors.white,
                onPressed: () => _undoCancelTrip(trip),
              ),
            ),
          );
        }
      } else {
        throw Exception(result['message'] ?? 'Failed to cancel trip');
      }
    } catch (e) {
      debugPrint('❌ Error cancelling trip: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel trip: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }
}

// ============================================================================
// FIX 2: CORRECTED _undoCancelTrip METHOD
// ============================================================================

Future<void> _undoCancelTrip(Map<String, dynamic> trip) async {
  try {
    // ✅ FIX: Safely get tripDate
    DateTime tripDate;
    if (trip['date'] is DateTime) {
      tripDate = trip['date'] as DateTime;
    } else if (trip['date'] is String) {
      tripDate = DateTime.parse(trip['date']);
    } else {
      throw Exception('Invalid trip date format');
    }

    final tripDateString = _tripsService.formatDateForApi(tripDate);
    
    // ✅ FIX: Safely get tripId
    String tripId;
    if (trip['tripId'] != null) {
      tripId = trip['tripId'].toString();
    } else if (trip['_id'] != null) {
      tripId = trip['_id'].toString();
    } else {
      throw Exception('Trip ID not found');
    }

    // ✅ FIX: Safely get rosterId
    String? rosterId;
    if (trip['rosterId'] != null) {
      rosterId = trip['rosterId'].toString();
    }
    
    debugPrint('🔄 Restoring trip:');
    debugPrint('   Trip ID: $tripId');
    debugPrint('   Trip Date: $tripDateString');
    
    final result = await _tripsService.restoreSingleTrip(
      tripId: tripId,
      tripDate: tripDateString,
      rosterId: rosterId,
    );

    debugPrint('📊 Restore result: ${result['success']}');

    if (result['success'] == true) {
      // ✅ FIX: Update local state
      if (mounted) {
        setState(() {
          trip['status'] = _getTripStatusForDate(tripDate);
          trip['canCancel'] = _canCancelTripForDate(tripDate);
          trip.remove('cancelledAt');
        });
      }
      
      // ✅ NEW: Force reload the daily trips from API to refresh UI
      await _loadDailyTrips();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Trip for ${trip['dateString'] ?? tripDateString} has been restored'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else {
      throw Exception(result['message'] ?? 'Failed to restore trip');
    }
  } catch (e) {
    debugPrint('❌ Error restoring trip: $e');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to restore trip: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }
}


  @override
  Widget build(BuildContext context) {
    final status = widget.roster['status'] ?? 'unknown';
    final dateRange = widget.roster['dateRange'] ?? {};
    
    // ✅ FIX: Better date extraction with multiple fallbacks
    String fromDate = '';
    String toDate = '';
    
    // Try dateRange first, then direct fields
    if (dateRange['from'] != null) {
      fromDate = _formatDate(dateRange['from'].toString());
    } else if (widget.roster['startDate'] != null) {
      fromDate = _formatDate(widget.roster['startDate'].toString());
    } else if (widget.roster['fromDate'] != null) {
      fromDate = _formatDate(widget.roster['fromDate'].toString());
    }
    
    if (dateRange['to'] != null) {
      toDate = _formatDate(dateRange['to'].toString());
    } else if (widget.roster['endDate'] != null) {
      toDate = _formatDate(widget.roster['endDate'].toString());
    } else if (widget.roster['toDate'] != null) {
      toDate = _formatDate(widget.roster['toDate'].toString());
    }
    
    final timeRange = widget.roster['timeRange'] ?? {};
    final fromTime = timeRange['from'] ?? widget.roster['startTime'] ?? widget.roster['fromTime'] ?? 'N/A';
    final toTime = timeRange['to'] ?? widget.roster['endTime'] ?? widget.roster['toTime'] ?? 'N/A';
    
    // ✅ FIX: Better weekdays extraction
    final weekdays = widget.roster['weekdays'] ?? 
                    widget.roster['weeklyOffDays'] ?? 
                    widget.roster['workingDays'] ?? 
                    [];

    return Card(
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.1),
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // Main roster card content
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row: Roster Type, Date Range, and Expand Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_titleCase(widget.roster['rosterType'] ?? '')} Roster',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          // Date range display
                          if (fromDate.isNotEmpty && toDate.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                fromDate == toDate 
                                  ? fromDate 
                                  : '$fromDate to $toDate',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).primaryColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _getStatusColor(status).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _titleCase(status),
                        style: TextStyle(
                          color: _getStatusColor(status),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Expand/Collapse button
                    IconButton(
                      icon: Icon(
                        _isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: Theme.of(context).primaryColor,
                      ),
                      onPressed: _toggleExpansion,
                      tooltip: _isExpanded ? 'Hide daily trips' : 'Show daily trips',
                    ),
                  ],
                ),
                const Divider(height: 24),

                // Roster summary information
                _buildDetailRow(
                  Icons.business, 
                  'Office:', 
                  _address ?? widget.roster['officeLocation'] ?? 'N/A'
                ),
                const SizedBox(height: 8),
                
                _buildDetailRow(
                  Icons.calendar_today, 
                  'From Date:', 
                  fromDate.isNotEmpty ? fromDate : 'N/A'
                ),
                const SizedBox(height: 8),
                _buildDetailRow(
                  Icons.calendar_today_outlined, 
                  'To Date:', 
                  toDate.isNotEmpty ? toDate : 'N/A'
                ),
                const SizedBox(height: 8),
                
                _buildDetailRow(
                  Icons.access_time, 
                  'Login Time:', 
                  fromTime
                ),
                const SizedBox(height: 8),
                _buildDetailRow(
                  Icons.access_time_filled, 
                  'Logout Time:', 
                  toTime
                ),
                const SizedBox(height: 8),
                
                _buildDetailRow(
                  Icons.event_repeat, 
                  'Working Days:', 
                  weekdays.isNotEmpty ? _formatWeekdays(weekdays) : 'All days'
                ),
                const SizedBox(height: 8),
                
                // Driver and Vehicle Info (if assigned)
                if (widget.roster['driverName'] != null && widget.roster['driverName'].toString().isNotEmpty)
                  _buildDetailRow(
                    Icons.person, 
                    'Driver:', 
                    widget.roster['driverName'] ?? 'Not assigned'
                  ),
                if (widget.roster['driverName'] != null && widget.roster['driverName'].toString().isNotEmpty)
                  const SizedBox(height: 8),
                
                if (widget.roster['vehicleNumber'] != null && widget.roster['vehicleNumber'].toString().isNotEmpty)
                  _buildDetailRow(
                    Icons.directions_car, 
                    'Vehicle:', 
                    widget.roster['vehicleNumber'] ?? 'Not assigned'
                  ),
                
                const Divider(height: 24),
                
                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Edit button - only for scheduled/assigned/pending trips
                    if (_canEditTrip(status))
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                        onPressed: widget.onUpdate,
                        tooltip: 'Edit Trip',
                      ),
                    if (_canEditTrip(status))
                      const SizedBox(width: 8),
                    // Delete button - only for pending/assigned trips
                    if (_canCancelTrip(status))
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: widget.onDelete,
                        tooltip: 'Cancel Trip',
                      ),
                  ],
                )
              ],
            ),
          ),
          
          // Expandable daily trips section
          if (_isExpanded) ...[
            const Divider(height: 1),
            _buildDailyTripsSection(),
          ],
        ],
      ),
    );
  }

  // Build the daily trips section
  Widget _buildDailyTripsSection() {
    if (_isLoadingTrips) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text(
                'Loading daily trips...',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    if (_dailyTrips.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.event_busy, color: Colors.grey.shade400, size: 32),
              const SizedBox(height: 8),
              const Text(
                'No daily trips available',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'This roster has no scheduled working days',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Count trips by status
    final scheduledCount = _dailyTrips.where((trip) => trip['status'] == 'scheduled').length;
    final completedCount = _dailyTrips.where((trip) => trip['status'] == 'completed').length;
    final cancelledCount = _dailyTrips.where((trip) => trip['status'] == 'cancelled').length;
    final ongoingCount = _dailyTrips.where((trip) => trip['status'] == 'ongoing').length;

    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with trip counts
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Daily Trips (${_dailyTrips.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Tap to expand',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          
          // Trip status summary
          if (_dailyTrips.length > 1) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (scheduledCount > 0)
                  _buildStatusChip('Scheduled', scheduledCount, Colors.orange),
                if (ongoingCount > 0)
                  _buildStatusChip('Ongoing', ongoingCount, Colors.purple),
                if (completedCount > 0)
                  _buildStatusChip('Completed', completedCount, Colors.green),
                if (cancelledCount > 0)
                  _buildStatusChip('Cancelled', cancelledCount, Colors.red),
              ],
            ),
          ],
          
          const SizedBox(height: 12),
          
          // Trip cards
          ...(_dailyTrips.map((trip) => _buildDailyTripCard(trip)).toList()),
          
          // Footer info
          if (_dailyTrips.length > 3) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Tip: You can cancel individual future trips by tapping the ✕ button',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Build status chip for trip summary
  Widget _buildStatusChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // Build individual daily trip card
  Widget _buildDailyTripCard(Map<String, dynamic> trip) {
    final status = trip['status'] ?? 'unknown';
    final isScheduled = status == 'scheduled';
    final isCancelled = status == 'cancelled';
    final isCompleted = status == 'completed';
    final isOngoing = status == 'ongoing';
    final distance = trip['distance'] ?? 0.0;
    final canCancel = trip['canCancel'] == true && !isCancelled;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCancelled 
          ? Colors.grey.shade100 
          : _getStatusColor(status).withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _getStatusColor(status).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Status indicator
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _getStatusColor(status),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              
              // Trip details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            trip['dateString'] ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isCancelled ? Colors.grey : Colors.black87,
                              decoration: isCancelled ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                        if (distance > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${distance.toStringAsFixed(1)} km',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    
                    // Vehicle and Driver info
                    if (trip['vehicleNumber'] != null && trip['vehicleNumber'] != 'To be assigned')
                      Row(
                        children: [
                          Icon(Icons.directions_car, size: 12, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            trip['vehicleNumber'],
                            style: TextStyle(
                              fontSize: 12,
                              color: isCancelled ? Colors.grey : Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    
                    if (trip['driverName'] != null && trip['driverName'] != 'To be assigned')
                      Row(
                        children: [
                          Icon(Icons.person, size: 12, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            trip['driverName'],
                            style: TextStyle(
                              fontSize: 12,
                              color: isCancelled ? Colors.grey : Colors.grey.shade600,
                            ),
                          ),
                          if (trip['driverPhone'] != null && trip['driverPhone'] != 'N/A')
                            Text(
                              ' • ${trip['driverPhone']}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isCancelled ? Colors.grey : Colors.grey.shade500,
                              ),
                            ),
                        ],
                      ),
                    
                    // Timing info
                    if (trip['pickupTime'] != null && trip['pickupTime'].isNotEmpty)
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 12, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            'Pickup: ${trip['pickupTime']}${trip['dropoffTime'] != null && trip['dropoffTime'].isNotEmpty ? ' • Drop: ${trip['dropoffTime']}' : ''}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isCancelled ? Colors.grey : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _titleCase(status),
                  style: TextStyle(
                    color: _getStatusColor(status),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              
              // Cancel button for cancellable trips only
              if (canCancel) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red, size: 20),
                  onPressed: () => _cancelTrip(trip),
                  tooltip: 'Cancel this trip',
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ],
          ),
          
          // Additional info for cancelled trips
          if (isCancelled) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cancel, size: 14, color: Colors.red),
                  const SizedBox(width: 6),
                  const Text(
                    'Trip Cancelled',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (_canCancelTripForDate(trip['date'])) // Only show undo for future dates
                    TextButton(
                      onPressed: () => _undoCancelTrip(trip),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Undo',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          
          // Additional info for ongoing trips
          if (isOngoing) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                children: [
                  Icon(Icons.directions_car, size: 14, color: Colors.purple),
                  SizedBox(width: 6),
                  Text(
                    'Trip in Progress - Track your ride',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.purple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: Colors.grey.shade800),
          ),
        ),
      ],
    );
  }

  // Helper to format weekdays nicely
  String _formatWeekdays(List<dynamic>? weekdays) {
    if (weekdays == null || weekdays.isEmpty) return 'All days';
    
    // Convert to strings and sort by weekday order
    final dayOrder = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final sortedDays = weekdays
        .map((day) => day.toString())
        .where((day) => dayOrder.contains(day))
        .toList()
      ..sort((a, b) => dayOrder.indexOf(a).compareTo(dayOrder.indexOf(b)));
    
    if (sortedDays.length >= 5) {
      return 'Weekdays';
    } else if (sortedDays.length <= 3) {
      return sortedDays.join(', ');
    } else {
      return '${sortedDays.take(2).join(', ')} +${sortedDays.length - 2} more';
    }
  }

  // Helper to get pickup/drop location details
  String _getLocationDetails(String locationType) {
    final locations = widget.roster['locations'];
    if (locations == null) return 'Not specified';

    Map<String, dynamic>? locationData;
    switch (locationType) {
      case 'pickup':
        locationData = locations['loginPickup'] ?? locations['pickup'];
        break;
      case 'drop':
        locationData = locations['logoutDrop'] ?? locations['drop'];
        break;
      default:
        return 'Not specified';
    }

    if (locationData == null) {
      // Fallback to direct fields
      final pickupAddress = widget.roster['loginPickupAddress'];
      final dropAddress = widget.roster['logoutDropAddress'];
      
      if (locationType == 'pickup' && pickupAddress != null && pickupAddress.isNotEmpty) {
        return pickupAddress;
      } else if (locationType == 'drop' && dropAddress != null && dropAddress.isNotEmpty) {
        return dropAddress;
      }
      
      return 'Not specified';
    }

    final address = locationData['address'] ?? '';
    final coordinates = locationData['coordinates'];
    
    if (address.isNotEmpty) {
      return address;
    } else if (coordinates != null) {
      final lat = coordinates['latitude']?.toString() ?? '0';
      final lng = coordinates['longitude']?.toString() ?? '0';
      return 'Location ($lat, $lng)';
    }
    
    return 'Not specified';
  }
}