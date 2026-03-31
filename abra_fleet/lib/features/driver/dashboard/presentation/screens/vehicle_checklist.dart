// lib/screens/vehicle_checklist.dart
// ============================================================================
// DAILY VEHICLE CHECKLIST - Flutter Side
// ============================================================================
// SETUP IN driver_trip_dashboard.dart:
//
//   1. import 'vehicle_checklist.dart';
//
//   2. Replace _initializeApp():
//      Future<void> _initializeApp() async {
//        await _requestPermissions();
//        await _checkDailyChecklist();
//        await _loadTrips();
//      }
//
//   3. Add this method to _DriverTripDashboardState:
//      Future<void> _checkDailyChecklist() async {
//        // First check backend, fallback to local prefs
//        final checklistApi = ChecklistApiService();
//        final vehicleNumber = trips.isNotEmpty
//            ? (trips[0]['trip'] as Trip).vehicleNumber
//            : 'Unknown';
//        final alreadyDone = await checklistApi.isTodayChecklistDone(vehicleNumber);
//        if (alreadyDone) return;
//        if (!mounted) return;
//        await showDialog<bool>(
//          context: context,
//          barrierDismissible: false,
//          builder: (_) => VehicleChecklistDialog(vehicleNumber: vehicleNumber),
//        );
//      }
// ============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:abra_fleet/app/config/api_config.dart';

// ============================================================================
// MODEL
// ============================================================================

class ChecklistItem {
  final String id;
  final String category;
  final String title;
  final String description;
  final IconData icon;
  bool isChecked;
  String note;

  ChecklistItem({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.icon,
    this.isChecked = false,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'title': title,
        'checked': isChecked,
        'note': note,
      };
}

// ============================================================================
// API SERVICE
// ============================================================================

class ChecklistApiService {
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  Future<Map<String, String?>> _getDriverInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString == null) return {'id': null, 'email': null};
    try {
      final userData = jsonDecode(userDataString) as Map<String, dynamic>;
      return {
        'id': userData['id']?.toString(),
        'email': userData['email']?.toString(),
      };
    } catch (_) {
      return {'id': null, 'email': null};
    }
  }

  /// Submit checklist → POST /api/vehicle-checklist/submit
  Future<void> submitChecklist({
    required String vehicleNumber,
    required List<ChecklistItem> items,
  }) async {
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Not authenticated. Please log in again.');
    }

    final driverInfo = await _getDriverInfo();
    final driverId = driverInfo['id'];
    final driverEmail = driverInfo['email'] ?? '';

    if (driverId == null) {
      throw Exception('Driver ID not found. Please log in again.');
    }

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final checkedCount = items.where((i) => i.isChecked).length;

    final body = jsonEncode({
      'driverId': driverId,
      'driverEmail': driverEmail,
      'vehicleNumber': vehicleNumber,
      'date': today,
      'submittedAt': DateTime.now().toIso8601String(),
      'totalItems': items.length,
      'checkedItems': checkedCount,
      'allPassed': checkedCount == items.length,
      'items': items.map((i) => i.toJson()).toList(),
      'failedItems': items
          .where((i) => !i.isChecked)
          .map((i) => {
                'id': i.id,
                'title': i.title,
                'category': i.category,
                'note': i.note,
              })
          .toList(),
    });

    final response = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/vehicle-checklist/submit'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 30));

    Map<String, dynamic> responseData;
    try {
      responseData = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Invalid server response (${response.statusCode})');
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
      if (responseData['success'] == true) {
        // Save locally as fallback
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('checklist_date', today);
        return;
      }
      throw Exception(responseData['message'] ?? 'Submission failed');
    } else if (response.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    } else {
      throw Exception(
          responseData['message'] ?? 'Server error (${response.statusCode})');
    }
  }

  /// Check if today's checklist already submitted
  /// Checks backend first, falls back to SharedPreferences
  Future<bool> isTodayChecklistDone(String vehicleNumber) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      final token = await _getToken();
      if (token == null) return _localCheck(today);

      final response = await http
          .get(
            Uri.parse(
                '${ApiConfig.baseUrl}/api/vehicle-checklist/status?date=$today&vehicleNumber=${Uri.encodeComponent(vehicleNumber)}'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['data']?['submitted'] == true;
      }
      return _localCheck(today);
    } catch (_) {
      return _localCheck(today);
    }
  }

  Future<bool> _localCheck(String today) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('checklist_date') == today;
  }
}

// ============================================================================
// DIALOG WIDGET
// ============================================================================

class VehicleChecklistDialog extends StatefulWidget {
  final String vehicleNumber;

  const VehicleChecklistDialog({super.key, required this.vehicleNumber});

  @override
  State<VehicleChecklistDialog> createState() =>
      _VehicleChecklistDialogState();
}

class _VehicleChecklistDialogState extends State<VehicleChecklistDialog> {
  final _api = ChecklistApiService();

  bool _isSubmitting = false;
  String _submitError = '';
  int _currentCategoryIndex = 0;

