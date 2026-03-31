# Flutter Backend Connection Setup

This document explains how to configure and use the Flutter app to connect to your Node.js backend.

## 🚀 Quick Start

### 1. Environment Configuration

The Flutter app uses a `.env` file for backend configuration. Update the file at `abra_fleet/.env`:

```env
# Backend Configuration
# For Web/Desktop
API_BASE_URL=http://localhost:3000
WEBSOCKET_URL=ws://localhost:3001

# For Android Emulator (uncomment when testing on emulator)
# API_BASE_URL=http://10.0.2.2:3000
# WEBSOCKET_URL=ws://10.0.2.2:3001

# For Physical Device (uncomment and replace with your machine's IP)
# API_BASE_URL=http://192.168.1.100:3000
# WEBSOCKET_URL=ws://192.168.1.100:3001
```

### 2. Backend Services

The Flutter app includes three main backend services:

- **ApiService**: HTTP REST API communication
- **WebSocketService**: Real-time WebSocket communication
- **BackendConnectionManager**: Unified connection management

### 3. Testing Connection

Use the built-in connection test screen to verify backend connectivity:

```dart
import 'package:abra_fleet/features/testing/connection_test_screen.dart';

// Navigate to test screen
Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => const ConnectionTestScreen()),
);
```

## 📋 Available Services

### ApiService

HTTP client for REST API calls:

```dart
import 'package:abra_fleet/core/services/api_service.dart';

final apiService = ApiService();

// Set authentication token
apiService.setAuthToken('your-jwt-token');

// Make API calls
final vehicles = await apiService.getVehicles();
final drivers = await apiService.getDrivers();
final trips = await apiService.getTrips();

// Create new records
await apiService.createVehicle(vehicleData);
await apiService.createDriver(driverData);
await apiService.createTrip(tripData);
```

### WebSocketService

Real-time communication for live tracking:

```dart
import 'package:abra_fleet/core/services/websocket_service.dart';

final wsService = WebSocketService();

// Connect to a trip
await wsService.connect('trip-id-123', authToken: 'your-jwt-token');

// Listen for messages
wsService.messageStream.listen((message) {
  print('Received: ${message.type} - ${message.data}');
});

// Send location update
await wsService.sendMessage('LOCATION_UPDATE', {
  'latitude': 40.7128,
  'longitude': -74.0060,
  'timestamp': DateTime.now().toIso8601String(),
});

// Send status update
await wsService.sendMessage('STATUS_UPDATE', {
  'status': 'en_route',
  'timestamp': DateTime.now().toIso8601String(),
});
```

### BackendConnectionManager

Unified connection management:

```dart
import 'package:abra_fleet/core/services/backend_connection_manager.dart';

final connectionManager = BackendConnectionManager();

// Initialize (done automatically in main.dart)
await connectionManager.initialize();

// Set authentication
connectionManager.setAuthToken('your-jwt-token');

// Connect to backend
await connectionManager.connect();

// Connect to specific trip
await connectionManager.connectToTrip('trip-id-123');

// Send real-time updates
await connectionManager.sendLocationUpdate(40.7128, -74.0060);
await connectionManager.sendStatusUpdate('arrived');
await connectionManager.sendEmergencyAlert('Need assistance');

// Monitor connection status
connectionManager.connectionStatus.addListener(() {
  print('Connection status: ${connectionManager.connectionStatus.value}');
});
```

## 🔧 Configuration Options

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `API_BASE_URL` | Backend API base URL | `http://localhost:3000` |
| `WEBSOCKET_URL` | WebSocket server URL | `ws://localhost:3001` |
| `FIREBASE_PROJECT_ID` | Firebase project ID | `abrafleet-cec94` |
| `MONGODB_URI` | MongoDB connection string | Cloud Atlas URI |

### Network Configuration

#### For Web/Desktop Development
```env
API_BASE_URL=http://localhost:3000
WEBSOCKET_URL=ws://localhost:3001
```

#### For Android Emulator
```env
API_BASE_URL=http://10.0.2.2:3000
WEBSOCKET_URL=ws://10.0.2.2:3001
```

#### For Physical Device
Replace `192.168.1.100` with your development machine's IP:
```env
API_BASE_URL=http://192.168.1.100:3000
WEBSOCKET_URL=ws://192.168.1.100:3001
```

## 🧪 Testing Backend Connection

### 1. Connection Test Screen

Navigate to the connection test screen from your app:

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const ConnectionTestScreen(),
  ),
);
```

### 2. Programmatic Testing

```dart
import 'package:abra_fleet/core/services/connection_test.dart';

// Test all connections
final results = await ConnectionTest.testAllConnections(
  tripId: 'test-trip-123',
  authToken: 'your-jwt-token',
);

