import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class LocationSearchResult {
  final String displayName;
  final String shortName;
  final String address;
  final double latitude;
  final double longitude;
  final String type;
  final String category;
  final Map<String, dynamic> addressComponents;

  LocationSearchResult({
    required this.displayName,
    required this.shortName,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.type,
    required this.category,
    required this.addressComponents,
  });

  factory LocationSearchResult.fromNominatim(Map<String, dynamic> json) {
    final addressDetails = json['address'] ?? {};
    
    // Create a readable short name
    String shortName = '';
    if (addressDetails['amenity'] != null) {
      shortName = addressDetails['amenity'];
    } else if (addressDetails['shop'] != null) {
      shortName = addressDetails['shop'];
    } else if (addressDetails['building'] != null) {
      shortName = addressDetails['building'];
    } else if (addressDetails['road'] != null) {
      shortName = addressDetails['road'];
    } else if (addressDetails['suburb'] != null) {
      shortName = addressDetails['suburb'];
    } else {
      shortName = json['name'] ?? 'Location';
    }

    // Create a formatted address
    List<String> addressParts = [];
    
    if (addressDetails['house_number'] != null && addressDetails['road'] != null) {
      addressParts.add('${addressDetails['house_number']} ${addressDetails['road']}');
    } else if (addressDetails['road'] != null) {
      addressParts.add(addressDetails['road']);
    }
    
    if (addressDetails['suburb'] != null) {
      addressParts.add(addressDetails['suburb']);
    }
    
    if (addressDetails['city'] != null) {
      addressParts.add(addressDetails['city']);
    } else if (addressDetails['town'] != null) {
      addressParts.add(addressDetails['town']);
    } else if (addressDetails['village'] != null) {
      addressParts.add(addressDetails['village']);
    }
    
    if (addressDetails['state'] != null) {
      addressParts.add(addressDetails['state']);
    }
    
    if (addressDetails['postcode'] != null) {
      addressParts.add(addressDetails['postcode']);
    }

    String formattedAddress = addressParts.join(', ');
    if (formattedAddress.isEmpty) {
      formattedAddress = json['display_name'] ?? 'Unknown Address';
    }

    return LocationSearchResult(
      displayName: json['display_name'] ?? '',
      shortName: shortName,
      address: formattedAddress,
      latitude: double.parse(json['lat'].toString()),
      longitude: double.parse(json['lon'].toString()),
      type: json['type'] ?? '',
      category: json['category'] ?? '',
      addressComponents: addressDetails,
    );
  }

  LatLng get latLng => LatLng(latitude, longitude);
}

class EnhancedLocationService {
  static const String _baseUrl = 'https://nominatim.openstreetmap.org';
  static const String _userAgent = 'AbraFleet/1.0';
  
  // Cache for recent searches
  static final Map<String, List<LocationSearchResult>> _searchCache = {};
  static const int _cacheMaxSize = 50;

  /// Search for locations with enhanced results
  static Future<List<LocationSearchResult>> searchLocations(
    String query, {
    String? city = 'Bengaluru',
    String? state = 'Karnataka',
    String? country = 'India',
    int limit = 10,
    double? proximityLat,
    double? proximityLon,
  }) async {
    if (query.trim().isEmpty) return [];

    // Check cache first
    final cacheKey = '${query.toLowerCase()}_${city}_$limit';
    if (_searchCache.containsKey(cacheKey)) {
      return _searchCache[cacheKey]!;
    }

    try {
      // Build search query with location context
      String searchQuery = query;
      if (city != null) searchQuery += ', $city';
      if (state != null) searchQuery += ', $state';
      if (country != null) searchQuery += ', $country';

      final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
        'q': searchQuery,
        'format': 'json',
        'limit': limit.toString(),
        'addressdetails': '1',
        'extratags': '1',
        'namedetails': '1',
        'dedupe': '1',
        'bounded': '1',
        if (proximityLat != null && proximityLon != null) ...{
          'lat': proximityLat.toString(),
          'lon': proximityLon.toString(),
        },
        // Bias towards more useful location types
        'featuretype': 'settlement,street,building',
      });

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': _userAgent,
          'Accept': 'application/json',
          'Accept-Language': 'en',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> results = json.decode(response.body);
        
        final searchResults = results
            .map((result) => LocationSearchResult.fromNominatim(result))
            .toList();

