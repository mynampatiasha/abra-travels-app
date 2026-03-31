import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import '../../../../../core/services/enhanced_location_service.dart';

class EnhancedLocationSearchWidget extends StatefulWidget {
  final String hintText;
  final Function(LocationSearchResult) onLocationSelected;
  final LatLng? currentLocation;
  final String? initialValue;
  final bool showCurrentLocationButton;
  final bool showNearbyPlaces;

  const EnhancedLocationSearchWidget({
    Key? key,
    required this.hintText,
    required this.onLocationSelected,
    this.currentLocation,
    this.initialValue,
    this.showCurrentLocationButton = true,
    this.showNearbyPlaces = true,
  }) : super(key: key);

  @override
  _EnhancedLocationSearchWidgetState createState() => _EnhancedLocationSearchWidgetState();
}

class _EnhancedLocationSearchWidgetState extends State<EnhancedLocationSearchWidget> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  
  List<LocationSearchResult> _searchResults = [];
  List<LocationSearchResult> _nearbyPlaces = [];
  bool _isSearching = false;
  bool _showResults = false;
  Timer? _searchDebounce;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _controller.text = widget.initialValue!;
    }
    
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _showSearchResults();
      }
    });

    // Load nearby places if current location is available
    if (widget.showNearbyPlaces && widget.currentLocation != null) {
      _loadNearbyPlaces();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _showSearchResults() {
    setState(() {
      _showResults = true;
    });
    
    if (_controller.text.isEmpty && _nearbyPlaces.isEmpty && widget.currentLocation != null) {
      _loadNearbyPlaces();
    } else if (_controller.text.isNotEmpty) {
      _performSearch(_controller.text);
    }
  }

  void _hideSearchResults() {
    setState(() {
      _showResults = false;
    });
  }

  Future<void> _loadNearbyPlaces() async {
    if (widget.currentLocation == null) return;

    try {
      final nearby = await EnhancedLocationService.searchNearbyPOI(
        widget.currentLocation!.latitude,
        widget.currentLocation!.longitude,
      );
      
      if (mounted) {
        setState(() {
          _nearbyPlaces = nearby;
        });
      }
    } catch (e) {
      print('Error loading nearby places: $e');
    }
  }

  void _onSearchChanged(String value) {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    
    if (value.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(value);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty || query == _lastQuery) return;
    
    _lastQuery = query;

    try {
      final results = await EnhancedLocationService.searchLocations(
        query,
        proximityLat: widget.currentLocation?.latitude,
        proximityLon: widget.currentLocation?.longitude,
      );
      
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
      print('Search error: $e');
    }
  }

  void _selectLocation(LocationSearchResult location) {
    setState(() {
      _controller.text = location.shortName;
      _showResults = false;
    });
    
    _focusNode.unfocus();
    widget.onLocationSelected(location);
  }

  void _useCurrentLocation() async {
    if (widget.currentLocation == null) return;

    setState(() {
      _isSearching = true;
    });

    try {
      final result = await EnhancedLocationService.getAddressFromCoordinates(
        widget.currentLocation!.latitude,
        widget.currentLocation!.longitude,
      );
      
      if (result != null && mounted) {
        _selectLocation(result);
      }
    } catch (e) {
      print('Error getting current location address: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  Widget _buildSearchResult(LocationSearchResult result, {bool isNearby = false}) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isNearby ? Colors.blue.shade50 : Colors.green.shade50,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          _getLocationIcon(result.type, result.category),
          color: isNearby ? Colors.blue.shade700 : Colors.green.shade700,
          size: 20,
        ),
      ),
      title: Text(
        result.shortName,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        result.address,
        style: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 13,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isNearby 
          ? Icon(Icons.near_me, color: Colors.blue.shade400, size: 16)
          : null,
      onTap: () => _selectLocation(result),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  IconData _getLocationIcon(String type, String category) {
    switch (category.toLowerCase()) {
      case 'amenity':
        return Icons.place;
      case 'shop':
        return Icons.store;
      case 'building':
        return Icons.business;
      case 'tourism':
        return Icons.attractions;
      default:
        switch (type.toLowerCase()) {
          case 'house':
          case 'residential':
            return Icons.home;
          case 'road':
          case 'street':
            return Icons.route;
          case 'restaurant':
            return Icons.restaurant;
          case 'hospital':
            return Icons.local_hospital;
          case 'school':
            return Icons.school;
          case 'bank':
            return Icons.account_balance;
          case 'fuel':
            return Icons.local_gas_station;
          default:
            return Icons.location_on;
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search Input Field
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focusNode.hasFocus ? Colors.blue.shade400 : Colors.grey.shade300,
              width: _focusNode.hasFocus ? 2 : 1,
            ),
            color: Colors.white,
            boxShadow: _focusNode.hasFocus ? [
              BoxShadow(
                color: Colors.blue.shade100,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ] : null,
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            onChanged: _onSearchChanged,
            onTap: _showSearchResults,
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: TextStyle(color: Colors.grey.shade500),
              prefixIcon: Icon(
                Icons.search,
                color: _focusNode.hasFocus ? Colors.blue.shade600 : Colors.grey.shade400,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isSearching)
                    Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.only(right: 8),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
                      ),
                    ),
                  if (_controller.text.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.clear, color: Colors.grey.shade400),
                      onPressed: () {
                        _controller.clear();
                        setState(() {
                          _searchResults = [];
                          _showResults = false;
                        });
                      },
                    ),
                  if (widget.showCurrentLocationButton && widget.currentLocation != null)
                    IconButton(
                      icon: Icon(Icons.my_location, color: Colors.blue.shade600),
                      onPressed: _useCurrentLocation,
                      tooltip: 'Use current location',
                    ),
                ],
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
        ),
        
        // Search Results Dropdown
        if (_showResults)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            constraints: const BoxConstraints(maxHeight: 300),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Search Results
                if (_searchResults.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      'Search Results',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        return _buildSearchResult(_searchResults[index]);
                      },
                    ),
                  ),
                ],
                
                // Nearby Places
                if (_nearbyPlaces.isNotEmpty && _controller.text.isEmpty) ...[
                  if (_searchResults.isNotEmpty) const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        Icon(Icons.near_me, size: 14, color: Colors.blue.shade600),
                        const SizedBox(width: 4),
                        Text(
                          'Nearby Places',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _nearbyPlaces.take(5).length,
                      itemBuilder: (context, index) {
                        return _buildSearchResult(_nearbyPlaces[index], isNearby: true);
                      },
                    ),
                  ),
                ],
                
                // No Results
                if (_searchResults.isEmpty && _nearbyPlaces.isEmpty && !_isSearching) ...[
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _controller.text.isEmpty 
                              ? 'Start typing to search for locations'
                              : 'No locations found',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}