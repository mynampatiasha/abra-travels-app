# Abra Fleet Management Backend

A comprehensive Node.js backend server for fleet management operations, providing REST APIs, real-time WebSocket communication, and database management for the Abra Fleet Management system.

## 🏗️ Architecture Overview

### Technology Stack
- **Runtime**: Node.js with Express.js framework
- **Database**: MongoDB Atlas (cloud-hosted)
- **Authentication**: Firebase Admin SDK with JWT tokens
- **Real-time Communication**: WebSocket (ws) and Socket.IO
- **API Documentation**: RESTful APIs with JSON responses

### Core Components
```
abra_fleet_backend/
├── index.js                 # Main server entry point
├── config/
│   └── firebase.js          # Firebase Admin SDK configuration
├── middleware/
│   └── auth.js              # Authentication middleware
├── routes/
│   ├── admin-drivers.js     # Driver management APIs
│   ├── admin-vehicles.js    # Vehicle management APIs
│   ├── admin-customers.js   # Customer management APIs
│   ├── admin-trips.js       # Trip management APIs
│   └── tracking.js          # Real-time tracking APIs
├── models/                  # Database models (future implementation)
└── test-*.js               # API testing scripts
```

## 🚀 Getting Started

### Prerequisites
- Node.js (v16 or higher)
- MongoDB Atlas account
- Firebase project with Admin SDK
- npm or yarn package manager

### Installation
1. **Clone and navigate to backend directory**:
   ```bash
   cd abra_fleet_backend
   ```

2. **Install dependencies**:
   ```bash
   npm install
   ```

3. **Environment Configuration**:
   Create a `.env` file with the following variables:
   ```env
   # Server Configuration
   PORT=3000
   NODE_ENV=development

   # MongoDB Atlas Connection
   MONGODB_URI=mongodb+srv://username:password@cluster.mongodb.net/

   # Firebase Configuration
   FIREBASE_PROJECT_ID=your-project-id
   FIREBASE_PRIVATE_KEY_ID=your-private-key-id
   FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
   FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxxxx@your-project.iam.gserviceaccount.com
   FIREBASE_CLIENT_ID=your-client-id
   FIREBASE_AUTH_URI=https://accounts.google.com/o/oauth2/auth
   FIREBASE_TOKEN_URI=https://oauth2.googleapis.com/token

   # JWT Configuration
   JWT_SECRET=your-super-secret-jwt-key
   JWT_EXPIRES_IN=24h
   ```

4. **Firebase Service Account**:
   - Download your Firebase service account key
   - Save as `serviceAccountKey.json.json` in the root directory

5. **Start the server**:
   ```bash
   # Development mode with auto-restart
   npm run dev

   # Production mode
   npm start
   ```

## 📡 API Endpoints

### Public Endpoints (No Authentication Required)
```http
GET  /health              # Server health check
GET  /test-db             # Database connection test
```

### Authentication Test
```http
GET  /api/test-auth       # Test JWT authentication
```

### Driver Management APIs
```http
GET    /api/admin/drivers           # List all drivers
POST   /api/admin/drivers           # Create new driver
GET    /api/admin/drivers/:id       # Get driver by ID
PUT    /api/admin/drivers/:id       # Update driver
DELETE /api/admin/drivers/:id       # Delete driver
GET    /api/admin/drivers/:id/trips # Get driver's trips
```

### Vehicle Management APIs
```http
GET    /api/admin/vehicles              # List all vehicles
POST   /api/admin/vehicles              # Create new vehicle
GET    /api/admin/vehicles/:id          # Get vehicle by ID
PUT    /api/admin/vehicles/:id          # Update vehicle
DELETE /api/admin/vehicles/:id          # Delete vehicle
GET    /api/admin/vehicles/:id/trips    # Get vehicle's trips
POST   /api/admin/vehicles/:id/assign   # Assign driver to vehicle
```

