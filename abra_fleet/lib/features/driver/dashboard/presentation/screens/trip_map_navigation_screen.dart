// lib/screens/trip_map_navigation_screen.dart
// ============================================================================
// TRIP MAP NAVIGATION - Full Screen Uber-like Navigation
// ============================================================================
// ✅ FIXED: Call + WhatsApp buttons always visible (not hidden when phone empty)
// ✅ FIXED: Phone number fallback from multiple fields
// ✅ FIXED: Debug prints to identify phone field from API
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../../../../../core/services/navigation_service.dart';
import '../../../../../core/services/live_tracking_service.dart';

// ============================================================================
// WHATSAPP MESSAGE TEMPLATES
// ============================================================================
class WhatsAppTemplates {
  static List<Map<String, String>> get templates => [
    {
      'label': '🕐 Running Late',
      'message': 'Hello, I am your Abra Travels driver. I am running a bit late and will arrive at your pickup location shortly. Sorry for the inconvenience!',
    },
    {
      'label': '🚗 Arrived at Pickup',
      'message': 'Hello! I am your Abra Travels driver. I have arrived at your pickup location. Please come down, I am waiting for you.',
    },
    {
      'label': '⏱️ 5 Minutes Away',
      'message': 'Hello, I am your Abra Travels driver. I will be reaching your pickup location in approximately 5 minutes. Please be ready!',
    },
    {
      'label': '⏱️ 10 Minutes Away',
      'message': 'Hello, I am your Abra Travels driver. I will be reaching your pickup location in approximately 10 minutes. Please be ready!',
    },
    {
      'label': '🚦 Stuck in Traffic',
      'message': 'Hello, I am your Abra Travels driver. I am currently stuck in traffic. I will reach your pickup location as soon as possible. Thank you for your patience!',
    },
    {
      'label': '📍 On My Way',
      'message': 'Hello! I am your Abra Travels driver. I am on the way to your pickup location. Please stay ready. Contact me if you need any help.',
    },
    {
      'label': '✅ Trip Started',
      'message': 'Hello! Your Abra Travels trip has started. I am on my way to pick you up. See you soon!',
    },
    {
      'label': '🔁 Wrong Location?',
      'message': 'Hello! I am your Abra Travels driver. I am at the pickup location mentioned in the app. If you are at a different spot, please let me know.',
    },
  ];
}

class TripMapNavigationScreen extends StatefulWidget {
  final String tripGroupId;
  final List<Map<String, dynamic>> stops;
  final int currentStopIndex;

  const TripMapNavigationScreen({
    Key? key,
    required this.tripGroupId,
    required this.stops,
    required this.currentStopIndex,
  }) : super(key: key);

  @override
  State<TripMapNavigationScreen> createState() => _TripMapNavigationScreenState();
}

class _TripMapNavigationScreenState extends State<TripMapNavigationScreen> {
  final MapController _mapController = MapController();
  final NavigationService _navigationService = NavigationService();
  final LiveTrackingService _trackingService = LiveTrackingService();

  StreamSubscription<NavigationUpdate>? _navigationSubscription;

  LatLng? _currentLocation;
  NavigationUpdate? _currentNavigationUpdate;
  bool _isNavigating = false;
  bool _isLoading = true;

  // ============================================================================
  // ✅ FIXED: Extract phone from ALL possible field names
  // ============================================================================
  String _extractPhone(Map<String, dynamic>? customer) {
    if (customer == null) return '';

    // Debug: print all customer fields to console
    print('🔍 NAV SCREEN - Customer object: $customer');
    print('🔍 NAV SCREEN - Customer keys: ${customer.keys.toList()}');

    // Try every possible field name your backend might use
    final phone = customer['phone']?.toString() ??
        customer['phoneNumber']?.toString() ??
        customer['mobile']?.toString() ??
        customer['mobileNumber']?.toString() ??
        customer['contact']?.toString() ??
        customer['contactNumber']?.toString() ??
        customer['customerPhone']?.toString() ??
        '';

    print('🔍 NAV SCREEN - Extracted phone: "$phone"');
    return phone;
  }

