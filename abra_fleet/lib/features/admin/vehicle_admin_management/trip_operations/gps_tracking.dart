// lib/features/admin/vehicle_admin_management/trip_operations/gps_tracking.dart
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import '../../../../app/config/api_config.dart';
import '../../../../core/services/api_service.dart';

class GPSTrackingScreen extends StatefulWidget {
  const GPSTrackingScreen({Key? key}) : super(key: key);
  @override
  State<GPSTrackingScreen> createState() => _GPSTrackingScreenState();
}

class _GPSTrackingScreenState extends State<GPSTrackingScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _imeiCtrl = TextEditingController();
  final TextEditingController _modelCtrl = TextEditingController();
  final TextEditingController _simCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _vehicleSearchCtrl = TextEditingController();

  String? _selectedVehicleId;
  String? _selectedVehicleName;
  List<Map<String, dynamic>> devices = [];
  List<Map<String, dynamic>> availableVehicles = [];
  List<String> testLogs = [];
  bool isTesting = false, isLoading = false, isLoadingVehicles = false;

  // Pagination
  int currentPage = 1;
  int totalPages = 1;
  int totalDeviceCount = 0;
  int pageSize = 50;
  String searchQuery = '';
  String statusFilter = 'all';

  // Statistics
  int totalCount = 0;
  int assignedCount = 0;
  int activeCount = 0;
  int unassignedCount = 0;

  Timer? _refreshTimer;
  Timer? _searchDebounce;

  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _loadAvailableVehicles();
    // Auto-refresh every 30 seconds — SILENT, no dialogs on failure
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadDevices());
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchDebounce?.cancel();
    _imeiCtrl.dispose();
    _modelCtrl.dispose();
    _simCtrl.dispose();
    _searchCtrl.dispose();
    _vehicleSearchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (searchQuery != _searchCtrl.text) {
        setState(() {
          searchQuery = _searchCtrl.text;
          currentPage = 1;
        });
        _loadDevices();
      }
    });
  }

  // ✅ COMPLETELY SILENT on failure — no dialog, no snackbar, just prints to console
  Future<void> _loadDevices() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      final Map<String, String> queryParams = {
        'page': currentPage.toString(),
        'limit': pageSize.toString(),
      };
      if (searchQuery.isNotEmpty) queryParams['search'] = searchQuery;
      if (statusFilter != 'all') queryParams['status'] = statusFilter;

      final data = await _apiService.get('/api/gps/devices', queryParams: queryParams);

      if (!mounted) return;

      setState(() {
        devices = List<Map<String, dynamic>>.from(data['devices'] ?? []);
        totalDeviceCount = data['pagination']?['total'] ?? 0;
        totalPages = data['pagination']?['pages'] ?? 1;
        final stats = data['statistics'] ?? {};
        totalCount = stats['total'] ?? 0;
        assignedCount = stats['assigned'] ?? 0;
        activeCount = stats['active'] ?? 0;
        unassignedCount = stats['unassigned'] ?? 0;
      });
    } catch (e) {
      // ✅ SILENT: console log only — NEVER show any dialog for background loads
      print('❌ GPS load devices error: $e');
      if (mounted) {
        setState(() {
          devices = [];
          totalDeviceCount = 0;
          totalPages = 1;
          totalCount = 0;
          assignedCount = 0;
          activeCount = 0;
          unassignedCount = 0;
        });
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ✅ COMPLETELY SILENT on failure — no dialog, shows empty list
  Future<void> _loadAvailableVehicles({String search = ''}) async {
    if (!mounted) return;
    setState(() => isLoadingVehicles = true);

    try {
      final Map<String, String> queryParams = {'limit': '100'};
      if (search.isNotEmpty) queryParams['search'] = search;

      final data = await _apiService.get('/api/gps/vehicles/available', queryParams: queryParams);

      if (mounted) {
        setState(() {
          availableVehicles = List<Map<String, dynamic>>.from(data['vehicles'] ?? []);
        });
      }
    } catch (e) {
      // ✅ SILENT: console log only — show empty list gracefully
      print('❌ GPS load vehicles error: $e');
      if (mounted) setState(() => availableVehicles = []);
    } finally {
      if (mounted) setState(() => isLoadingVehicles = false);
    }
  }

  Future<void> _registerDevice() async {
    if (!_formKey.currentState!.validate()) return;

    final imei = _imeiCtrl.text.trim();
    if (devices.any((d) => d['imei'] == imei)) {
      _showError('Duplicate IMEI', 'IMEI already registered');
      return;
    }

    setState(() => isLoading = true);

    try {
      final body = {
        'imei': imei,
        'model': _modelCtrl.text.trim(),
        'sim': _simCtrl.text.trim(),
        'vehicleId': _selectedVehicleId ?? 'unassigned',
      };

      await _apiService.post('/api/gps/devices', body: body);

      _showSuccess(
        'Registered!',
        'IMEI: $imei\n${_selectedVehicleName ?? "Unassigned"}\n\n✅ Next: Test connection before installation',
      );
      _clearForm();
      _loadDevices();
      _loadAvailableVehicles();
    } catch (e) {
      _showError('Registration Failed', e.toString());
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _testConnection(String? imei) async {
    final testImei = imei ?? _imeiCtrl.text.trim();
    if (testImei.isEmpty) {
      _showError('No IMEI', 'Enter IMEI to test');
      return;
    }

    setState(() {
      isTesting = true;
      testLogs = ['⏳ Testing IMEI: $testImei...', '🔄 Contacting device...'];
    });

    try {
      await Future.delayed(const Duration(milliseconds: 500));
      final data = await _apiService.post('/api/gps/devices/$testImei/test');
      await Future.delayed(const Duration(milliseconds: 300));

      setState(() {
        testLogs.addAll([
          '',
          '✅ Server Connection: SUCCESS',
          '✅ GPS Module: ACTIVE',
          '✅ SIM Network: CONNECTED',
          '',
          '📍 Current Location:',
          '   Lat: ${data['latitude']}',
          '   Lng: ${data['longitude']}',
          '',
          '🛰️ Satellites: ${data['satellites'] ?? 'N/A'}',
          '📶 Signal: ${data['signal'] ?? 'Unknown'}',
          '⏰ Last Update: ${data['lastUpdate'] ?? 'Just now'}',
          '',
          '✅ ALL TESTS PASSED',
          '✅ Device ready for installation!',
        ]);
      });
      _showSuccess('Test Passed!', 'Device is working correctly');
    } catch (e) {
      Map<String, dynamic> err = {};
      if (e.toString().contains('ApiException:')) {
        try {
          final errorJson = e.toString().replaceFirst('ApiException: ', '');
          err = Map<String, dynamic>.from(json.decode(errorJson));
        } catch (_) {
          err = {'message': e.toString(), 'code': 'UNKNOWN'};
        }
      } else {
        err = {'message': e.toString(), 'code': 'NETWORK_ERROR'};
      }
      _handleTestError(err);
    } finally {
      if (mounted) setState(() => isTesting = false);
    }
  }

  void _handleTestError(Map<String, dynamic> err) {
    final code = err['code'] ?? 'UNKNOWN';
    setState(() {
      testLogs = [
        '❌ TEST FAILED',
        'Error Code: $code',
        '',
        'Problem: ${err['message'] ?? 'Unknown error'}',
        '',
      ];
    });

    List<String> actions = [];
    switch (code) {
      case 'NO_RESPONSE':
        actions = [
          '🔧 IMMEDIATE ACTIONS:',
          '',
          '1️⃣ Check Power',
          '   • Verify device is powered ON',
          '   • Check red LED is lit',
          '   • Inspect power connections',
          '',
          '2️⃣ Wait for Boot',
          '   • Device needs 2-3 min to boot',
          '   • Wait for GPS lock (blue LED)',
          '   • Wait for network (green LED)',
          '',
          '3️⃣ Restart Device',
          '   • Power OFF for 30 seconds',
          '   • Power ON and wait 3 minutes',
          '   • Retest connection',
          '',
          '4️⃣ If Still Fails',
          '   • Device may be faulty',
          '   • Contact supplier',
          '   • Request replacement',
        ];
        break;
      case 'SIM_NOT_ACTIVATED':
        actions = [
          '🔧 SIM CARD ISSUE:',
          '',
          'SIM Number: ${err['sim'] ?? 'Unknown'}',
          '',
          '1️⃣ Contact Provider',
          '   • Call customer service',
          '   • Verify SIM activation',
          '   • Confirm data plan active',
          '',
          '2️⃣ Check Account',
          '   • Verify balance',
          '   • Check data quota',
          '   • No service suspension',
          '',
          '3️⃣ Wait & Retry',
          '   • Activation takes 15-30 min',
          '   • Restart after activation',
          '   • Retest connection',
        ];
        break;
      case 'NO_GPS_SIGNAL':
        actions = [
          '🔧 GPS SIGNAL ISSUE:',
          '',
          '1️⃣ Environment',
          '   • Move to outdoor area',
          '   • Clear sky view needed',
          '   • Away from buildings',
          '   • Remove metal objects',
          '',
          '2️⃣ Wait for Lock',
          '   • First lock: 5-10 minutes',
          '   • Blue LED blinks → solid',
          '   • Be patient outdoors',
          '',
          '3️⃣ Check Antenna',
          '   • Verify connected',
          '   • Check for damage',
          '   • Proper placement',
          '',
          '4️⃣ Post-Install',
          '   • Better after installation',
          '   • Vehicle roof = better signal',
        ];
        break;
      case 'WEAK_SIGNAL':
        actions = [
          '⚠️ WEAK NETWORK:',
          '',
          'Signal: ${err['signal'] ?? 'Unknown'}',
          '',
          '1️⃣ Coverage',
          '   • Check coverage map',
          '   • Move to better area',
          '   • Try different location',
          '',
          '2️⃣ Settings',
          '   • Verify APN config',
          '   • Check network settings',
          '   • Restart connection',
          '',
          '3️⃣ Provider',
          '   • Different provider?',
          '   • Check 4G coverage',
          '   • Verify data plan',
        ];
        break;
      case 'DEVICE_NOT_CONFIGURED':
        actions = [
          '🔧 CONFIG NEEDED:',
          '',
          'Server IP: ${err['server_ip'] ?? 'YOUR_IP'}',
          'Port: ${err['server_port'] ?? '8080'}',
          '',
          '1️⃣ SMS Commands',
          '   SERVER123456,IP,PORT#',
          '   APN123456,YOUR_APN#',
          '   TIMER123456,30#',
          '',
          '2️⃣ Verify',
          '   Send: STATUS#',
          '   Reply: "Server OK"',
          '',
          '3️⃣ Common APNs',
          '   Airtel: airtelgprs.com',
          '   Jio: jionet',
          '   Vi: www',
        ];
        break;
      case 'NETWORK_ERROR':
        actions = [
          '🔧 NETWORK ERROR:',
          '',
          '1️⃣ Your Internet',
          '   • Check WiFi/data',
          '   • Try opening website',
          '   • Restart connection',
          '',
          '2️⃣ Backend Server',
          '   • Is server running?',
          '   • Check server logs',
          '   • Verify API endpoint',
          '',
          '3️⃣ Firewall',
          '   • Check settings',
          '   • Allow port 3001',
          '   • Test different network',
        ];
        break;
      default:
        actions = [
          '🔧 UNKNOWN ERROR:',
          '',
          'Message: ${err['message']}',
          '',
          '1️⃣ Note Details',
          '   • Screenshot error',
          '   • Note IMEI',
          '   • Note error code',
          '',
          '2️⃣ Check Manual',
          '   • Device manual',
          '   • Troubleshooting section',
          '',
          '3️⃣ Contact Support',
          '   • Supplier support',
          '   • Provide details',
        ];
    }

    setState(() => testLogs.addAll(actions));
  }

  Future<void> _deleteDevice(String imei, String vehicleName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('⚠️ Delete GPS Device?'),
        content: Text('Delete:\n\nIMEI: $imei\nVehicle: $vehicleName\n\nThis will delete all location history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _apiService.delete('/api/gps/devices/$imei');
      _showSuccess('Deleted', 'Device removed successfully');
      _loadDevices();
      _loadAvailableVehicles();
    } catch (e) {
      _showError('Delete Failed', e.toString());
    }
  }

  void _showVehicleSelector() {
    _vehicleSearchCtrl.clear();
    _loadAvailableVehicles();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('🚗 Select Vehicle'),
          content: SizedBox(
            width: 500,
            height: 500,
            child: Column(
              children: [
                TextField(
                  controller: _vehicleSearchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search vehicles...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (v) {
                    setDialogState(() {});
                    _loadAvailableVehicles(search: v);
                  },
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: isLoadingVehicles
                      ? const Center(child: CircularProgressIndicator())
                      : availableVehicles.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.info, size: 48, color: Colors.grey),
                                  const SizedBox(height: 16),
                                  const Text('No available vehicles'),
                                  Text('All have GPS assigned', style: TextStyle(color: Colors.grey[600])),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: availableVehicles.length + 1,
                              itemBuilder: (c, i) {
                                if (i == 0) {
                                  return ListTile(
                                    leading: const Icon(Icons.clear, color: Colors.orange),
                                    title: const Text('-- Not Assigned --'),
                                    onTap: () {
                                      setState(() {
                                        _selectedVehicleId = null;
                                        _selectedVehicleName = null;
                                      });
                                      Navigator.pop(context);
                                    },
                                  );
                                }
                                final vehicle = availableVehicles[i - 1];
                                return ListTile(
                                  leading: const Icon(Icons.directions_bus, color: Colors.blue),
                                  title: Text(vehicle['name']),
                                  subtitle: Text('${vehicle['registrationNumber']} • ${vehicle['type'] ?? 'N/A'}'),
                                  onTap: () {
                                    setState(() {
                                      _selectedVehicleId = vehicle['id'];
                                      _selectedVehicleName = vehicle['name'];
                                    });
                                    Navigator.pop(context);
                                  },
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }

  void _clearForm() {
    _imeiCtrl.clear();
    _modelCtrl.clear();
    _simCtrl.clear();
    setState(() {
      _selectedVehicleId = null;
      _selectedVehicleName = null;
      testLogs.clear();
    });
  }

  // ✅ _showError is ONLY for explicit user actions: register, delete, test
  // NEVER call from _loadDevices() or _loadAvailableVehicles()
  void _showError(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.error, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(child: Text(title)),
        ]),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
  }

  void _showSuccess(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 10),
          Expanded(child: Text(title)),
        ]),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('🛰️ GPS Device Management'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadDevices, tooltip: 'Refresh'),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildStats(),
            const SizedBox(height: 32),
            LayoutBuilder(
              builder: (c, constraints) {
                if (constraints.maxWidth > 1200) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 450, child: _buildRegForm()),
                      const SizedBox(width: 24),
                      Expanded(child: _buildDeviceList()),
                    ],
                  );
                }
                return Column(children: [
                  _buildRegForm(),
                  const SizedBox(height: 24),
                  _buildDeviceList(),
                ]);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats() {
    return Row(
      children: [
        Expanded(child: _statCard('📡', '$totalCount', 'Total Devices', const Color(0xFFDBEAFE), Colors.blue)),
        const SizedBox(width: 16),
        Expanded(child: _statCard('🚗', '$assignedCount', 'Assigned', const Color(0xFFDDD6FE), Colors.purple)),
        const SizedBox(width: 16),
        Expanded(child: _statCard('✅', '$activeCount', 'Active Online', const Color(0xFFD1FAE5), Colors.green)),
        const SizedBox(width: 16),
        Expanded(child: _statCard('⚠️', '$unassignedCount', 'Unassigned', const Color(0xFFFEF3C7), Colors.orange)),
      ],
    );
  }

  Widget _statCard(String icon, String val, String label, Color bg, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(val, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: iconColor)),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
            ],
          ),
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(icon, style: const TextStyle(fontSize: 24))),
          ),
        ],
      ),
    );
  }

  Widget _buildRegForm() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
            ),
            child: Row(
              children: const [
                Icon(Icons.add_circle_outline, color: Color(0xFF3B82F6)),
                SizedBox(width: 12),
                Text('Register New GPS Device', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _imeiCtrl,
                    maxLength: 15,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'IMEI Number *',
                      hintText: '861234567890123',
                      helperText: '15-digit ID on device label',
                      prefixIcon: const Icon(Icons.fingerprint),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      counterText: '',
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'IMEI required';
                      if (!RegExp(r'^\d{15}$').hasMatch(v)) return 'Must be 15 digits';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _modelCtrl,
                    decoration: InputDecoration(
                      labelText: 'Device Brand/Model',
                      hintText: 'e.g., Teltonika FMB920',
                      prefixIcon: const Icon(Icons.devices),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _simCtrl,
                    decoration: InputDecoration(
                      labelText: 'SIM Card Number',
                      hintText: '+91 98765 43210',
                      prefixIcon: const Icon(Icons.sim_card),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  InkWell(
                    onTap: _showVehicleSelector,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            const Icon(Icons.directions_bus, color: Colors.blue),
                            const SizedBox(width: 12),
                            Text(
                              _selectedVehicleName ?? 'Select Vehicle (Optional)',
                              style: TextStyle(
                                fontSize: 16,
                                color: _selectedVehicleName != null ? Colors.black : Colors.grey,
                              ),
                            ),
                          ]),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  ),
                  if (_selectedVehicleName != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 16),
                        const SizedBox(width: 8),
                        Text('Assigned to: $_selectedVehicleName', style: const TextStyle(color: Colors.green, fontSize: 12)),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setState(() { _selectedVehicleId = null; _selectedVehicleName = null; }),
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _registerDevice,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: isLoading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('➕ Register Device', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildTestSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFF0F9FF), Color(0xFFE0F2FE)]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF0EA5E9), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.science, color: Color(0xFF0C4A6E)),
            SizedBox(width: 8),
            Text('🧪 Test GPS Connection', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF0C4A6E))),
          ]),
          const SizedBox(height: 6),
          const Text('Verify connectivity before installation', style: TextStyle(fontSize: 12, color: Color(0xFF0C4A6E))),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isTesting ? null : () => _testConnection(null),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF64748B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: isTesting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('🔄 Run Connection Test', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
          if (testLogs.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              height: 300,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBAE6FD)),
              ),
              child: ListView.builder(
                itemCount: testLogs.length,
                itemBuilder: (c, i) {
                  final log = testLogs[i];
                  Color bg = const Color(0xFFDBEAFE);
                  Color txt = const Color(0xFF1E40AF);
                  if (log.startsWith('✅')) { bg = const Color(0xFFD1FAE5); txt = const Color(0xFF065F46); }
                  else if (log.startsWith('❌') || log.startsWith('⚠️')) { bg = const Color(0xFFFEE2E2); txt = const Color(0xFF991B1B); }
                  else if (log.startsWith('🔧') || log.contains('ACTION')) { bg = const Color(0xFFFEF3C7); txt = const Color(0xFF92400E); }
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                    child: Text(log, style: TextStyle(fontSize: 12, color: txt, fontWeight: FontWeight.w500)),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: const [
                  Icon(Icons.list_alt, color: Color(0xFF3B82F6)),
                  SizedBox(width: 12),
                  Text('Registered GPS Devices', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ]),
                Text('$totalDeviceCount devices', style: const TextStyle(color: Colors.grey, fontSize: 14)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search by IMEI, vehicle, SIM...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButton<String>(
                        value: statusFilter,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All Status')),
                          DropdownMenuItem(value: 'active', child: Text('Active')),
                          DropdownMenuItem(value: 'offline', child: Text('Offline')),
                          DropdownMenuItem(value: 'unassigned', child: Text('Unassigned')),
                        ],
                        onChanged: (v) {
                          setState(() { statusFilter = v!; currentPage = 1; });
                          _loadDevices();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (isLoading)
                  const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
                else if (devices.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(60),
                    child: Column(
                      children: [
                        const Icon(Icons.gps_off, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text('No devices found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        Text('Register your first GPS device', style: TextStyle(color: Colors.grey[600])),
                      ],
                    ),
                  )
                else ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: MaterialStateProperty.all(const Color(0xFFF8FAFC)),
                      columns: const [
                        DataColumn(label: Text('IMEI', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Model', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Vehicle', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('SIM', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Last Update', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                      rows: devices.map((d) {
                        final status = d['status'] ?? 'unknown';
                        Color statusColor = Colors.grey;
                        if (status == 'active') statusColor = Colors.green;
                        if (status == 'offline') statusColor = Colors.red;
                        if (status == 'unassigned') statusColor = Colors.orange;

                        return DataRow(cells: [
                          DataCell(SelectableText(d['imei'] ?? '',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'))),
                          DataCell(Text(d['model'] ?? 'N/A')),
                          DataCell(Text(d['vehicleName'] ?? 'Unassigned')),
                          DataCell(Text(d['sim'] ?? 'N/A')),
                          DataCell(Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: statusColor),
                            ),
                            child: Text(status.toUpperCase(),
                                style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                          )),
                          DataCell(Text(d['lastUpdate'] != null ? _formatDate(d['lastUpdate']) : 'Never')),
                          DataCell(Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Tooltip(
                                message: 'Test Connection',
                                child: IconButton(
                                  icon: const Icon(Icons.bug_report, color: Colors.blue),
                                  onPressed: () => _testConnection(d['imei']),
                                ),
                              ),
                              Tooltip(
                                message: 'Delete Device',
                                child: IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _deleteDevice(d['imei'], d['vehicleName'] ?? 'Unknown'),
                                ),
                              ),
                            ],
                          )),
                        ]);
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildPagination(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPagination() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Page $currentPage of $totalPages ($totalDeviceCount total)',
            style: const TextStyle(color: Colors.grey)),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.first_page),
              onPressed: currentPage > 1 ? () => setState(() { currentPage = 1; _loadDevices(); }) : null,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: currentPage > 1 ? () => setState(() { currentPage--; _loadDevices(); }) : null,
            ),
            ...List.generate(totalPages > 5 ? 5 : totalPages, (i) {
              int pageNum;
              if (totalPages <= 5) pageNum = i + 1;
              else if (currentPage <= 3) pageNum = i + 1;
              else if (currentPage >= totalPages - 2) pageNum = totalPages - 4 + i;
              else pageNum = currentPage - 2 + i;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  onTap: () => setState(() { currentPage = pageNum; _loadDevices(); }),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: currentPage == pageNum ? const Color(0xFF3B82F6) : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text('$pageNum',
                          style: TextStyle(
                            color: currentPage == pageNum ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                          )),
                    ),
                  ),
                ),
              );
            }),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: currentPage < totalPages ? () => setState(() { currentPage++; _loadDevices(); }) : null,
            ),
            IconButton(
              icon: const Icon(Icons.last_page),
              onPressed: currentPage < totalPages ? () => setState(() { currentPage = totalPages; _loadDevices(); }) : null,
            ),
          ],
        ),
      ],
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      DateTime dt = date is String ? DateTime.parse(date) : date;
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (e) {
      return 'Invalid';
    }
  }
}