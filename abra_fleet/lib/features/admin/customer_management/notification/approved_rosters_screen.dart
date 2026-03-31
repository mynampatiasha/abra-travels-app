// lib/features/admin/customer_management/notification/approved_rosters_screen.dart
// HTTP API IMPLEMENTATION (Firebase removed)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:abra_fleet/core/services/roster_service.dart';
import 'package:abra_fleet/features/admin/customer_management/notification/edit_roster_assignment_screen.dart';
import 'package:intl/intl.dart';

class ApprovedRostersScreen extends StatefulWidget {
  final RosterService rosterService;
  final Function(Map<String, dynamic>)? onRosterTapped;

  const ApprovedRostersScreen({
    super.key,
    required this.rosterService,
    this.onRosterTapped,
  });

  @override
  State<ApprovedRostersScreen> createState() => _ApprovedRostersScreenState();
}

class _ApprovedRostersScreenState extends State<ApprovedRostersScreen> {
  List<Map<String, dynamic>> _approvedRosters = [];
  List<Map<String, dynamic>> _filteredRosters = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterType = 'all';

  @override
  void initState() {
    super.initState();
    // Firebase listener removed - using HTTP polling instead
    _loadApprovedRosters();
    
    // Set up periodic refresh every 30 seconds
    Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _loadApprovedRosters();
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    // No Firebase subscription to cancel
    super.dispose();
  }

  // Firebase listener removed - using HTTP API instead

