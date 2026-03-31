// lib/core/services/geocoding_service.dart

import 'package:geocoding/geocoding.dart';

class GeocodingService {
  static final GeocodingService _instance = GeocodingService._internal();
  factory GeocodingService() => _instance;
  GeocodingService._internal();

  // Cache to avoid repeated API calls for same coordinates
  final Map<String, String> _addressCache = {};

  /// Convert coordinates string to readable address
  /// Accepts formats: "lat, lng" or "address string"
  Future<String> getAddressFromLocation(String location) async {
    if (location.isEmpty) return 'Unknown location';

    // Check cache first
    if (_addressCache.containsKey(location)) {
      return _addressCache[location]!;
    }

    // If it's already an address (contains letters), return it
    if (RegExp(r'[a-zA-Z]').hasMatch(location)) {
      _addressCache[location] = location;
      return location;
    }

    // Try to parse as coordinates
    try {
      final parts = location.split(',').map((e) => e.trim()).toList();
      if (parts.length != 2) {
        _addressCache[location] = location;
        return location;
      }

      final lat = double.tryParse(parts[0]);
      final lng = double.tryParse(parts[1]);

      if (lat == null || lng == null) {
        _addressCache[location] = location;
        return location;
      }

      // Perform reverse geocoding
      final placemarks = await placemarkFromCoordinates(lat, lng);
      
      if (placemarks.isEmpty) {
        _addressCache[location] = location;
        return location;
      }

      final place = placemarks.first;
      final address = _formatAddress(place);
      
      _addressCache[location] = address;
      return address;
    } catch (e) {
      print('Geocoding error for $location: $e');
      _addressCache[location] = location;
      return location;
    }
  }

  String _formatAddress(Placemark place) {
    final parts = <String>[];
    
    if (place.street != null && place.street!.isNotEmpty) {
      parts.add(place.street!);
    }
    if (place.subLocality != null && place.subLocality!.isNotEmpty) {
      parts.add(place.subLocality!);
    }
    if (place.locality != null && place.locality!.isNotEmpty) {
      parts.add(place.locality!);
    }
    if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
      parts.add(place.administrativeArea!);
    }
    
    return parts.isEmpty ? 'Unknown location' : parts.join(', ');
  }

  /// Convert latitude and longitude to readable address
  Future<String> getAddressFromCoordinates(double latitude, double longitude) async {
    final locationKey = '$latitude,$longitude';
    
    // Check cache first
    if (_addressCache.containsKey(locationKey)) {
      return _addressCache[locationKey]!;
    }

    try {
      // Perform reverse geocoding
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      
      if (placemarks.isEmpty) {
        final fallback = 'Location ($latitude, $longitude)';
        _addressCache[locationKey] = fallback;
        return fallback;
      }

      final place = placemarks.first;
      final address = _formatAddress(place);
      
      _addressCache[locationKey] = address;
      return address;
    } catch (e) {
      print('Geocoding error for coordinates $latitude, $longitude: $e');
      final fallback = 'Location ($latitude, $longitude)';
      _addressCache[locationKey] = fallback;
      return fallback;
    }
  }

  /// Clear the address cache
  void clearCache() {
    _addressCache.clear();
  }
}
