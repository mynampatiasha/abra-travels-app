// lib/features/customer/dashboard/presentation/screens/roster_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'package:abra_fleet/features/customer/dashboard/data/repositories/roster_repository.dart';
import 'package:abra_fleet/core/services/backend_connection_manager.dart';
import 'package:abra_fleet/core/services/location_service.dart';
import 'package:abra_fleet/core/services/geocoding_service.dart';
import 'location_picker_screen.dart';
import 'package:abra_fleet/features/client/organization_model.dart';


class CreateRosterScreen extends StatefulWidget {
  final Map<String, dynamic>? existingRoster;
  final String? organizationId;  
  final OrganizationModel? organization;  
  final Function(bool)? onRosterSaved; // Add this callback
  
  const CreateRosterScreen({
    super.key,
    this.existingRoster,
    this.organizationId,  
    this.organization,  
    this.onRosterSaved, // Add this parameter
  });

  @override
  State<CreateRosterScreen> createState() => _CreateRosterScreenState();
}

class _CreateRosterScreenState extends State<CreateRosterScreen> 
    with TickerProviderStateMixin {
  // All your existing properties are preserved
  final _formKey = GlobalKey<FormState>();
  final LocationService _locationService = LocationService();
  late final RosterRepository _rosterRepository;
  
  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  
  String rosterType = 'both';
  String? selectedOfficeLocation;
  ShiftDefinition? selectedShift; // NEW: Selected shift from organization
  LocationData? officeLocationData;
  bool useCustomTime = false;
  List<String> selectedWeekdays = [];
  DateTime? fromDate;
  DateTime? toDate;
  TimeOfDay? fromTime;
  TimeOfDay? toTime;
  
  LocationData? loginPickupLocationData;
  LocationData? logoutDropLocationData;
  String? loginPickupAddress;
  String? logoutDropAddress;
  
  bool isLoading = false;
  bool isLoadingLocation = false;

  bool get isEditing => widget.existingRoster != null;
  String? editingRosterId;

  final List<String> weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  


  // NEW: Get available shifts from organization OR use defaults for testing
List<ShiftDefinition> get availableShifts {
  // If organization is provided, use its shifts
  if (widget.organization != null) {
    return widget.organization!.shifts.where((s) => s.isActive).toList();
  }
  
  // TEMPORARY: For testing, return default shifts
  debugPrint('⚠️ Using default shifts - no organization provided');
  return ShiftTemplates.getDefaultShifts();
}

  // All your existing methods (initState, dispose, etc.) are preserved
  @override
  void initState() {
    super.initState();
    
    _rosterRepository = RosterRepository(
      apiService: BackendConnectionManager().apiService,
    );

    // ADD THIS SECTION FOR TESTING - Load default shifts if no organization provided
    if (widget.organization == null) {
      debugPrint('⚠️ No organization provided - using default shifts for testing');
      // You can still work with the screen using custom time toggle
    }
    
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));
    
    _fadeController.forward();
    _slideController.forward();
    
    _initializeLocationService();
    
    if (isEditing) {
      _populateFormWithExistingData();
    }
  }

  Future<void> _populateFormWithExistingData() async {
    final roster = widget.existingRoster!;
    final geocodingService = GeocodingService();
    
    // Convert office location coordinates to address if needed
    String? officeAddress = roster['officeLocation'];
    if (officeAddress != null && officeAddress.isNotEmpty) {
      officeAddress = await geocodingService.getAddressFromLocation(officeAddress);
    }

    // Prepare location data variables
    LocationData? tempOfficeLocationData;
    String? tempSelectedOfficeLocation = officeAddress;
    LocationData? tempLoginPickupLocationData;
    String? tempLoginPickupAddress;
    LocationData? tempLogoutDropLocationData;
    String? tempLogoutDropAddress;

    // Process locations with async operations BEFORE setState
    if (roster['locations'] != null) {
      final locations = roster['locations'];

      if (locations['office'] != null) {
        final office = locations['office'];
        if (office['coordinates'] != null) {
          final lat = office['coordinates']['latitude']?.toDouble() ?? 0.0;
          final lng = office['coordinates']['longitude']?.toDouble() ?? 0.0;
          
          // Convert coordinates to readable address
          String readableAddress = office['address'] ?? '';
          if (readableAddress.contains(',') && readableAddress.split(',').length == 2) {
            // This looks like lat,lng - convert to readable address
            try {
              readableAddress = await geocodingService.getAddressFromCoordinates(lat, lng);
            } catch (e) {
              debugPrint('Error converting office coordinates to address: $e');
              readableAddress = 'Office Location';
            }
          }
          
          tempOfficeLocationData = LocationData(
            latitude: lat,
            longitude: lng,
            timestamp: DateTime.now(),
            address: readableAddress,
          );
          tempSelectedOfficeLocation = readableAddress;
        }
      }
      
      if (locations['loginPickup'] != null) {
        final pickup = locations['loginPickup'];
        if (pickup['coordinates'] != null) {
          final lat = pickup['coordinates']['latitude']?.toDouble() ?? 0.0;
          final lng = pickup['coordinates']['longitude']?.toDouble() ?? 0.0;
          
          // Convert coordinates to readable address
          String readableAddress = pickup['address'] ?? '';
          if (readableAddress.contains(',') && readableAddress.split(',').length == 2) {
            // This looks like lat,lng - convert to readable address
            try {
              readableAddress = await geocodingService.getAddressFromCoordinates(lat, lng);
            } catch (e) {
              debugPrint('Error converting pickup coordinates to address: $e');
              readableAddress = 'Pickup Location';
            }
          }
          
          tempLoginPickupLocationData = LocationData(
            latitude: lat,
            longitude: lng,
            timestamp: DateTime.now(),
            address: readableAddress,
          );
          tempLoginPickupAddress = readableAddress;
        }
      }
      
      if (locations['logoutDrop'] != null) {
        final drop = locations['logoutDrop'];
        if (drop['coordinates'] != null) {
          final lat = drop['coordinates']['latitude']?.toDouble() ?? 0.0;
          final lng = drop['coordinates']['longitude']?.toDouble() ?? 0.0;
          
          // Convert coordinates to readable address
          String readableAddress = drop['address'] ?? '';
          if (readableAddress.contains(',') && readableAddress.split(',').length == 2) {
            // This looks like lat,lng - convert to readable address
            try {
              readableAddress = await geocodingService.getAddressFromCoordinates(lat, lng);
            } catch (e) {
              debugPrint('Error converting drop coordinates to address: $e');
              readableAddress = 'Drop Location';
            }
          }
          
          tempLogoutDropLocationData = LocationData(
            latitude: lat,
            longitude: lng,
            timestamp: DateTime.now(),
            address: readableAddress,
          );
          tempLogoutDropAddress = readableAddress;
        }
      }
    } else {
      if (roster['loginPickupLocation'] != null) {
        final pickup = roster['loginPickupLocation'];
        tempLoginPickupLocationData = LocationData(
          latitude: pickup['latitude']?.toDouble() ?? 0.0,
          longitude: pickup['longitude']?.toDouble() ?? 0.0,
          timestamp: DateTime.now(),
          address: roster['loginPickupAddress'] ?? '',
        );
        tempLoginPickupAddress = roster['loginPickupAddress'];
      }
      
      if (roster['logoutDropLocation'] != null) {
        final drop = roster['logoutDropLocation'];
        tempLogoutDropLocationData = LocationData(
          latitude: drop['latitude']?.toDouble() ?? 0.0,
          longitude: drop['longitude']?.toDouble() ?? 0.0,
          timestamp: DateTime.now(),
          address: roster['logoutDropAddress'] ?? '',
        );
        tempLogoutDropAddress = roster['logoutDropAddress'];
      }
    }
    
    // Now call setState with all processed data
    setState(() {
      editingRosterId = roster['id'] ?? roster['_id'];
      rosterType = roster['rosterType'] ?? 'both';
      selectedOfficeLocation = tempSelectedOfficeLocation;
      officeLocationData = tempOfficeLocationData;
      loginPickupLocationData = tempLoginPickupLocationData;
      loginPickupAddress = tempLoginPickupAddress;
      logoutDropLocationData = tempLogoutDropLocationData;
      logoutDropAddress = tempLogoutDropAddress;
      
      // NEW: Try to match existing shift
      if (roster['shiftId'] != null) {
        try {
          selectedShift = availableShifts.firstWhere(
            (s) => s.id == roster['shiftId'],
          );
        } catch (e) {
          debugPrint('Shift not found: ${roster['shiftId']}');
        }
      }
      
      // NEW: Check if using custom time
      useCustomTime = roster['useCustomTime'] ?? false;
      
      if (roster['weekdays'] is List) {
        selectedWeekdays = List<String>.from(roster['weekdays']);
      } else if (roster['weeklyOffDays'] is List) {
        selectedWeekdays = List<String>.from(roster['weeklyOffDays']);
      }
      
      try {
        if (roster['dateRange'] != null) {
          final dateRange = roster['dateRange'];
          fromDate = DateTime.parse(dateRange['from']);
          toDate = DateTime.parse(dateRange['to']);
        } else if (roster['fromDate'] != null && roster['toDate'] != null) {
          fromDate = DateTime.parse(roster['fromDate']);
          toDate = DateTime.parse(roster['toDate']);
        } else if (roster['startDate'] != null && roster['endDate'] != null) {
          fromDate = DateTime.parse(roster['startDate']);
          toDate = DateTime.parse(roster['endDate']);
        }
      } catch (e) {
        debugPrint('Error parsing dates: $e');
      }
      
      try {
        if (roster['timeRange'] != null) {
          final timeRange = roster['timeRange'];
          fromTime = _parseTimeString(timeRange['from']);
          toTime = _parseTimeString(timeRange['to']);
        } else if (roster['fromTime'] != null && roster['toTime'] != null) {
          fromTime = _parseTimeString(roster['fromTime']);
          toTime = _parseTimeString(roster['toTime']);
        } else if (roster['startTime'] != null && roster['endTime'] != null) {
          fromTime = _parseTimeString(roster['startTime']);
          toTime = _parseTimeString(roster['endTime']);
        }
      } catch (e) {
        debugPrint('Error parsing times: $e');
      }
    });
  }

  TimeOfDay _parseTimeString(String timeString) {
    try {
      final parts = timeString.split(':');
      return TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
    } catch (e) {
      debugPrint('Error parsing time string: $timeString, error: $e');
      return TimeOfDay.now();
    }
  }

  Future<void> _initializeLocationService() async {
    await _locationService.initialize();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // UPDATE: Form validation now checks for both locations regardless of roster type.
  bool _isFormValid() {
  final hasTimeConfig = useCustomTime 
      ? (fromTime != null && toTime != null)
      : selectedShift != null;
      
  // Office location is required (either coordinates OR address text)
  final hasOfficeLocation = selectedOfficeLocation != null && selectedOfficeLocation!.isNotEmpty;
  
  return hasOfficeLocation &&
         selectedWeekdays.isNotEmpty &&
         fromDate != null &&
         toDate != null &&
         hasTimeConfig &&
         loginPickupLocationData != null &&
         logoutDropLocationData != null;
}

  Future<void> _openLocationPicker({required bool isPickup}) async {
    try {
      setState(() => isLoadingLocation = true);

      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (context) => LocationPickerScreen(
            title: isPickup ? 'Select Pickup Location' : 'Select Drop Location',
            isPickup: isPickup,
            initialLocation: isPickup 
                ? (loginPickupLocationData != null ? LatLng(loginPickupLocationData!.latitude, loginPickupLocationData!.longitude) : null)
                : (logoutDropLocationData != null ? LatLng(logoutDropLocationData!.latitude, logoutDropLocationData!.longitude) : null),
          ),
        ),
      );

      if (result != null && mounted) {
        final LatLng selectedLocation = result['location'] as LatLng;
        final String selectedAddress = result['address'] as String;
        final LocationData? locationData = result['locationData'] as LocationData?;

        setState(() {
          if (isPickup) {
            loginPickupLocationData = locationData ?? LocationData(
              latitude: selectedLocation.latitude,
              longitude: selectedLocation.longitude,
              timestamp: DateTime.now(),
              address: selectedAddress,
            );
            loginPickupAddress = selectedAddress;
          } else {
            logoutDropLocationData = locationData ?? LocationData(
              latitude: selectedLocation.latitude,
              longitude: selectedLocation.longitude,
              timestamp: DateTime.now(),
              address: selectedAddress,
            );
            logoutDropAddress = selectedAddress;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  isPickup ? Icons.my_location : Icons.location_on,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${isPickup ? "Pickup" : "Drop"} location selected successfully',
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('Failed to select location: $e')),
              ],
            ),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoadingLocation = false);
      }
    }
  }

  // ADD this new method after _openLocationPicker:

