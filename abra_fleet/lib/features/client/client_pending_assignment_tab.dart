import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:abra_fleet/features/customer/dashboard/data/repositories/roster_repository.dart';
import 'package:abra_fleet/core/services/backend_connection_manager.dart';

class ClientPendingAssignmentTab extends StatefulWidget {
  final VoidCallback onImportPressed;
  final Function(int count)? onRosterCountChanged; // ✅ NEW: Callback to report count

  const ClientPendingAssignmentTab({
    Key? key, 
    required this.onImportPressed,
    this.onRosterCountChanged, // ✅ NEW
  }) : super(key: key);

  @override
  State<ClientPendingAssignmentTab> createState() => _ClientPendingAssignmentTabState();
}

class _ClientPendingAssignmentTabState extends State<ClientPendingAssignmentTab> {
  List<RosterModel> _pendingRosters = [];
  bool _isLoading = false;
  late final RosterRepository _rosterRepository;

  @override
  void initState() {
    super.initState();
    _rosterRepository = RosterRepository(
      apiService: BackendConnectionManager().apiService,
    );
    _fetchPendingRosters();
  }

  // --- SMART DATA FINDER FUNCTIONS ---
  String _findEmployeeName(Map<String, dynamic> data) {
    debugPrint('🔍 SMART NAME FINDER - Detailed Analysis:');
    
    // 1. Check backend API field names FIRST (most likely to have data)
    if (data['customerName'] != null && data['customerName'].toString().isNotEmpty) {
      debugPrint('   ✅ Found customerName: "${data['customerName']}"');
      return data['customerName'];
    } else {
      debugPrint('   ❌ customerName: ${data['customerName']} (empty or null)');
    }
    
    // 2. Check CSV field names (from your uploaded CSV)
    if (data['Employee Name'] != null && data['Employee Name'].toString().isNotEmpty) {
      debugPrint('   ✅ Found Employee Name: "${data['Employee Name']}"');
      return data['Employee Name'];
    } else {
      debugPrint('   ❌ Employee Name: ${data['Employee Name']} (empty or null)');
    }
    
    // 3. Check other common API field names
    if (data['employeeName'] != null && data['employeeName'].toString().isNotEmpty) {
      debugPrint('   ✅ Found employeeName: "${data['employeeName']}"');
      return data['employeeName'];
    } else {
      debugPrint('   ❌ employeeName: ${data['employeeName']} (empty or null)');
    }
    
    if (data['name'] != null && data['name'].toString().isNotEmpty) {
      debugPrint('   ✅ Found name: "${data['name']}"');
      return data['name'];
    } else {
      debugPrint('   ❌ name: ${data['name']} (empty or null)');
    }
    
    // 4. Check inside nested objects (employeeData from backend)
    if (data['employeeData'] != null) {
      debugPrint('   🔍 Checking employeeData: ${data['employeeData']}');
      final empData = data['employeeData'];
      if (empData is Map) {
        if (empData['Employee Name'] != null && empData['Employee Name'].toString().isNotEmpty) {
          debugPrint('   ✅ Found employeeData.Employee Name: "${empData['Employee Name']}"');
          return empData['Employee Name'];
        }
        if (empData['name'] != null && empData['name'].toString().isNotEmpty) {
          debugPrint('   ✅ Found employeeData.name: "${empData['name']}"');
          return empData['name'];
        }
        if (empData['fullName'] != null && empData['fullName'].toString().isNotEmpty) {
          debugPrint('   ✅ Found employeeData.fullName: "${empData['fullName']}"');
          return empData['fullName'];
        }
        if (empData['firstName'] != null && empData['firstName'].toString().isNotEmpty) {
          debugPrint('   ✅ Found employeeData.firstName: "${empData['firstName']}"');
          return empData['firstName'];
        }
      }
    } else {
      debugPrint('   ❌ employeeData is null');
    }

    // 5. Check inside employeeDetails
    if (data['employeeDetails'] != null) {
      debugPrint('   🔍 Checking employeeDetails: ${data['employeeDetails']}');
      final details = data['employeeDetails'];
      if (details is Map) {
        if (details['Employee Name'] != null && details['Employee Name'].toString().isNotEmpty) {
          debugPrint('   ✅ Found employeeDetails.Employee Name: "${details['Employee Name']}"');
          return details['Employee Name'];
        }
        if (details['name'] != null && details['name'].toString().isNotEmpty) {
          debugPrint('   ✅ Found employeeDetails.name: "${details['name']}"');
          return details['name'];
        }
        if (details['fullName'] != null && details['fullName'].toString().isNotEmpty) {
          debugPrint('   ✅ Found employeeDetails.fullName: "${details['fullName']}"');
          return details['fullName'];
        }
        if (details['firstName'] != null && details['firstName'].toString().isNotEmpty) {
          debugPrint('   ✅ Found employeeDetails.firstName: "${details['firstName']}"');
          return details['firstName'];
        }
      }
    } else {
      debugPrint('   ❌ employeeDetails is null');
    }

    // 6. Fallback: Search ALL keys for the word 'name'
    debugPrint('   🔍 Fallback: Searching all keys containing "name"...');
    for (String key in data.keys) {
      if (key.toLowerCase().contains('name') && data[key] is String && data[key].toString().isNotEmpty) {
        debugPrint('   ✅ Found fallback name in $key: "${data[key]}"');
        return data[key];
      }
    }

    debugPrint('   ❌ NO NAME FOUND - returning "Unknown Employee"');
    return 'Unknown Employee';
  }