  @override
  void initState() {
    super.initState();

    // ✅ Debug: print all stops data when screen opens
    print('\n🗺️ NAV SCREEN OPENED');
    print('   Total stops: ${widget.stops.length}');
    print('   Current stop index: ${widget.currentStopIndex}');
    if (widget.currentStopIndex < widget.stops.length) {
      final stop = widget.stops[widget.currentStopIndex];
      print('   Current stop: $stop');
      print('   Customer field: ${stop['customer']}');
    }

    _initializeNavigation();
  }

  @override
  void dispose() {
    _navigationSubscription?.cancel();
    _navigationService.stopNavigation();
    _trackingService.stopTracking();
    super.dispose();
  }

  // ============================================================================
  // NAVIGATION INIT
  // ============================================================================
  Future<void> _initializeNavigation() async {
    try {
      print('\n🗺️ INITIALIZING MAP NAVIGATION');

      await _navigationService.initialize();

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _currentLocation = LatLng(position.latitude, position.longitude);

      if (widget.currentStopIndex < widget.stops.length) {
        final stop = widget.stops[widget.currentStopIndex];
        final coords = stop['location']?['coordinates'];

        if (coords != null) {
          final destLat = _extractLatitude(coords);
          final destLng = _extractLongitude(coords);

          if (destLat != 0 && destLng != 0) {
            final destination = LatLng(destLat, destLng);

            final started = await _navigationService.startNavigation(
              start: _currentLocation!,
              destination: destination,
              voiceEnabled: true,
            );

            if (started) {
              _navigationSubscription =
                  _navigationService.navigationStream.listen((update) {
                if (mounted) {
                  setState(() {
                    _currentNavigationUpdate = update;
                    _currentLocation = update.currentLocation;
                  });
                  _mapController.move(update.currentLocation, 16.0);
                }
              });

              _trackingService.startTracking(
                tripGroupId: widget.tripGroupId,
                stops: widget.stops,
                currentStopIndex: widget.currentStopIndex,
              );

              setState(() {
                _isNavigating = true;
                _isLoading = false;
              });

              print('✅ Navigation started successfully');
            }
          }
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      print('❌ Navigation initialization failed: $e');
      setState(() => _isLoading = false);
      _showSnackBar('Failed to start navigation: $e', Colors.red);
    }
  }

  // ============================================================================
  // ✅ FIXED: CALL CUSTOMER - works mobile + web
  // ============================================================================
  Future<void> _callCustomer(String phone, String name) async {
    if (phone.isEmpty) {
      _showSnackBar('No phone number available for $name', Colors.orange);
      return;
    }

    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');

    if (kIsWeb) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.phone, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(child: Text('Call $name', overflow: TextOverflow.ellipsis)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Dial this number:'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Text(
                  cleanPhone,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                final uri = Uri(scheme: 'tel', path: cleanPhone);
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
              icon: const Icon(Icons.phone),
              label: const Text('Call'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            ),
          ],
        ),
      );
      return;
    }