Future<void> _openOfficeLocationPicker() async {
  try {
    setState(() => isLoadingLocation = true);

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          title: 'Select Office Location',
          isPickup: false, // Not a pickup, just a location
          initialLocation: officeLocationData != null 
              ? LatLng(officeLocationData!.latitude, officeLocationData!.longitude) 
              : null,
        ),
      ),
    );

    if (result != null && mounted) {
      final LatLng selectedLocation = result['location'] as LatLng;
      final String selectedAddress = result['address'] as String;
      final LocationData? locationData = result['locationData'] as LocationData?;

      setState(() {
        officeLocationData = locationData ?? LocationData(
          latitude: selectedLocation.latitude,
          longitude: selectedLocation.longitude,
          timestamp: DateTime.now(),
          address: selectedAddress,
        );
        selectedOfficeLocation = selectedAddress;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.business, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Office location selected successfully'),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Failed to select office location: $e')),
            ],
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  } finally {
    if (mounted) {
      setState(() => isLoadingLocation = false);
    }
  }
}

Future<void> _saveRoster() async {
  if (!_isFormValid()) {
    _showValidationError();
    return;
  }

  if (!mounted) return;
  
  setState(() {
    isLoading = true;
  });

  try {
    // NEW: Determine time to use based on custom time toggle
    final effectiveFromTime = useCustomTime ? fromTime! : selectedShift!.startTime;
    final effectiveToTime = useCustomTime ? toTime! : selectedShift!.endTime;
    
    final validationErrors = _rosterRepository.validateRosterData(
      rosterType: rosterType,
      officeLocation: selectedOfficeLocation!,
      weekdays: selectedWeekdays,
      fromDate: fromDate!,
      toDate: toDate!,
      fromTime: effectiveFromTime,  // CHANGED from fromTime!
      toTime: effectiveToTime,      // CHANGED from toTime!
      loginPickupLocation: loginPickupLocationData != null 
          ? LatLng(loginPickupLocationData!.latitude, loginPickupLocationData!.longitude)
          : null,
      loginPickupAddress: loginPickupAddress,
      logoutDropLocation: logoutDropLocationData != null 
          ? LatLng(logoutDropLocationData!.latitude, logoutDropLocationData!.longitude)
          : null,
      logoutDropAddress: logoutDropAddress,
    );

    if (validationErrors.isNotEmpty) {
      throw Exception(validationErrors.values.first);
    }

    Map<String, dynamic> response;
    
    if (isEditing && editingRosterId != null) {
      response = await _rosterRepository.updateRoster(
        rosterId: editingRosterId!,
        rosterType: rosterType,
        officeLocation: selectedOfficeLocation!,
        weekdays: selectedWeekdays,
        fromDate: fromDate!,
        toDate: toDate!,
        fromTime: effectiveFromTime,  // CHANGED from fromTime!
        toTime: effectiveToTime,      // CHANGED from toTime!
        loginPickupLocation: loginPickupLocationData != null 
            ? LatLng(loginPickupLocationData!.latitude, loginPickupLocationData!.longitude)
            : null,
        loginPickupAddress: loginPickupAddress,
        logoutDropLocation: logoutDropLocationData != null 
            ? LatLng(logoutDropLocationData!.latitude, logoutDropLocationData!.longitude)
            : null,
        logoutDropAddress: logoutDropAddress,
      );
    } else {
      // In _saveRoster(), find where you call createRoster/updateRoster and add:

// ✅ FIX: Ensure office location coordinates are provided
// If officeLocationData is null, backend will geocode the address
response = await _rosterRepository.createRoster(
  rosterType: rosterType,
  officeLocation: selectedOfficeLocation!,
  officeLocationCoordinates: officeLocationData != null
      ? LatLng(officeLocationData!.latitude, officeLocationData!.longitude)
      : null,  // Backend will geocode if null
  weekdays: selectedWeekdays,
  fromDate: fromDate!,
  toDate: toDate!,
  fromTime: effectiveFromTime,
  toTime: effectiveToTime,
  loginPickupLocation: loginPickupLocationData != null 
      ? LatLng(loginPickupLocationData!.latitude, loginPickupLocationData!.longitude)
      : null,
  loginPickupAddress: loginPickupAddress,
  logoutDropLocation: logoutDropLocationData != null 
      ? LatLng(logoutDropLocationData!.latitude, logoutDropLocationData!.longitude)
      : null,
  logoutDropAddress: logoutDropAddress,
);
    }

    // Check if the response indicates success
    if (response['success'] != true) {
      throw Exception(response['message'] ?? 'Roster operation failed');
    }

    debugPrint('✅ Roster operation completed successfully');
    if (!mounted) return;
    
    try {
      // Show success message
      debugPrint('✅ Showing success message...');
      _showSuccessMessage(isEditing);
      
      // Wait a bit for the SnackBar to show
      debugPrint('⏳ Waiting before navigation...');
      await Future.delayed(const Duration(milliseconds: 1500));
      
      if (!mounted) return;
      
      // Call the callback if provided (for tab-based navigation)
      if (widget.onRosterSaved != null) {
        debugPrint('🔄 Calling onRosterSaved callback...');
        widget.onRosterSaved!(true);
      } else {
        // Only pop if there's no callback (for modal navigation)
        debugPrint('🔄 Navigating back with success result...');
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        }
      }
      
      debugPrint('✅ Navigation completed successfully');
    } catch (e) {
      debugPrint('❌ Error in success handling: $e');
      // If success handling fails, still try to handle navigation
      if (mounted) {
        if (widget.onRosterSaved != null) {
          widget.onRosterSaved!(false);
        } else if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(false);
        }
      }
    }
    
  } catch (e) {
    debugPrint('❌ Error in _saveRoster: $e');
    debugPrint('❌ Error type: ${e.runtimeType}');
    debugPrint('❌ Stack trace: ${StackTrace.current}');
    
    if (!mounted) {
      debugPrint('⚠️ Widget not mounted, skipping error message');
      return;
    }
    
    try {
      _showErrorMessage('Failed to ${isEditing ? 'update' : 'create'} roster: ${e.toString()}');
    } catch (errorShowingError) {
      debugPrint('❌ Failed to show error message: $errorShowingError');
    }
  } finally {
    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }
}
  void _showValidationError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(child: Text('Please fill in all required fields and select locations')),
          ],
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showSuccessMessage([bool isUpdate = false]) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isUpdate 
                  ? 'Trip updated successfully! Returning to My Trips...' 
                  : 'Trip created successfully! Returning to dashboard...',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );

    if (!isUpdate && mounted) {
      setState(() {
        selectedOfficeLocation = null;
        selectedWeekdays.clear();
        fromDate = null;
        toDate = null;
        fromTime = null;
        toTime = null;
        loginPickupLocationData = null;
        loginPickupAddress = null;
        logoutDropLocationData = null;
        logoutDropAddress = null;
      });
    }
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;
    
    // Use a try-catch to prevent widget lifecycle errors
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      // If SnackBar fails, just print the error
      debugPrint('Error showing SnackBar: $e');
      debugPrint('Original message: $message');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isEditing ? 'Edit Roster' : 'Create New Roster',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: false,
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isTablet ? 24 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderCard(),
                  const SizedBox(height: 24),

                  _buildRosterTypeSection(),
                  const SizedBox(height: 24),

                  _buildOfficeLocationSection(),
                  const SizedBox(height: 24),

                  _buildShiftSection(),
                  const SizedBox(height: 24),

                  _buildWeeklyOffSection(),
                  const SizedBox(height: 24),

                  _buildDateRangeSection(),
                  const SizedBox(height: 24),
