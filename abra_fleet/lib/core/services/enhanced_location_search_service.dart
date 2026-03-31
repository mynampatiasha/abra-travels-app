// lib/core/services/enhanced_location_search_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:abra_fleet/core/models/place_suggestion.dart';

/// Enhanced location search service with Google Maps-like functionality
/// Uses Nominatim (OpenStreetMap) with improved search algorithms
class EnhancedLocationSearchService {
  static final EnhancedLocationSearchService _instance = EnhancedLocationSearchService._internal();
  factory EnhancedLocationSearchService() => _instance;
  EnhancedLocationSearchService._internal();

  // Nominatim API endpoint
  static const String _nominatimBaseUrl = 'https://nominatim.openstreetmap.org';
  
  // Cache for search results
  final Map<String, List<PlaceSuggestion>> _searchCache = {};
  final Map<String, Map<String, dynamic>> _reverseGeocodeCache = {};
  
  // Rate limiting
  DateTime? _lastRequestTime;
  static const Duration _minRequestInterval = Duration(milliseconds: 1000);

  /// Search for places with enhanced accuracy
  Future<List<PlaceSuggestion>> searchPlaces(
    String query, {
    int limit = 10,
    LatLng? nearLocation,
    String? countryCode = 'in', // Default to India
  }) async {
    if (query.trim().isEmpty) return [];

    // Check cache first
    final cacheKey = '$query|$limit|${nearLocation?.latitude}|${nearLocation?.longitude}';
    if (_searchCache.containsKey(cacheKey)) {
      return _searchCache[cacheKey]!;
    }

    await _respectRateLimit();

    try {
      // Build search query with enhanced parameters
      final searchQuery = _enhanceSearchQuery(query);
      
      final uri = Uri.parse('$_nominatimBaseUrl/search').replace(
        queryParameters: {
          'q': searchQuery,
          'format': 'json',
          'addressdetails': '1',
          'limit': limit.toString(),
          'countrycodes': countryCode ?? 'in',
          'dedupe': '1', // Remove duplicate results
          'namedetails': '1',
          'extratags': '1',
          if (nearLocation != null) ...{
            'viewbox': _createViewBox(nearLocation),
            'bounded': '0', // Don't strictly limit to viewbox
          },
        },
      );

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'AbraFleet/1.0 (Fleet Management App)',
          'Accept-Language': 'en',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        
        final suggestions = data.map((item) {
          return _parsePlaceSuggestion(item, query);
        }).where((suggestion) {
          // Filter out results without coordinates
          return suggestion.coordinates != null;
        }).toList();

        // Sort by relevance
        suggestions.sort((a, b) => _calculateRelevanceScore(b, query, nearLocation)
            .compareTo(_calculateRelevanceScore(a, query, nearLocation)));

        // Cache the results
        _searchCache[cacheKey] = suggestions;
        
        // Limit cache size
        if (_searchCache.length > 100) {
          _searchCache.remove(_searchCache.keys.first);
        }

        return suggestions;
      } else {
        throw Exception('Search failed with status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Enhanced search error: $e');
      return [];
    }
  }

  /// Get detailed address from coordinates (reverse geocoding)
  Future<Map<String, dynamic>?> reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    final cacheKey = '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';
    
    if (_reverseGeocodeCache.containsKey(cacheKey)) {
      return _reverseGeocodeCache[cacheKey];
    }

    await _respectRateLimit();

