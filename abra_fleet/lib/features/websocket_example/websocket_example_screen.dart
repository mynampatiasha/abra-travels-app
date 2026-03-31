import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../core/providers/websocket_provider.dart';

class WebSocketExampleScreen extends StatefulWidget {
  const WebSocketExampleScreen({super.key});

  @override
  _WebSocketExampleScreenState createState() => _WebSocketExampleScreenState();
}

class _WebSocketExampleScreenState extends State<WebSocketExampleScreen> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _tripIdController = TextEditingController(text: 'test123');
  final TextEditingController _authTokenController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Load the auth token from environment variables or your auth provider
    _authTokenController.text = 'YOUR_AUTH_TOKEN_HERE'; // Replace with actual token
  }

  @override
  void dispose() {
    _messageController.dispose();
    _tripIdController.dispose();
    _authTokenController.dispose();
    super.dispose();
  }

  void _sendMessage(WebSocketProvider wsProvider) {
    if (_messageController.text.isNotEmpty) {
      wsProvider.sendMessage({
        'type': 'CUSTOM_MESSAGE',
        'data': {
          'message': _messageController.text,
          'timestamp': DateTime.now().toIso8601String(),
        },
      });
      _messageController.clear();
    }
  }

  void _sendLocationUpdate(WebSocketProvider wsProvider) {
    wsProvider.sendMessage({
      'type': 'LOCATION_UPDATE',
      'data': {
        'latitude': 1.2345 + (DateTime.now().millisecondsSinceEpoch % 100) / 10000,
        'longitude': 2.3456 + (DateTime.now().millisecondsSinceEpoch % 100) / 10000,
        'accuracy': 10.0,
        'speed': 25.5,
        'heading': 90,
        'timestamp': DateTime.now().toIso8601String(),
      },
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebSocket Example'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              final wsProvider = context.read<WebSocketProvider>();
              wsProvider.connect(
                _tripIdController.text,
                _authTokenController.text,
              );
            },
          ),
        ],
      ),
      body: ChangeNotifierProvider(
        create: (_) => WebSocketProvider(),
        child: Consumer<WebSocketProvider>(
          builder: (context, wsProvider, _) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Connection Status
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Connection Status',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: wsProvider.isConnected ? Colors.green : Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                wsProvider.isConnected ? 'Connected' : 'Disconnected',
                                style: TextStyle(
                                  color: wsProvider.isConnected ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          if (wsProvider.error != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Error: ${wsProvider.error}',
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Connection Settings
                  TextField(
                    controller: _tripIdController,
                    decoration: const InputDecoration(
                      labelText: 'Trip ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _authTokenController,
                    decoration: const InputDecoration(
                      labelText: 'Auth Token',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: wsProvider.isConnected
                        ? () {
                            wsProvider.disconnect();
                          }
                        : () {
                            wsProvider.connect(
                              _tripIdController.text,
                              _authTokenController.text,
                            );
                          },
                    child: Text(wsProvider.isConnected ? 'Disconnect' : 'Connect'),
                  ),

                  const SizedBox(height: 24),

                  // Send Message
                  const Text(
                    'Send Test Message',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            hintText: 'Type a message...',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _sendMessage(wsProvider),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: () => _sendMessage(wsProvider),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => _sendLocationUpdate(wsProvider),
                    child: const Text('Send Location Update'),
                  ),

                  const SizedBox(height: 24),

                  // Received Messages
                  const Text(
                    'Last Received Message',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          wsProvider.lastMessage ?? 'No messages received yet',
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
