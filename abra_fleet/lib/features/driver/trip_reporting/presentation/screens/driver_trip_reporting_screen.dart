// File: lib/features/driver/trip_reporting/presentation/screens/driver_trip_reporting_screen.dart
// Screen for Driver to start and manage trip reports, now using TripLogProvider to save logs.

import 'dart:typed_data';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart'; // For formatting dates if needed for display
import 'package:cross_file/cross_file.dart';

// Import entities and providers
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart'; // To get current driver ID
import 'package:abra_fleet/features/auth/domain/entities/user_entity.dart';
import 'package:abra_fleet/features/driver/trip_history/domain/entities/trip_log_entity.dart';
import 'package:abra_fleet/features/driver/trip_history/presentation/providers/trip_log_provider.dart';
import 'package:abra_fleet/core/services/location_service.dart';
import 'package:abra_fleet/core/widgets/fleet_map_widget.dart';

// Placeholder for current vehicle assignment
class AssignedVehicleInfo {
  final String vehicleId;
  final String vehicleName;
  final String licensePlate;

  const AssignedVehicleInfo({
    required this.vehicleId,
    required this.vehicleName,
    required this.licensePlate,
  });
}

class DriverTripReportingScreen extends StatefulWidget {
  const DriverTripReportingScreen({super.key});

  @override
  State<DriverTripReportingScreen> createState() => _DriverTripReportingScreenState();
}

class _DriverTripReportingScreenState extends State<DriverTripReportingScreen> {
  final _startTripFormKey = GlobalKey<FormState>();
  final _endTripFormKey = GlobalKey<FormState>();

  final _startOdometerController = TextEditingController();
  final _endOdometerController = TextEditingController();
  final _tripNotesController = TextEditingController();

  bool _isTripActive = false;
  String _activeTripStartOdometer = '';
  AssignedVehicleInfo? _activeTripVehicle;
  DateTime? _activeTripStartTime; // To store when the trip started

  bool _preTripCheckLights = false;
  bool _preTripCheckTires = false;

  XFile? _startOdometerImageFile;
  XFile? _endOdometerImageFile;
  final ImagePicker _picker = ImagePicker();

  // Location tracking
  final LocationService _locationService = LocationService();
  LocationData? _startLocation;
  LocationData? _endLocation;
  bool _isCapturingLocation = false;

  // Mock assigned vehicle (in a real app, this would be fetched or passed)
  final AssignedVehicleInfo? _assignedVehicle = const AssignedVehicleInfo(
    vehicleId: 'v001',
    vehicleName: 'Cargo Van 1',
    licensePlate: 'AB-123-CD',
  );

  @override
  void dispose() {
    _startOdometerController.dispose();
    _endOdometerController.dispose();
    _tripNotesController.dispose();
    super.dispose();
  }

