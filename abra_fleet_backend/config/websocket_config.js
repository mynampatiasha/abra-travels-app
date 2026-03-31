// config/websocket_config.js
const { Server } = require('socket.io');
const { getRedisSub, getRedisPub, getRedisClient } = require('./redis');

let io = null;

function initializeWebSocket(server) {
  console.log('🔄 Initializing WebSocket server...');
  
  io = new Server(server, {
    cors: {
      origin: '*', // In production, specify your domains
      methods: ['GET', 'POST'],
      credentials: true,
    },
    transports: ['websocket', 'polling'],
    pingTimeout: 60000,
    pingInterval: 25000,
  });
  
  // Connected clients tracking
  const connectedClients = new Map();
  
  io.on('connection', (socket) => {
    console.log('✅ WebSocket client connected:', socket.id);
    
    // ════════════════════════════════════════════════════════════════════
    // CLIENT IDENTIFICATION
    // ════════════════════════════════════════════════════════════════════
    
    socket.on('identify', (data) => {
      const { userType, userId, vehicleId, email } = data;
      
      connectedClients.set(socket.id, {
        userType, // 'admin', 'driver', 'customer'
        userId,
        vehicleId,
        email,
        connectedAt: new Date(),
      });
      
      console.log(`📱 Client identified: ${userType} (${userId})`);
      
      // Join rooms based on user type
      if (userType === 'admin' || userType === 'dispatcher') {
        socket.join('admin-room');
        console.log(`   ✅ Joined admin-room`);
      } else if (userType === 'driver' && vehicleId) {
        socket.join(`vehicle-${vehicleId}`);
        socket.join('driver-room');
        console.log(`   ✅ Joined vehicle-${vehicleId} and driver-room`);
      } else if (userType === 'customer' && userId) {
        socket.join(`customer-${userId}`);
        console.log(`   ✅ Joined customer-${userId}`);
      }
      
      // Send confirmation with stats
      const stats = {
        totalConnected: connectedClients.size,
        admins: Array.from(connectedClients.values()).filter(c => c.userType === 'admin').length,
        drivers: Array.from(connectedClients.values()).filter(c => c.userType === 'driver').length,
        customers: Array.from(connectedClients.values()).filter(c => c.userType === 'customer').length,
      };
      
      socket.emit('identified', {
        success: true,
        message: 'Connected to real-time server',
        socketId: socket.id,
        stats,
      });
      
      // Notify admins of new connection
      if (userType === 'driver') {
        io.to('admin-room').emit('driver_connected', {
          driverId: userId,
          vehicleId,
          timestamp: new Date().toISOString(),
        });
      }
    });
    
    // ════════════════════════════════════════════════════════════════════
    // ASSIGNMENT EVENTS (NEW)
    // ════════════════════════════════════════════════════════════════════
    
    // Admin requests live pending rosters count
    socket.on('get_pending_count', async () => {
      try {
        const redis = getRedisClient();
        if (redis) {
          const count = await redis.get('pending_rosters_count');
          socket.emit('pending_count_update', {
            count: parseInt(count || 0),
            timestamp: new Date().toISOString(),
          });
        }
      } catch (error) {
        console.error('Error getting pending count:', error.message);
      }
    });
    
    // Admin requests available vehicles count
    socket.on('get_available_vehicles_count', async () => {
      try {
        const redis = getRedisClient();
        if (redis) {
          const count = await redis.get('available_vehicles_count');
          socket.emit('available_vehicles_count_update', {
            count: parseInt(count || 0),
            timestamp: new Date().toISOString(),
          });
        }
      } catch (error) {
        console.error('Error getting available vehicles count:', error.message);
      }
    });
    
    // Admin subscribes to specific roster updates
    socket.on('subscribe_roster', (data) => {
      const { rosterId } = data;
      if (rosterId) {
        socket.join(`roster-${rosterId}`);
        console.log(`   ✅ Subscribed to roster-${rosterId}`);
      }
    });
    
    // Admin unsubscribes from roster updates
    socket.on('unsubscribe_roster', (data) => {
      const { rosterId } = data;
      if (rosterId) {
        socket.leave(`roster-${rosterId}`);
        console.log(`   ✅ Unsubscribed from roster-${rosterId}`);
      }
    });
    
    // Admin subscribes to specific vehicle updates
    socket.on('subscribe_vehicle', (data) => {
      const { vehicleId } = data;
      if (vehicleId) {
        socket.join(`vehicle-${vehicleId}`);
        console.log(`   ✅ Subscribed to vehicle-${vehicleId}`);
      }
    });
    
    // Admin unsubscribes from vehicle updates
    socket.on('unsubscribe_vehicle', (data) => {
      const { vehicleId } = data;
      if (vehicleId) {
        socket.leave(`vehicle-${vehicleId}`);
        console.log(`   ✅ Unsubscribed from vehicle-${vehicleId}`);
      }
    });
    
    // ════════════════════════════════════════════════════════════════════
    // DRIVER LOCATION UPDATES
    // ════════════════════════════════════════════════════════════════════
    
    socket.on('location_update', async (data) => {
      const { vehicleId, lat, lon, speed, heading, timestamp } = data;
      
      console.log(`📍 Location update from vehicle ${vehicleId}`);
      
      // Store in Redis (expires in 1 hour)
      const redis = getRedisClient();
      if (redis) {
        try {
          await redis.setex(
            `vehicle:${vehicleId}:location`,
            3600,
            JSON.stringify({ 
              lat, 
              lon, 
              speed, 
              heading, 
              timestamp, 
              updatedAt: new Date().toISOString() 
            })
          );
        } catch (error) {
          console.error('Redis error storing location:', error.message);
        }
      }
      
      // Broadcast to admin room
      io.to('admin-room').emit('vehicle_location_updated', {
        vehicleId,
        lat,
        lon,
        speed,
        heading,
        timestamp,
      });
      
      // Also broadcast to anyone subscribed to this specific vehicle
      io.to(`vehicle-${vehicleId}`).emit('vehicle_location_updated', {
        vehicleId,
        lat,
        lon,
        speed,
        heading,
        timestamp,
      });
    });
    
    // ════════════════════════════════════════════════════════════════════
    // TRIP MANAGEMENT EVENTS
    // ════════════════════════════════════════════════════════════════════
    
    // Driver marks passenger picked
    socket.on('passenger_picked', async (data) => {
      const { tripId, rosterId, passengerId, vehicleId, timestamp } = data;
      
      console.log(`✅ Passenger picked: Trip ${tripId}, Passenger ${passengerId}`);
      
      // Update in Redis
      const redis = getRedisClient();
      if (redis) {
        try {
          await redis.hset(
            `trip:${tripId}:passengers`,
            passengerId,
            JSON.stringify({ status: 'picked', timestamp })
          );
          
          // Increment picked count
          await redis.hincrby(`trip:${tripId}:stats`, 'pickedCount', 1);
          await redis.hincrby(`trip:${tripId}:stats`, 'waitingCount', -1);
        } catch (error) {
          console.error('Redis error updating passenger status:', error.message);
        }
      }
      
      // Broadcast to admin
      io.to('admin-room').emit('passenger_status_changed', {
        tripId,
        rosterId,
        passengerId,
        vehicleId,
        status: 'picked',
        timestamp,
      });
      
      // Broadcast to roster subscribers
      io.to(`roster-${rosterId}`).emit('passenger_status_changed', {
        tripId,
        rosterId,
        passengerId,
        vehicleId,
        status: 'picked',
        timestamp,
      });
      
      // Send confirmation to driver
      socket.emit('passenger_picked_confirmed', {
        success: true,
        tripId,
        passengerId,
      });
    });
    
    // Driver marks passenger dropped
    socket.on('passenger_dropped', async (data) => {
      const { tripId, rosterId, passengerId, vehicleId, timestamp } = data;
      
      console.log(`🏁 Passenger dropped: Trip ${tripId}, Passenger ${passengerId}`);
      
      // Update in Redis
      const redis = getRedisClient();
      if (redis) {
        try {
          await redis.hset(
            `trip:${tripId}:passengers`,
            passengerId,
            JSON.stringify({ status: 'dropped', timestamp })
          );
          
          // Increment dropped count
          await redis.hincrby(`trip:${tripId}:stats`, 'droppedCount', 1);
          await redis.hincrby(`trip:${tripId}:stats`, 'pickedCount', -1);
        } catch (error) {
          console.error('Redis error updating passenger status:', error.message);
        }
      }
      
      // Broadcast to admin
      io.to('admin-room').emit('passenger_status_changed', {
        tripId,
        rosterId,
        passengerId,
        vehicleId,
        status: 'dropped',
        timestamp,
      });
      
      // Broadcast to roster subscribers
      io.to(`roster-${rosterId}`).emit('passenger_status_changed', {
        tripId,
        rosterId,
        passengerId,
        vehicleId,
        status: 'dropped',
        timestamp,
      });
      
      // Send confirmation to driver
      socket.emit('passenger_dropped_confirmed', {
        success: true,
        tripId,
        passengerId,
      });
    });
    
    // Trip started
    socket.on('trip_started', async (data) => {
      const { tripId, vehicleId, driverId, timestamp } = data;
      
      console.log(`🚀 Trip started: ${tripId}`);
      
      const redis = getRedisClient();
      if (redis) {
        try {
          await redis.setex(
            `vehicle:${vehicleId}:current_trip`,
            3600,
            JSON.stringify({ tripId, status: 'in-progress', startedAt: timestamp })
          );
        } catch (error) {
          console.error('Redis error storing trip:', error.message);
        }
      }
      
      // Broadcast to admin
      io.to('admin-room').emit('trip_started', {
        tripId,
        vehicleId,
        driverId,
        timestamp,
      });
      
      // Broadcast to vehicle subscribers
      io.to(`vehicle-${vehicleId}`).emit('trip_started', {
        tripId,
        vehicleId,
        driverId,
        timestamp,
      });
    });
    
    // Trip completed
    socket.on('trip_completed', async (data) => {
      const { tripId, vehicleId, driverId, timestamp } = data;
      
      console.log(`🏁 Trip completed: ${tripId}`);
      
      const redis = getRedisClient();
      if (redis) {
        try {
          await redis.del(`vehicle:${vehicleId}:current_trip`);
          await redis.del(`trip:${tripId}:passengers`);
          await redis.del(`trip:${tripId}:stats`);
        } catch (error) {
          console.error('Redis error cleaning up trip:', error.message);
        }
      }
      
      // Broadcast to admin
      io.to('admin-room').emit('trip_completed', {
        tripId,
        vehicleId,
        driverId,
        timestamp,
      });
      
      // Broadcast to vehicle subscribers
      io.to(`vehicle-${vehicleId}`).emit('trip_completed', {
        tripId,
        vehicleId,
        driverId,
        timestamp,
      });
      
      // Update vehicle status to idle
      io.to('admin-room').emit('vehicle_status_changed', {
        vehicleId,
        status: 'idle',
        timestamp,
      });
    });
    
    // ════════════════════════════════════════════════════════════════════
    // HEARTBEAT / PING
    // ════════════════════════════════════════════════════════════════════
    
    socket.on('ping', () => {
      socket.emit('pong', {
        timestamp: new Date().toISOString(),
      });
    });
    
    // ════════════════════════════════════════════════════════════════════
    // DISCONNECT HANDLING
    // ════════════════════════════════════════════════════════════════════
    
    socket.on('disconnect', () => {
      const clientInfo = connectedClients.get(socket.id);
      console.log(`❌ WebSocket client disconnected: ${socket.id}`, clientInfo);
      
      // Notify admins if driver disconnected
      if (clientInfo?.userType === 'driver') {
        io.to('admin-room').emit('driver_disconnected', {
          driverId: clientInfo.userId,
          vehicleId: clientInfo.vehicleId,
          timestamp: new Date().toISOString(),
        });
      }
      
      connectedClients.delete(socket.id);
    });
  });
  
  console.log('✅ WebSocket server initialized');
  return io;
}