// Generate report
final report = ConnectionTest.generateTestReport(results);
print(report);

// Test specific endpoints
final apiResults = await ConnectionTest.testApiEndpoints(
  authToken: 'your-jwt-token',
);
```

## 🔐 Authentication Integration

### Setting Up Authentication

```dart
// After successful login
final loginResponse = await apiService.login(email, password);
final token = loginResponse['token'];

// Set token for all services
connectionManager.setAuthToken(token);

// Connect to backend
await connectionManager.connect();
```

### Clearing Authentication

```dart
// On logout
await apiService.logout();
connectionManager.clearAuthToken();
await connectionManager.disconnect();
```

## 📱 Real-time Features

### Location Tracking

```dart
// Send location updates
await connectionManager.sendLocationUpdate(
  latitude,
  longitude,
  additionalData: {
    'speed': 45.0,
    'heading': 180.0,
    'accuracy': 5.0,
  },
);
```

### Status Updates

```dart
// Update trip status
await connectionManager.sendStatusUpdate(
  'en_route',
  additionalData: {
    'eta': DateTime.now().add(Duration(minutes: 30)).toIso8601String(),
    'distance_remaining': 15.5,
  },
);
```

### Emergency Alerts

```dart
// Send emergency alert
await connectionManager.sendEmergencyAlert(
  'Vehicle breakdown - need assistance',
  additionalData: {
    'location': 'Highway 101, Mile Marker 45',
    'severity': 'high',
  },
);
```

## 🐛 Troubleshooting

### Common Issues

1. **Connection Refused**
   - Ensure backend server is running on correct port
   - Check firewall settings
   - Verify IP address for physical devices

2. **WebSocket Connection Failed**
   - Confirm WebSocket server is running (port 3001)
   - Check authentication token is valid
   - Verify trip ID exists

3. **API Calls Failing**
   - Check API server is running (port 3000)
   - Verify authentication token
   - Check request format and endpoints

### Debug Information

```dart
// Get connection info for debugging
final info = connectionManager.getConnectionInfo();
print('Connection Info: $info');

// Check individual service status
print('API Health: ${await apiService.checkHealth()}');
print('WebSocket Connected: ${wsService.isConnected.value}');
```

### Logs

The services provide detailed logging. Look for these prefixes in console:
- `🔄` - Connection attempts
- `✅` - Successful operations
- `❌` - Errors
- `📡` - API responses
- `🌐` - Network requests

## 🚀 Production Deployment

### Environment Configuration

For production, update the `.env` file with production URLs:

```env
API_BASE_URL=https://your-api-domain.com
WEBSOCKET_URL=wss://your-websocket-domain.com
```

### Security Considerations

1. Use HTTPS/WSS in production
2. Implement proper JWT token refresh
3. Add request timeout configurations
4. Enable connection retry logic
5. Implement proper error handling

## 📚 API Endpoints

The backend supports these main endpoints:

### Authentication
- `POST /auth/login` - User login
- `POST /auth/register` - User registration
- `POST /auth/logout` - User logout

### Vehicles
- `GET /vehicles` - List all vehicles
- `POST /vehicles` - Create vehicle
- `GET /vehicles/:id` - Get vehicle details
- `PUT /vehicles/:id` - Update vehicle
- `DELETE /vehicles/:id` - Delete vehicle

### Drivers
- `GET /drivers` - List all drivers
- `POST /drivers` - Create driver
- `GET /drivers/:id` - Get driver details
- `PUT /drivers/:id` - Update driver
- `DELETE /drivers/:id` - Delete driver

### Trips
- `GET /trips` - List all trips
- `POST /trips` - Create trip
- `GET /trips/:id` - Get trip details
- `PUT /trips/:id` - Update trip
- `DELETE /trips/:id` - Delete trip
- `POST /trips/:id/location` - Update trip location

### WebSocket Events

#### Outgoing (Flutter → Backend)
- `LOCATION_UPDATE` - Send location data
- `STATUS_UPDATE` - Send status change
- `EMERGENCY_ALERT` - Send emergency notification

#### Incoming (Backend → Flutter)
- `LOCATION_UPDATE` - Receive location updates
- `STATUS_UPDATE` - Receive status changes
- `ETA_UPDATE` - Receive ETA updates
- `EMERGENCY_ALERT` - Receive emergency alerts
- `CONNECTION_ESTABLISHED` - Connection confirmation
- `ACK` - Message acknowledgment
- `ERROR` - Error notifications

## 🎯 Next Steps

1. Start your backend server
2. Update `.env` with correct URLs
3. Run the connection tests
4. Integrate authentication flow
5. Implement real-time features
6. Test on different platforms (web, mobile)

For additional help, check the connection test screen or review the service implementations in `lib/core/services/`.
