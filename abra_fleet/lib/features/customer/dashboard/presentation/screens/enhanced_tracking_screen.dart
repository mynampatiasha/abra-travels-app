// lib/features/tracking/screens/enhanced_tracking_screen.dart
// ============================================================================
// ENHANCED CUSTOMER TRACKING SCREEN
// ============================================================================
// ✅ FIXED: Call button always visible (not hidden when phone empty)
// ✅ NEW:   WhatsApp button added for customer → driver messaging
// ✅ FIXED: Buttons show greyed-out with notice when no phone available
// ✅ FIXED: WebView crash on Flutter Web — uses flutter_map on web, Leaflet
//           WebView on mobile (Android/iOS) via conditional import
// ✅ NEW:   Compact driver info + buttons row (reduced vertical space)
// ✅ NEW:   Enhanced card UI with gradients, badges, animations
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'package:abra_fleet/core/services/enhanced_customer_tracking_service.dart';
import 'package:abra_fleet/app/config/api_config.dart';

// Conditional import: stub (web) vs real WebView widget (mobile)
import 'package:abra_fleet/features/tracking/screens/map_widget_stub.dart'
    if (dart.library.io) 'package:abra_fleet/features/tracking/screens/map_widget_mobile.dart';

// ============================================================================
// CUSTOMER → DRIVER WHATSAPP TEMPLATES
// ============================================================================
class CustomerWhatsAppTemplates {
  static List<Map<String, String>> get templates => [
        {
          'label': '🕐 Are You On the Way?',
          'message':
              'Hello! I am your passenger waiting for pickup. Are you on the way? Please let me know your ETA.',
        },
        {
          'label': '📍 Where Are You?',
          'message':
              'Hi! I am at my pickup location. I can\'t see your vehicle yet. Could you let me know where you are?',
        },
        {
          'label': '🚗 I Am Ready',
          'message':
              'Hello! I am ready at my pickup location. Please come when you arrive. I will be waiting.',
        },
        {
          'label': '⏳ Please Wait 5 Minutes',
          'message':
              'Hi! I will be at my pickup location in about 5 minutes. Please wait for me. Sorry for the delay!',
        },
        {
          'label': '🔁 I Think Wrong Location',
          'message':
              'Hello! I think there might be a confusion with the pickup location. I am at a different spot. Can we connect?',
        },
        {
          'label': '🚦 Running a Bit Late',
          'message':
              'Hi! I am running a little late. Please wait for me, I will be there in a few minutes. Sorry!',
        },
        {
          'label': '✅ I Can See Your Vehicle',
          'message':
              'Hello! I can see your vehicle. I am walking towards you now. Please wait!',
        },
        {
          'label': '🆘 Need Help',
          'message':
              'Hello! I need some help with my pickup. Can you please call me or reply to this message?',
        },
      ];
}

// ============================================================================
// MAIN TRACKING SCREEN
// ============================================================================
class EnhancedTrackingScreen extends StatefulWidget {
  final String tripId;

  const EnhancedTrackingScreen({
    Key? key,
    required this.tripId,
  }) : super(key: key);

  @override
  State<EnhancedTrackingScreen> createState() =>
      _EnhancedTrackingScreenState();
}

