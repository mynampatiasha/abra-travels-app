// lib/features/tracking/screens/map_widget_stub.dart
// Used on Flutter Web — WebViewController is not available on web.
// Exports no-op stubs so the main screen can compile on all platforms.

import 'package:flutter/material.dart';
import 'package:abra_fleet/core/services/enhanced_customer_tracking_service.dart';

/// No-op controller — never instantiated on web
class LeafletMapController {
  void updateMapData(TripTrackingData data) {}
}

/// No-op widget — never rendered on web (flutter_map is used instead)
class LeafletMapWidget extends StatelessWidget {
  final void Function(LeafletMapController controller)? onControllerReady;

  const LeafletMapWidget({Key? key, this.onControllerReady}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Should never render on web; flutter_map is used via kIsWeb guard
    return const SizedBox.shrink();
  }
}