import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class WebSocketException implements Exception {
  final String message;
  final dynamic error;
  
  WebSocketException(this.message, [this.error]);
  
  @override
  String toString() => 'WebSocketException: $message${error != null ? ' - $error' : ''}';
}

class WebSocketMessage {
  final String type;
  final Map<String, dynamic> data;
  final String? messageId;
  final String? timestamp;

  WebSocketMessage({
    required this.type,
    required this.data,
    this.messageId,
    this.timestamp,
  });

  factory WebSocketMessage.fromJson(Map<String, dynamic> json) => WebSocketMessage(
        type: json['type'],
        data: json['data'] ?? {},
        messageId: json['messageId'],
        timestamp: json['timestamp'],
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'data': data,
        if (messageId != null) 'messageId': messageId,
        'timestamp': timestamp ?? DateTime.now().toIso8601String(),
      };
}

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  WebSocketChannel? _channel;
  final StreamController<WebSocketMessage> _messageController = 
      StreamController<WebSocketMessage>.broadcast();
  
  // Connection state
  final ValueNotifier<bool> isConnected = ValueNotifier<bool>(false);
  final ValueNotifier<DateTime?> lastConnectionTime = ValueNotifier<DateTime?>(null);
  final ValueNotifier<Exception?> lastError = ValueNotifier<Exception?>(null);
  
  // Reconnection
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _initialReconnectDelay = Duration(seconds: 1);
  static const Duration _maxReconnectDelay = Duration(seconds: 30);
  
  // Message queue for when connection is down
  final List<WebSocketMessage> _messageQueue = [];
  
  factory WebSocketService() => _instance;
  
  WebSocketService._internal();

  // Get WebSocket URL from environment or use default
  String _getWebSocketUrl(String tripId, {String? authToken}) {
    final baseUrl = dotenv.env['WEBSOCKET_URL'] ?? 'ws://localhost:3001';
    var url = '$baseUrl?tripId=$tripId';
    if (authToken != null) {
      url += '&token=$authToken';
    }
    return url;
  }

  // Connect to WebSocket server
  Future<void> connect(String tripId, {String? authToken}) async {
    try {
      // Close existing connection if any
      await disconnect();
      
      // Create connection headers
      final headers = <String, dynamic>{
        if (authToken != null) 'Authorization': 'Bearer $authToken',
        'X-Client-Type': 'mobile',
        'X-Client-Version': '1.0.0',
      };
      
      // Get WebSocket URL from environment
      final wsUrl = _getWebSocketUrl(tripId, authToken: authToken);
      debugPrint('🔄 Connecting to WebSocket: $wsUrl');
      
      // Create a new WebSocket connection
      final newChannel = IOWebSocketChannel.connect(
        Uri.parse(wsUrl),
        headers: headers,
      );
      
      _channel = newChannel;

      // Reset reconnection attempts on successful connection
      _reconnectAttempts = 0;
      isConnected.value = true;
      lastConnectionTime.value = DateTime.now();
      lastError.value = null;
      
      // Process any queued messages
      _processMessageQueue();

      // Listen for incoming messages using the local variable
      newChannel.stream.listen(
        _handleIncomingMessage,
        onError: (error, stackTrace) {
          debugPrint('WebSocket error: $error\n$stackTrace');
          _handleConnectionError(WebSocketException('WebSocket error', error), stackTrace);
        },
        onDone: () {
          debugPrint('WebSocket connection closed');
          isConnected.value = false;
          _scheduleReconnection(tripId, authToken);
        },
        cancelOnError: true,
      );
      
      debugPrint('✅ WebSocket connected successfully');
      
    } catch (e, stackTrace) {
      debugPrint('❌ WebSocket connection failed: $e\n$stackTrace');
      _handleConnectionError(WebSocketException('Failed to connect to WebSocket', e), stackTrace);
      rethrow;
    }
  }
  
  void _handleIncomingMessage(dynamic message) {
    try {
      if (message is String) {
        final data = jsonDecode(message) as Map<String, dynamic>;
        final wsMessage = WebSocketMessage.fromJson(data);
        
        // Handle message acknowledgment if needed
        if (wsMessage.type == 'ACK') {
          // TODO: Handle acknowledgment
          return;
        }
        
        _messageController.add(wsMessage);
      }
    } catch (e, stackTrace) {
      debugPrint('Error processing WebSocket message: $e\n$stackTrace');
    }
  }
  
  void _handleConnectionError(WebSocketException error, StackTrace stackTrace) {
    debugPrint('WebSocket error: $error\n$stackTrace');
    isConnected.value = false;
    lastError.value = error;
    
    // Notify listeners about the error
    _messageController.addError(error, stackTrace);
  }
  
  void _scheduleReconnection(String tripId, String? authToken) {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('Max reconnection attempts reached');
      return;
    }
    
    // Exponential backoff with jitter
    final delay = _calculateReconnectDelay();
    _reconnectAttempts++;
    
    _reconnectTimer = Timer(delay, () {
      debugPrint('Attempting to reconnect (attempt $_reconnectAttempts)...');
      connect(tripId, authToken: authToken);
    });
  }
  
  Duration _calculateReconnectDelay() {
    final baseDelay = _initialReconnectDelay.inMilliseconds * pow(2, _reconnectAttempts);
    final jitter = (Random().nextDouble() * 1000).toInt(); // Add up to 1s jitter
    final calculatedMs = baseDelay.toInt() + jitter;
    // Ensure the delay is within bounds
    final boundedMs = calculatedMs.clamp(
      _initialReconnectDelay.inMilliseconds,
      _maxReconnectDelay.inMilliseconds,
    );
    return Duration(milliseconds: boundedMs);
  }
  
  void _processMessageQueue() {
    if (_messageQueue.isEmpty) return;
    
    debugPrint('Processing ${_messageQueue.length} queued messages');
    while (_messageQueue.isNotEmpty) {
      final message = _messageQueue.removeAt(0);
      _sendMessageInternal(message);
    }
  }
  
  // Send message to server
  Future<void> sendMessage(String type, Map<String, dynamic> data) async {
    final message = WebSocketMessage(
      type: type,
      data: data,
      messageId: DateTime.now().millisecondsSinceEpoch.toString(),
    );
    
    if (!isConnected.value) {
      debugPrint('Queueing message (${message.type}) - not connected');
      _messageQueue.add(message);
      return;
    }
    
    _sendMessageInternal(message);
  }
  
  void _sendMessageInternal(WebSocketMessage message) {
    try {
      final channel = _channel;
      if (channel != null && channel.closeCode == null) {
        channel.sink.add(jsonEncode(message.toJson()));
      } else {
        throw WebSocketException('Cannot send message - WebSocket is not connected');
      }
    } catch (e, stackTrace) {
      debugPrint('Error sending WebSocket message: $e\n$stackTrace');
      _messageQueue.add(message); // Re-queue failed message
      rethrow;
    }
  }

  // Stream of messages
  Stream<WebSocketMessage> get messageStream => _messageController.stream;

  // Close connection
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    
    try {
      final channel = _channel;
      if (channel != null && channel.closeCode == null) {
        await channel.sink.close();
      }
    } catch (e) {
      debugPrint('Error closing WebSocket: $e');
    } finally {
      _channel = null;
      isConnected.value = false;
    }
  }
  
  // Clean up resources
  void dispose() {
    disconnect();
    _messageController.close();
    isConnected.dispose();
    lastConnectionTime.dispose();
    lastError.dispose();
  }
}