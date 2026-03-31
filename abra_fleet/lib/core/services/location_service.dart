// File: lib/core/services/location_service.dart
// Enhanced location service with hybrid search approach

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:abra_fleet/core/models/place_suggestion.dart';
import 'package:abra_fleet/core/services/enhanced_location_search_service.dart';

class LocationData {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? altitude;
  final double? speed;
  final double? heading;
  final DateTime timestamp;
  final String? address;

  const LocationData({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.altitude,
    this.speed,
    this.heading,
    required this.timestamp,
    this.address,
  });

  LatLng get latLng => LatLng(latitude, longitude);

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'altitude': altitude,
    'speed': speed,
    'heading': heading,
    'timestamp': timestamp.toIso8601String(),
    'address': address,
  };

  factory LocationData.fromJson(Map<String, dynamic> json) => LocationData(
    latitude: json['latitude']?.toDouble() ?? 0.0,
    longitude: json['longitude']?.toDouble() ?? 0.0,
    accuracy: json['accuracy']?.toDouble(),
    altitude: json['altitude']?.toDouble(),
    speed: json['speed']?.toDouble(),
    heading: json['heading']?.toDouble(),
    timestamp: DateTime.parse(json['timestamp']),
    address: json['address'],
  );

  @override
  String toString() => 'LocationData(lat: $latitude, lng: $longitude, address: $address)';
}

enum LocationServiceStatus {
  unknown,
  disabled,
  denied,
  deniedForever,
  whileInUse,
  always,
  unableToDetermine,
}

class LocationService extends ChangeNotifier {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  LocationData? _currentLocation;
  LocationServiceStatus _status = LocationServiceStatus.unknown;
  StreamSubscription<Position>? _positionStreamSubscription;
  String? _errorMessage;
  bool _isTracking = false;

  // Enhanced search service
  final EnhancedLocationSearchService _enhancedSearch = EnhancedLocationSearchService();

  // Rate limiting for API calls
  DateTime? _lastApiCall;
  static const Duration _apiCallDelay = Duration(milliseconds: 500);

  // Getters
  LocationData? get currentLocation => _currentLocation;
  LocationServiceStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isTracking => _isTracking;
  bool get hasLocationPermission => _status == LocationServiceStatus.whileInUse || _status == LocationServiceStatus.always;