### Customer Management APIs
```http
GET    /api/admin/customers         # List all customers
POST   /api/admin/customers         # Create new customer
GET    /api/admin/customers/:id     # Get customer by ID
PUT    /api/admin/customers/:id     # Update customer
DELETE /api/admin/customers/:id     # Delete customer
GET    /api/admin/customers/:id/trips # Get customer's trips
```

### Trip Management APIs
```http
GET    /api/admin/trips             # List all trips
POST   /api/admin/trips             # Create new trip
GET    /api/admin/trips/:id         # Get trip by ID
PUT    /api/admin/trips/:id         # Update trip
DELETE /api/admin/trips/:id         # Delete trip
POST   /api/admin/trips/:id/start   # Start trip
POST   /api/admin/trips/:id/complete # Complete trip
```

### Real-time Tracking APIs
```http
GET    /api/tracking/vehicles       # Get all vehicle locations
POST   /api/tracking/location       # Update vehicle location
GET    /api/tracking/trips/active   # Get active trips
POST   /api/tracking/emergency      # Send emergency alert
```

## 🔌 WebSocket Communication

### Connection
```javascript
const ws = new WebSocket('ws://localhost:3000');

// Or using Socket.IO
const socket = io('http://localhost:3000');
```

### Real-time Events
- **Location Updates**: Vehicle position changes
- **Trip Status**: Trip start/stop/completion events
- **Emergency Alerts**: Driver emergency notifications
- **System Notifications**: General fleet notifications

### WebSocket Message Format
```json
{
  "type": "location_update",
  "vehicleId": "v001",
  "data": {
    "latitude": 37.7749,
    "longitude": -122.4194,
    "timestamp": "2024-01-15T10:30:00Z",
    "speed": 45.5,
    "heading": 90
  }
}
```

## 🔐 Authentication & Authorization

### JWT Token Authentication
All protected routes require a valid JWT token in the Authorization header:
```http
Authorization: Bearer <your-jwt-token>
```

### Firebase Integration
- User authentication handled by Firebase Auth
- Server validates tokens using Firebase Admin SDK
- Role-based access control for different user types

### Token Generation
Use the provided test script to generate tokens:
```bash
node generate-test-token.js
```

## 🗄️ Database Schema

### Collections
- **drivers**: Driver information and credentials
- **vehicles**: Vehicle details and status
- **customers**: Customer information
- **trips**: Trip records and tracking data
- **locations**: Real-time location history

### Sample Documents

#### Driver Document
```json
{
  "_id": "driver_001",
  "name": "John Smith",
  "email": "john@example.com",
  "phone": "+1234567890",
  "licenseNumber": "DL123456789",
  "status": "active",
  "assignedVehicle": "vehicle_001",
  "createdAt": "2024-01-15T10:00:00Z"
}
```

#### Vehicle Document
```json
{
  "_id": "vehicle_001",
  "name": "Cargo Van 1",
  "licensePlate": "AB-123-CD",
  "model": "Ford Transit",
  "year": 2023,
  "status": "active",
  "assignedDriver": "driver_001",
  "currentLocation": {
    "latitude": 37.7749,
    "longitude": -122.4194,
    "lastUpdate": "2024-01-15T10:30:00Z"
  }
}
```

#### Trip Document
```json
{
  "_id": "trip_001",
  "vehicleId": "vehicle_001",
  "driverId": "driver_001",
  "customerId": "customer_001",
  "status": "active",
  "startLocation": {
    "address": "123 Main St, San Francisco, CA",
    "coordinates": [37.7749, -122.4194]
  },
  "endLocation": {
    "address": "456 Oak Ave, San Francisco, CA",
    "coordinates": [37.7849, -122.4094]
  },
  "startTime": "2024-01-15T10:00:00Z",
  "estimatedEndTime": "2024-01-15T11:00:00Z"
}
```

## 🧪 Testing

### API Testing Scripts
The backend includes comprehensive testing scripts:

```bash
# Test driver APIs
node test-driver-apis.js

# Test vehicle APIs
node test-add-vehicle.js

# Test customer APIs
node test-customer-apis.js

# Test trip APIs
node test-add-trips.js

# Test WebSocket connection
node test-websocket.js
```