  Future<void> _loadApprovedRosters() async {
    if (!mounted) return;
    
    setState(() => _isLoading = true);
    
    try {
      // ✅ FIXED: Use same API as Trips screen (/admin/assigned-trips)
      final response = await widget.rosterService.getAssignedTrips(
        status: 'assigned', // Only get assigned/approved trips
      );
      
      if (!mounted) return;
      
      if (response != null && response['success'] == true) {
        final data = response['data'];
        final rosters = data != null ? List<Map<String, dynamic>>.from(data) : <Map<String, dynamic>>[];
        
        // Filter out any null entries and ensure all required fields exist
        final validRosters = rosters.where((roster) {
          return roster != null && 
                 roster['customerName'] != null &&
                 roster['startDate'] != null &&
                 roster['endDate'] != null;
        }).toList();
        
        setState(() {
          _approvedRosters = validRosters;
          _applyFilters();
          _isLoading = false;
        });
        
        print('✅ Loaded ${validRosters.length} approved rosters from /admin/assigned-trips');
      } else {
        throw Exception(response?['message'] ?? 'Failed to load rosters');
      }
    } catch (e) {
      if (!mounted) return;
      
      print('❌ Error loading approved rosters: $e');
      
      setState(() {
        _approvedRosters = [];
        _filteredRosters = [];
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading rosters: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _applyFilters() {
    List<Map<String, dynamic>> filtered = List.from(_approvedRosters);

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((roster) {
        if (roster == null) return false;
        
        final customerName = roster['customerName']?.toString().toLowerCase() ?? '';
        final driverName = roster['driverName']?.toString().toLowerCase() ?? '';
        final vehicleReg = roster['vehicleNumber']?.toString().toLowerCase() ?? '';
        final query = _searchQuery.toLowerCase();
        
        return customerName.contains(query) || 
               driverName.contains(query) || 
               vehicleReg.contains(query);
      }).toList();
    }

    // Apply type filter
    if (_filterType != 'all') {
      filtered = filtered.where((roster) {
        if (roster == null) return false;
        
        final status = _getRosterStatus(roster);
        
        if (_filterType == 'active') {
          return status == 'Active' || status == 'In Progress';
        } else if (_filterType == 'scheduled') {
          return status == 'Scheduled';
        } else if (_filterType == 'completed') {
          return status == 'Completed';
        }
        return true;
      }).toList();
    }

    setState(() {
      _filteredRosters = filtered;
    });
  }

  // ✅ FIXED: Status based on database status field (priority) + date fallback
  String _getRosterStatus(Map<String, dynamic>? roster) {
    if (roster == null) return 'Unknown';
    
    // Priority 1: Check database status field (driver-controlled)
    final dbStatus = roster['status']?.toString().toLowerCase();
    
    if (dbStatus == 'completed') {
      return 'Completed';
    } else if (dbStatus == 'in_progress') {
      return 'In Progress';
    } else if (dbStatus == 'assigned') {
      // Check if it should be active based on date
      final now = DateTime.now();
      final startDate = DateTime.tryParse(roster['startDate']?.toString() ?? '');
      final endDate = DateTime.tryParse(roster['endDate']?.toString() ?? '');
      
      if (startDate != null && endDate != null) {
        if (now.isAfter(startDate) && now.isBefore(endDate)) {
          return 'Active';
        } else if (now.isBefore(startDate)) {
          return 'Scheduled';
        } else if (now.isAfter(endDate)) {
          // Date passed but driver hasn't marked completed
          return 'Overdue';
        }
      }
      
      return 'Assigned';
    } else if (dbStatus == 'pending_assignment') {
      return 'Pending';
    }
    
    // Fallback: Date-based calculation (only if no status)
    final now = DateTime.now();
    final startDate = DateTime.tryParse(roster['startDate']?.toString() ?? '');
    final endDate = DateTime.tryParse(roster['endDate']?.toString() ?? '');
    
    if (startDate == null || endDate == null) return 'Unknown';
    
    if (now.isBefore(startDate)) {
      return 'Scheduled';
    } else if (now.isAfter(startDate) && now.isBefore(endDate)) {
      return 'Active';
    } else {
      return 'Overdue'; // Not completed by driver even though date passed
    }
  }

  // ✅ UPDATED: Better status colors
  Color _getStatusColor(String status) {
    switch (status) {
      case 'Active':
      case 'In Progress':
        return Colors.green;
      case 'Scheduled':
      case 'Assigned':
        return Colors.blue;
      case 'Completed':
        return Colors.grey;
      case 'Overdue':
        return Colors.orange;
      case 'Pending':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  void _navigateToEditScreen(Map<String, dynamic> roster) async {
    final status = _getRosterStatus(roster);
    
    // Can't edit completed or overdue rosters
    if (status == 'Completed' || status == 'Overdue') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot edit $status roster'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EditRosterAssignmentScreen(
          roster: roster,
          onBack: () => Navigator.pop(context, true),
        ),
      ),
    );

    if (result == true && mounted) {
      _loadApprovedRosters();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('✓ Assignment updated successfully'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _handleRosterTap(Map<String, dynamic> roster) {
    if (widget.onRosterTapped != null) {
      widget.onRosterTapped!(roster);
    } else {
      _showRosterDetailsDialog(roster);
    }
  }

  void _showRosterDetailsDialog(Map<String, dynamic> roster) {
    final status = _getRosterStatus(roster);
    final statusColor = _getStatusColor(status);
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.assignment,
                      color: statusColor,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Roster Details',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow('Customer Name', roster['customerName'] ?? 'Unknown', Icons.person),
                      _buildDetailRow('Email', roster['customerEmail'] ?? 'N/A', Icons.email),
                      _buildDetailRow('Phone', roster['customerPhone'] ?? 'N/A', Icons.phone_android),
                      _buildDetailRow('Company', roster['companyName'] ?? 'Unknown', Icons.business),
                      const Divider(height: 24),
                      _buildDetailRow('Vehicle Number', roster['vehicleNumber'] ?? 'Not Assigned', Icons.directions_car),
                      _buildDetailRow('Driver Name', roster['driverName'] ?? 'Not Assigned', Icons.person_outline),
                      _buildDetailRow(
                        'Driver Phone', 
                        (roster['driverPhone'] != null && roster['driverPhone'].toString().isNotEmpty) 
                            ? roster['driverPhone'].toString() 
                            : 'Not Available', 
                        Icons.phone
                      ),
                      const Divider(height: 24),
                      _buildDetailRow('Trip Type', _formatRosterType(roster['rosterType']), Icons.sync_alt),
                      if (roster['pickupLocation'] != null && roster['pickupLocation'].toString().isNotEmpty)
                        _buildDetailRow('Pickup Location', roster['pickupLocation'].toString(), Icons.location_on),
                      if (roster['dropLocation'] != null && roster['dropLocation'].toString().isNotEmpty)
                        _buildDetailRow('Drop Location', roster['dropLocation'].toString(), Icons.location_on_outlined),
                      if (roster['pickupTime'] != null && roster['pickupTime'].toString().isNotEmpty)
                        _buildDetailRow('Pickup Time', roster['pickupTime'].toString(), Icons.access_time),
                      if (roster['dropTime'] != null && roster['dropTime'].toString().isNotEmpty)
                        _buildDetailRow('Drop Time', roster['dropTime'].toString(), Icons.access_time_filled),
                      const Divider(height: 24),
                      _buildDetailRow('Start Date', _formatDate(roster['startDate']), Icons.calendar_today),
                      _buildDetailRow('End Date', _formatDate(roster['endDate']), Icons.calendar_today),
                      if (roster['assignedAt'] != null)
                        _buildDetailRow('Assigned At', _formatDate(roster['assignedAt']), Icons.schedule),
                    ],
                  ),
                ),
              ),
              // Footer
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
                    if (status != 'Completed' && status != 'Overdue')
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _navigateToEditScreen(roster);
                        },
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit Assignment'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF0D47A1),
                        ),
                      ),
                    const SizedBox(width: 8),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(),
          _buildSearchAndFilter(),
          _buildSummaryCards(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredRosters.isEmpty
                    ? _buildEmptyState()
                    : _buildRosterList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loadApprovedRosters,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh'),
        backgroundColor: const Color(0xFF0D47A1),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF0D47A1), size: 28),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Approved Rosters',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      'Real-time updates',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.circle, size: 8, color: Colors.green), // Live indicator
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0D47A1).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_filteredRosters.length} Rosters',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF0D47A1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilter() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by customer, driver, or vehicle...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _applyFilters();
                });
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _filterType,
              decoration: InputDecoration(
                labelText: 'Filter',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'scheduled', child: Text('Scheduled')),
                DropdownMenuItem(value: 'completed', child: Text('Completed')),
              ],
              onChanged: (value) {
                setState(() {
                  _filterType = value ?? 'all';
                  _applyFilters();
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final activeCount = _approvedRosters.where((r) {
      final status = _getRosterStatus(r);
      return status == 'Active' || status == 'In Progress';
    }).length;
    
    final scheduledCount = _approvedRosters.where((r) => _getRosterStatus(r) == 'Scheduled').length;
    final completedCount = _approvedRosters.where((r) => _getRosterStatus(r) == 'Completed').length;
    final totalCount = _approvedRosters.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildSummaryCard('Total', totalCount.toString(), Icons.assignment, Colors.blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildSummaryCard('Active', activeCount.toString(), Icons.play_circle, Colors.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildSummaryCard('Scheduled', scheduledCount.toString(), Icons.schedule, Colors.orange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildSummaryCard('Done', completedCount.toString(), Icons.check_circle, Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'No Approved Rosters',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? 'No rosters match your search'
                : 'All roster assignments will appear here',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildRosterList() {
    return RefreshIndicator(
      onRefresh: _loadApprovedRosters,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredRosters.length,
        itemBuilder: (context, index) {
          final roster = _filteredRosters[index];
          return _buildRosterCard(roster);
        },
      ),
    );
  }

  Widget _buildRosterCard(Map<String, dynamic> roster) {
    final status = _getRosterStatus(roster);
    final statusColor = _getStatusColor(status);
    final canEdit = status != 'Completed' && status != 'Overdue';
    
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _handleRosterTap(roster),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          status == 'Active' || status == 'In Progress' 
                              ? Icons.circle 
                              : status == 'Completed'
                                  ? Icons.check_circle
                                  : Icons.schedule,
                          size: 12,
                          color: statusColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          status,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (canEdit)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit, size: 12, color: Colors.blue[700]),
                          const SizedBox(width: 4),
                          Text(
                            'Tap to edit',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue[700],
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock, size: 12, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            status,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _formatRosterType(roster['rosterType']),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.person, size: 20, color: Color(0xFF0D47A1)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      roster['customerName']?.toString() ?? 'Unknown',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.business, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      roster['officeLocation']?.toString() ?? 'N/A',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _buildInfoChip(
                      Icons.person_pin,
                      roster['driverName']?.toString() ?? 'Not assigned',
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildInfoChip(
                      Icons.directions_car,
                      roster['vehicleNumber']?.toString() ?? 'Not assigned',
                      Colors.green,
                    ),
                  ),
                ],
              ),
              if ((roster['driverPhone']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildInfoChip(
                  Icons.phone,
                  roster['driverPhone'].toString(),
                  Colors.orange,
                ),
              ],
              if ((roster['pickupLocation']?.toString() ?? '').isNotEmpty || 
                  (roster['dropLocation']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                if ((roster['pickupLocation']?.toString() ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildInfoChip(
                      Icons.location_on,
                      'Pickup: ${roster['pickupLocation']}',
                      const Color(0xFFEF4444),
                    ),
                  ),
                if ((roster['dropLocation']?.toString() ?? '').isNotEmpty)
                  _buildInfoChip(
                    Icons.location_on_outlined,
                    'Drop: ${roster['dropLocation']}',
                    const Color(0xFFEF4444),
                  ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    '${_formatDate(roster['startDate'])} - ${_formatDate(roster['endDate'])}',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
              if ((roster['pickupTime']?.toString() ?? '').isNotEmpty || 
                  (roster['dropTime']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if ((roster['pickupTime']?.toString() ?? '').isNotEmpty) ...[
                      const Icon(Icons.access_time, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        'Pickup: ${roster['pickupTime']}',
                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                    if ((roster['pickupTime']?.toString() ?? '').isNotEmpty && 
                        (roster['dropTime']?.toString() ?? '').isNotEmpty)
                      const SizedBox(width: 16),
                    if ((roster['dropTime']?.toString() ?? '').isNotEmpty) ...[
                      const Icon(Icons.access_time_filled, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        'Drop: ${roster['dropTime']}',
                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatRosterType(dynamic type) {
    if (type == null) return 'N/A';
    switch (type.toString().toLowerCase()) {
      case 'login':
        return 'Login Only';
      case 'logout':
        return 'Logout Only';
      case 'both':
        return 'Login & Logout';
      default:
        return type.toString();
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      final dateTime = date is DateTime ? date : DateTime.parse(date.toString());
      return DateFormat('MMM dd, yyyy').format(dateTime);
    } catch (e) {
      return date.toString();
    }
  }
}