  String? _findEmployeeEmail(Map<String, dynamic> data) {
    // 1. Check backend API field names FIRST (most likely to have data)
    if (data['customerEmail'] != null) return data['customerEmail'];
    
    // 2. Check CSV field names
    if (data['Employee Email'] != null) return data['Employee Email'];
    
    // 3. Check other common email fields
    if (data['employeeEmail'] != null) return data['employeeEmail'];
    if (data['email'] != null) return data['email'];
    
    // 4. Check nested objects (employeeData from backend)
    if (data['employeeData'] != null) {
      final empData = data['employeeData'];
      if (empData['Employee Email'] != null) return empData['Employee Email'];
      if (empData['email'] != null) return empData['email'];
    }
    
    if (data['employeeDetails'] != null) {
      final details = data['employeeDetails'];
      if (details['Employee Email'] != null) return details['Employee Email'];
      if (details['email'] != null) return details['email'];
    }

    // 5. Search for any key containing 'email'
    for (String key in data.keys) {
      if (key.toLowerCase().contains('email') && data[key] is String && data[key].toString().isNotEmpty) {
        return data[key];
      }
    }

    return null;
  }

  String _findPhoneNumber(Map<String, dynamic> data) {
    debugPrint('🔍 PHONE FINDER - Searching for phone number...');
    
    // 1. Check backend API field names FIRST
    if (data['customerPhone'] != null && data['customerPhone'].toString().isNotEmpty) {
      debugPrint('   ✅ Found customerPhone: ${data['customerPhone']}');
      return data['customerPhone'];
    }
    
    // 2. Check CSV field names
    if (data['Employee Phone'] != null && data['Employee Phone'].toString().isNotEmpty) {
      debugPrint('   ✅ Found Employee Phone: ${data['Employee Phone']}');
      return data['Employee Phone'];
    }
    if (data['Alternative Phone'] != null && data['Alternative Phone'].toString().isNotEmpty) {
      debugPrint('   ✅ Found Alternative Phone: ${data['Alternative Phone']}');
      return data['Alternative Phone'];
    }
    
    // 3. Check other common phone fields
    if (data['employeePhone'] != null && data['employeePhone'].toString().isNotEmpty) {
      debugPrint('   ✅ Found employeePhone: ${data['employeePhone']}');
      return data['employeePhone'];
    }
    if (data['phone'] != null && data['phone'].toString().isNotEmpty) {
      debugPrint('   ✅ Found phone: ${data['phone']}');
      return data['phone'];
    }
    if (data['phoneNumber'] != null && data['phoneNumber'].toString().isNotEmpty) {
      debugPrint('   ✅ Found phoneNumber: ${data['phoneNumber']}');
      return data['phoneNumber'];
    }
    if (data['mobile'] != null && data['mobile'].toString().isNotEmpty) {
      debugPrint('   ✅ Found mobile: ${data['mobile']}');
      return data['mobile'];
    }
    
    // 4. Check nested objects (employeeData from backend)
    if (data['employeeData'] != null) {
      final empData = data['employeeData'];
      debugPrint('   🔍 Checking employeeData for phone...');
      if (empData['Employee Phone'] != null && empData['Employee Phone'].toString().isNotEmpty) {
        debugPrint('   ✅ Found employeeData.Employee Phone: ${empData['Employee Phone']}');
        return empData['Employee Phone'];
      }
      if (empData['phone'] != null && empData['phone'].toString().isNotEmpty) {
        debugPrint('   ✅ Found employeeData.phone: ${empData['phone']}');
        return empData['phone'];
      }
      if (empData['phoneNumber'] != null && empData['phoneNumber'].toString().isNotEmpty) {
        debugPrint('   ✅ Found employeeData.phoneNumber: ${empData['phoneNumber']}');
        return empData['phoneNumber'];
      }
      if (empData['mobile'] != null && empData['mobile'].toString().isNotEmpty) {
        debugPrint('   ✅ Found employeeData.mobile: ${empData['mobile']}');
        return empData['mobile'];
      }
    }
    
    if (data['employeeDetails'] != null) {
      final details = data['employeeDetails'];
      debugPrint('   🔍 Checking employeeDetails for phone...');
      if (details['Employee Phone'] != null && details['Employee Phone'].toString().isNotEmpty) {
        debugPrint('   ✅ Found employeeDetails.Employee Phone: ${details['Employee Phone']}');
        return details['Employee Phone'];
      }
      if (details['phone'] != null && details['phone'].toString().isNotEmpty) {
        debugPrint('   ✅ Found employeeDetails.phone: ${details['phone']}');
        return details['phone'];
      }
      if (details['phoneNumber'] != null && details['phoneNumber'].toString().isNotEmpty) {
        debugPrint('   ✅ Found employeeDetails.phoneNumber: ${details['phoneNumber']}');
        return details['phoneNumber'];
      }
      if (details['mobile'] != null && details['mobile'].toString().isNotEmpty) {
        debugPrint('   ✅ Found employeeDetails.mobile: ${details['mobile']}');
        return details['mobile'];
      }
    }

    // 5. Search for any key containing 'phone' or 'mobile'
    debugPrint('   🔍 Searching all keys for phone/mobile...');
    for (String key in data.keys) {
      if ((key.toLowerCase().contains('phone') || key.toLowerCase().contains('mobile')) && 
          data[key] is String && data[key].toString().isNotEmpty) {
        debugPrint('   ✅ Found phone in $key: ${data[key]}');
        return data[key];
      }
    }

    debugPrint('   ❌ No phone number found - using fallback');
    return 'Not provided'; // Fallback if no phone found
  }