### Manual Testing
1. **Health Check**:
   ```bash
   curl http://localhost:3000/health
   ```

2. **Database Test**:
   ```bash
   curl http://localhost:3000/test-db
   ```

3. **Authentication Test**:
   ```bash
   curl -H "Authorization: Bearer <token>" http://localhost:3000/api/test-auth
   ```

## 🔧 Configuration

### Environment Variables
| Variable | Description | Required |
|----------|-------------|----------|
| `PORT` | Server port number | No (default: 3000) |
| `MONGODB_URI` | MongoDB connection string | Yes |
| `FIREBASE_PROJECT_ID` | Firebase project ID | Yes |
| `FIREBASE_PRIVATE_KEY` | Firebase private key | Yes |
| `FIREBASE_CLIENT_EMAIL` | Firebase client email | Yes |
| `JWT_SECRET` | JWT signing secret | Yes |

### Database Setup
Run the database setup script to initialize collections:
```bash
node setup-database.js
```

## 🚀 Deployment

### Production Checklist
- [ ] Set `NODE_ENV=production`
- [ ] Use strong JWT secrets
- [ ] Configure MongoDB Atlas IP whitelist
- [ ] Set up SSL/TLS certificates
- [ ] Configure rate limiting
- [ ] Set up monitoring and logging
- [ ] Configure backup strategies

### Docker Deployment (Optional)
```dockerfile
FROM node:16-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 3000
CMD ["node", "index.js"]
```

## 📊 Monitoring & Logging

### Health Monitoring
- Server health endpoint: `/health`
- Database connectivity: `/test-db`
- Authentication status: `/api/test-auth`

### Error Handling
- Centralized error handling middleware
- Structured error responses
- Graceful shutdown on SIGINT

## 🔒 Security Features

- **JWT Authentication**: Secure token-based authentication
- **Firebase Integration**: Enterprise-grade user management
- **CORS Configuration**: Cross-origin request handling
- **Input Validation**: Request data validation
- **Rate Limiting**: API abuse prevention (configurable)

## 🤝 Integration with Flutter App

### Backend Connection Manager
The Flutter app connects using the `BackendConnectionManager`:
```dart
final connectionManager = BackendConnectionManager();
await connectionManager.initialize();

// HTTP API calls
final response = await connectionManager.apiService.get('/api/vehicles');

// WebSocket communication
connectionManager.webSocketService.sendMessage({
  'type': 'location_update',
  'data': locationData
});
```

### Real-time Features
- Live vehicle tracking
- Trip status updates
- Emergency notifications
- Driver communication

## 📝 Development Notes

### Code Structure
- **Modular Design**: Separate route files for different domains
- **Middleware Pattern**: Reusable authentication and validation
- **Error Handling**: Consistent error response format
- **Database Abstraction**: MongoDB operations wrapped in try-catch

### Best Practices
- Use environment variables for configuration
- Implement proper error handling
- Follow RESTful API conventions
- Maintain consistent response formats
- Use meaningful HTTP status codes

## 🆘 Troubleshooting

### Common Issues

1. **MongoDB Connection Failed**:
   - Check MONGODB_URI in .env file
   - Verify network connectivity
   - Check MongoDB Atlas IP whitelist

2. **Firebase Authentication Error**:
   - Verify Firebase service account key
   - Check Firebase project configuration
   - Ensure proper environment variables

3. **WebSocket Connection Issues**:
   - Check port availability
   - Verify firewall settings
   - Test with WebSocket client tools

### Debug Mode
Enable detailed logging:
```bash
DEBUG=* node index.js
```

## 📞 Support

For issues and questions:
1. Check the troubleshooting section
2. Review API documentation
3. Test with provided scripts
4. Check server logs for detailed error messages

---

**Last Updated**: January 2024  
**Version**: 1.0.0  
**Maintainer**: Abra Fleet Development Team
