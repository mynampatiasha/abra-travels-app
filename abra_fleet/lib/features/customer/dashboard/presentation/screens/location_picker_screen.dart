import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:abra_fleet/core/services/location_service.dart';
import 'package:abra_fleet/core/widgets/fleet_map_widget.dart';
import 'package:abra_fleet/core/models/place_suggestion.dart';

class LocationPickerScreen extends StatefulWidget {
  final LatLng? initialLocation;
  final String title;
  final bool isPickup;

  const LocationPickerScreen({
    super.key,
    this.initialLocation,
    required this.title,
    this.isPickup = true,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final LocationService _locationService = LocationService();
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  
  LatLng? _selectedLocation;
  LocationData? _selectedLocationData;
  bool _isLoadingAddress = false;
  bool _isSearching = false;
  String? _selectedAddress;
  List<PlaceSuggestion> _suggestions = [];
  bool _showSuggestions = false;
  Timer? _debounceTimer;
  String _currentQuery = '';
  String? _searchError;
  
  // For real-time search improvements
  final List<PlaceSuggestion> _recentSearches = [];
  final List<PlaceSuggestion> _popularPlaces = [];
  bool _hasUserTyped = false;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
    if (_selectedLocation != null) {
      _loadAddressForLocation(_selectedLocation!);
    } else {
      _getCurrentLocation();
    }
    
    _searchController.addListener(_onSearchTextChanged);
    _searchFocusNode.addListener(_onFocusChanged);
    _loadPopularPlaces();
    _testSearchFunctionality(); // Debug helper
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchTextChanged);
    _searchFocusNode.removeListener(_onFocusChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  // Debug helper to test search functionality
  Future<void> _testSearchFunctionality() async {
    // Test with a known query in debug mode
    if (mounted) {
      await _locationService.testSearch('Infosys Bangalore');
    }
  }

  // Load popular/nearby places for initial suggestions
  Future<void> _loadPopularPlaces() async {
    try {
      // Add some popular Bangalore locations as examples
      final popularQueries = [
        'Electronic City Bangalore',
        'Whitefield Bangalore',
        'Koramangala Bangalore',
        'Indiranagar Bangalore',
        'MG Road Bangalore',
      ];

      for (final query in popularQueries) {
        try {
          final results = await _locationService.searchPlaces(query, limit: 1);
          if (results.isNotEmpty) {
            _popularPlaces.add(results.first);
          }
        } catch (e) {
          // Continue with other queries if one fails
        }
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      // Handle error silently for popular places
    }
  }

  Future<void> _getCurrentLocation() async {
    // Show loading indicator
    if (mounted) {
      setState(() => _isLoadingAddress = true);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Getting accurate GPS location... Please wait'),
              ),
            ],
          ),
          backgroundColor: Colors.blue[700],
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        ),
      );
    }

    try {
      // First check if location service is initialized
      final hasPermission = await _locationService.initialize();
      
      if (!hasPermission) {
        if (mounted) {
          setState(() => _isLoadingAddress = false);
          
          // Show permission dialog
          final shouldOpenSettings = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.location_off, color: Colors.red),
                  SizedBox(width: 12),
                  Text('Location Permission Required'),
                ],
              ),
              content: Text(
                _locationService.errorMessage ?? 
                'Location permission is required to get your current location. '
                'Please enable location services and grant permission to this app.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.settings),
                  label: const Text('Open Settings'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          );
          
          if (shouldOpenSettings == true) {
            await _locationService.openAppSettings();
          }
        }
        return;
      }

      // Get current location with address
      final locationData = await _locationService.getCurrentLocation(withAddress: true);
      
      if (locationData != null && mounted) {
        // Check GPS accuracy
        final accuracy = locationData.accuracy ?? 999;
        String accuracyMessage = '';
        Color accuracyColor = Colors.green;
        
        if (accuracy <= 20) {
          accuracyMessage = 'Excellent GPS accuracy (${accuracy.toStringAsFixed(0)}m)';
          accuracyColor = Colors.green;
        } else if (accuracy <= 50) {
          accuracyMessage = 'Good GPS accuracy (${accuracy.toStringAsFixed(0)}m)';
          accuracyColor = Colors.blue;
        } else if (accuracy <= 100) {
          accuracyMessage = 'Fair GPS accuracy (${accuracy.toStringAsFixed(0)}m)';
          accuracyColor = Colors.orange;
        } else {
          accuracyMessage = 'Low GPS accuracy (${accuracy.toStringAsFixed(0)}m) - Try moving near a window';
          accuracyColor = Colors.red;
        }
        
        setState(() {
          _selectedLocation = LatLng(locationData.latitude, locationData.longitude);
          _selectedLocationData = locationData;
          _selectedAddress = locationData.displayText;
          _isLoadingAddress = false;
        });
        
        // Move map to current location with animation
        _mapController.move(_selectedLocation!, 17.0); // Zoom in more for accuracy
        
        // Show success message with accuracy info
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 20),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Current location selected!',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      accuracy <= 50 ? Icons.gps_fixed : Icons.gps_not_fixed,
                      color: Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        accuracyMessage,
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            backgroundColor: accuracyColor,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
          ),
        );
      } else {
        throw Exception('Unable to retrieve location data');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingAddress = false);
        
        // Show detailed error dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 12),
                Text('Location Error'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Unable to get your current location:'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Text(
                    e.toString(),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.red[900],
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Troubleshooting tips:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('• Enable location services on your device'),
                const Text('• Grant location permission to this app'),
                const Text('• Move near a window for better GPS signal'),
                const Text('• Wait 10-20 seconds for GPS to lock'),
                const Text('• Try searching for "Kasturi Nagar Bangalore" instead'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _locationService.openAppSettings();
                },
                icon: const Icon(Icons.settings),
                label: const Text('Settings'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _loadAddressForLocation(LatLng location) async {
    setState(() => _isLoadingAddress = true);
    
    try {
      final locationData = await _locationService.getLocationFromCoordinates(
        location.latitude,
        location.longitude,
      );
      
      if (mounted) {
        final address = locationData?.displayText ?? 
                       '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}';
        
        setState(() {
          _selectedLocationData = locationData;
          _selectedAddress = address;
          _isLoadingAddress = false;
          // Update search bar with the address for clarity
          _searchController.text = address;
        });
      }
    } catch (e) {
      if (mounted) {
        final fallbackAddress = '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}';
        setState(() {
          _selectedAddress = fallbackAddress;
          _isLoadingAddress = false;
          _searchController.text = fallbackAddress;
        });
      }
    }
  }

  void _onMapTap(LatLng point) {
    setState(() {
      _selectedLocation = point;
      _showSuggestions = false;
      _searchFocusNode.unfocus();
      _searchError = null;
      _isLoadingAddress = true;
      // Show coordinates immediately while loading address
      _selectedAddress = 'Loading address...';
    });
    _loadAddressForLocation(point);
    
    // Provide immediate feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.touch_app, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Location selected, getting address...'),
            ),
          ],
        ),
        backgroundColor: Colors.blue[700],
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      ),
    );
  }

  void _onFocusChanged() {
    if (_searchFocusNode.hasFocus) {
      setState(() {
        _showSuggestions = true;
        _searchError = null;
        if (_searchController.text.isEmpty && !_hasUserTyped) {
          _suggestions = [..._recentSearches, ..._popularPlaces];
        }
      });
    } else {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && !_searchFocusNode.hasFocus) {
          setState(() => _showSuggestions = false);
        }
      });
    }
  }

  void _onSearchTextChanged() {
    final query = _searchController.text.trim();
    
    if (query == _currentQuery) return;
    _currentQuery = query;
    _hasUserTyped = true;
    
    _debounceTimer?.cancel();
    
    setState(() => _searchError = null);
    
    if (query.isEmpty) {
      setState(() {
        _showSuggestions = _searchFocusNode.hasFocus;
        _suggestions = [..._recentSearches, ..._popularPlaces];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _showSuggestions = true;
    });

    // Faster debounce for real-time feel like Google Maps
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _searchPlaces(query);
    });
  }

  Future<void> _searchPlaces(String query) async {
    if (!mounted || query != _currentQuery) return;

    print('Searching for: $query'); // Debug log

    try {
      final suggestions = await _locationService.searchPlaces(query, limit: 8);
      
      print('Found ${suggestions.length} suggestions'); // Debug log
      for (final suggestion in suggestions) {
        print('  - ${suggestion.title} at ${suggestion.coordinates}');
      }
      
      if (mounted && query == _currentQuery) {
        setState(() {
          _suggestions = suggestions;
          _showSuggestions = true;
          _isSearching = false;
          
          if (suggestions.isEmpty) {
            _searchError = 'No results found for "$query". Try searching with more specific terms or include "Bangalore" in your search.';
          } else {
            _searchError = null;
          }
        });
      }
    } catch (e) {
      print('Search error: $e'); // Debug log
      
      if (mounted && query == _currentQuery) {
        setState(() {
          _suggestions.clear();
          _showSuggestions = true;
          _isSearching = false;
          _searchError = 'Search failed: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    print('Selecting suggestion: ${suggestion.title} at ${suggestion.coordinates}'); // Debug log

    if (suggestion.coordinates == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This location doesn\'t have valid coordinates'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Add to recent searches
    _recentSearches.removeWhere((item) => item.title == suggestion.title);
    _recentSearches.insert(0, suggestion);
    if (_recentSearches.length > 5) {
      _recentSearches.removeLast();
    }

    setState(() {
      _isSearching = true;
      _showSuggestions = false;
      // Show the full address in search bar for clarity
      _searchController.text = suggestion.subtitle.isNotEmpty ? suggestion.subtitle : suggestion.title;
      _hasUserTyped = false;
      _searchError = null;
    });
    
    _searchFocusNode.unfocus();

    try {
      final locationData = await _locationService.getLocationFromCoordinates(
        suggestion.coordinates!.latitude,
        suggestion.coordinates!.longitude,
      );
      
      if (mounted && locationData != null) {
        // Use the full address from suggestion for better clarity
        final displayAddress = suggestion.subtitle.isNotEmpty 
            ? suggestion.subtitle 
            : (locationData.displayText ?? suggestion.title);
            
        setState(() {
          _selectedLocation = suggestion.coordinates;
          _selectedLocationData = locationData;
          _selectedAddress = displayAddress;
          _isSearching = false;
        });
        
        _mapController.move(_selectedLocation!, 16.0);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Location selected: ${suggestion.title}'),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      } else {
        throw Exception('Could not retrieve detailed address for this location');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to select location: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _showSuggestions = _searchFocusNode.hasFocus;
      _suggestions = [..._recentSearches, ..._popularPlaces];
      _currentQuery = '';
      _hasUserTyped = false;
      _isSearching = false;
      _searchError = null;
    });
  }

  void _confirmLocation() {
    if (_selectedLocation != null && _selectedAddress != null) {
      Navigator.of(context).pop({
        'location': _selectedLocation,
        'address': _selectedAddress,
        'locationData': _selectedLocationData,
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a location first.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        decoration: InputDecoration(
          hintText: 'Search for places, addresses, landmarks...',
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
          prefixIcon: Icon(
            Icons.search, 
            color: Theme.of(context).primaryColor, 
            size: 24
          ),
          suffixIcon: _isSearching
              ? const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: _clearSearch,
                      tooltip: 'Clear search',
                    )
                  : Icon(Icons.my_location, color: Colors.grey[400], size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        textInputAction: TextInputAction.search,
        onSubmitted: (value) {
          if (_suggestions.isNotEmpty) {
            _selectSuggestion(_suggestions.first);
          }
        },
      ),
    );
  }

  Widget _buildSuggestions() {
    if (!_showSuggestions) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      constraints: const BoxConstraints(maxHeight: 400),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          if (_suggestions.isNotEmpty || _searchError != null) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(
                  bottom: BorderSide(color: Colors.grey[200]!, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _searchController.text.isEmpty 
                        ? Icons.history 
                        : _searchError != null 
                            ? Icons.error_outline 
                            : Icons.location_searching,
                    size: 16,
                    color: _searchError != null ? Colors.red[700] : Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _searchController.text.isEmpty 
                          ? 'Recent & Popular Places'
                          : _searchError != null 
                              ? 'Search Error'
                              : 'Search Results',
                      style: TextStyle(
                        color: _searchError != null ? Colors.red[700] : Colors.grey[700],
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty && _suggestions.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_suggestions.length}',
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          
          // Content
          Flexible(
            child: _isSearching && _suggestions.isEmpty && _searchError == null
                ? const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Searching...'),
                        ],
                      ),
                    ),
                  )
                : _searchError != null
                    ? Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Icon(Icons.search_off, color: Colors.grey[400], size: 48),
                            const SizedBox(height: 8),
                            Text(
                              _searchError!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Search Tips:\n• Include "Bangalore" or "Bengaluru"\n• Try company name + location\n• Use full business names',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _suggestions.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          color: Colors.grey[200],
                          indent: 56,
                        ),
                        itemBuilder: (context, index) {
                          final suggestion = _suggestions[index];
                          final isRecent = _recentSearches.contains(suggestion);
                          
                          return InkWell(
                            onTap: () => _selectSuggestion(suggestion),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                              color: Colors.transparent,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: suggestion.coordinates != null 
                                          ? (isRecent 
                                              ? Colors.blue[50] 
                                              : Colors.green[50])
                                          : Colors.red[50],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      isRecent 
                                          ? Icons.history 
                                          : _getIconForSuggestionType(suggestion.type),
                                      color: suggestion.coordinates != null 
                                          ? (isRecent 
                                              ? Colors.blue[700] 
                                              : Colors.green[700])
                                          : Colors.red[700],
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          suggestion.title,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                            color: suggestion.coordinates != null 
                                                ? Colors.black87 
                                                : Colors.grey[500],
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (suggestion.subtitle.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            suggestion.subtitle,
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 13,
                                              height: 1.3,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                        if (suggestion.coordinates == null) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.warning_amber_rounded,
                                                size: 12,
                                                color: Colors.red[400],
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'No coordinates available',
                                                style: TextStyle(
                                                  color: Colors.red[400],
                                                  fontSize: 11,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (isRecent)
                                    IconButton(
                                      icon: Icon(Icons.close, color: Colors.grey[400], size: 18),
                                      onPressed: () {
                                        setState(() {
                                          _recentSearches.remove(suggestion);
                                          _suggestions.remove(suggestion);
                                        });
                                      },
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      padding: EdgeInsets.zero,
                                    )
                                  else
                                    Icon(
                                      suggestion.coordinates != null 
                                          ? Icons.north_east 
                                          : Icons.error_outline,
                                      color: suggestion.coordinates != null 
                                          ? Colors.grey[400] 
                                          : Colors.red[400],
                                      size: 18,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  IconData _getIconForSuggestionType(PlaceSuggestionType type) {
    switch (type) {
      case PlaceSuggestionType.address:
        return Icons.location_on_outlined;
      case PlaceSuggestionType.business:
        return Icons.business_outlined;
      case PlaceSuggestionType.landmark:
        return Icons.place_outlined;
      case PlaceSuggestionType.transport:
        return Icons.train_outlined;
      default:
        return Icons.location_on_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _getCurrentLocation,
            tooltip: 'Current Location',
          ),
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () async {
              // Debug button to test search
              await _locationService.testSearch(_searchController.text.isNotEmpty 
                  ? _searchController.text 
                  : 'Infosys Bangalore');
            },
            tooltip: 'Debug Search',
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          if (_showSuggestions) {
            setState(() => _showSuggestions = false);
            _searchFocusNode.unfocus();
          }
        },
        child: Stack(
          children: [
            Column(
              children: [
                _buildSearchBar(),
                
                if (!_showSuggestions) ...[
                  // Helpful tip banner when no location selected
                  if (_selectedLocation == null)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8.0),
                      padding: const EdgeInsets.all(12.0),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8.0),
                        border: Border.all(color: Colors.blue[200]!, width: 1),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Search for a place or tap anywhere on the map',
                              style: TextStyle(
                                color: Colors.blue[900],
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_selectedLocation == null) const SizedBox(height: 8),
                  
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16.0),
                    margin: const EdgeInsets.symmetric(horizontal: 8.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (widget.isPickup ? Colors.green : Colors.red).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                widget.isPickup ? Icons.my_location : Icons.location_on,
                                color: widget.isPickup ? Colors.green : Colors.red,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.isPickup ? 'Pickup Location' : 'Drop-off Location',
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _selectedLocation != null 
                                        ? 'Selected' 
                                        : 'Not selected',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _selectedLocation != null 
                                          ? Colors.green[600] 
                                          : Colors.orange[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        if (_isLoadingAddress)
                          Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Theme.of(context).primaryColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Getting address details...',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.place,
                                    size: 16,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _selectedAddress ?? 'Search or tap on the map to select a location',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: _selectedAddress != null 
                                            ? Colors.black87 
                                            : Colors.grey[600],
                                        fontWeight: _selectedAddress != null 
                                            ? FontWeight.w500 
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_selectedLocation != null) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.gps_fixed,
                                      size: 14,
                                      color: Colors.grey[500],
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8.0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12.0),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12.0),
                      child: FleetMapWidget(
                        controller: _mapController,
                        onTap: _onMapTap,
                        markers: _selectedLocation != null
                            ? [
                                Marker(
                                  point: _selectedLocation!,
                                  width: 40,
                                  height: 40,
                                  child: Icon(
                                    widget.isPickup ? Icons.my_location : Icons.location_on,
                                    color: widget.isPickup ? Colors.green : Colors.red,
                                    size: 30,
                                  ),
                                ),
                              ]
                            : [],
                        showCurrentLocation: true,
                        enableInteraction: true,
                      ),
                    ),
                  ),
                ),
                
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton.icon(
                    onPressed: _selectedLocation != null ? _confirmLocation : null,
                    icon: const Icon(Icons.check_circle, size: 22),
                    label: const Text('Confirm Location'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      backgroundColor: _selectedLocation != null 
                          ? Theme.of(context).primaryColor 
                          : Colors.grey[300],
                      foregroundColor: Colors.white,
                      elevation: _selectedLocation != null ? 4 : 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            
            if (_showSuggestions)
              Positioned(
                top: 80,
                left: 0,
                right: 0,
                child: _buildSuggestions(),
              ),
          ],
        ),
      ),
    );
  }
}