        // Sort results by relevance
        searchResults.sort((a, b) {
          // Prioritize exact matches
          final aExact = a.shortName.toLowerCase().contains(query.toLowerCase());
          final bExact = b.shortName.toLowerCase().contains(query.toLowerCase());
          
          if (aExact && !bExact) return -1;
          if (!aExact && bExact) return 1;
          
          // Prioritize certain types
          final aPriority = _getTypePriority(a.type, a.category);
          final bPriority = _getTypePriority(b.type, b.category);
          
          return aPriority.compareTo(bPriority);
        });

        // Cache the results
        _cacheResults(cacheKey, searchResults);
        
        return searchResults;
      } else {
        throw Exception('Search failed with status: ${response.statusCode}');
      }
    } catch (e) {
      print('Location search error: $e');
      return [];
    }
  }

  /// Get address from coordinates (reverse geocoding)
  static Future<LocationSearchResult?> getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      final uri = Uri.parse('$_baseUrl/reverse').replace(queryParameters: {
        'lat': latitude.toString(),
        'lon': longitude.toString(),
        'format': 'json',
        'addressdetails': '1',
        'zoom': '18',
      });

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': _userAgent,
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        if (result != null && result['lat'] != null) {
          return LocationSearchResult.fromNominatim(result);
        }
      }
    } catch (e) {
      print('Reverse geocoding error: $e');
    }
    return null;
  }

  /// Search for nearby places of interest
  static Future<List<LocationSearchResult>> searchNearbyPOI(
    double latitude,
    double longitude, {
    double radiusKm = 2.0,
    List<String> categories = const ['amenity', 'shop', 'tourism'],
  }) async {
    try {
      final results = <LocationSearchResult>[];
      
      for (final category in categories) {
        final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
          'format': 'json',
          'limit': '20',
          'addressdetails': '1',
          category: '*',
          'bounded': '1',
          'viewbox': _getBoundingBox(latitude, longitude, radiusKm),
        });

        final response = await http.get(
          uri,
          headers: {'User-Agent': _userAgent},
        );

        if (response.statusCode == 200) {
          final List<dynamic> categoryResults = json.decode(response.body);
          results.addAll(
            categoryResults.map((result) => LocationSearchResult.fromNominatim(result)),
          );
        }
      }

      // Remove duplicates and sort by distance
      final uniqueResults = <LocationSearchResult>[];
      final seenCoordinates = <String>{};
      
      for (final result in results) {
        final coordKey = '${result.latitude.toStringAsFixed(6)}_${result.longitude.toStringAsFixed(6)}';
        if (!seenCoordinates.contains(coordKey)) {
          seenCoordinates.add(coordKey);
          uniqueResults.add(result);
        }
      }

      // Sort by distance from center point
      uniqueResults.sort((a, b) {
        final distanceA = _calculateDistance(latitude, longitude, a.latitude, a.longitude);
        final distanceB = _calculateDistance(latitude, longitude, b.latitude, b.longitude);
        return distanceA.compareTo(distanceB);
      });

      return uniqueResults.take(15).toList();
    } catch (e) {
      print('Nearby POI search error: $e');
      return [];
    }
  }

  // Helper methods
  static int _getTypePriority(String type, String category) {
    // Lower number = higher priority
    if (category == 'amenity') return 1;
    if (category == 'building') return 2;
    if (category == 'shop') return 3;
    if (type == 'house') return 4;
    if (type == 'road') return 5;
    if (category == 'place') return 6;
    return 10;
  }

  static void _cacheResults(String key, List<LocationSearchResult> results) {
    if (_searchCache.length >= _cacheMaxSize) {
      // Remove oldest entry
      final oldestKey = _searchCache.keys.first;
      _searchCache.remove(oldestKey);
    }
    _searchCache[key] = results;
  }

  static String _getBoundingBox(double lat, double lon, double radiusKm) {
    const double kmPerDegree = 111.0;
    final double deltaLat = radiusKm / kmPerDegree;
    final double deltaLon = radiusKm / (kmPerDegree * cos(lat * pi / 180));
    
    final double minLon = lon - deltaLon;
    final double minLat = lat - deltaLat;
    final double maxLon = lon + deltaLon;
    final double maxLat = lat + deltaLat;
    
    return '$minLon,$minLat,$maxLon,$maxLat';
  }

  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // km
    final double dLat = (lat2 - lat1) * pi / 180;
    final double dLon = (lon2 - lon1) * pi / 180;
    
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadius * c;
  }

  /// Clear search cache
  static void clearCache() {
    _searchCache.clear();
  }
}