  String? _findPickupLocation(Map<String, dynamic> data) {
    // 1. Check backend API field names FIRST
    if (data['loginPickupAddress'] != null) return data['loginPickupAddress'];
    
    // 2. Check CSV field names
    if (data['Login Pickup Address'] != null) return data['Login Pickup Address'];
    
    // 3. Check other pickup location fields
    if (data['pickupAddress'] != null) return data['pickupAddress'];
    if (data['pickupLocation'] != null) return data['pickupLocation'];
    
    // 4. Check nested objects (employeeData from backend)
    if (data['employeeData'] != null) {
      final empData = data['employeeData'];
      if (empData['Login Pickup Address'] != null) return empData['Login Pickup Address'];
      if (empData['pickupAddress'] != null) return empData['pickupAddress'];
      if (empData['address'] != null) return empData['address'];
    }

    // 5. Search for pickup-related keys
    for (String key in data.keys) {
      if (key.toLowerCase().contains('pickup') && data[key] is String && data[key].toString().isNotEmpty) {
        return data[key];
      }
    }

    return null;
  }

  String? _findDropLocation(Map<String, dynamic> data) {
    // 1. Check backend API field names FIRST
    if (data['logoutDropAddress'] != null) return data['logoutDropAddress'];
    
    // 2. Check CSV field names
    if (data['Logout Drop Address'] != null) return data['Logout Drop Address'];
    
    // 3. Check other drop location fields
    if (data['dropAddress'] != null) return data['dropAddress'];
    if (data['dropLocation'] != null) return data['dropLocation'];
    
    // 4. Check nested objects (employeeData from backend)
    if (data['employeeData'] != null) {
      final empData = data['employeeData'];
      if (empData['Logout Drop Address'] != null) return empData['Logout Drop Address'];
      if (empData['dropAddress'] != null) return empData['dropAddress'];
    }
    
    // 5. For 'both' type rosters, drop location might be same as office
    if (data['rosterType'] == 'both' || data['rosterType'] == 'logout') {
      if (data['officeLocation'] != null) return data['officeLocation'];
      if (data['Office Location'] != null) return data['Office Location'];
    }

    // 6. Search for drop-related keys
    for (String key in data.keys) {
      if ((key.toLowerCase().contains('drop') || key.toLowerCase().contains('logout')) && 
          data[key] is String && data[key].toString().isNotEmpty) {
        return data[key];
      }
    }

    return null;
  }