class _EnhancedTrackingScreenState extends State<EnhancedTrackingScreen>
    with SingleTickerProviderStateMixin {
  final EnhancedCustomerTrackingService _trackingService =
      EnhancedCustomerTrackingService();

  // ── flutter_map (Web only) ─────────────────────────────────────────────────
  final MapController _mapController = MapController();
  List<LatLng>? _routePolyline;
  bool _mapCentered = false;

  // ── Leaflet WebView (Mobile only) — provided via conditional import ─────────
  LeafletMapController? _leafletController;

  TripTrackingData? _currentData;
  bool _isLoading = true;
  StreamSubscription? _trackingSubscription;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const Color _whatsAppGreen = Color(0xFF25D366);
  static const Color _primaryBlue = Color(0xFF0D47A1);
  static const Color _accentBlue = Color(0xFF1E88E5);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initializeTracking();
  }

  @override
  void dispose() {
    _trackingService.stopTracking();
    _trackingSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TRACKING INIT
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _initializeTracking() async {
    _trackingSubscription = _trackingService.trackingStream.listen(
      (data) async {
        if (!mounted) return;

        setState(() {
          _currentData = data;
          _isLoading = false;
        });

        if (kIsWeb) {
          // Web: flutter_map polyline + auto-center
          if (_routePolyline == null && data.driverLocation != null) {
            final route = await _trackingService.getRoutePolyline(
              data.driverLocation!.toLatLng(),
              data.customerLocation.toLatLng(),
            );
            if (mounted) setState(() => _routePolyline = route);
          }
          if (!_mapCentered && data.driverLocation != null) {
            _centerFlutterMap(data);
            _mapCentered = true;
          }
        } else {
          // Mobile: push data to Leaflet WebView
          _leafletController?.updateMapData(data);
        }
      },
      onError: (error) {
        debugPrint('❌ Tracking stream error: $error');
        if (mounted) setState(() => _isLoading = false);
      },
    );
    _trackingService.startTracking(widget.tripId);
  }

  void _centerFlutterMap(TripTrackingData data) {
    if (data.driverLocation == null) return;
    final centerLat =
        (data.driverLocation!.latitude + data.customerLocation.latitude) /
            2;
    final centerLng =
        (data.driverLocation!.longitude +
                data.customerLocation.longitude) /
            2;
    _mapController.move(LatLng(centerLat, centerLng), 14);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ✅ SHARE LIVE LOCATION via WhatsApp
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _shareLiveLocation() async {
    try {
      if (_currentData == null) {
        _showSnackBar('Trip data not available', Colors.orange);
        return;
      }
      final tripId = widget.tripId;
      final tripNumber = _currentData!.trip.tripNumber;
      final vehicleNumber =
          _currentData!.vehicle?.registrationNumber ?? 'N/A';
      final driverName = _currentData!.driver?.name ?? 'Driver';
      final liveTrackingUrl =
          '${ApiConfig.baseUrl}/live-track/$tripId';
      final message = 'Hello! 👋\n\n'
          'I\'m sharing my live trip location with you.\n\n'
          '🚗 Trip: *$tripNumber*\n'
          '🚙 Vehicle: *$vehicleNumber*\n'
          '👤 Driver: *$driverName*\n\n'
          '📍 Track my ride in real time:\n'
          '$liveTrackingUrl\n\n'
          'Powered by Abra Travels';
      final encodedMsg = Uri.encodeComponent(message);
      final uri = Uri.parse('https://wa.me/?text=$encodedMsg');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        _showSnackBar('Opening WhatsApp...', Colors.green);
      } else {
        _showSnackBar(
            'Could not open WhatsApp. Please install WhatsApp.',
            Colors.red);
      }
    } catch (e) {
      debugPrint('❌ Error sharing live location: $e');
      _showSnackBar('Error sharing location: $e', Colors.red);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ✅ CALL DRIVER — always works, shows dialog on web
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _callDriver() async {
    final phone = _currentData?.driver?.phone ?? '';
    final name = _currentData?.driver?.name ?? 'Driver';
    if (phone.isEmpty) {
      _showSnackBar('Driver phone number not available', Colors.orange);
      return;
    }
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (kIsWeb) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.phone, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('Call $name',
                      overflow: TextOverflow.ellipsis)),
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
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close')),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                final uri = Uri(scheme: 'tel', path: cleanPhone);
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
              icon: const Icon(Icons.phone),
              label: const Text('Call'),
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.green),
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
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ✅ WHATSAPP TO DRIVER — template picker + launch
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _whatsAppDriver() async {
    final phone = _currentData?.driver?.phone ?? '';
    final name = _currentData?.driver?.name ?? 'Driver';
    if (phone.isEmpty) {
      _showSnackBar('Driver phone number not available', Colors.orange);
      return;
    }
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildCustomerTemplateSheet(name),
    );
    if (selected == null) return;
    final encodedMsg = Uri.encodeComponent(selected);
    final mobileUri =
        Uri.parse('https://wa.me/$cleanPhone?text=$encodedMsg');
    final webUri = Uri.parse(
        'https://web.whatsapp.com/send?phone=$cleanPhone&text=$encodedMsg');
    try {
      if (await canLaunchUrl(mobileUri)) {
        await launchUrl(mobileUri, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } else {
        _showSnackBar('Could not open WhatsApp', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error opening WhatsApp: $e', Colors.red);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // CUSTOMER TEMPLATE PICKER SHEET
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildCustomerTemplateSheet(String driverName) {
    final customController = TextEditingController();
    bool showCustom = false;
    return StatefulBuilder(
      builder: (context, setSheet) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _whatsAppGreen.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.chat,
                        color: _whatsAppGreen, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Message Driver',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        Text('To: $driverName',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600])),
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
                  maxHeight:
                      MediaQuery.of(context).size.height * 0.58),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                children: [
                  ...CustomerWhatsAppTemplates.templates.map((t) {
                    final emoji = t['label']!.split(' ').first;
                    final label =
                        t['label']!.split(' ').skip(1).join(' ');
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                            color: _whatsAppGreen.withOpacity(0.2)),
                      ),
                      child: ListTile(
                        leading: Text(emoji,
                            style: const TextStyle(fontSize: 22)),
                        title: Text(label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                        subtitle: Text(t['message']!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600])),
                        trailing: const Icon(Icons.send,
                            color: _whatsAppGreen, size: 20),
                        onTap: () =>
                            Navigator.pop(context, t['message']),
                      ),
                    );
                  }).toList(),
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
                          leading: const Text('✏️',
                              style: TextStyle(fontSize: 22)),
                          title: const Text('Custom Message',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14)),
                          subtitle: const Text('Type your own message',
                              style: TextStyle(fontSize: 12)),
                          trailing: Icon(
                            showCustom
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: Colors.blue,
                          ),
                          onTap: () =>
                              setSheet(() => showCustom = !showCustom),
                        ),
                        if (showCustom)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                                16, 0, 16, 12),
                            child: Column(
                              children: [
                                TextField(
                                  controller: customController,
                                  maxLines: 3,
                                  decoration: InputDecoration(
                                    hintText: 'Type your message...',
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(8)),
                                    contentPadding:
                                        const EdgeInsets.all(12),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      if (customController.text
                                          .trim()
                                          .isNotEmpty) {
                                        Navigator.pop(
                                            context,
                                            customController.text
                                                .trim());
                                      }
                                    },
                                    icon: const Icon(Icons.send,
                                        size: 16),
                                    label: const Text(
                                        'Send Custom Message'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(
                                                  8)),
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
      ),
    );
  }

  void _showSnackBar(String message, [Color color = Colors.black87]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF082e70), Color(0xFF1E88E5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 20),
                Text('Locating your vehicle…',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                SizedBox(height: 6),
                Text('ABRA Tours and Travels Live Tracking',
                    style:
                        TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
        ),
      );
    }

    if (_currentData == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Track Your Vehicle'),
          backgroundColor: _primaryBlue,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('Unable to load trip information'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() => _isLoading = true);
                  _initializeTracking();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // ── MAP ───────────────────────────────────────────────────────
          Positioned.fill(child: _buildMap()),

          // ── STATUS BANNER ─────────────────────────────────────────────
          Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildStatusBanner()),

          // ── BACK BUTTON ───────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 56,
            left: 16,
            child: _buildFloatingButton(
              icon: Icons.arrow_back,
              onTap: () => Navigator.pop(context),
              color: Colors.white,
              iconColor: Colors.black87,
            ),
          ),

          // ── REFRESH BUTTON ────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 56,
            right: 16,
            child: _buildFloatingButton(
              icon: Icons.refresh,
              onTap: () {
                _trackingService.stopTracking();
                _trackingService.startTracking(widget.tripId);
                _showSnackBar('Refreshing location…');
              },
              color: Colors.white,
              iconColor: _accentBlue,
            ),
          ),

          // ── BOTTOM INFO SHEET ─────────────────────────────────────────
          Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomInfoSheet()),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // MAP: flutter_map on web, Leaflet WebView on mobile
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildMap() {
    if (kIsWeb) {
      return _buildFlutterMap();
    }
    // Mobile: Leaflet via WebView (from conditional import)
    return LeafletMapWidget(
      onControllerReady: (controller) {
        _leafletController = controller;
        if (_currentData != null) {
          controller.updateMapData(_currentData!);
        }
      },
    );
  }

  /// flutter_map — used only on web
  Widget _buildFlutterMap() {
    final data = _currentData!;
    final driverLoc = data.driverLocation;
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: data.customerLocation.toLatLng(),
        initialZoom: 14,
        minZoom: 10,
        maxZoom: 18,
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.example.abra_fleet',
        ),
        if (_routePolyline != null && _routePolyline!.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePolyline!,
                color: Colors.blue,
                strokeWidth: 5,
                borderStrokeWidth: 2,
                borderColor: Colors.white,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (driverLoc != null)
              Marker(
                point: driverLoc.toLatLng(),
                width: 60,
                height: 60,
                child: Transform.rotate(
                  angle:
                      (driverLoc.heading ?? 0) * (3.14159 / 180),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.5),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.navigation,
                        color: Colors.white, size: 28),
                  ),
                ),
              ),
            Marker(
              point: data.customerLocation.toLatLng(),
              width: 50,
              height: 50,
              child: const Icon(Icons.location_on,
                  color: Colors.red, size: 50),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFloatingButton({
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
    required Color iconColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
    );
  }

  Widget _buildStatusBanner() {
    final status = _currentData!.status;
    Color bgColor;
    String message;
    IconData icon;
    switch (status) {
      case TripStatus.arrived:
        bgColor = const Color(0xFF00A040);
        message = 'Driver has arrived!';
        icon = Icons.check_circle;
        break;
      case TripStatus.nearby:
        bgColor = Colors.orange;
        message = 'Driver is nearby — arriving soon';
        icon = Icons.near_me;
        break;
      case TripStatus.onTheWay:
        bgColor = _primaryBlue;
        message = 'Driver is on the way';
        icon = Icons.directions_car;
        break;
      default:
        bgColor = Colors.grey.shade700;
        message = 'Trip not started';
        icon = Icons.schedule;
    }
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 10,
        left: 16,
        right: 16,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(message,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ✅ COMPACT BOTTOM SHEET
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildBottomInfoSheet() {
    final data = _currentData!;
    final driver = data.driver;
    final vehicle = data.vehicle;
    final hasPhone =
        driver?.phone != null && driver!.phone.isNotEmpty;
    final distanceKm =
        (data.distanceToCustomer / 1000).toStringAsFixed(1);
    final speedKmh = data.driverLocation?.speed != null
        ? (data.driverLocation!.speed! * 3.6).toStringAsFixed(0)
        : '0';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(22),
          topRight: Radius.circular(22),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 24,
              offset: const Offset(0, -6))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 6),
            width: 36,
            height: 3.5,
            decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                _buildCompactStat(
                  icon: Icons.location_on,
                  value: '$distanceKm km',
                  label: 'Dist',
                  color: data.status == TripStatus.nearby
                      ? Colors.orange
                      : _accentBlue,
                ),
                _buildCompactStat(
                  icon: Icons.access_time,
                  value: '${data.eta} min',
                  label: 'ETA',
                  color: _primaryBlue,
                ),
                _buildCompactStat(
                  icon: Icons.speed,
                  value: '$speedKmh km/h',
                  label: 'Speed',
                  color: _accentBlue,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D47A1), Color(0xFF1E88E5)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: _primaryBlue.withOpacity(0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withOpacity(0.5),
                          width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        driver?.name.isNotEmpty == true
                            ? driver!.name[0].toUpperCase()
                            : 'D',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          driver?.name ?? 'Unknown Driver',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.directions_car,
                                size: 13, color: Colors.white70),
                            const SizedBox(width: 4),
                            Text(
                              vehicle?.registrationNumber ?? 'N/A',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                            if (vehicle?.make != null) ...[
                              const SizedBox(width: 6),
                              Text(
                                '${vehicle!.make} ${vehicle.model ?? ''}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white60),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C853).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFF00C853)
                                .withOpacity(0.6)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF00C853),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text('LIVE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF00C853),
                                letterSpacing: 1,
                              )),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.phone_rounded,
                    label: 'Call',
                    color: hasPhone
                        ? const Color(0xFF2ECC71)
                        : Colors.grey.shade300,
                    iconColor: hasPhone
                        ? Colors.white
                        : Colors.grey.shade500,
                    onTap: hasPhone ? _callDriver : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.chat_rounded,
                    label: 'Chat',
                    color: hasPhone
                        ? _whatsAppGreen
                        : Colors.grey.shade300,
                    iconColor: hasPhone
                        ? Colors.white
                        : Colors.grey.shade500,
                    onTap: hasPhone ? _whatsAppDriver : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.share_location_rounded,
                    label: 'Share',
                    color: _accentBlue,
                    iconColor: Colors.white,
                    onTap: _shareLiveLocation,
                  ),
                ),
              ],
            ),
          ),
          if (!hasPhone) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline,
                      size: 12, color: Colors.orange.shade700),
                  const SizedBox(width: 4),
                  Text('Driver phone number not available',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.orange.shade700)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x1F0D47A1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildInfoPill(
                      icon: Icons.tag,
                      label: 'Trip',
                      value: data.trip.tripNumber,
                    ),
                  ),
                  Container(
                      width: 1,
                      height: 32,
                      color: const Color(0x1F0D47A1)),
                  Expanded(
                    child: _buildInfoPill(
                      icon: Icons.schedule,
                      label: 'Pickup',
                      value: data.trip.scheduledPickupTime,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
              height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }

  Widget _buildCompactStat({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                      overflow: TextOverflow.ellipsis),
                  Text(label,
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color iconColor,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: onTap != null
              ? [
                  BoxShadow(
                      color: color.withOpacity(0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: iconColor,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoPill({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[500],
                      letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 3),
          Text(value,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A237E)),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ============================================================================
// LIVE TRIP CARD — Customer Dashboard with Call + WhatsApp
// ============================================================================
class LiveTripCard extends StatefulWidget {
  final String tripId;
  const LiveTripCard({Key? key, required this.tripId}) : super(key: key);

  @override
  State<LiveTripCard> createState() => _LiveTripCardState();
}

class _LiveTripCardState extends State<LiveTripCard>
    with SingleTickerProviderStateMixin {
  final EnhancedCustomerTrackingService _trackingService =
      EnhancedCustomerTrackingService();
  TripTrackingData? _data;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const Color _whatsAppGreen = Color(0xFF25D366);
  static const Color _primaryBlue = Color(0xFF0D47A1);
  static const Color _accentBlue = Color(0xFF1E88E5);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadData();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final data =
        await _trackingService.getTripTrackingData(widget.tripId);
    if (mounted) setState(() => _data = data);
  }

  Future<void> _callDriver() async {
    final phone = _data?.driver?.phone ?? '';
    if (phone.isEmpty) return;
    final uri = Uri(
        scheme: 'tel',
        path: phone.replaceAll(RegExp(r'[^\d+]'), ''));
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _whatsAppDriver(BuildContext context) async {
    final phone = _data?.driver?.phone ?? '';
    final name = _data?.driver?.name ?? 'Driver';
    if (phone.isEmpty) return;
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _buildQuickTemplateSheet(name),
    );
    if (selected == null) return;
    final encodedMsg = Uri.encodeComponent(selected);
    final uri =
        Uri.parse('https://wa.me/$cleanPhone?text=$encodedMsg');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildQuickTemplateSheet(String driverName) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
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
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.chat, color: _whatsAppGreen),
                const SizedBox(width: 10),
                Expanded(
                    child: Text('Message $driverName',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16))),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon:
                      const Icon(Icons.close, color: Colors.grey),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight:
                    MediaQuery.of(context).size.height * 0.45),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              children: CustomerWhatsAppTemplates.templates
                  .map((t) => Card(
                        margin:
                            const EdgeInsets.only(bottom: 8),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(10),
                          side: BorderSide(
                              color:
                                  _whatsAppGreen.withOpacity(0.2)),
                        ),
                        child: ListTile(
                          leading: Text(
                              t['label']!.split(' ').first,
                              style: const TextStyle(
                                  fontSize: 22)),
                          title: Text(
                              t['label']!
                                  .split(' ')
                                  .skip(1)
                                  .join(' '),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          subtitle: Text(t['message']!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600])),
                          trailing: const Icon(Icons.send,
                              color: _whatsAppGreen, size: 18),
                          onTap: () => Navigator.pop(
                              context, t['message']),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null) return const SizedBox.shrink();

    final distanceKm =
        (_data!.distanceToCustomer / 1000).toStringAsFixed(1);
    final hasPhone = _data!.driver?.phone?.isNotEmpty == true;
    final driverName = _data!.driver?.name ?? 'Unknown';
    final vehicleNumber =
        _data!.vehicle?.registrationNumber ?? 'N/A';
    final initial =
        driverName.isNotEmpty ? driverName[0].toUpperCase() : 'D';
    final progress =
        (1 - (_data!.distanceToCustomer / 5000)).clamp(0.0, 1.0);

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFFEBF0FF), Color(0xFFDCEAFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: const Color(0x1A0D47A1)),
          boxShadow: [
            BoxShadow(
              color: _primaryBlue.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 6),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D47A1), Color(0xFF1E88E5)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withOpacity(0.5),
                          width: 1.5),
                    ),
                    child: Center(
                      child: Text(initial,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          )),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(driverName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            )),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.directions_car,
                                size: 13, color: Colors.white70),
                            const SizedBox(width: 4),
                            Text(vehicleNumber,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                )),
                          ],
                        ),
                      ],
                    ),
                  ),
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C853)
                            .withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFF00C853)
                                .withOpacity(0.7)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                                color: Color(0xFF00C853),
                                shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 4),
                          const Text('LIVE',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF00C853),
                                  letterSpacing: 1)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: [
                  Text('$distanceKm km away',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _primaryBlue,
                      )),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _accentBlue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('⏱ ETA: ${_data!.eta} min',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 11)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white.withOpacity(0.5),
                  color: _accentBlue,
                  minHeight: 7,
                ),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EnhancedTrackingScreen(
                              tripId: widget.tripId),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 11),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF0D47A1),
                              Color(0xFF1E88E5)
                            ],
                          ),
                          borderRadius:
                              BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: _primaryBlue.withOpacity(0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            )
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            Icon(Icons.map_rounded,
                                color: Colors.white, size: 18),
                            SizedBox(width: 6),
                            Text('Track Live',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                )),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildCircleActionBtn(
                    icon: Icons.phone_rounded,
                    color: hasPhone
                        ? const Color(0xFF2ECC71)
                        : Colors.grey.shade300,
                    iconColor: hasPhone
                        ? Colors.white
                        : Colors.grey.shade500,
                    onTap: hasPhone ? _callDriver : null,
                  ),
                  const SizedBox(width: 8),
                  _buildCircleActionBtn(
                    icon: Icons.chat_rounded,
                    color: hasPhone
                        ? _whatsAppGreen
                        : Colors.grey.shade300,
                    iconColor: hasPhone
                        ? Colors.white
                        : Colors.grey.shade500,
                    onTap: hasPhone
                        ? () => _whatsAppDriver(context)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircleActionBtn({
    required IconData icon,
    required Color color,
    required Color iconColor,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: onTap != null
              ? [
                  BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ]
              : null,
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
    );
  }
}