import 'package:flutter/material.dart';
import '../../core/services/backend_connection_manager.dart';
import 'connection_test_screen.dart';

class BackendTestScreen extends StatefulWidget {
  const BackendTestScreen({Key? key}) : super(key: key);

  @override
  State<BackendTestScreen> createState() => _BackendTestScreenState();
}

class _BackendTestScreenState extends State<BackendTestScreen> {
  final BackendConnectionManager _connectionManager = BackendConnectionManager();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backend Testing'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Backend Connection Status',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ValueListenableBuilder(
                      valueListenable: _connectionManager.connectionStatus,
                      builder: (context, status, child) {
                        return Row(
                          children: [
                            Icon(
                              _getStatusIcon(status),
                              color: _getStatusColor(status),
                            ),
                            const SizedBox(width: 8),
                            Text(_getStatusText(status)),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ConnectionTestScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.network_check),
              label: const Text('Run Connection Tests'),
            ),
            
            const SizedBox(height: 8),
            
            ElevatedButton.icon(
              onPressed: () => _connectToBackend(),
              icon: const Icon(Icons.connect_without_contact),
              label: const Text('Connect to Backend'),
            ),
            
            const SizedBox(height: 8),
            
            ElevatedButton.icon(
              onPressed: () => _disconnectFromBackend(),
              icon: const Icon(Icons.link_off),
              label: const Text('Disconnect from Backend'),
            ),
            
            const Spacer(),
            
            Card(
              color: Colors.blue[50],
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Backend Configuration',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('• API: http://localhost:3001'),
                    Text('• WebSocket: ws://localhost:3001'),
                    Text('• MongoDB: Cloud Atlas'),
                    SizedBox(height: 8),
                    Text(
                      'Note: Update .env file for different environments',
                      style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getStatusIcon(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return Icons.check_circle;
      case ConnectionStatus.connecting:
        return Icons.sync;
      case ConnectionStatus.reconnecting:
        return Icons.refresh;
      case ConnectionStatus.error:
        return Icons.error;
      case ConnectionStatus.disconnected:
      default:
        return Icons.cloud_off;
    }
  }

  Color _getStatusColor(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return Colors.green;
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
        return Colors.orange;
      case ConnectionStatus.error:
        return Colors.red;
      case ConnectionStatus.disconnected:
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return 'Connected';
      case ConnectionStatus.connecting:
        return 'Connecting...';
      case ConnectionStatus.reconnecting:
        return 'Reconnecting...';
      case ConnectionStatus.error:
        return 'Connection Error';
      case ConnectionStatus.disconnected:
      default:
        return 'Disconnected';
    }
  }

  Future<void> _connectToBackend() async {
    try {
      await _connectionManager.connect();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connected to backend successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _disconnectFromBackend() async {
    try {
      await _connectionManager.disconnect();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Disconnected from backend'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Disconnect error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