  Future<void> _fetchPendingRosters() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    debugPrint('\n' + '🚀 CLIENT PENDING ROSTERS - COMPREHENSIVE ERROR TRACKING'.padRight(80, '='));
    debugPrint('📅 Timestamp: ${DateTime.now().toIso8601String()}');
    debugPrint('🔄 Starting fetch process...');

    try {
      debugPrint('📡 Calling _rosterRepository.getPendingRosters()...');
      final rosters = await _rosterRepository.getPendingRosters();
      
      debugPrint('✅ API Response received successfully');
      debugPrint('📊 Total rosters received: ${rosters.length}');
      debugPrint('📋 Response type: ${rosters.runtimeType}');
      
      if (rosters.isEmpty) {
        debugPrint('⚠️  WARNING: No rosters returned from API');
        debugPrint('🔍 This could mean:');
        debugPrint('   - No pending rosters exist for this user');
        debugPrint('   - API endpoint returned empty array');
        debugPrint('   - User authentication issue');
        debugPrint('   - Backend filtering issue');
      }
      
      // ✅ Enhanced roster parsing with comprehensive error tracking
      final parsedRosters = <RosterModel>[];
      
      for (int i = 0; i < rosters.length; i++) {
        final roster = rosters[i];
        debugPrint('\n${'📋 PROCESSING ROSTER ${i + 1}/${rosters.length}'.padRight(60, '-')}');
        
        try {
          // 🔍 COMPREHENSIVE DATA ANALYSIS
          debugPrint('🔍 RAW ROSTER ANALYSIS:');
          debugPrint('   Type: ${roster.runtimeType}');
          debugPrint('   Is Map: ${roster is Map}');
          debugPrint('   Is Empty: ${roster.isEmpty}');
          debugPrint('   Keys Count: ${roster.keys.length}');
          debugPrint('   All Keys: ${roster.keys.toList()}');
          
          // Check for employee name fields specifically
          debugPrint('\n🏷️  EMPLOYEE NAME FIELD ANALYSIS:');
          final nameFields = ['customerName', 'Employee Name', 'employeeName', 'name'];
          for (String field in nameFields) {
            if (roster.containsKey(field)) {
              debugPrint('   ✅ Found $field: "${roster[field]}" (${roster[field].runtimeType})');
            } else {
              debugPrint('   ❌ Missing $field');
            }
          }
          
          // Check for nested employee data
          debugPrint('\n👥 NESTED EMPLOYEE DATA ANALYSIS:');
          if (roster['employeeData'] != null) {
            debugPrint('   ✅ employeeData exists: ${roster['employeeData'].runtimeType}');
            debugPrint('   Content: ${roster['employeeData']}');
            if (roster['employeeData'] is Map) {
              debugPrint('   Keys: ${(roster['employeeData'] as Map).keys.toList()}');
            }
          } else {
            debugPrint('   ❌ employeeData is null');
          }
          
          if (roster['employeeDetails'] != null) {
            debugPrint('   ✅ employeeDetails exists: ${roster['employeeDetails'].runtimeType}');
            debugPrint('   Content: ${roster['employeeDetails']}');
            if (roster['employeeDetails'] is Map) {
              debugPrint('   Keys: ${(roster['employeeDetails'] as Map).keys.toList()}');
            }
          } else {
            debugPrint('   ❌ employeeDetails is null');
          }
          
          // Check for email fields
          debugPrint('\n📧 EMAIL FIELD ANALYSIS:');
          final emailFields = ['customerEmail', 'Employee Email', 'employeeEmail', 'email'];
          for (String field in emailFields) {
            if (roster.containsKey(field)) {
              debugPrint('   ✅ Found $field: "${roster[field]}" (${roster[field].runtimeType})');
            } else {
              debugPrint('   ❌ Missing $field');
            }
          }
          
          // Show full roster data for first 2 rosters
          if (i < 2) {
            debugPrint('\n📄 FULL ROSTER DATA:');
            debugPrint(roster.toString());
          }

          // Parse Dates with error handling
          DateTime validFrom = DateTime.now();
          DateTime validTo = DateTime.now().add(const Duration(days: 30));
          try {
            if (roster['startDate'] != null) {
              validFrom = DateTime.parse(roster['startDate']);
              debugPrint('✅ Parsed startDate: $validFrom');
            } else if (roster['fromDate'] != null) {
              validFrom = DateTime.parse(roster['fromDate']);
              debugPrint('✅ Parsed fromDate: $validFrom');
            } else {
              debugPrint('⚠️  No valid start date found, using default');
            }
            
            if (roster['endDate'] != null) {
              validTo = DateTime.parse(roster['endDate']);
              debugPrint('✅ Parsed endDate: $validTo');
            } else if (roster['toDate'] != null) {
              validTo = DateTime.parse(roster['toDate']);
              debugPrint('✅ Parsed toDate: $validTo');
            } else {
              debugPrint('⚠️  No valid end date found, using default');
            }
          } catch (dateError) {
            debugPrint('❌ Date parsing error: $dateError');
          }

          // Use the smart name finder with detailed logging
          debugPrint('\n🔍 RUNNING SMART NAME FINDER...');
          String employeeName = _findEmployeeName(roster);
          debugPrint('🎯 Smart finder result: "$employeeName"');
          
          if (employeeName == 'Unknown Employee') {
            debugPrint('❌ CRITICAL: Smart finder failed to find employee name!');
            debugPrint('🔍 Manual fallback check:');
            
            // Manual fallback with detailed logging
            for (String key in roster.keys) {
              final value = roster[key];
              if (value is String && value.isNotEmpty && value != 'null') {
                debugPrint('   Checking $key: "$value"');
                if (key.toLowerCase().contains('name') || 
                    (key.toLowerCase().contains('customer') && !key.toLowerCase().contains('email'))) {
                  debugPrint('   🎯 Potential name field found: $key = "$value"');
                }
              }
            }
          }
          
          String officeLocation = roster['officeLocation'] ?? roster['Office Location'] ?? 'Unknown Office';
          debugPrint('🏢 Office Location: "$officeLocation"');

          // Parse Time
          String startTime = roster['startTime'] ?? roster['fromTime'] ?? '09:00';
          String endTime = roster['endTime'] ?? roster['toTime'] ?? '18:00';
          String rosterType = roster['rosterType'] ?? 'both';
          debugPrint('⏰ Time: $startTime - $endTime, Type: $rosterType');

          // Extract employee details with logging
          debugPrint('\n🔍 EXTRACTING ADDITIONAL EMPLOYEE DETAILS...');
          String? employeeEmail = _findEmployeeEmail(roster);
          debugPrint('📧 Email found: ${employeeEmail ?? "None"}');
          
          String phoneNumber = _findPhoneNumber(roster);
          debugPrint('📱 Phone found: "$phoneNumber"');
          
          String? pickupLocation = _findPickupLocation(roster);
          debugPrint('📍 Pickup found: ${pickupLocation ?? "None"}');
          
          String? dropLocation = _findDropLocation(roster);
          debugPrint('📍 Drop found: ${dropLocation ?? "None"}');

          // Create roster model
          final rosterModel = RosterModel(
            id: roster['_id']?.toString() ?? roster['id']?.toString() ?? 'N/A',
            name: employeeName, 
            shift: '$rosterType ($startTime - $endTime)',
            routeCount: 0,
            employeeCount: 0,
            vehicleCount: 0,
            validFrom: validFrom,
            validTo: validTo,
            status: officeLocation,
            employeeEmail: employeeEmail,
            phoneNumber: phoneNumber,
            pickupLocation: pickupLocation,
            dropLocation: dropLocation,
          );
          
          parsedRosters.add(rosterModel);
          debugPrint('✅ Roster ${i + 1} parsed successfully');
          debugPrint('🎯 Final name in model: "${rosterModel.name}"');
          
        } catch (rosterError) {
          debugPrint('❌ ERROR parsing roster ${i + 1}: $rosterError');
          debugPrint('📄 Problematic roster data: ${roster.toString()}');
          // Continue with next roster instead of failing completely
        }
      }

      debugPrint('\n📊 PARSING SUMMARY:');
      debugPrint('   Total received: ${rosters.length}');
      debugPrint('   Successfully parsed: ${parsedRosters.length}');
      debugPrint('   Failed to parse: ${rosters.length - parsedRosters.length}');
      
      // Show summary of parsed names
      debugPrint('\n🏷️  PARSED EMPLOYEE NAMES SUMMARY:');
      for (int i = 0; i < parsedRosters.length && i < 10; i++) {
        debugPrint('   ${i + 1}. "${parsedRosters[i].name}" (ID: ${parsedRosters[i].id})');
      }
      
      if (parsedRosters.length > 10) {
        debugPrint('   ... and ${parsedRosters.length - 10} more');
      }

      if (mounted) {
        setState(() {
          _pendingRosters = parsedRosters;
          _isLoading = false;
        });

        // ✅ CRITICAL: Report count back to parent
        widget.onRosterCountChanged?.call(_pendingRosters.length);
        debugPrint('✅ State updated successfully with ${_pendingRosters.length} rosters');
      }
      
    } catch (e, stackTrace) {
      debugPrint('❌ CRITICAL ERROR in _fetchPendingRosters:');
      debugPrint('   Error: $e');
      debugPrint('   Type: ${e.runtimeType}');
      debugPrint('   Stack trace: $stackTrace');
      
      if (mounted) {
        setState(() => _isLoading = false);
        widget.onRosterCountChanged?.call(0); // ✅ Report 0 on error
      }
    }
    