// ════════════════════════════════════════════════════════════════════════
// GET IO INSTANCE
// ════════════════════════════════════════════════════════════════════════

function getIO() {
  if (!io) {
    throw new Error('WebSocket not initialized. Call initializeWebSocket() first.');
  }
  return io;
}

// ════════════════════════════════════════════════════════════════════════
// BROADCAST HELPERS (Called from APIs)
// ════════════════════════════════════════════════════════════════════════

/**
 * Broadcast new roster created event
 */
function broadcastNewRoster(roster) {
  if (!io) return;
  
  console.log(`📢 Broadcasting new roster: ${roster._id}`);
  
  io.to('admin-room').emit('new_roster', {
    rosterId: roster._id.toString(),
    customerName: roster.customerName,
    customerEmail: roster.customerEmail,
    officeLocation: roster.officeLocation,
    pickupTime: roster.startTime,
    rosterType: roster.rosterType,
    priority: roster.priority,
    createdAt: roster.createdAt,
    timestamp: new Date().toISOString(),
  });
}

/**
 * Broadcast roster assigned event
 */
function broadcastRosterAssigned(roster, vehicle, driver) {
  if (!io) return;
  
  console.log(`📢 Broadcasting roster assigned: ${roster._id}`);
  
  // To all admins
  io.to('admin-room').emit('roster_assigned', {
    rosterId: roster._id.toString(),
    vehicleId: vehicle._id.toString(),
    driverId: driver._id.toString(),
    vehicleReg: vehicle.registrationNumber,
    driverName: driver.name,
    customerName: roster.customerName,
    timestamp: new Date().toISOString(),
  });
  
  // To specific roster subscribers
  io.to(`roster-${roster._id}`).emit('roster_assigned', {
    rosterId: roster._id.toString(),
    vehicleId: vehicle._id.toString(),
    driverId: driver._id.toString(),
    vehicleReg: vehicle.registrationNumber,
    driverName: driver.name,
    timestamp: new Date().toISOString(),
  });
  
  // To customer (if connected)
  if (roster.userId || roster.firebaseUid) {
    const customerId = roster.userId || roster.firebaseUid;
    io.to(`customer-${customerId}`).emit('roster_assigned', {
      rosterId: roster._id.toString(),
      vehicleReg: vehicle.registrationNumber,
      driverName: driver.name,
      driverPhone: driver.phone,
      pickupTime: roster.startTime,
      timestamp: new Date().toISOString(),
    });
  }
}

