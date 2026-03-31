import 'package:universal_html/html.dart' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart' if (dart.library.html) 'package:web_socket_channel/html.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class WebSocketProvider with ChangeNotifier {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  String? _error;
  String? _lastMessage;

  bool get isConnected => _isConnected;
  String? get error => _error;
  String? get lastMessage => _lastMessage;

  // Connect to WebSocket server
  void connect(String tripId, String authToken) {
    try {
      // Close existing connection if any
      _channel?.sink.close();

      // Get WebSocket URL from environment
      String wsUrl = '${dotenv.env['WEBSOCKET_URL']}/ws?tripId=$tripId';
      
      if (kIsWeb) {
        // For web, handle protocol and CORS
        if (wsUrl.startsWith('ws://') && html.window.location.protocol == 'https:') {
          wsUrl = wsUrl.replaceFirst('ws://', 'wss://');
        }
        
        // Add token to URL for web as headers might be blocked by CORS
        wsUrl += '&token=$authToken';
      }
      
      if (kDebugMode) {
        print('🔄 Connecting to WebSocket: $wsUrl');
      }

      // Create a new WebSocket connection
      if (kIsWeb) {
        try {
          // Web implementation with error handling
          _channel = WebSocketChannel.connect(
            Uri.parse(wsUrl),
          );
          
          // For web, we'll rely on the connection events to update status
          _isConnected = true;
          _error = null;
          notifyListeners();
          
          if (kDebugMode) {
            print('✅ WebSocket connection established');
          }
          
        } catch (e) {
          _handleError('WebSocket connection error: $e');
          return;
        }
      } else {
        // Mobile/Desktop implementation
        try {
          _channel = IOWebSocketChannel.connect(
            Uri.parse(wsUrl),
            headers: {
              'Authorization': 'Bearer $authToken',
              'X-Client-Type': 'mobile',
              'X-Client-Version': '1.0.0',
            },
          );
          _isConnected = true;
          _error = null;
          notifyListeners();
        } catch (e) {
          _handleError('Failed to connect: $e');
          return;
        }
      }

      // Listen for messages only if not web (web handles this differently)
      if (!kIsWeb) {
        _channel!.stream.listen(
          _handleMessage,
          onError: (error) {
            _handleError('WebSocket error: $error');
          },
          onDone: () {
            _handleDisconnect();
          },
        );
      } else {
        // For web, set up event listeners directly
        _channel?.stream.listen(
          _handleMessage,
          onError: (error) {
            _handleError('WebSocket error: $error');
          },
          onDone: () {
            _handleDisconnect();
          },
        );
      }

      if (kDebugMode) {
        print('✅ WebSocket connected successfully');
      }
    } catch (e) {
      _handleError('Failed to connect to WebSocket: $e');
    }
  }

  // Send a message to the WebSocket server
  void sendMessage(Map<String, dynamic> message) {
    if (_channel != null && _isConnected) {
      try {
        _channel!.sink.add(message);
      } catch (e) {
        _handleError('Failed to send message: $e');
      }
    } else {
      _handleError('Not connected to WebSocket');
    }
  }

  // Handle incoming messages
  void _handleMessage(dynamic message) {
    _lastMessage = message.toString();
    if (kDebugMode) {
      print('📨 Received message: $_lastMessage');
    }
    notifyListeners();
  }

  // Handle errors
  void _handleError(String error) {
    _error = error;
    _isConnected = false;
    if (kDebugMode) {
      print('❌ $error');
    }
    notifyListeners();
  }

  // Handle disconnection
  void _handleDisconnect() {
    _isConnected = false;
    if (kDebugMode) {
      print('🔌 WebSocket disconnected');
    }
    notifyListeners();
  }

  // Disconnect from WebSocket server
  void disconnect() {
    _channel?.sink.close();
    _isConnected = false;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