    debugPrint('🏁 CLIENT PENDING ROSTERS FETCH COMPLETED'.padRight(80, '='));
  }

  // --- SHOW DETAILS OVERLAY ---
  void _showRosterDetails(BuildContext context, RosterModel roster) {
    showDialog(
      context: context,
      barrierDismissible: true, 
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            width: 500,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85, 
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFF2563EB), size: 28),
                    const SizedBox(width: 12),
                    const Text(
                      'Roster Details',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    )
                  ],
                ),
                const Divider(height: 30),
                
                // Scrollable Content
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Employee Information Section
                        _buildSectionHeader('Employee Information'),
                        const SizedBox(height: 12),
                        _buildDetailRow(Icons.person, 'Employee Name', roster.name),
                        const SizedBox(height: 12),
                        _buildDetailRow(Icons.email, 'Email ID', roster.employeeEmail ?? 'Not available'),
                        const SizedBox(height: 12),
                        _buildDetailRow(Icons.phone, 'Phone Number', roster.phoneNumber),
                        
                        const SizedBox(height: 24),
                        
                        // Location Information Section
                        _buildSectionHeader('Location Information'),
                        const SizedBox(height: 12),
                        _buildDetailRow(Icons.business, 'Office Location', roster.status),
                        const SizedBox(height: 12),
                        _buildDetailRow(Icons.location_on, 'Pickup Location', roster.pickupLocation ?? 'Not specified'),
                        const SizedBox(height: 12),
                        _buildDetailRow(Icons.place, 'Drop Location', roster.dropLocation ?? 'Not specified'),
                        
                        const SizedBox(height: 24),
                        
                        // Schedule Information Section
                        _buildSectionHeader('Schedule Information'),
                        const SizedBox(height: 12),
                        _buildDetailRow(Icons.access_time, 'Shift Details', roster.shift),
                        const SizedBox(height: 12),
                        _buildDetailRow(
                          Icons.calendar_today, 
                          'Date Range', 
                          '${DateFormat('dd MMM yyyy').format(roster.validFrom)} - ${DateFormat('dd MMM yyyy').format(roster.validTo)}'
                        ),
                        const SizedBox(height: 12),
                        _buildDetailRow(Icons.tag, 'Roster ID', roster.id),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Footer Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Close'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF64748B),
                          side: const BorderSide(color: Color(0xFF64748B)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _editRoster(context, roster);
                        },
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Edit Roster'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: const Color(0xFF2563EB),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2563EB),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
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
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF1E293B),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- EDIT ROSTER FUNCTIONALITY ---
  void _editRoster(BuildContext context, RosterModel roster) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            width: 500,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(Icons.edit, color: Color(0xFF2563EB), size: 28),
                    const SizedBox(width: 12),
                    const Text(
                      'Edit Roster',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    )
                  ],
                ),
                const Divider(height: 30),
                
                // Edit Form Content
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Information message
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, color: Color(0xFFF59E0B)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Edit Roster Request',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFF59E0B),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'You can modify the roster details below. Changes will be saved and the roster will remain in pending status.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Current roster details (read-only display)
                        _buildSectionHeader('Current Roster Details'),
                        const SizedBox(height: 16),
                        
                        _buildEditDetailRow('Employee Name', roster.name),
                        const SizedBox(height: 12),
                        _buildEditDetailRow('Phone Number', roster.phoneNumber),
                        const SizedBox(height: 12),
                        _buildEditDetailRow('Email', roster.employeeEmail ?? 'Not provided'),
                        const SizedBox(height: 12),
                        _buildEditDetailRow('Office Location', roster.status),
                        const SizedBox(height: 12),
                        _buildEditDetailRow('Pickup Location', roster.pickupLocation ?? 'Not specified'),
                        const SizedBox(height: 12),
                        _buildEditDetailRow('Drop Location', roster.dropLocation ?? 'Not specified'),
                        const SizedBox(height: 12),
                        _buildEditDetailRow('Shift Details', roster.shift),
                        const SizedBox(height: 12),
                        _buildEditDetailRow('Date Range', 
                          '${DateFormat('dd MMM yyyy').format(roster.validFrom)} - ${DateFormat('dd MMM yyyy').format(roster.validTo)}'
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Note about editing
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.lightbulb_outline, color: Color(0xFF2563EB)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'To make changes to this roster, please contact your administrator or use the bulk import feature to upload a new roster file.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Footer Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Close'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF64748B),
                          side: const BorderSide(color: Color(0xFF64748B)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showContactAdminDialog(context);
                        },
                        icon: const Icon(Icons.contact_support, size: 18),
                        label: const Text('Contact Admin'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditDetailRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Text(
            ': ',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF1E293B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showContactAdminDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.contact_support, color: Color(0xFF2563EB)),
            const SizedBox(width: 12),
            const Text('Contact Administrator'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('To modify this roster request, please contact your administrator with the following details:'),
            SizedBox(height: 16),
            Text('• Roster ID'),
            Text('• Requested changes'),
            Text('• Reason for modification'),
            SizedBox(height: 16),
            Text('Your administrator will help you update the roster details.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  // --- ARROW ICON LOGIC ---
  IconData _getArrowIcon(String shiftText) {
    final lower = shiftText.toLowerCase();
    if (lower.contains('login')) return Icons.arrow_forward; 
    if (lower.contains('logout')) return Icons.arrow_back;   
    return Icons.swap_horiz; 
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_pendingRosters.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pending_actions, size: 60, color: Colors.grey[300]),
            const SizedBox(height: 16),
            const Text('No pending rosters found', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: widget.onImportPressed,
              child: const Text('Import Rosters'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchPendingRosters, // ✅ Pull-to-refresh
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _pendingRosters.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return _buildSimplifiedPendingCard(_pendingRosters[index]);
        },
      ),
    );
  }

  Widget _buildSimplifiedPendingCard(RosterModel roster) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(0.1), 
                shape: BoxShape.circle
              ),
              child: Icon(
                _getArrowIcon(roster.shift), 
                color: const Color(0xFFF59E0B), 
                size: 20
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${roster.name} - ${roster.status}',
                    style: const TextStyle(
                      fontSize: 15, 
                      fontWeight: FontWeight.w600, 
                      color: Color(0xFF1E293B)
                    ),
                    maxLines: 1, 
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 12, color: Color(0xFF64748B)),
                      const SizedBox(width: 4),
                      Text(
                        '${DateFormat('MMM dd').format(roster.validFrom)} - ${DateFormat('MMM dd').format(roster.validTo)}',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _showRosterDetails(context, roster),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF2563EB),
                backgroundColor: const Color(0xFF2563EB).withOpacity(0.05),
              ),
              child: const Text('View Details'),
            ),
          ],
        ),
      ),
    );
  }
}

// --- LOCAL MODEL DEFINITION ---
class RosterModel {
  final String id;
  final String name;
  final String shift;
  final int routeCount;
  final int employeeCount;
  final int vehicleCount;
  final DateTime validFrom;
  final DateTime validTo;
  final String status;
  final String? employeeEmail;
  final String phoneNumber; // Mandatory field
  final String? pickupLocation;
  final String? dropLocation;

  RosterModel({
    required this.id,
    required this.name,
    required this.shift,
    required this.routeCount,
    required this.employeeCount,
    required this.vehicleCount,
    required this.validFrom,
    required this.validTo,
    required this.status,
    this.employeeEmail,
    required this.phoneNumber, // Mandatory
    this.pickupLocation,
    this.dropLocation,
  });
}