// File: lib/core/models/place_suggestion.dart
// Enhanced model for handling place suggestions with better error handling

import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';

enum PlaceSuggestionType {
  address,
  business,
  landmark,
  transport,
  unknown,
}

class PlaceSuggestion {
  final String title;
  final String subtitle;
  final LatLng? coordinates;
  final PlaceSuggestionType type;
  final String? placeId;
  final String? osmType;
  final String? osmId;
  final Map<String, dynamic>? metadata;

  const PlaceSuggestion({
    required this.title,
    required this.subtitle,
    this.coordinates,
    this.type = PlaceSuggestionType.unknown,
    this.placeId,
    this.osmType,
    this.osmId,
    this.metadata,
  });

  /// Create PlaceSuggestion from Nominatim API response with enhanced error handling
  factory PlaceSuggestion.fromNominatim(Map<String, dynamic> json) {
    try {
      // Extract coordinates with validation
      LatLng? coordinates;
      final lat = json['lat'];
      final lon = json['lon'];
      
      if (lat != null && lon != null) {
        try {
          final latitude = double.parse(lat.toString());
          final longitude = double.parse(lon.toString());
          
          // Validate coordinate ranges
          if (latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180) {
            coordinates = LatLng(latitude, longitude);
          } else {
            if (kDebugMode) {
              print('Invalid coordinates: lat=$latitude, lon=$longitude');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing coordinates: $e');
          }
        }
      }

      // Extract and format display name
      String title = '';
      String subtitle = '';
      
      final displayName = json['display_name']?.toString() ?? '';
      final name = json['name']?.toString() ?? '';
      
      if (displayName.isNotEmpty) {
        final parts = displayName.split(',').map((e) => e.trim()).toList();
        if (parts.isNotEmpty) {
          // Use the most specific name as title
          title = name.isNotEmpty ? name : parts[0];
          
          // Create subtitle from remaining parts
          if (parts.length > 1) {
            final remainingParts = name.isNotEmpty ? parts : parts.skip(1);
            subtitle = remainingParts.join(', ');
          }
        }
      }

      // Fallback if title is still empty
      if (title.isEmpty) {
        title = name.isNotEmpty ? name : 'Unknown location';
      }

      // Determine suggestion type based on OSM data
      final type = _determineSuggestionType(json);

      // Extract place ID
      final placeId = json['place_id']?.toString();

      // Store additional metadata
      final metadata = {
        'osm_type': json['osm_type'],
        'osm_id': json['osm_id'],
        'class': json['class'],
        'type': json['type'],
        'importance': json['importance'],
        'icon': json['icon'],
        'address': json['address'],
        'boundingbox': json['boundingbox'],
      };

      return PlaceSuggestion(
        title: title,
        subtitle: subtitle,
        coordinates: coordinates,
        type: type,
        placeId: placeId,
        osmType: json['osm_type']?.toString(),
        osmId: json['osm_id']?.toString(),
        metadata: metadata,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error creating PlaceSuggestion from Nominatim data: $e');
        print('JSON data: $json');
      }
      
      // Return a basic suggestion even if parsing fails
      return PlaceSuggestion(
        title: json['display_name']?.toString() ?? 'Unknown location',
        subtitle: '',
        coordinates: null,
        type: PlaceSuggestionType.unknown,
        osmType: json['osm_type']?.toString(),
        osmId: json['osm_id']?.toString(),
      );
    }
  }

  /// Determine suggestion type based on OSM class and type
  static PlaceSuggestionType _determineSuggestionType(Map<String, dynamic> json) {
    final osmClass = json['class']?.toString().toLowerCase() ?? '';
    final osmType = json['type']?.toString().toLowerCase() ?? '';

    // Business/Commercial
    if (osmClass == 'amenity' || 
        osmClass == 'shop' || 
        osmClass == 'office' ||
        osmClass == 'commercial' ||
        osmType.contains('company') ||
        osmType.contains('office') ||
        osmType.contains('industrial')) {
      return PlaceSuggestionType.business;
    }

    // Transport
    if (osmClass == 'railway' || 
        osmClass == 'aeroway' || 
        osmClass == 'highway' ||
        osmType.contains('station') ||
        osmType.contains('airport') ||
        osmType.contains('bus_stop')) {
      return PlaceSuggestionType.transport;
    }

    // Landmarks
    if (osmClass == 'tourism' || 
        osmClass == 'historic' || 
        osmClass == 'leisure' ||
        osmType.contains('monument') ||
        osmType.contains('memorial') ||
        osmType.contains('attraction')) {
      return PlaceSuggestionType.landmark;
    }

    // Address/Place
    if (osmClass == 'place' || 
        osmClass == 'boundary' ||
        osmType.contains('house') ||
        osmType.contains('building') ||
        osmType.contains('residential')) {
      return PlaceSuggestionType.address;
    }

    return PlaceSuggestionType.unknown;
  }

  /// Get formatted address parts for display
  Map<String, String> get addressParts {
    final parts = <String, String>{};
    final address = metadata?['address'] as Map<String, dynamic>?;
    
    if (address != null) {
      parts['house_number'] = address['house_number']?.toString() ?? '';
      parts['road'] = address['road']?.toString() ?? '';
      parts['neighbourhood'] = address['neighbourhood']?.toString() ?? '';
      parts['suburb'] = address['suburb']?.toString() ?? '';
      parts['city'] = address['city']?.toString() ?? address['town']?.toString() ?? '';
      parts['state'] = address['state']?.toString() ?? '';
      parts['country'] = address['country']?.toString() ?? '';
      parts['postcode'] = address['postcode']?.toString() ?? '';
    }
    
    return parts;
  }

  /// Get formatted short address for Indian locations
  String get shortAddress {
    final address = addressParts;
    final parts = <String>[];
    
    // Add road if available
    if (address['road']?.isNotEmpty == true) {
      parts.add(address['road']!);
    }
    
    // Add area/suburb
    if (address['suburb']?.isNotEmpty == true) {
      parts.add(address['suburb']!);
    } else if (address['neighbourhood']?.isNotEmpty == true) {
      parts.add(address['neighbourhood']!);
    }
    
    // Add city
    if (address['city']?.isNotEmpty == true) {
      parts.add(address['city']!);
    }
    
    return parts.isNotEmpty ? parts.join(', ') : subtitle;
  }

  /// Check if this suggestion represents a specific business/office
  bool get isBusiness => type == PlaceSuggestionType.business || 
                        title.toLowerCase().contains(RegExp(r'\b(office|headquarters|campus|building|tower|complex)\b'));

  /// Get importance score for ranking (higher is better)
  double get importance {
    final importanceValue = metadata?['importance'] as double?;
    if (importanceValue != null) return importanceValue;
    
    // Fallback scoring based on type and other factors
    double score = 0.0;
    
    // Type-based scoring
    switch (type) {
      case PlaceSuggestionType.business:
        score += 0.3;
        break;
      case PlaceSuggestionType.landmark:
        score += 0.2;
        break;
      case PlaceSuggestionType.address:
        score += 0.1;
        break;
      default:
        score += 0.0;
    }
    
    // Business-specific boost
    if (isBusiness) score += 0.2;
    
    // Title length penalty (shorter is often better)
    score -= title.length * 0.001;
    
    return score;
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
    'title': title,
    'subtitle': subtitle,
    'coordinates': coordinates != null ? {
      'latitude': coordinates!.latitude,
      'longitude': coordinates!.longitude,
    } : null,
    'type': type.toString(),
    'placeId': placeId,
    'osmType': osmType,
    'osmId': osmId,
    'metadata': metadata,
  };

  /// Create from JSON
  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) {
    LatLng? coordinates;
    final coordsData = json['coordinates'] as Map<String, dynamic>?;
    if (coordsData != null) {
      coordinates = LatLng(
        coordsData['latitude']?.toDouble() ?? 0.0,
        coordsData['longitude']?.toDouble() ?? 0.0,
      );
    }

    PlaceSuggestionType type = PlaceSuggestionType.unknown;
    final typeString = json['type']?.toString() ?? '';
    for (final t in PlaceSuggestionType.values) {
      if (t.toString() == typeString) {
        type = t;
        break;
      }
    }

    return PlaceSuggestion(
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      coordinates: coordinates,
      type: type,
      placeId: json['placeId']?.toString(),
      osmType: json['osmType']?.toString(),
      osmId: json['osmId']?.toString(),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() => 'PlaceSuggestion(title: $title, coordinates: $coordinates, type: $type)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaceSuggestion &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          coordinates == other.coordinates &&
          placeId == other.placeId;

  @override
  int get hashCode => title.hashCode ^ coordinates.hashCode ^ placeId.hashCode;
}