  static const _categories = [
    'Exterior',
    'Lights & Signals',
    'Interior',
    'Engine & Fluids',
    'Safety',
  ];

  late final List<ChecklistItem> _items;

  @override
  void initState() {
    super.initState();
    _items = _buildItems();
  }

  List<ChecklistItem> _buildItems() => [
        // EXTERIOR
        ChecklistItem(id: 'ext_tyres', category: 'Exterior', title: 'Tyre Condition', description: 'All 4 tyres properly inflated, no visible damage', icon: Icons.tire_repair),
        ChecklistItem(id: 'ext_body', category: 'Exterior', title: 'Body & Panels', description: 'No new dents, scratches or damage since last trip', icon: Icons.directions_car),
        ChecklistItem(id: 'ext_mirrors', category: 'Exterior', title: 'Mirrors', description: 'All mirrors intact and properly adjusted', icon: Icons.compare_arrows),
        ChecklistItem(id: 'ext_windshield', category: 'Exterior', title: 'Windshield', description: 'No cracks or chips obstructing visibility', icon: Icons.window),
        ChecklistItem(id: 'ext_wipers', category: 'Exterior', title: 'Windshield Wipers', description: 'Wipers functional, blades in good condition', icon: Icons.water_drop),
        // LIGHTS & SIGNALS
        ChecklistItem(id: 'light_head', category: 'Lights & Signals', title: 'Headlights', description: 'Both low and high beam headlights working', icon: Icons.light_mode),
        ChecklistItem(id: 'light_tail', category: 'Lights & Signals', title: 'Tail Lights', description: 'Rear tail lights and brake lights functioning', icon: Icons.light_mode_outlined),
        ChecklistItem(id: 'light_indicators', category: 'Lights & Signals', title: 'Turn Signals', description: 'Left and right turn signals working correctly', icon: Icons.turn_right),
        ChecklistItem(id: 'light_hazard', category: 'Lights & Signals', title: 'Hazard Lights', description: 'Hazard warning lights operational', icon: Icons.warning_amber),
        // INTERIOR
        ChecklistItem(id: 'int_seatbelts', category: 'Interior', title: 'Seat Belts', description: 'All passenger and driver seat belts working', icon: Icons.airline_seat_recline_normal),
        ChecklistItem(id: 'int_seats', category: 'Interior', title: 'Seats & Upholstery', description: 'Seats clean, undamaged and securely fixed', icon: Icons.event_seat),
        ChecklistItem(id: 'int_ac', category: 'Interior', title: 'Air Conditioning', description: 'AC working and cabin temperature control functional', icon: Icons.ac_unit),
        ChecklistItem(id: 'int_horn', category: 'Interior', title: 'Horn', description: 'Horn is audible and working correctly', icon: Icons.spatial_audio_off),
        ChecklistItem(id: 'int_cleanliness', category: 'Interior', title: 'Cabin Cleanliness', description: 'Interior clean and presentable for passengers', icon: Icons.cleaning_services),
        // ENGINE & FLUIDS
        ChecklistItem(id: 'eng_fuel', category: 'Engine & Fluids', title: 'Fuel Level', description: 'Fuel level sufficient for today\'s trips', icon: Icons.local_gas_station),
        ChecklistItem(id: 'eng_oil', category: 'Engine & Fluids', title: 'Engine Oil', description: 'Oil level within acceptable range', icon: Icons.opacity),
        ChecklistItem(id: 'eng_coolant', category: 'Engine & Fluids', title: 'Coolant Level', description: 'Coolant reservoir at correct level', icon: Icons.thermostat),
        ChecklistItem(id: 'eng_brakes', category: 'Engine & Fluids', title: 'Brakes', description: 'Brakes firm and responsive, no unusual sounds', icon: Icons.stop_circle),
        // SAFETY
        ChecklistItem(id: 'safe_kit', category: 'Safety', title: 'First Aid Kit', description: 'First aid kit present and stocked', icon: Icons.medical_services),
        ChecklistItem(id: 'safe_fire', category: 'Safety', title: 'Fire Extinguisher', description: 'Present, pressure gauge shows green', icon: Icons.fire_extinguisher),
        ChecklistItem(id: 'safe_triangle', category: 'Safety', title: 'Warning Triangle', description: 'Reflective warning triangle in vehicle', icon: Icons.change_history),
        ChecklistItem(id: 'safe_docs', category: 'Safety', title: 'Vehicle Documents', description: 'RC, insurance, and permit documents present', icon: Icons.folder),
      ];

  List<ChecklistItem> get _currentItems =>
      _items.where((i) => i.category == _categories[_currentCategoryIndex]).toList();

  int get _checkedCount => _items.where((i) => i.isChecked).length;
  bool get _allChecked => _items.every((i) => i.isChecked);