    try {
      final uri = Uri.parse('$_nominatimBaseUrl/reverse').replace(
        queryParameters: {
          'lat': latitude.toString(),
          'lon': longitude.toString(),
          'format': 'json',
          'addressdetails': '1',
          'namedetails': '1',
          'zoom': '18', // Maximum detail level
        },
      );

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'AbraFleet/1.0 (Fleet Management App)',
          'Accept-Language': 'en',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        final result = {
          'display_name': data['display_name'] ?? '',
          'address': data['address'] ?? {},
          'lat': data['lat'] ?? latitude.toString(),
          'lon': data['lon'] ?? longitude.toString(),
          'formatted_address': _formatAddress(data['address'] ?? {}),
        };

        _reverseGeocodeCache[cacheKey] = result;
        
        if (_reverseGeocodeCache.length > 50) {
          _reverseGeocodeCache.remove(_reverseGeocodeCache.keys.first);
        }

        return result;
      }
    } catch (e) {
      debugPrint('Reverse geocode error: $e');
    }

    return null;
  }

  /// Get autocomplete suggestions as user types (like Google Maps)
  Future<List<PlaceSuggestion>> getAutocompleteSuggestions(
    String query, {
    LatLng? nearLocation,
    int limit = 5,
  }) async {
    if (query.trim().length < 2) return [];

    // For autocomplete, we want faster results with lower limit
    return searchPlaces(
      query,
      limit: limit,
      nearLocation: nearLocation,
    );
  }

  /// Enhance search query for better results
  String _enhanceSearchQuery(String query) {
    String enhanced = query.trim();
    
    // If query doesn't contain city name, add Bangalore as default
    if (!enhanced.toLowerCase().contains('bangalore') &&
        !enhanced.toLowerCase().contains('bengaluru') &&
        !enhanced.toLowerCase().contains('karnataka')) {
      enhanced = '$enhanced, Bangalore, Karnataka';
    }

    return enhanced;
  }

  /// Create viewbox for location-biased search
  String _createViewBox(LatLng center, {double radiusKm = 50}) {
    // Approximate degrees per km (at equator)
    const double degPerKm = 0.009;
    final double offset = radiusKm * degPerKm;

    final double minLon = center.longitude - offset;
    final double maxLon = center.longitude + offset;
    final double minLat = center.latitude - offset;
    final double maxLat = center.latitude + offset;

    return '$minLon,$maxLat,$maxLon,$minLat';
  }

  /// Parse Nominatim response into PlaceSuggestion
  PlaceSuggestion _parsePlaceSuggestion(Map<String, dynamic> item, String query) {
    final address = item['address'] as Map<String, dynamic>? ?? {};
    final lat = double.tryParse(item['lat']?.toString() ?? '');
    final lon = double.tryParse(item['lon']?.toString() ?? '');

    // Determine place type
    final type = _determinePlaceType(item);

    // Create title (main name)
    String title = _extractTitle(item, address);

    // Create subtitle (detailed address)
    String subtitle = _formatAddress(address);

    return PlaceSuggestion(
      title: title,
      subtitle: subtitle,
      coordinates: (lat != null && lon != null) ? LatLng(lat, lon) : null,
      type: type,
      placeId: item['place_id']?.toString(),
      osmType: item['osm_type']?.toString(),
      osmId: item['osm_id']?.toString(),
    );
  }

  /// Extract meaningful title from place data
  String _extractTitle(Map<String, dynamic> item, Map<String, dynamic> address) {
    // Priority order for title
    final nameDetails = item['namedetails'] as Map<String, dynamic>? ?? {};
    
    if (nameDetails['name'] != null && nameDetails['name'].toString().isNotEmpty) {
      return nameDetails['name'].toString();
    }

    if (item['name'] != null && item['name'].toString().isNotEmpty) {
      return item['name'].toString();
    }

    // Try address components
    final titleCandidates = [
      address['building'],
      address['house_name'],
      address['amenity'],
      address['shop'],
      address['office'],
      address['road'],
      address['suburb'],
      address['neighbourhood'],
    ];

    for (final candidate in titleCandidates) {
      if (candidate != null && candidate.toString().isNotEmpty) {
        return candidate.toString();
      }
    }

    return item['display_name']?.toString().split(',').first ?? 'Location';
  }

  /// Format address into readable string
  String _formatAddress(Map<String, dynamic> address) {
    final parts = <String>[];

    // Building/House
    if (address['building'] != null) parts.add(address['building'].toString());
    if (address['house_number'] != null && address['road'] != null) {
      parts.add('${address['house_number']} ${address['road']}');
    } else if (address['road'] != null) {
      parts.add(address['road'].toString());
    }

    // Area
    if (address['suburb'] != null) {
      parts.add(address['suburb'].toString());
    } else if (address['neighbourhood'] != null) {
      parts.add(address['neighbourhood'].toString());
    }

    // City
    if (address['city'] != null) {
      parts.add(address['city'].toString());
    } else if (address['town'] != null) {
      parts.add(address['town'].toString());
    } else if (address['village'] != null) {
      parts.add(address['village'].toString());
    }

    // State
    if (address['state'] != null) {
      parts.add(address['state'].toString());
    }

    // Postcode
    if (address['postcode'] != null) {
      parts.add(address['postcode'].toString());
    }

    return parts.isEmpty ? 'Unknown location' : parts.join(', ');
  }

  /// Determine place type from OSM data
  PlaceSuggestionType _determinePlaceType(Map<String, dynamic> item) {
    final type = item['type']?.toString().toLowerCase() ?? '';
    final osmClass = item['class']?.toString().toLowerCase() ?? '';

    if (osmClass == 'building' || type == 'building') {
      return PlaceSuggestionType.business;
    }
    if (osmClass == 'amenity') {
      return PlaceSuggestionType.landmark;
    }
    if (osmClass == 'highway' || osmClass == 'railway') {
      return PlaceSuggestionType.transport;
    }
    if (type == 'administrative' || type == 'city' || type == 'town') {
      return PlaceSuggestionType.address;
    }

    return PlaceSuggestionType.address;
  }

  /// Calculate relevance score for sorting
  double _calculateRelevanceScore(
    PlaceSuggestion suggestion,
    String query,
    LatLng? nearLocation,
  ) {
    double score = 0.0;

    final queryLower = query.toLowerCase();
    final titleLower = suggestion.title.toLowerCase();
    final subtitleLower = suggestion.subtitle.toLowerCase();

    // Exact match bonus
    if (titleLower == queryLower) {
      score += 100.0;
    } else if (titleLower.startsWith(queryLower)) {
      score += 50.0;
    } else if (titleLower.contains(queryLower)) {
      score += 25.0;
    }

    // Subtitle match
    if (subtitleLower.contains(queryLower)) {
      score += 10.0;
    }

    // Type bonus (businesses and landmarks are more relevant)
    if (suggestion.type == PlaceSuggestionType.business) {
      score += 15.0;
    } else if (suggestion.type == PlaceSuggestionType.landmark) {
      score += 10.0;
    }

    // Proximity bonus
    if (nearLocation != null && suggestion.coordinates != null) {
      final distance = _calculateDistance(
        nearLocation,
        suggestion.coordinates!,
      );
      // Closer locations get higher scores (max 20 points)
      score += (20.0 / (1.0 + distance / 10.0));
    }

    return score;
  }

  /// Calculate distance between two points in kilometers
  double _calculateDistance(LatLng point1, LatLng point2) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Kilometer, point1, point2);
  }

  /// Respect rate limiting
  Future<void> _respectRateLimit() async {
    if (_lastRequestTime != null) {
      final timeSinceLastRequest = DateTime.now().difference(_lastRequestTime!);
      if (timeSinceLastRequest < _minRequestInterval) {
        await Future.delayed(_minRequestInterval - timeSinceLastRequest);
      }
    }
    _lastRequestTime = DateTime.now();
  }

  /// Clear all caches
  void clearCache() {
    _searchCache.clear();
    _reverseGeocodeCache.clear();
  }
}