/**
 * Broadcast roster unassigned event
 */
function broadcastRosterUnassigned(roster, vehicleId) {
  if (!io) return;
  
  console.log(`📢 Broadcasting roster unassigned: ${roster._id}`);
  
  io.to('admin-room').emit('roster_unassigned', {
    rosterId: roster._id.toString(),
    vehicleId: vehicleId?.toString(),
    timestamp: new Date().toISOString(),
  });
  
  io.to(`roster-${roster._id}`).emit('roster_unassigned', {
    rosterId: roster._id.toString(),
    timestamp: new Date().toISOString(),
  });
}

/**
 * Broadcast vehicle status changed
 */
function broadcastVehicleStatusChanged(vehicleId, status, additionalData = {}) {
  if (!io) return;
  
  console.log(`📢 Broadcasting vehicle status changed: ${vehicleId} → ${status}`);
  
  io.to('admin-room').emit('vehicle_status_changed', {
    vehicleId: vehicleId.toString(),
    status,
    ...additionalData,
    timestamp: new Date().toISOString(),
  });
  
  io.to(`vehicle-${vehicleId}`).emit('vehicle_status_changed', {
    vehicleId: vehicleId.toString(),
    status,
    ...additionalData,
    timestamp: new Date().toISOString(),
  });
}