// Updated: Time section only shows when custom time is enabled
                  if (useCustomTime) _buildTimeRangeSection(),
                  if (useCustomTime) const SizedBox(height: 24),

                  _buildLocationSection(),
                  const SizedBox(height: 24),

                  _buildSaveButton(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final primaryColor = Theme.of(context).primaryColor;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primaryColor,
            primaryColor.withOpacity(0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.schedule_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditing ? 'Edit Roster' : 'New Roster Setup',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isEditing 
                      ? 'Update your roster details and locations'
                      : 'Configure schedule and select precise locations on map',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
Widget _buildOfficeLocationSection() {
  return _buildSection(
    title: 'Office Location',
    required: true,
    child: _buildLocationPickerCard(
      title: 'Office Location',
      subtitle: 'Tap to select office on map',
      address: selectedOfficeLocation,
      locationData: officeLocationData,
      icon: Icons.business,
      iconColor: Colors.blue,
      onTap: () => _openOfficeLocationPicker(),
    ),
  );
}

Widget _buildShiftSection() {
  return _buildShiftSelectionSection();
}

Widget _buildRosterTypeSection() {
    return _buildSection(
      title: 'Roster Type',
      required: true,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _buildToggleOption('Login', 'login'),
            _buildToggleOption('Logout', 'logout'),
            _buildToggleOption('Both', 'both'),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleOption(String label, String value) {
    final isSelected = rosterType == value;
    final primaryColor = Theme.of(context).primaryColor;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => rosterType = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected ? [
              BoxShadow(
                color: primaryColor.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ] : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey.shade600,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShiftSelectionSection() {
    final primaryColor = Theme.of(context).primaryColor;
    
    return _buildSection(
      title: 'Shift Timing',
      required: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (availableShifts.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No shifts configured. Please contact your admin or use custom time.',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          
          if (availableShifts.isNotEmpty) ...[
            // Shift cards
            ...availableShifts.map((shift) {
              final isSelected = selectedShift?.id == shift.id;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    selectedShift = shift;
                    useCustomTime = false;
                    // Auto-populate from shift
                    fromTime = shift.startTime;
                    toTime = shift.endTime;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? (shift.color ?? primaryColor).withOpacity(0.1)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected 
                          ? (shift.color ?? primaryColor)
                          : Colors.grey.shade300,
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: isSelected ? [
                      BoxShadow(
                        color: (shift.color ?? primaryColor).withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ] : null,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (shift.color ?? primaryColor).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _getShiftIcon(shift.shiftType),
                          color: shift.color ?? primaryColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shift.shiftName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isSelected 
                                    ? (shift.color ?? primaryColor)
                                    : Colors.grey.shade800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              shift.getTimeRange(),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            if (shift.description != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                shift.description!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(
                          Icons.check_circle,
                          color: shift.color ?? primaryColor,
                          size: 28,
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
            
            const SizedBox(height: 12),
          ],
          
          // Custom time toggle
          SwitchListTile(
            value: useCustomTime,
            onChanged: (value) {
              setState(() {
                useCustomTime = value;
                if (value) {
                  selectedShift = null;
                } else {
                  fromTime = null;
                  toTime = null;
                }
              });
            },
            title: const Text(
              'Use Custom Time',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              'Specify your own timing instead of using predefined shifts',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
            activeColor: primaryColor,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  IconData _getShiftIcon(String shiftType) {
    switch (shiftType.toLowerCase()) {
      case 'morning':
        return Icons.wb_sunny;
      case 'afternoon':
        return Icons.wb_twilight;
      case 'evening':
        return Icons.wb_twilight;
      case 'night':
        return Icons.nightlight_round;
      default:
        return Icons.access_time;
    }
  }
  Widget _buildWeeklyOffSection() {
    final primaryColor = Theme.of(context).primaryColor;

    return _buildSection(
      title: 'Weekly Off Days',
      required: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // UPDATE: The red error message is removed from here.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: weekdays.map((day) {
              final isSelected = selectedWeekdays.contains(day);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      selectedWeekdays.remove(day);
                    } else {
                      selectedWeekdays.add(day);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? primaryColor : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? primaryColor : Colors.grey.shade300,
                    ),
                    boxShadow: isSelected ? [
                      BoxShadow(
                        color: primaryColor.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ] : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    day,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRangeSection() {
    return _buildSection(
      title: 'Date Range',
      required: true,
      child: Row(
        children: [
          Expanded(
            child: _buildDateField(
              'From Date',
              fromDate,
              (date) => setState(() => fromDate = date),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildDateField(
              'To Date',
              toDate,
              (date) => setState(() => toDate = date),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeRangeSection() {
    return _buildSection(
      title: 'Time Range',
      required: true,
      child: Row(
        children: [
          Expanded(
            child: _buildTimeField(
              'Start Time',
              fromTime,
              (time) => setState(() => fromTime = time),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildTimeField(
              'End Time',
              toTime,
              (time) => setState(() => toTime = time),
            ),
          ),
        ],
      ),
    );
  }

  // UPDATE: This widget is updated to show both cards always.
  Widget _buildLocationSection() {
    return _buildSection(
      title: 'Transport Locations',
      required: true,
      child: Column(
        children: [
          _buildLocationPickerCard(
            title: 'Pickup Location',
            subtitle: 'Tap to select on map',
            address: loginPickupAddress,
            locationData: loginPickupLocationData,
            icon: Icons.my_location_rounded,
            iconColor: Colors.green,
            onTap: () => _openLocationPicker(isPickup: true),
          ),
          const SizedBox(height: 16),
          _buildLocationPickerCard(
            title: 'Drop-off Location',
            subtitle: 'Tap to select on map',
            address: logoutDropAddress,
            locationData: logoutDropLocationData,
            icon: Icons.location_on_rounded,
            iconColor: Colors.red,
            onTap: () => _openLocationPicker(isPickup: false),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationPickerCard({
    required String title,
    required String subtitle,
    String? address,
    LocationData? locationData,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    final hasLocation = locationData != null;
    
    return GestureDetector(
      onTap: isLoadingLocation ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: hasLocation ? Colors.green.shade50 : Colors.grey.shade50,
          // UPDATE: Red border is removed for a neutral look.
          border: Border.all(
            color: hasLocation ? Colors.green.shade300 : Colors.grey.shade300,
            width: hasLocation ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12), 
          boxShadow: hasLocation ? [
            BoxShadow(
              color: Colors.green.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ] : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasLocation 
                        ? (address != null && address.isNotEmpty 
                            ? address 
                            : (locationData != null 
                                ? 'Lat: ${locationData.latitude.toStringAsFixed(6)}, Lng: ${locationData.longitude.toStringAsFixed(6)}'
                                : 'Location selected'))
                        : subtitle,
                    style: TextStyle(
                      color: hasLocation ? Colors.green.shade700 : Colors.grey.shade600,
                      fontSize: 14,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isLoadingLocation)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                hasLocation ? Icons.check_circle : Icons.map_outlined,
                color: hasLocation ? Colors.green : iconColor,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required Widget child,
    bool required = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (required) ...[
                const SizedBox(width: 4),
                Text(
                  '*',
                  style: TextStyle(
                    color: Colors.red.shade600,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildDropdownField({
    required String? value,
    required String hint,
    required IconData icon,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    final primaryColor = Theme.of(context).primaryColor;

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        // UPDATE: Red border is removed for a neutral look.
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade500),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          prefixIcon: Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: primaryColor,
              size: 20,
            ),
          ),
        ),
        items: items.map((item) => DropdownMenuItem(
          value: item,
          child: Text(item),
        )).toList(),
        onChanged: onChanged,
        validator: (val) => val == null ? 'This field is required' : null,
      ),
    );
  }

  Widget _buildDateField(String label, DateTime? date, Function(DateTime) onDateSelected) {
    final primaryColor = Theme.of(context).primaryColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
            final selectedDate = await showDatePicker(
              context: context,
              initialDate: date ?? DateTime.now(),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              builder: (context, child) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: ColorScheme.light(
                      primary: primaryColor,
                      onPrimary: Colors.white,
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (selectedDate != null) {
              onDateSelected(selectedDate);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              // UPDATE: Red border is removed for a neutral look.
              border: Border.all(
                color: Colors.grey.shade300,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  // UPDATE: Red icon color is removed for a neutral look.
                  color: primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    date != null
                        ? DateFormat('MMM dd, yyyy').format(date)
                        : 'Select date',
                    style: TextStyle(
                      // UPDATE: Red text color is removed for a neutral look.
                      color: date == null ? Colors.grey.shade600 : Colors.grey.shade800,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeField(String label, TimeOfDay? time, Function(TimeOfDay) onTimeSelected) {
    final primaryColor = Theme.of(context).primaryColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
            final selectedTime = await showTimePicker(
              context: context,
              initialTime: time ?? TimeOfDay.now(),
              builder: (context, child) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: ColorScheme.light(
                      primary: primaryColor,
                      onPrimary: Colors.white,
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (selectedTime != null) {
              onTimeSelected(selectedTime);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              // UPDATE: Red border is removed for a neutral look.
              border: Border.all(
                color: Colors.grey.shade300,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.access_time_rounded,
                  // UPDATE: Red icon color is removed for a neutral look.
                  color: primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    time != null
                        ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'
                        : 'Select time',
                    style: TextStyle(
                      // UPDATE: Red text color is removed for a neutral look.
                      color: time == null ? Colors.grey.shade600 : Colors.grey.shade800,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    final isValid = _isFormValid();
    final primaryColor = Theme.of(context).primaryColor;
    
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: isValid ? [
          BoxShadow(
            color: primaryColor.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ] : null,
      ),
      child: ElevatedButton(
        onPressed: isValid && !isLoading ? _saveRoster : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: isValid ? primaryColor : Colors.grey.shade300,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(isEditing ? Icons.update_rounded : Icons.save_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    isEditing ? 'Update Roster' : 'Create Roster',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}