  Future<void> _submit() async {
    if (!_allChecked) {
      final unchecked = _items.where((i) => !i.isChecked).toList();
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Incomplete Checklist'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${unchecked.length} item(s) not checked:',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...unchecked.take(5).map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      const Icon(Icons.close, color: Colors.red, size: 16),
                      const SizedBox(width: 6),
                      Expanded(child: Text(item.title, style: const TextStyle(fontSize: 13))),
                    ]),
                  )),
              if (unchecked.length > 5)
                Text('...and ${unchecked.length - 5} more',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              const Text('Issues will be recorded. Submit anyway?',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Go Back & Fix')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text('Submit Anyway',
                    style: TextStyle(color: Colors.white))),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = '';
    });

    try {
      await _api.submitChecklist(
        vehicleNumber: widget.vehicleNumber,
        items: _items,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _submitError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            _buildProgressBar(),
            _buildCategoryTabs(),
            Flexible(child: _buildItemsList()),
            if (_submitError.isNotEmpty) _buildErrorBanner(),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF0D47A1),
        borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16), topRight: Radius.circular(16)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.checklist, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Daily Vehicle Checklist',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              Text(
                '${widget.vehicleNumber} • ${DateFormat('EEE, MMM d yyyy').format(DateTime.now())}',
                style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Icon(Icons.info_outline, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            const Expanded(
                child: Text('Complete before starting your first trip today.',
                    style: TextStyle(color: Colors.white, fontSize: 12))),
            Text('$_checkedCount / ${_items.length}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildProgressBar() {
    final progress = _items.isEmpty ? 0.0 : _checkedCount / _items.length;
    return Container(
      color: const Color(0xFF0D47A1).withOpacity(0.06),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(
                progress == 1.0 ? Colors.green : const Color(0xFF0D47A1)),
            minHeight: 8,
          ),
        ),
        if (progress == 1.0)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Row(children: [
              Icon(Icons.check_circle, color: Colors.green, size: 14),
              SizedBox(width: 4),
              Text('All items checked! Ready to submit.',
                  style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
            ]),
          ),
      ]),
    );
  }

  Widget _buildCategoryTabs() {
    return Container(
      color: Colors.grey.shade100,
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final isSelected = index == _currentCategoryIndex;
          final allDone = _items
              .where((i) => i.category == _categories[index])
              .every((i) => i.isChecked);
          return GestureDetector(
            onTap: () => setState(() => _currentCategoryIndex = index),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF0D47A1) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: isSelected ? const Color(0xFF0D47A1) : Colors.grey.shade300),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (allDone)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.check_circle,
                        color: isSelected ? Colors.white : Colors.green, size: 14),
                  ),
                Text(_categories[index],
                    style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey.shade700,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildItemsList() {
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _currentItems.length,
      itemBuilder: (context, index) => _buildCard(_currentItems[index]),
    );
  }

  Widget _buildCard(ChecklistItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: item.isChecked ? Colors.green.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: item.isChecked ? Colors.green.shade300 : Colors.grey.shade300,
            width: 1.5),
      ),
      child: InkWell(
        onTap: () => setState(() => item.isChecked = !item.isChecked),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 26, height: 26,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                  color: item.isChecked ? Colors.green : Colors.grey.shade200,
                  shape: BoxShape.circle),
              child: item.isChecked
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: item.isChecked
                    ? Colors.green.withOpacity(0.1)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(item.icon,
                  size: 20,
                  color: item.isChecked ? Colors.green : Colors.grey.shade600),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: item.isChecked ? Colors.green.shade800 : Colors.black87)),
                const SizedBox(height: 2),
                Text(item.description,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                if (!item.isChecked) ...[
                  const SizedBox(height: 6),
                  TextField(
                    onChanged: (val) => setState(() => item.note = val),
                    decoration: InputDecoration(
                      hintText: 'Note any issue (optional)',
                      hintStyle:
                          TextStyle(fontSize: 11, color: Colors.grey.shade400),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: Colors.grey.shade300)),
                    ),
                    style: const TextStyle(fontSize: 12),
                    maxLines: 2,
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade300)),
      child: Row(children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 18),
        const SizedBox(width: 8),
        Expanded(
            child: Text(_submitError,
                style: const TextStyle(color: Colors.red, fontSize: 12))),
        GestureDetector(
            onTap: () => setState(() => _submitError = ''),
            child: const Icon(Icons.close, color: Colors.red, size: 16)),
      ]),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, -2))
        ],
      ),
      child: Row(children: [
        if (_currentCategoryIndex > 0)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _currentCategoryIndex--),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Back'),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
        if (_currentCategoryIndex > 0) const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: _currentCategoryIndex < _categories.length - 1
              ? ElevatedButton.icon(
                  onPressed: () => setState(() => _currentCategoryIndex++),
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: Text('Next: ${_categories[_currentCategoryIndex + 1]}'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D47A1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                )
              : ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check_circle, size: 18),
                  label: Text(_isSubmitting ? 'Saving...' : 'Submit Checklist'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _allChecked ? Colors.green : Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
        ),
      ]),
    );
  }
}