  /// Initialize the location service and check permissions
  Future<bool> initialize() async {
    try {
      _errorMessage = null;
      
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _status = LocationServiceStatus.disabled;
        _errorMessage = 'Location services are disabled. Please enable location services.';
        notifyListeners();
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _status = LocationServiceStatus.denied;
          _errorMessage = 'Location permissions are denied.';
          notifyListeners();
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _status = LocationServiceStatus.deniedForever;
        _errorMessage = 'Location permissions are permanently denied. Please enable them in settings.';
        notifyListeners();
        return false;
      }

      switch (permission) {
        case LocationPermission.whileInUse:
          _status = LocationServiceStatus.whileInUse;
          break;
        case LocationPermission.always:
          _status = LocationServiceStatus.always;
          break;
        default:
          _status = LocationServiceStatus.unableToDetermine;
          break;
      }

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to initialize location service: $e';
      _status = LocationServiceStatus.unableToDetermine;
      notifyListeners();
      return false;
    }
  }

  /// Get current location once with improved accuracy
  Future<LocationData?> getCurrentLocation({bool withAddress = false}) async {
    try {
      if (!hasLocationPermission) {
        bool initialized = await initialize();
        if (!initialized) return null;
      }

      _errorMessage = null;
      
      // Use best accuracy for precise location capture
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 15), // Wait up to 15 seconds for accurate GPS
      );

      // Check if accuracy is acceptable (within 50 meters)
      if (position.accuracy > 50) {
        if (kDebugMode) {
          print('⚠️ GPS accuracy is low: ${position.accuracy}m - trying again...');
        }
        
        // Try one more time with a longer timeout
        try {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.best,
            timeLimit: const Duration(seconds: 20),
          );
        } catch (e) {
          if (kDebugMode) {
            print('Second attempt failed, using first position: $e');
          }
        }
      }

      if (kDebugMode) {
        print('📍 GPS Location captured:');
        print('   Latitude: ${position.latitude}');
        print('   Longitude: ${position.longitude}');
        print('   Accuracy: ${position.accuracy}m');
        print('   Timestamp: ${position.timestamp}');
      }

      String? address;
      if (withAddress) {
        address = await _getAddressFromCoordinates(position.latitude, position.longitude);
        if (kDebugMode) {
          print('   Address: $address');
        }
      }

      _currentLocation = LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        altitude: position.altitude,
        speed: position.speed,
        heading: position.heading,
        timestamp: position.timestamp,
        address: address,
      );

      notifyListeners();
      return _currentLocation;
    } catch (e) {
      _errorMessage = 'Failed to get current location: $e';
      if (kDebugMode) {
        print('❌ Location error: $e');
      }
      notifyListeners();
      return null;
    }
  }

  /// Start real-time location tracking
  Future<bool> startTracking({
    bool highAccuracy = true,
    bool withAddress = false,
    Function(LocationData)? onLocationUpdate,
  }) async {
    try {
      if (_isTracking) {
        await stopTracking();
      }

      if (!hasLocationPermission) {
        bool initialized = await initialize();
        if (!initialized) return false;
      }

      _errorMessage = null;

      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: highAccuracy ? LocationAccuracy.high : LocationAccuracy.medium,
          distanceFilter: highAccuracy ? 5 : 50,
        ),
      ).listen(
        (Position position) async {
          String? address;
          if (withAddress) {
            address = await _getAddressFromCoordinates(position.latitude, position.longitude);
          }

          _currentLocation = LocationData(
            latitude: position.latitude,
            longitude: position.longitude,
            accuracy: position.accuracy,
            altitude: position.altitude,
            speed: position.speed,
            heading: position.heading,
            timestamp: position.timestamp,
            address: address,
          );

          notifyListeners();
          onLocationUpdate?.call(_currentLocation!);
        },
        onError: (error) {
          _errorMessage = 'Location tracking error: $error';
          notifyListeners();
        },
      );

      _isTracking = true;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to start location tracking: $e';
      notifyListeners();
      return false;
    }
  }

  /// Stop location tracking
  Future<void> stopTracking() async {
    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _isTracking = false;
    notifyListeners();
  }

  /// Get address from coordinates (reverse geocoding)
  Future<String?> _getAddressFromCoordinates(double latitude, double longitude) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        return '${place.street ?? ''}, ${place.locality ?? ''}, ${place.administrativeArea ?? ''}, ${place.country ?? ''}'
            .replaceAll(RegExp(r'^,\s*|,\s*$'), '')
            .replaceAll(RegExp(r',\s*,'), ',');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Reverse geocoding failed: $e');
      }
    }
    return null;
  }

  /// Get coordinates from address using native geocoding (primary method)
  Future<LocationData?> getLocationFromAddress(String address) async {
    try {
      // First try with native geocoding service (iOS/Android)
      List<Location> locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        Location location = locations[0];
        return LocationData(
          latitude: location.latitude,
          longitude: location.longitude,
          timestamp: DateTime.now(),
          address: address,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Native geocoding failed for "$address": $e');
      }
      // Continue to try other methods
    }

    // If native geocoding fails, try manual parsing
    return await _tryManualAddressParsing(address);
  }

  /// Manual address parsing for detailed addresses
  Future<LocationData?> _tryManualAddressParsing(String fullAddress) async {
    try {
      // Extract key components from the address
      final addressParts = _parseDetailedAddress(fullAddress);
      
      if (kDebugMode) {
        print('Parsed address parts: $addressParts');
      }

      // Try different combinations of address parts
      final searchQueries = _generateSearchQueries(addressParts);
      
      for (final query in searchQueries) {
        try {
          if (kDebugMode) {
            print('Trying search query: "$query"');
          }
          
          // First try with native geocoding
          final locations = await locationFromAddress(query);
          if (locations.isNotEmpty) {
            final location = locations.first;
            return LocationData(
              latitude: location.latitude,
              longitude: location.longitude,
              timestamp: DateTime.now(),
              address: fullAddress,
            );
          }
        } catch (e) {
          if (kDebugMode) {
            print('Query "$query" failed with native geocoding: $e');
          }
          // Continue with next query
        }
      }

      // If all native geocoding attempts fail, try Nominatim
      for (final query in searchQueries) {
        try {
          final suggestions = await _searchWithNominatim(query, 1);
          if (suggestions.isNotEmpty && suggestions.first.coordinates != null) {
            final coords = suggestions.first.coordinates!;
            return LocationData(
              latitude: coords.latitude,
              longitude: coords.longitude,
              timestamp: DateTime.now(),
              address: fullAddress,
            );
          }
        } catch (e) {
          if (kDebugMode) {
            print('Query "$query" failed with Nominatim: $e');
          }
        }
      }

    } catch (e) {
      if (kDebugMode) {
        print('Manual address parsing failed: $e');
      }
    }

    return null;
  }

  /// Parse detailed address into components
  Map<String, String> _parseDetailedAddress(String address) {
    final parts = <String, String>{};
    
    // Common patterns in Indian addresses
    final patterns = {
      'pincode': RegExp(r'\b(\d{6})\b'),
      'state': RegExp(r'\b(karnataka|bengaluru|bangalore)\b', caseSensitive: false),
      'area': RegExp(r'\b(layout|nagar|road|street|main|cross|block)\b', caseSensitive: false),
      'landmark': RegExp(r'\b(near|opposite|behind|front)\s+(.+?)(?:,|$)', caseSensitive: false),
    };

    // Extract pincode
    final pincodeMatch = patterns['pincode']!.firstMatch(address);
    if (pincodeMatch != null) {
      parts['pincode'] = pincodeMatch.group(1)!;
    }

    // Extract area/locality names
    final addressSplit = address.split(',').map((s) => s.trim()).toList();
    
    for (int i = 0; i < addressSplit.length; i++) {
      final part = addressSplit[i];
      
      if (part.toLowerCase().contains('layout') || 
          part.toLowerCase().contains('nagar') ||
          part.toLowerCase().contains('block')) {
        parts['locality'] = part;
        break;
      }
    }

    // Extract main components
    if (addressSplit.length > 2) {
      parts['area'] = addressSplit[addressSplit.length - 3];
      parts['city'] = addressSplit[addressSplit.length - 2];
      parts['state'] = addressSplit.last;
    }

    return parts;
  }

  /// Generate search queries from address parts
  List<String> _generateSearchQueries(Map<String, String> parts) {
    final queries = <String>[];
    
    // Strategy 1: Use locality + city + pincode
    if (parts['locality'] != null && parts['city'] != null && parts['pincode'] != null) {
      queries.add('${parts['locality']}, ${parts['city']}, ${parts['pincode']}');
    }
    
    // Strategy 2: Use area + city + state
    if (parts['area'] != null && parts['city'] != null) {
      queries.add('${parts['area']}, ${parts['city']}, Karnataka');
    }
    
    // Strategy 3: Use locality + city
    if (parts['locality'] != null && parts['city'] != null) {
      queries.add('${parts['locality']}, ${parts['city']}');
    }
    
    // Strategy 4: Just pincode
    if (parts['pincode'] != null) {
      queries.add(parts['pincode']!);
    }
    
    // Strategy 5: Area + Bangalore
    if (parts['area'] != null) {
      queries.add('${parts['area']}, Bangalore');
      queries.add('${parts['area']}, Bengaluru');
    }
    
    // Strategy 6: Locality + Bangalore  
    if (parts['locality'] != null) {
      queries.add('${parts['locality']}, Bangalore');
      queries.add('${parts['locality']}, Bengaluru');
    }

    return queries.where((q) => q.isNotEmpty).toList();
  }

  /// Get LocationData from coordinates (reverse geocoding)
  Future<LocationData?> getLocationFromCoordinates(double latitude, double longitude) async {
    try {
      // Try enhanced reverse geocoding first
      final enhancedResult = await _enhancedSearch.reverseGeocode(latitude, longitude);
      
      if (enhancedResult != null && enhancedResult['formatted_address'] != null) {
        final formattedAddress = enhancedResult['formatted_address'] as String;
        if (kDebugMode) {
          print('✓ Enhanced reverse geocoding successful: $formattedAddress');
        }
        return LocationData(
          latitude: latitude,
          longitude: longitude,
          timestamp: DateTime.now(),
          address: formattedAddress,
        );
      }
      
      // Fallback to native geocoding
      if (kDebugMode) {
        print('Enhanced reverse geocoding returned null, trying native...');
      }
      String? address = await _getAddressFromCoordinates(latitude, longitude);
      return LocationData(
        latitude: latitude,
        longitude: longitude,
        timestamp: DateTime.now(),
        address: address,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Reverse geocoding error: $e');
      }
      _errorMessage = 'Failed to get location from coordinates: $e';
      notifyListeners();
    }
    return null;
  }

  /// Calculate distance between two points in meters
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  /// Calculate bearing between two points in degrees
  double calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.bearingBetween(lat1, lon1, lat2, lon2);
  }

  /// Rate limiting helper
  Future<void> _waitForApiLimit() async {
    if (_lastApiCall != null) {
      final timeSinceLastCall = DateTime.now().difference(_lastApiCall!);
      if (timeSinceLastCall < _apiCallDelay) {
        await Future.delayed(_apiCallDelay - timeSinceLastCall);
      }
    }
    _lastApiCall = DateTime.now();
  }

  /// Enhanced search for places with hybrid approach
  Future<List<PlaceSuggestion>> searchPlaces(String query, {int limit = 5}) async {
    if (query.trim().isEmpty) return [];

    if (kDebugMode) {
      print('\n=== Starting enhanced search for: "$query" ===');
    }

    try {
      // Use the enhanced search service for better results
      final results = await _enhancedSearch.searchPlaces(
        query,
        limit: limit,
        nearLocation: _currentLocation != null 
            ? LatLng(_currentLocation!.latitude, _currentLocation!.longitude)
            : null,
      );

      if (kDebugMode) {
        print('=== Enhanced search returned ${results.length} results ===');
        for (int i = 0; i < results.length; i++) {
          final result = results[i];
          print('${i + 1}. ${result.title}');
          print('    ${result.subtitle}');
          print('    Coords: ${result.coordinates}');
        }
        print('================================\n');
      }
      
      return results;

    } catch (e) {
      if (kDebugMode) {
        print('❌ Enhanced search failed, falling back to legacy search: $e');
      }
      
      // Fallback to legacy search if enhanced search fails
      return await _legacySearchPlaces(query, limit: limit);
    }
  }

  /// Legacy search method as fallback
  Future<List<PlaceSuggestion>> _legacySearchPlaces(String query, {int limit = 5}) async {
    if (query.trim().isEmpty) return [];

    try {
      List<PlaceSuggestion> results = [];

      // Strategy 1: Try native geocoding first (most reliable for addresses)
      if (_isDetailedAddress(query)) {
        final locationData = await getLocationFromAddress(query);
        if (locationData != null) {
          results.add(PlaceSuggestion(
            title: _extractMainTitle(query),
            subtitle: query,
            coordinates: LatLng(locationData.latitude, locationData.longitude),
            type: PlaceSuggestionType.address,
          ));
        }
      }

      // Strategy 2: Try Nominatim with original query
      await _waitForApiLimit();
      final directResults = await _searchWithNominatim(query.trim(), limit);
      results.addAll(directResults);

      // Strategy 3: If no results and query looks like a business/detailed address
      if (results.isEmpty && (_isCompanyQuery(query) || _isDetailedAddress(query))) {
        final contextResults = await _searchWithLocationContext(query.trim(), limit);
        results.addAll(contextResults);
      }

      // Strategy 4: Try simplified query if still no results
      if (results.isEmpty) {
        final simplifiedQuery = _simplifyQuery(query.trim());
        if (simplifiedQuery != query.trim()) {
          await _waitForApiLimit();
          final simplifiedResults = await _searchWithNominatim(simplifiedQuery, limit);
          results.addAll(simplifiedResults);
        }
      }

      // Remove duplicates and limit results
      final uniqueResults = _removeDuplicateSuggestions(results);
      return uniqueResults.take(limit).toList();

    } catch (e) {
      if (kDebugMode) {
        print('❌ Legacy search failed: $e');
      }
      return [];
    }
  }

  /// Check if query is a detailed address (contains multiple components)
  bool _isDetailedAddress(String query) {
    final addressIndicators = [
      RegExp(r'\d{6}'), // Pincode
      RegExp(r'\d+[a-zA-Z]?\s*(st|nd|rd|th)?\s+(main|cross|road|street)', caseSensitive: false),
      RegExp(r'(layout|block|nagar|area|sector)', caseSensitive: false),
      RegExp(r'(pg|paying\s*guest|hostel|apartment)', caseSensitive: false),
      RegExp(r',.*,.*,'), // Multiple commas indicating structured address
    ];

    return addressIndicators.any((pattern) => pattern.hasMatch(query)) || 
           query.split(',').length > 2;
  }

  /// Extract main title from detailed address
  String _extractMainTitle(String fullAddress) {
    final parts = fullAddress.split(',').map((s) => s.trim()).toList();
    if (parts.isNotEmpty) {
      // Return the first meaningful part
      final firstPart = parts[0];
      if (firstPart.length > 5) { // Avoid very short parts
        return firstPart;
      } else if (parts.length > 1) {
        return parts[1];
      }
    }
    return fullAddress.length > 50 ? '${fullAddress.substring(0, 47)}...' : fullAddress;
  }

  /// Check if query contains company/business names
  bool _isCompanyQuery(String query) {
    final businessKeywords = [
      'infosys', 'wipro', 'tcs', 'accenture', 'microsoft', 'google', 'amazon', 'flipkart',
      'office', 'headquarters', 'campus', 'tech park', 'it park', 'pg', 'hostel',
      'paying guest', 'apartment', 'residency'
    ];
    final lowerQuery = query.toLowerCase();
    return businessKeywords.any((keyword) => lowerQuery.contains(keyword));
  }

  /// Search with location context for better business results
  Future<List<PlaceSuggestion>> _searchWithLocationContext(String query, int limit) async {
    final variations = [
      '$query bangalore',
      '$query bengaluru', 
      '$query karnataka',
      '$query india',
    ];

    for (final variation in variations) {
      try {
        await _waitForApiLimit();
        final results = await _searchWithNominatim(variation, limit);
        if (results.isNotEmpty) {
          return results;
        }
      } catch (e) {
        if (kDebugMode) {
          print('Search variation failed: $variation - $e');
        }
      }
    }
    return [];
  }

  /// Simplify query by removing common words
  String _simplifyQuery(String query) {
    final wordsToRemove = ['the', 'a', 'an', 'at', 'in', 'on', 'near', 'close to', 'next to', 'for', 'ladies', 'gents'];
    String simplified = query.toLowerCase();
    
    for (final word in wordsToRemove) {
      simplified = simplified.replaceAll(RegExp(r'\b' + word + r'\b'), ' ');
    }
    
    // Clean up extra spaces and punctuation
    simplified = simplified.replaceAll(RegExp(r'[,\.]'), ' ');
    simplified = simplified.replaceAll(RegExp(r'\s+'), ' ').trim();
    return simplified.isEmpty ? query : simplified;
  }

  /// Core Nominatim search with improved error handling
  Future<List<PlaceSuggestion>> _searchWithNominatim(String query, int limit) async {
    final encodedQuery = Uri.encodeComponent(query);
    
    final url = 'https://nominatim.openstreetmap.org/search'
        '?q=$encodedQuery'
        '&format=json'
        '&limit=$limit'
        '&addressdetails=1'
        '&countrycodes=in'
        '&bounded=0'
        '&dedupe=1'
        '&extratags=1'
        '&namedetails=1';

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': 'AbraFleet/1.0.0 (Fleet Management App)',
        'Accept': 'application/json',
        'Accept-Language': 'en',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final List<dynamic> results = json.decode(response.body);
      
      if (results.isEmpty) {
        if (kDebugMode) {
          print('No results found for query: $query');
        }
        return [];
      }

      return results
          .map((json) {
            try {
              final suggestion = PlaceSuggestion.fromNominatim(json);
              return suggestion;
            } catch (e) {
              if (kDebugMode) {
                print('Error creating suggestion from: $json - $e');
              }
              return null;
            }
          })
          .where((suggestion) => suggestion != null && suggestion.coordinates != null)
          .cast<PlaceSuggestion>()
          .toList();
    } else {
      throw Exception('Search API returned status: ${response.statusCode} - ${response.body}');
    }
  }

  /// Remove duplicate suggestions based on coordinates and title similarity
  List<PlaceSuggestion> _removeDuplicateSuggestions(List<PlaceSuggestion> suggestions) {
    final Map<String, PlaceSuggestion> uniqueMap = {};
    
    for (final suggestion in suggestions) {
      if (suggestion.coordinates != null) {
        final key = '${suggestion.coordinates!.latitude.toStringAsFixed(4)}_'
                   '${suggestion.coordinates!.longitude.toStringAsFixed(4)}_'
                   '${suggestion.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}';
        
        if (!uniqueMap.containsKey(key) || 
            suggestion.subtitle.length > uniqueMap[key]!.subtitle.length) {
          uniqueMap[key] = suggestion;
        }
      }
    }
    
    return uniqueMap.values.toList();
  }

  /// Test search functionality (for debugging)
  Future<void> testSearch(String query) async {
    if (kDebugMode) {
      print('\n🔍 Testing search for: "$query"');
      try {
        final results = await searchPlaces(query);
        print('📍 Found ${results.length} results:');
        for (final result in results) {
          print('  - ${result.title} (${result.coordinates})');
          print('    ${result.subtitle}');
        }
      } catch (e) {
        print('❌ Test search failed: $e');
      }
      print('');
    }
  }

  /// Open device location settings
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }

  /// Open app settings
  Future<bool> openAppSettings() async {
    return await Geolocator.openAppSettings();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}

/// Extension methods for LocationData
extension LocationDataExtensions on LocationData {
  /// Get formatted address or coordinates
  String get displayText => address ?? '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  
  /// Get short address (first part only)
  String get shortAddress {
    if (address == null) return '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
    List<String> parts = address!.split(',');
    return parts.isNotEmpty ? parts[0].trim() : address!;
  }
}