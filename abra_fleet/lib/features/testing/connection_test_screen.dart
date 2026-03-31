import 'package:flutter/material.dart';
import '../../core/services/connection_test.dart';
import '../../core/services/backend_connection_manager.dart';

class ConnectionTestScreen extends StatefulWidget {
  const ConnectionTestScreen({Key? key}) : super(key: key);

  @override
  State<ConnectionTestScreen> createState() => _ConnectionTestScreenState();
}

class _ConnectionTestScreenState extends State<ConnectionTestScreen> {
  final BackendConnectionManager _connectionManager = BackendConnectionManager();
  bool _isLoading = false;
  String _testResults = '';
  Map<String, ConnectionTestResult> _lastResults = {};

  @override
  void initState() {
    super.initState();
    _initializeConnectionManager();
  }

  Future<void> _initializeConnectionManager() async {
    await _connectionManager.initialize();
  }

  Future<void> _runBasicTests() async {
    setState(() {
      _isLoading = true;
      _testResults = 'Running basic connectivity tests...\n';
    });

    try {
      final results = await ConnectionTest.testAllConnections();
      final report = ConnectionTest.generateTestReport(results);
      
      setState(() {
        _lastResults = results;
        _testResults = report;
      });
    } catch (e) {
      setState(() {
        _testResults = 'Test failed with error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _runTripTests() async {
    setState(() {
      _isLoading = true;
      _testResults = 'Running trip connectivity tests...\n';
    });

    try {
      const testTripId = 'test-trip-123';
      final results = await ConnectionTest.testAllConnections(tripId: testTripId);
      final report = ConnectionTest.generateTestReport(results);
      
      setState(() {
        _lastResults = results;
        _testResults = report;
      });
    } catch (e) {
      setState(() {
        _testResults = 'Trip test failed with error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _runEndpointTests() async {
    setState(() {
      _isLoading = true;
      _testResults = 'Running API endpoint tests...\n';
    });

    try {
      final results = await ConnectionTest.testApiEndpoints();
      final report = ConnectionTest.generateTestReport(results);
      
      setState(() {
        _lastResults = results;
        _testResults = report;
      });
    } catch (e) {
      setState(() {
        _testResults = 'Endpoint test failed with error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildConnectionStatus() {
    return ValueListenableBuilder(
      valueListenable: _connectionManager.connectionStatus,
      builder: (context, status, child) {
        Color statusColor;
        IconData statusIcon;
        String statusText;

        switch (status) {
          case ConnectionStatus.connected:
            statusColor = Colors.green;
            statusIcon = Icons.check_circle;
            statusText = 'Connected';
            break;
          case ConnectionStatus.connecting:
            statusColor = Colors.orange;
            statusIcon = Icons.sync;
            statusText = 'Connecting...';
            break;
          case ConnectionStatus.reconnecting:
            statusColor = Colors.orange;
            statusIcon = Icons.refresh;
            statusText = 'Reconnecting...';
            break;
          case ConnectionStatus.error:
            statusColor = Colors.red;
            statusIcon = Icons.error;
            statusText = 'Error';
            break;
          case ConnectionStatus.disconnected:
          default:
            statusColor = Colors.grey;
            statusIcon = Icons.cloud_off;
            statusText = 'Disconnected';
            break;
        }

        return Card(
          child: ListTile(
            leading: Icon(statusIcon, color: statusColor),
            title: Text('Backend Status'),
            subtitle: Text(statusText),
            trailing: ValueListenableBuilder(
              valueListenable: _connectionManager.lastError,
              builder: (context, error, child) {
                if (error != null) {
                  return IconButton(
                    icon: const Icon(Icons.info, color: Colors.red),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Connection Error'),
                          content: Text(error),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildTestResults() {
    if (_testResults.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'No tests run yet. Click a test button to start.',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Test Results:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: SingleChildScrollView(
                child: Text(
                  _testResults,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backend Connection Test'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildConnectionStatus(),
            const SizedBox(height: 16),
            
            // Test buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _runBasicTests,
                    icon: const Icon(Icons.network_check),
                    label: const Text('Basic Tests'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _runTripTests,
                    icon: const Icon(Icons.route),
                    label: const Text('Trip Tests'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _runEndpointTests,
              icon: const Icon(Icons.api),
              label: const Text('API Endpoint Tests'),
            ),
            
            const SizedBox(height: 16),
            
            // Loading indicator
            if (_isLoading)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 8),
                    Text('Running tests...'),
                  ],
                ),
              ),
            
            // Test results
            Expanded(
              child: _buildTestResults(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final info = _connectionManager.getConnectionInfo();
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Connection Info'),
              content: SingleChildScrollView(
                child: Text(
                  info.entries
                      .map((e) => '${e.key}: ${e.value}')
                      .join('\n'),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        },
        child: const Icon(Icons.info),
      ),
    );
  }
}