  Future<XFile?> _captureImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1000,
      );
      return pickedFile;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error capturing image: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
    return null;
  }

  // Helper method to build image widget cross-platform
  Widget _buildImageWidget(XFile imageFile, {double? height, double? width, BoxFit? fit}) {
    if (kIsWeb) {
      return Image.network(imageFile.path, height: height, width: width, fit: fit);
    } else {
      return Image.file(
        io.File(imageFile.path), 
        height: height, 
        width: width, 
        fit: fit
      );
    }
  }

  Future<void> _startTrip() async {
    if (!_startTripFormKey.currentState!.validate()) {
      setState(() {});
      return;
    }
    if (!_preTripCheckLights || !_preTripCheckTires) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all pre-trip checks.'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }
    // _startOdometerImageFile is validated by its FormField

    // Capture start location
    setState(() => _isCapturingLocation = true);
    _startLocation = await _locationService.getCurrentLocation(withAddress: true);
    setState(() => _isCapturingLocation = false);

    if (_startLocation == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to capture location. Please check location permissions.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
      return;
    }

    // TODO: Upload _startOdometerImageFile to cloud storage and get URL.
    // For now, we'll assume this step is done and we'd have an image URL.
    // String startOdometerImageUrl = "mock_start_image_url.jpg";

    setState(() {
      _isTripActive = true;
      _activeTripStartOdometer = _startOdometerController.text;
      _activeTripVehicle = _assignedVehicle;
      _activeTripStartTime = DateTime.now(); // Record trip start time
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Trip started for ${_activeTripVehicle?.vehicleName ?? 'vehicle'} at ${_startOdometerController.text} km. Location: ${_startLocation?.shortAddress ?? 'Unknown'}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _endTrip() async {
    if (!_endTripFormKey.currentState!.validate()) {
      setState(() {});
      return;
    }

    final double startOdo = double.tryParse(_activeTripStartOdometer) ?? 0;
    final double endOdo = double.tryParse(_endOdometerController.text) ?? 0;

    if (endOdo <= startOdo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End odometer must be greater than start odometer.'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    // _endOdometerImageFile is validated by its FormField

    // Capture end location
    setState(() => _isCapturingLocation = true);
    _endLocation = await _locationService.getCurrentLocation(withAddress: true);
    setState(() => _isCapturingLocation = false);

    if (_endLocation == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to capture end location. Please check location permissions.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
      return;
    }

    // Get current user for driverId (placeholder - this should ideally come from auth state)
    // final authRepository = Provider.of<AuthRepository>(context, listen: false);
    // final String driverId = authRepository.currentUser.id; // Assuming currentUser is available and has an ID

    // TODO: Upload _endOdometerImageFile and get URL.
    // String endOdometerImageUrl = "mock_end_image_url.jpg";

    final tripLog = TripLogEntity(
      id: 'trip_local_${DateTime.now().millisecondsSinceEpoch}', // Temporary local ID, backend should generate final
      vehicleName: _activeTripVehicle?.vehicleName ?? 'Unknown Vehicle',
      vehicleLicensePlate: _activeTripVehicle?.licensePlate ?? 'N/A',
      startTime: _activeTripStartTime ?? DateTime.now(), // Use stored start time
      endTime: DateTime.now(), // Current time as end time
      startOdometer: startOdo,
      endOdometer: endOdo,
      notes: _tripNotesController.text.trim().isNotEmpty ? _tripNotesController.text.trim() : null,
      startLocation: _startLocation?.displayText,
      endLocation: _endLocation?.displayText,
      // startOdometerPhotoUrl: startOdometerImageUrl, // TODO
      // endOdometerPhotoUrl: endOdometerImageUrl,     // TODO
    );

    final tripLogProvider = Provider.of<TripLogProvider>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final success = await tripLogProvider.addTripLog(tripLog);

    if (mounted) {
      if (success) {
        final distance = _startLocation != null && _endLocation != null
            ? _locationService.calculateDistance(
                _startLocation!.latitude, _startLocation!.longitude,
                _endLocation!.latitude, _endLocation!.longitude,
              ) / 1000 // Convert to km
            : null;
        
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              'Trip ended: ${_activeTripVehicle?.vehicleName ?? 'vehicle'} at ${endOdo}km.'
              '${distance != null ? ' Distance: ${distance.toStringAsFixed(1)}km' : ''}'
            ),
            backgroundColor: Colors.blueAccent,
          ),
        );
        setState(() {
          _isTripActive = false;
          _startOdometerController.clear();
          _endOdometerController.clear();
          _tripNotesController.clear();
          _preTripCheckLights = false;
          _preTripCheckTires = false;
          _startOdometerImageFile = null;
          _endOdometerImageFile = null;
          _activeTripStartOdometer = '';
          _activeTripVehicle = null;
          _activeTripStartTime = null;
          _startLocation = null;
          _endLocation = null;
        });
      } else {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Failed to log trip: ${tripLogProvider.errorMessage ?? "Unknown error"}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Widget _buildImagePickerFormField({
    required String label,
    required XFile? imageFile,
    required Function(XFile? file) onImageChanged,
    required FormFieldValidator<XFile> validator,
  }) {
    return FormField<XFile>(
      initialValue: imageFile,
      validator: validator,
      builder: (FormFieldState<XFile> field) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8.0),
            Container(
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(
                  color: field.hasError ? Theme.of(context).colorScheme.error : Colors.grey.shade400,
                  width: field.hasError ? 2.0 : 1.5,
                ),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: InkWell(
                onTap: () async {
                  final XFile? capturedImage = await _captureImage();
                  if (capturedImage != null) {
                    onImageChanged(capturedImage);
                    field.didChange(capturedImage);
                  }
                },
                child: imageFile != null
                    ? Stack(
                  alignment: Alignment.topRight,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(7.0),
                      child: _buildImageWidget(imageFile, width: double.infinity, height: 150, fit: BoxFit.cover),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
                      onPressed: () {
                        onImageChanged(null);
                        field.didChange(null);
                      },
                      tooltip: 'Remove Image',
                    )
                  ],
                )
                    : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.camera_alt_outlined, size: 40, color: Colors.grey.shade600),
                      const SizedBox(height: 4),
                      Text('Tap to capture photo', style: TextStyle(color: Colors.grey.shade700)),
                    ],
                  ),
                ),
              ),
            ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, left: 12.0),
                child: Text(field.errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
              ),
          ],
        );
      },
    );
  }

  Widget _buildStartTripForm(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Form(
        key: _startTripFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (_assignedVehicle != null) ...[
              Text('Current Vehicle:', style: textTheme.titleMedium),
              Card(
                elevation: 1,
                child: ListTile(
                  leading: const Icon(Icons.directions_car_filled_rounded, size: 30),
                  title: Text(_assignedVehicle!.vehicleName, style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  subtitle: Text('Plate: ${_assignedVehicle!.licensePlate}'),
                ),
              ),
              const SizedBox(height: 24.0),
            ] else ...[
              const Center(child: Text('No vehicle assigned. Please contact admin.', style: TextStyle(color: Colors.red, fontSize: 16))),
              const SizedBox(height: 24.0),
            ],
            TextFormField(
              controller: _startOdometerController,
              decoration: const InputDecoration(labelText: 'Starting Odometer Reading (km)*', prefixIcon: Icon(Icons.speed_rounded)),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) return 'Please enter reading';
                if (double.tryParse(value) == null) return 'Enter a valid number';
                return null;
              },
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16.0),
            _buildImagePickerFormField(
              label: 'Start Odometer Photo (Mandatory)*',
              imageFile: _startOdometerImageFile,
              onImageChanged: (file) => setState(() => _startOdometerImageFile = file),
              validator: (file) => file == null ? 'Please capture start odometer photo.' : null,
            ),
            const SizedBox(height: 20.0),
            Text('Pre-Trip Checklist:', style: textTheme.titleMedium),
            CheckboxListTile(
              title: const Text('Check Lights & Signals*'),
              value: _preTripCheckLights,
              onChanged: (bool? value) => setState(() => _preTripCheckLights = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              title: const Text('Check Tire Pressure & Condition*'),
              value: _preTripCheckTires,
              onChanged: (bool? value) => setState(() => _preTripCheckTires = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            // Location status
            if (_startLocation != null) ...[
              const SizedBox(height: 16.0),
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  border: Border.all(color: Colors.green.shade200),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_on, color: Colors.green.shade600, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Location: ${_startLocation!.shortAddress}',
                        style: TextStyle(color: Colors.green.shade700, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 32.0),
            ElevatedButton.icon(
              icon: _isCapturingLocation 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.play_arrow_rounded),
              label: Text(_isCapturingLocation ? 'Capturing Location...' : 'Start Trip'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              onPressed: (_assignedVehicle != null && !_isCapturingLocation) ? _startTrip : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEndTripUI(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Form(
        key: _endTripFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Trip in Progress for ${_activeTripVehicle?.vehicleName ?? 'Vehicle'}',
              style: textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Started at: $_activeTripStartOdometer km on ${DateFormat('MMM dd, hh:mm a').format(_activeTripStartTime ?? DateTime.now())}',
              style: textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (_startOdometerImageFile != null) ...[
              const SizedBox(height: 16),
              Text('Start Odometer Photo:', style: textTheme.titleSmall),
              const SizedBox(height: 4),
              _buildImageWidget(_startOdometerImageFile!, height: 100, fit: BoxFit.contain),
              const SizedBox(height: 16),
            ],
            if (_startLocation != null) ...[
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  border: Border.all(color: Colors.blue.shade200),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.location_on, color: Colors.blue.shade600, size: 16),
                        const SizedBox(width: 4),
                        Text('Start Location:', style: textTheme.titleSmall?.copyWith(color: Colors.blue.shade700)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _startLocation!.displayText,
                      style: TextStyle(color: Colors.blue.shade600, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Divider(height: 24),
            TextFormField(
              controller: _endOdometerController,
              decoration: const InputDecoration(labelText: 'Ending Odometer Reading (km)*', prefixIcon: Icon(Icons.speed_rounded)),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) return 'Please enter reading';
                final endOdo = double.tryParse(value);
                final startOdo = double.tryParse(_activeTripStartOdometer);
                if (endOdo == null) return 'Enter a valid number';
                if (startOdo != null && endOdo <= startOdo) {
                  return 'Must be > start odometer ($_activeTripStartOdometer km)';
                }
                return null;
              },
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16.0),
            _buildImagePickerFormField(
              label: 'End Odometer Photo (Mandatory)*',
              imageFile: _endOdometerImageFile,
              onImageChanged: (file) => setState(() => _endOdometerImageFile = file),
              validator: (file) => file == null ? 'Please capture end odometer photo.' : null,
            ),
            const SizedBox(height: 16.0),
            TextFormField(
              controller: _tripNotesController,
              decoration: const InputDecoration(labelText: 'Trip Notes (Optional)', prefixIcon: Icon(Icons.notes_rounded), hintText: 'e.g., Any incidents, delays...'),
              maxLines: 3,
              textInputAction: TextInputAction.done,
            ),
            // End location status
            if (_endLocation != null) ...[
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  border: Border.all(color: Colors.green.shade200),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.location_on, color: Colors.green.shade600, size: 16),
                        const SizedBox(width: 4),
                        Text('End Location:', style: textTheme.titleSmall?.copyWith(color: Colors.green.shade700)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _endLocation!.displayText,
                      style: TextStyle(color: Colors.green.shade600, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 32.0),
            ElevatedButton.icon(
              icon: _isCapturingLocation 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.stop_circle_rounded),
              label: Text(_isCapturingLocation ? 'Capturing Location...' : 'End Trip'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                backgroundColor: Colors.redAccent,
              ),
              onPressed: !_isCapturingLocation ? _endTrip : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isTripActive ? _buildEndTripUI(context) : _buildStartTripForm(context),
    );
  }
}