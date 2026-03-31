const WebSocket = require('ws');
const { ObjectId } = require('mongodb');
const jwt = require('jsonwebtoken');
const { RateLimiterMemory } = require('rate-limiter-flexible');

// Rate limiting: max 100 messages per minute per IP
const rateLimiter = new RateLimiterMemory({
  points: 100, // 100 messages
  duration: 60, // per 60 seconds
});

// Message type validation
const MESSAGE_TYPES = new Set([
  'LOCATION_UPDATE',
  'STATUS_UPDATE',
  'ETA_UPDATE',
  'EMERGENCY_ALERT',
  'ACK',
]);

// Message schema validation
const validateMessage = (message) => {
  if (typeof message !== 'object' || message === null) {
    throw new Error('Message must be an object');
  }

  if (typeof message.type !== 'string' || !MESSAGE_TYPES.has(message.type)) {
    throw new Error(`Invalid message type: ${message.type}`);
  }

  if (typeof message.data !== 'object' || message.data === null) {
    throw new Error('Message data must be an object');
  }

  // Add more specific validation based on message type
  switch (message.type) {
    case 'LOCATION_UPDATE':
      if (typeof message.data.latitude !== 'number' || 
          typeof message.data.longitude !== 'number') {
        throw new Error('Invalid location data');
      }
      break;
    // Add other message type validations as needed
  }

  return true;
};

// Authentication middleware
const authenticate = async (req) => {
  // Try to get token from Authorization header first
  let token = req.headers.authorization?.split(' ')[1];
  
  // If no token in header, try to get from URL query parameters
  if (!token) {
    const queryParams = new URLSearchParams(req.url.split('?')[1] || '');
    token = queryParams.get('token');
  }
  
  if (!token) {
    // For development/testing, allow connections without token
    if (process.env.NODE_ENV === 'development' || process.env.ALLOW_ANONYMOUS_WS === 'true') {
      console.log('⚠️  Anonymous WebSocket connection allowed (development mode)');
      return { id: 'anonymous', role: 'guest' };
    }
    throw new Error('Authentication required');
  }

  try {
    // Verify JWT token
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    return decoded;
  } catch (error) {
    console.error('Authentication error:', error.message);
    
    // For development, allow invalid tokens
    if (process.env.NODE_ENV === 'development' || process.env.ALLOW_ANONYMOUS_WS === 'true') {
      console.log('⚠️  Invalid token ignored (development mode)');
      return { id: 'anonymous', role: 'guest' };
    }
    
    throw new Error('Invalid or expired token');
  }
};

class WSServer {
  constructor(server) {
    // If server is provided, use it, otherwise create a new HTTP server
    if (server) {
      this.wss = new WebSocket.Server({ server });
    } else {
      const http = require('http');
      const port = process.env.WEBSOCKET_PORT || 3001;
      this.server = http.createServer();
      this.wss = new WebSocket.Server({ server: this.server });
      
      this.server.listen(port, () => {
        console.log(`🚀 WebSocket Server running on port ${port}`);
      });
    }
    
    this.clients = new Map(); // Map of tripId -> Map of clientId -> client info
    this.setup();
  }

  setup() {
    this.wss.on('connection', async (ws, req) => {
      try {
        // Rate limiting by IP
        const ip = req.socket.remoteAddress;
        await rateLimiter.consume(ip);

        // Get tripId from query params - make it optional for general connections
        const urlParams = new URLSearchParams(req.url.split('?')[1] || '');
        const tripId = urlParams.get('tripId');
        
        // If no tripId provided, allow general connection but log it
        if (!tripId) {
          console.log('WebSocket connection without tripId - allowing general connection');
        }

        // Authenticate the connection
        const user = await authenticate(req);
        
        // Validate that user has access to this trip (only if tripId is provided)
        if (tripId && !this.hasTripAccess(user, tripId)) {
          throw new Error('Unauthorized access to trip');
        }

        // Generate a unique client ID
        const clientId = this.generateClientId();
        
        // If tripId is provided, add client to the trip's client set
        if (tripId) {
          if (!this.clients.has(tripId)) {
            this.clients.set(tripId, new Map());
          }
          
          this.clients.get(tripId).set(clientId, {
            ws,
            userId: user.id,
            connectedAt: new Date(),
            ip,
          });
          
          console.log(`Client ${clientId} connected to trip ${tripId}`);
        } else {
          // For general connections, store in a general pool
          if (!this.clients.has('general')) {
            this.clients.set('general', new Map());
          }
          
          this.clients.get('general').set(clientId, {
            ws,
            userId: user.id,
            connectedAt: new Date(),
            ip,
          });
          
          console.log(`Client ${clientId} connected (general connection)`);
        }

        // Handle incoming messages
        ws.on('message', (data) => this.handleMessage(ws, clientId, tripId || 'general', data));

        // Handle client disconnection
        ws.on('close', () => {
          const connectionKey = tripId || 'general';
          if (this.clients.has(connectionKey)) {
            this.clients.get(connectionKey).delete(clientId);
            if (this.clients.get(connectionKey).size === 0) {
              this.clients.delete(connectionKey);
            }
            console.log(`Client ${clientId} disconnected from ${connectionKey}`);
          }
        });

        // Handle errors
        ws.on('error', (error) => {
          console.error(`WebSocket error for client ${clientId}:`, error);
          ws.close(1011, 'Internal server error');
        });

        // Send welcome message
        this.sendToClient(ws, {
          type: 'CONNECTION_ESTABLISHED',
          data: { clientId, tripId: tripId || null },
        });

      } catch (error) {
        console.error('WebSocket connection error:', error);
        ws.close(1008, error.message || 'Connection error');
      }
    });
  }

