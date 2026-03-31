// lib/services/navigation_service.dart
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class NavigationService {
  static final NavigationService _instance = NavigationService._internal();
  factory NavigationService() => _instance;
  NavigationService._internal();
  StreamController<NavigationUpdate>? _navigationController;
  Timer? _trackingTimer;
  
  List<NavigationStep> _steps = [];
  int _currentStepIndex = 0;
  LatLng? _destination;
  List<LatLng> _routePoints = [];
  
  bool _isNavigating = false;
  double _lastAnnouncedDistance = 0;

  Stream<NavigationUpdate> get navigationStream {
    _navigationController ??= StreamController<NavigationUpdate>.broadcast();
    return _navigationController!.stream;
  }

  // Initialize TTS (disabled on web)
  Future<void> initialize() async {
    if (kIsWeb) {
      print('ℹ️ TTS not available on web platform');
      return;
    }
    // TTS initialization would go here for mobile platforms
  }

  // Start navigation to destination
  Future<bool> startNavigation({
    required LatLng start,
    required LatLng destination,
    bool voiceEnabled = true,
  }) async {
    try {
      print('\n🗺️ STARTING NAVIGATION');
      print('From: ${start.latitude}, ${start.longitude}');
      print('To: ${destination.latitude}, ${destination.longitude}');

      _destination = destination;
      _isNavigating = true;
      _currentStepIndex = 0;

      // Get route from OSRM
      final route = await _getOSRMRoute(start, destination);
      
      if (route == null) {
        throw Exception('Failed to get route');
      }

      _routePoints = route['polyline'];
      _steps = route['steps'];

      print('✅ Route loaded: ${_steps.length} steps, ${_routePoints.length} points');

      // Start tracking
      _startLocationTracking(voiceEnabled);

      // Announce first instruction
      if (voiceEnabled && _steps.isNotEmpty) {
        _speak(_steps[0].instruction);
      }

      // Emit initial update
      _emitUpdate(start, 0);

      return true;
    } catch (e) {
      print('❌ Navigation start failed: $e');
      return false;
    }
  }

  // Stop navigation
  void stopNavigation() {
    print('🛑 Stopping navigation');
    _isNavigating = false;
    _trackingTimer?.cancel();
    _trackingTimer = null;
    _steps.clear();
    _routePoints.clear();
    _currentStepIndex = 0;
  }

  // Get route from OSRM
  Future<Map<String, dynamic>?> _getOSRMRoute(LatLng start, LatLng end) async {
    try {
      final url = 'https://router.project-osrm.org/route/v1/driving/'
          '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
          '?overview=full&geometries=geojson&steps=true&annotations=true';

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final leg = route['legs'][0];

          // Extract polyline points
          final List<dynamic> coords = route['geometry']['coordinates'];
          final polyline = coords.map((c) => LatLng(c[1], c[0])).toList();

          // Extract turn-by-turn steps
          final List<dynamic> stepsData = leg['steps'];
          final steps = stepsData.map((step) {
            return NavigationStep(
              instruction: _formatInstruction(step),
              distance: (step['distance'] as num).toDouble(),
              duration: (step['duration'] as num).toDouble(),
              maneuver: step['maneuver']['type'] ?? 'continue',
              location: LatLng(
                step['maneuver']['location'][1],
                step['maneuver']['location'][0],
              ),
            );
          }).toList();

          return {
            'polyline': polyline,
            'steps': steps,
            'distance': (route['distance'] as num).toDouble(),
            'duration': (route['duration'] as num).toDouble(),
          };
        }
      }

      return null;
    } catch (e) {
      print('❌ OSRM route error: $e');
      return null;
    }
  }

  // Format navigation instruction
  String _formatInstruction(Map<String, dynamic> step) {
    final maneuver = step['maneuver']['type'];
    final modifier = step['maneuver']['modifier'];
    final distance = (step['distance'] as num).toDouble();
    final roadName = step['name'] ?? '';

    String instruction = '';

    switch (maneuver) {
      case 'depart':
        instruction = 'Start driving';
        break;
      case 'turn':
        if (modifier == 'left') {
          instruction = 'Turn left';
        } else if (modifier == 'right') {
          instruction = 'Turn right';
        } else if (modifier == 'slight left') {
          instruction = 'Bear left';
        } else if (modifier == 'slight right') {
          instruction = 'Bear right';
        } else if (modifier == 'sharp left') {
          instruction = 'Sharp left turn';
        } else if (modifier == 'sharp right') {
          instruction = 'Sharp right turn';
        }
        break;
      case 'continue':
        instruction = 'Continue straight';
        break;
      case 'arrive':
        instruction = 'You have arrived at your destination';
        break;
      case 'roundabout':
        instruction = 'Enter the roundabout';
        break;
      default:
        instruction = 'Continue on route';
    }

    if (roadName.isNotEmpty && maneuver != 'arrive') {
      instruction += ' onto $roadName';
    }

    if (distance > 0 && maneuver != 'arrive') {
      if (distance >= 1000) {
        instruction += ' in ${(distance / 1000).toStringAsFixed(1)} kilometers';
      } else {
        instruction += ' in ${distance.toInt()} meters';
      }
    }

    return instruction;
  }

  // Start location tracking
  void _startLocationTracking(bool voiceEnabled) {
    _trackingTimer?.cancel();
    
    _trackingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!_isNavigating) {
        timer.cancel();
        return;
      }

      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        final currentLocation = LatLng(position.latitude, position.longitude);
        
        // Calculate distance to current step
        if (_currentStepIndex < _steps.length) {
          final step = _steps[_currentStepIndex];
          final distanceToStep = _calculateDistance(
            currentLocation,
            step.location,
          );

          // Move to next step if close enough (20 meters)
          if (distanceToStep < 20 && _currentStepIndex < _steps.length - 1) {
            _currentStepIndex++;
            _lastAnnouncedDistance = 0;
            
            if (voiceEnabled && _currentStepIndex < _steps.length) {
              _speak(_steps[_currentStepIndex].instruction);
            }
          }

          // Announce distance milestones
          if (voiceEnabled && distanceToStep > 20) {
            if (distanceToStep < 100 && _lastAnnouncedDistance >= 100) {
              _speak('In 100 meters, ${_steps[_currentStepIndex].instruction}');
              _lastAnnouncedDistance = distanceToStep;
            } else if (distanceToStep < 500 && _lastAnnouncedDistance >= 500) {
              _speak('In 500 meters, ${_steps[_currentStepIndex].instruction}');
              _lastAnnouncedDistance = distanceToStep;
            }
          }

          // Emit navigation update
          _emitUpdate(currentLocation, distanceToStep);
        }

        // Check if arrived at destination
        if (_destination != null) {
          final distanceToDestination = _calculateDistance(
            currentLocation,
            _destination!,
          );

          if (distanceToDestination < 30) {
            if (voiceEnabled) {
              _speak('You have arrived at your destination');
            }
            stopNavigation();
          }
        }

      } catch (e) {
        print('❌ Location tracking error: $e');
      }
    });
  }

  // Emit navigation update
  void _emitUpdate(LatLng currentLocation, double distanceToNextStep) {
    if (_navigationController != null && !_navigationController!.isClosed) {
      final update = NavigationUpdate(
        currentLocation: currentLocation,
        currentStep: _currentStepIndex < _steps.length ? _steps[_currentStepIndex] : null,
        distanceToNextStep: distanceToNextStep,
        distanceToDestination: _destination != null 
            ? _calculateDistance(currentLocation, _destination!)
            : 0,
        routePoints: _routePoints,
        remainingSteps: _steps.length - _currentStepIndex - 1,
      );

      _navigationController!.add(update);
    }
  }

  // Text-to-speech (disabled on web)
  Future<void> _speak(String text) async {
    if (kIsWeb) {
      print('🔊 [Voice]: $text');
      return;
    }
    // TTS would be called here for mobile platforms
  }

  // Calculate distance between two points
  double _calculateDistance(LatLng point1, LatLng point2) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Meter, point1, point2);
  }

  void dispose() {
    stopNavigation();
    _navigationController?.close();
  }
}

// Navigation data classes
class NavigationStep {
  final String instruction;
  final double distance;
  final double duration;
  final String maneuver;
  final LatLng location;

  NavigationStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.maneuver,
    required this.location,
  });
}

class NavigationUpdate {
  final LatLng currentLocation;
  final NavigationStep? currentStep;
  final double distanceToNextStep;
  final double distanceToDestination;
  final List<LatLng> routePoints;
  final int remainingSteps;

  NavigationUpdate({
    required this.currentLocation,
    required this.currentStep,
    required this.distanceToNextStep,
    required this.distanceToDestination,
    required this.routePoints,
    required this.remainingSteps,
  });
}