    final uri = Uri(scheme: 'tel', path: cleanPhone);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        _showSnackBar('Could not open dialer', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error making call: $e', Colors.red);
    }
  }

  // ============================================================================
  // ✅ WHATSAPP: Show template picker then open WhatsApp
  // ============================================================================
  Future<void> _openWhatsAppWithTemplate(String phone, String customerName) async {
    if (phone.isEmpty) {
      _showSnackBar('No phone number available for $customerName', Colors.orange);
      return;
    }

    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');

    final selectedTemplate = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildTemplatePickerSheet(customerName),
    );

    if (selectedTemplate == null) return;

    await _sendWhatsApp(cleanPhone, selectedTemplate, customerName);
  }

  Future<void> _sendWhatsApp(String phone, String message, String name) async {
    final encodedMessage = Uri.encodeComponent(message);
    final uri = Uri.parse('https://wa.me/$phone?text=$encodedMessage');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        final webUri = Uri.parse(
            'https://web.whatsapp.com/send?phone=$phone&text=$encodedMessage');
        if (await canLaunchUrl(webUri)) {
          await launchUrl(webUri, mode: LaunchMode.externalApplication);
        } else {
          _showSnackBar('Could not open WhatsApp for $name', Colors.red);
        }
      }
    } catch (e) {
      _showSnackBar('Error opening WhatsApp: $e', Colors.red);
    }
  }

  // ============================================================================
  // TEMPLATE PICKER BOTTOM SHEET
  // ============================================================================
  Widget _buildTemplatePickerSheet(String customerName) {
    final TextEditingController customController = TextEditingController();
    bool showCustomInput = false;

    return StatefulBuilder(
      builder: (context, setSheetState) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.chat, color: Colors.green, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'WhatsApp Message',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'To: $customerName',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.55,
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    ...WhatsAppTemplates.templates.map((template) {
                      final emoji = template['label']!.split(' ').first;
                      final label = template['label']!.split(' ').skip(1).join(' ');
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: Colors.green.shade100),
                        ),
                        child: ListTile(
                          leading: Text(emoji, style: const TextStyle(fontSize: 22)),
                          title: Text(label,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text(
                            template['message']!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                          trailing: const Icon(Icons.send, color: Colors.green, size: 20),
                          onTap: () => Navigator.pop(context, template['message']),
                        ),
                      );
                    }).toList(),
                    // Custom message
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Colors.blue.shade100),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Text('✏️', style: TextStyle(fontSize: 22)),
                            title: const Text('Custom Message',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: const Text('Type your own message',
                                style: TextStyle(fontSize: 12)),
                            trailing: Icon(
                              showCustomInput
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              color: Colors.blue,
                            ),
                            onTap: () => setSheetState(
                                () => showCustomInput = !showCustomInput),
                          ),
                          if (showCustomInput)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Column(
                                children: [
                                  TextField(
                                    controller: customController,
                                    maxLines: 3,
                                    decoration: InputDecoration(
                                      hintText: 'Type your message here...',
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8)),
                                      contentPadding: const EdgeInsets.all(12),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        if (customController.text.trim().isNotEmpty) {
                                          Navigator.pop(
                                              context, customController.text.trim());
                                        }
                                      },
                                      icon: const Icon(Icons.send, size: 16),
                                      label: const Text('Send Custom Message'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  double _extractLatitude(dynamic coords) {
    if (coords is Map) return (coords['latitude'] ?? coords[1] ?? 0).toDouble();
    if (coords is List && coords.length >= 2) return (coords[1] ?? 0).toDouble();
    return 0.0;
  }

  double _extractLongitude(dynamic coords) {
    if (coords is Map) return (coords['longitude'] ?? coords[0] ?? 0).toDouble();
    if (coords is List && coords.length >= 2) return (coords[0] ?? 0).toDouble();
    return 0.0;
  }

  // ============================================================================
  // BUILD
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                _buildMap(),
                if (_currentNavigationUpdate?.currentStep != null)
                  _buildInstructionCard(),
                _buildBottomPanel(),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  right: 16,
                  child: FloatingActionButton.small(
                    onPressed: () => Navigator.pop(context),
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.close, color: Colors.black),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentLocation ?? const LatLng(12.9716, 77.5946),
        initialZoom: 16.0,
        minZoom: 10.0,
        maxZoom: 18.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.abra_fleet',
        ),
        if (_currentNavigationUpdate?.routePoints.isNotEmpty ?? false)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _currentNavigationUpdate!.routePoints,
                strokeWidth: 6.0,
                color: Colors.blue,
                borderStrokeWidth: 2.0,
                borderColor: Colors.white,
              ),
            ],
          ),
        MarkerLayer(markers: _buildMarkers()),
      ],
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    if (_currentLocation != null) {
      markers.add(
        Marker(
          point: _currentLocation!,
          width: 40,
          height: 40,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.5),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.navigation, color: Colors.white, size: 20),
          ),
        ),
      );
    }

    if (widget.currentStopIndex < widget.stops.length) {
      final stop = widget.stops[widget.currentStopIndex];
      final coords = stop['location']?['coordinates'];

      if (coords != null) {
        final lat = _extractLatitude(coords);
        final lng = _extractLongitude(coords);

        if (lat != 0 && lng != 0) {
          markers.add(
            Marker(
              point: LatLng(lat, lng),
              width: 50,
              height: 50,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${widget.currentStopIndex + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Icon(Icons.location_on, color: Colors.red, size: 36),
                ],
              ),
            ),
          );
        }
      }
    }

    return markers;
  }

  Widget _buildInstructionCard() {
    final step = _currentNavigationUpdate!.currentStep!;
    final distance = _currentNavigationUpdate!.distanceToNextStep;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 16,
      right: 80,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
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
                Icon(_getManeuverIcon(step.maneuver), size: 32, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    step.instruction,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              distance >= 1000
                  ? 'in ${(distance / 1000).toStringAsFixed(1)} km'
                  : 'in ${distance.toInt()} meters',
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // ✅ FIXED BOTTOM PANEL - Buttons ALWAYS visible, show message if no phone
  // ============================================================================
  Widget _buildBottomPanel() {
    final stop = widget.stops[widget.currentStopIndex];
    final distance = _currentNavigationUpdate?.distanceToDestination ?? 0;
    final eta = (distance / 1000 * 3).round();

    final customerName = stop['customer']?['name']?.toString() ?? 'Customer';

    // ✅ Extract phone using all possible field names
    final customerPhone = _extractPhone(
        stop['customer'] as Map<String, dynamic>?);

    final stopType = stop['type']?.toString() ?? 'pickup';
    final address = stop['location']?['address']?.toString() ?? 'Unknown location';

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Stop title + ETA ──────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stop ${widget.currentStopIndex + 1} — '
                        '${stopType == 'pickup' ? '📍 Pickup' : '🏁 Drop'}',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        address,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'ETA: $eta min',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Customer name row ─────────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.person, size: 18, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    customerName,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                // Phone badge (only shown if phone available)
                if (customerPhone.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Text(
                      customerPhone,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // ── ✅ CALL + WHATSAPP BUTTONS — always visible ───────────────
            Row(
              children: [
                // CALL button
                Expanded(
                  child: GestureDetector(
                    onTap: () => _callCustomer(customerPhone, customerName),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: customerPhone.isNotEmpty
                            ? Colors.green
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.phone,
                            color: customerPhone.isNotEmpty
                                ? Colors.white
                                : Colors.grey.shade600,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Call',
                            style: TextStyle(
                              color: customerPhone.isNotEmpty
                                  ? Colors.white
                                  : Colors.grey.shade600,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                // WHATSAPP button
                Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        _openWhatsAppWithTemplate(customerPhone, customerName),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: customerPhone.isNotEmpty
                            ? const Color(0xFF25D366)
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat,
                            color: customerPhone.isNotEmpty
                                ? Colors.white
                                : Colors.grey.shade600,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'WhatsApp',
                            style: TextStyle(
                              color: customerPhone.isNotEmpty
                                  ? Colors.white
                                  : Colors.grey.shade600,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // ── "No phone" notice if missing ──────────────────────────────
            if (customerPhone.isEmpty) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline,
                      size: 13, color: Colors.orange.shade700),
                  const SizedBox(width: 4),
                  Text(
                    'Phone number not available in system',
                    style: TextStyle(
                        fontSize: 11, color: Colors.orange.shade700),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),

            // ── Stats row ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    icon: Icons.navigation,
                    label: 'Distance',
                    value: '${(distance / 1000).toStringAsFixed(1)} km',
                  ),
                  Container(width: 1, height: 40, color: Colors.grey[300]),
                  _buildStatItem(
                    icon: Icons.access_time,
                    label: 'ETA',
                    value: '$eta min',
                  ),
                  Container(width: 1, height: 40, color: Colors.grey[300]),
                  _buildStatItem(
                    icon: Icons.location_on,
                    label: 'Stops',
                    value:
                        '${widget.currentStopIndex + 1}/${widget.stops.length}',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
      ],
    );
  }

  IconData _getManeuverIcon(String maneuver) {
    switch (maneuver) {
      case 'turn':
        return Icons.turn_right;
      case 'depart':
        return Icons.straight;
      case 'arrive':
        return Icons.flag;
      case 'roundabout':
        return Icons.roundabout_right;
      default:
        return Icons.navigation;
    }
  }
}