/**
 * Broadcast assignment conflict (lock failed)
 */
function broadcastAssignmentConflict(rosterId, vehicleId, dispatcherId, currentOwner) {
  if (!io) return;
  
  console.log(`📢 Broadcasting assignment conflict: ${vehicleId}`);
  
  io.to('admin-room').emit('assignment_conflict', {
    rosterId: rosterId?.toString(),
    vehicleId: vehicleId.toString(),
    dispatcherId,
    currentOwner,
    message: 'Another dispatcher is currently assigning this vehicle',
    timestamp: new Date().toISOString(),
  });
}

/**
 * Update pending rosters count (for dashboard stats)
 */
async function updatePendingCount(db) {
  if (!io) return;
  
  try {
    const count = await db.collection('rosters').countDocuments({
      status: { $in: ['pending_assignment', 'pending', 'created'] },
      assignedVehicleId: { $exists: false },
      assignedDriverId: { $exists: false },
    });
    
    // Store in Redis for quick access
    const redis = getRedisClient();
    if (redis) {
      await redis.setex('pending_rosters_count', 60, count.toString());
    }
    
    // Broadcast to all admins
    io.to('admin-room').emit('pending_count_update', {
      count,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    console.error('Error updating pending count:', error.message);
  }
}

/**
 * Update available vehicles count
 */
async function updateAvailableVehiclesCount(db) {
  if (!io) return;
  
  try {
    const count = await db.collection('vehicles').countDocuments({
      status: { $in: ['idle', 'active'] },
      $or: [
        { assignedDriver: { $exists: true } },
        { driverId: { $exists: true } },
      ],
    });
    
    // Store in Redis
    const redis = getRedisClient();
    if (redis) {
      await redis.setex('available_vehicles_count', 60, count.toString());
    }
    
    // Broadcast to all admins
    io.to('admin-room').emit('available_vehicles_count_update', {
      count,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    console.error('Error updating available vehicles count:', error.message);
  }
}

// ════════════════════════════════════════════════════════════════════════
// EXPORTS
// ════════════════════════════════════════════════════════════════════════

module.exports = {
  initializeWebSocket,
  getIO,
  
  // Broadcast helpers
  broadcastNewRoster,
  broadcastRosterAssigned,
  broadcastRosterUnassigned,
  broadcastVehicleStatusChanged,
  broadcastAssignmentConflict,
  updatePendingCount,
  updateAvailableVehiclesCount,
};