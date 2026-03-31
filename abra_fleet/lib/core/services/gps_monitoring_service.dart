// lib/core/services/gps_monitoring_service.dart
// ============================================================================
// GPS MONITORING SERVICE - Web-Safe GPS Status Monitoring
// ============================================================================
// ✅ Provides platform-safe GPS status monitoring
// ✅ Works on mobile (Android/iOS) with real GPS status stream
// ✅ Works on web with mock/fallback implementation (no-op)
// ✅ Prevents "Unsupported operation" errors on web
// ============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';

/// GPS Status Monitoring Service
/// Provides platform-safe GPS status monitoring that works on both mobile and web
class GPSMonitoringService {
  StreamSubscription<ServiceStatus>? _subscription;
  StreamController<ServiceStatus>? _mockController;

  /// Start monitoring GPS status
  /// Returns a stream that emits GPS status changes
  /// On web, returns an empty stream (no-op) since GPS monitoring is not supported
  Stream<ServiceStatus> getServiceStatusStream() {
    // CRITICAL: Check web platform FIRST and return immediately
    if (kIsWeb) {
      print('🌐 Web platform detected - GPS status monitoring not supported');
      print('🔄 Returning empty stream (no GPS monitoring on web)');
      
      // Create a broadcast stream controller if not already created
      _mockController ??= StreamController<ServiceStatus>.broadcast();
      
      // Return the empty stream - no GPS status updates on web
      return _mockController!.stream;
    }
    
    // Mobile platform: Use real GPS status stream
    print('📱 Mobile platform detected - using real GPS status stream');
    
    // Return the real GPS status stream for mobile platforms only
    return _getMobileGPSStream();
  }
  
  /// Get the real GPS status stream (mobile only)
  /// This is a separate method to ensure platform checks work correctly
  Stream<ServiceStatus> _getMobileGPSStream() {
    try {
      // This method is only available on mobile platforms
      // The geolocator package will handle platform-specific implementation
      return Geolocator.getServiceStatusStream();
    } catch (e) {
      // Fallback if getServiceStatusStream fails for any reason
      print('⚠️ getServiceStatusStream error: $e');
      print('🔄 Falling back to empty stream');
      
      // Return an empty broadcast stream as fallback
      _mockController ??= StreamController<ServiceStatus>.broadcast();
      return _mockController!.stream;
    }
  }

  /// Check if GPS is currently enabled
  /// Works on both mobile and web
  Future<bool> isLocationServiceEnabled() async {
    try {
      if (kIsWeb) {
        // On web, always return true (browser handles location permissions)
        print('🌐 Web platform - location service check skipped (always true)');
        return true;
      }
      
      // On mobile, check actual GPS status
      final enabled = await Geolocator.isLocationServiceEnabled();
      print('📱 Mobile platform - GPS enabled: $enabled');
      return enabled;
      
    } catch (e) {
      print('⚠️ Error checking location service: $e');
      // On error, assume enabled to avoid blocking the app
      return true;
    }
  }

  /// Open location settings
  /// Works on both mobile and web
  Future<void> openLocationSettings() async {
    try {
      if (kIsWeb) {
        print('🌐 Web platform - cannot open location settings');
        print('ℹ️ Browser will prompt for location permission when needed');
        return;
      }
      
      print('📱 Opening location settings...');
      await Geolocator.openLocationSettings();
      
    } catch (e) {
      print('⚠️ Error opening location settings: $e');
      // Silently fail - not critical
    }
  }

  /// Dispose and clean up resources
  void dispose() {
    try {
      _subscription?.cancel();
      _subscription = null;
      
      _mockController?.close();
      _mockController = null;
      
      print('🧹 GPS Monitoring Service disposed');
    } catch (e) {
      print('⚠️ Error disposing GPS monitoring service: $e');
    }
  }
}