  // Generate a unique client ID
  generateClientId() {
    return Math.random().toString(36).substr(2, 9);
  }

  // Check if user has access to the trip
  hasTripAccess(user, tripId) {
    // TODO: Implement actual trip access logic
    // This is a placeholder - implement based on your auth system
    return true;
  }

  // Handle incoming messages
  async handleMessage(ws, clientId, tripId, data) {
    try {
      const message = JSON.parse(data);
      
      // Validate message structure
      validateMessage(message);
      
      // Add metadata
      message.metadata = {
        sender: clientId,
        timestamp: new Date().toISOString(),
        tripId,
      };

      // Process message based on type
      switch (message.type) {
        case 'LOCATION_UPDATE':
          await this.handleLocationUpdate(message);
          break;
        case 'STATUS_UPDATE':
          await this.handleStatusUpdate(message);
          break;
        // Add other message handlers as needed
      }

      // Broadcast to all clients in the trip
      this.broadcastToTrip(tripId, message);
      
      // Send acknowledgment
      this.sendToClient(ws, {
        type: 'ACK',
        data: { messageId: message.messageId },
      });
      
    } catch (error) {
      console.error('Error handling message:', error);
      this.sendToClient(ws, {
        type: 'ERROR',
        data: { error: error.message },
      });
    }
  }

  // Send message to a specific client
  sendToClient(ws, message) {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(message));
    }
  }

  // Broadcast message to all clients in a trip
  broadcastToTrip(tripId, message) {
    if (this.clients.has(tripId)) {
      const clients = this.clients.get(tripId);
      const messageString = JSON.stringify(message);
      
      clients.forEach(({ ws }) => {
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(messageString);
        }
      });
    }
  }
  
  // Handle location update
  async handleLocationUpdate(message) {
    // TODO: Store location in database
    console.log('Location update:', message);
  }
  
  // Handle status update
  async handleStatusUpdate(message) {
    // TODO: Update trip status in database
    console.log('Status update:', message);
  }

  // Send location update to all clients tracking this trip
  sendLocationUpdate(tripId, locationData) {
    this.broadcastToTrip(tripId, {
      type: 'LOCATION_UPDATE',
      data: locationData,
      timestamp: new Date().toISOString()
    });
  }

  // Send trip status update to all clients
  sendStatusUpdate(tripId, statusData) {
    this.broadcastToTrip(tripId, {
      type: 'STATUS_UPDATE',
      data: statusData,
      timestamp: new Date().toISOString()
    });
  }

  // Send ETA update to all clients
  sendEtaUpdate(tripId, etaData) {
    this.broadcastToTrip(tripId, {
      type: 'ETA_UPDATE',
      data: etaData,
      timestamp: new Date().toISOString()
    });
  }

  // Send emergency alert to all clients
  sendEmergencyAlert(tripId, alertData) {
    this.broadcastToTrip(tripId, {
      type: 'EMERGENCY_ALERT',
      data: alertData,
      timestamp: new Date().toISOString()
    });
  }
}

// Create a singleton instance
let instance = null;

function createWebSocketServer(server) {
  if (!instance) {
    instance = new WSServer(server);
  }
  return instance;
}

module.exports = createWebSocketServer;
