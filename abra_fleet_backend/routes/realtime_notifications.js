const express = require('express');
const router = express.Router();
const { Server } = require('socket.io');
const redis = require('redis');

// Redis client for pub/sub
let redisClient;
let redisSubscriber;

// Initialize Redis connections
async function initializeRedis() {
    try {
        redisClient = redis.createClient({
            host: process.env.REDIS_HOST || 'localhost',
            port: process.env.REDIS_PORT || 6379,
            password: process.env.REDIS_PASSWORD || undefined
        });
        
        redisSubscriber = redis.createClient({
            host: process.env.REDIS_HOST || 'localhost',
            port: process.env.REDIS_PORT || 6379,
            password: process.env.REDIS_PASSWORD || undefined
        });

        await redisClient.connect();
        await redisSubscriber.connect();
        
        console.log('Redis connected for real-time notifications');
    } catch (error) {
        console.log('Redis not available, using in-memory notifications:', error.message);
    }
}

// In-memory storage for when Redis is not available
const inMemoryNotifications = new Map();
const connectedClients = new Map();

// Initialize WebSocket server
function initializeWebSocket(server) {
    const io = new Server(server, {
        cors: {
            origin: "*",
            methods: ["GET", "POST"]
        },
        transports: ['websocket', 'polling']
    });

    // Handle WebSocket connections
    io.on('connection', (socket) => {
        console.log('Client connected:', socket.id);

        // Handle user authentication and room joining
        socket.on('authenticate', async (data) => {
            try {
                const { userId, userType, organizationId } = data;
                
                // Store client info
                connectedClients.set(socket.id, {
                    userId,
                    userType,
                    organizationId,
                    socketId: socket.id,
                    connectedAt: new Date()
                });

                // Join user-specific room
                socket.join(`user_${userId}`);
                
                // Join organization room if applicable
                if (organizationId) {
                    socket.join(`org_${organizationId}`);
                }
                
                // Join user type room (admin, driver, customer, client)
                socket.join(`type_${userType}`);

                socket.emit('authenticated', { success: true });
                console.log(`User ${userId} (${userType}) authenticated and joined rooms`);

                // Send any pending notifications
                await sendPendingNotifications(socket, userId);

            } catch (error) {
                console.error('Authentication error:', error);
                socket.emit('auth_error', { error: error.message });
            }
        });

        // Handle disconnection
        socket.on('disconnect', () => {
            console.log('Client disconnected:', socket.id);
            connectedClients.delete(socket.id);
        });

        // Handle ping for connection health
        socket.on('ping', () => {
            socket.emit('pong');
        });
    });

    // Subscribe to Redis channels if available
    if (redisSubscriber) {
        redisSubscriber.subscribe('notifications', (message) => {
            try {
                const notification = JSON.parse(message);
                broadcastNotification(io, notification);
            } catch (error) {
                console.error('Error processing Redis notification:', error);
            }
        });
    }

    return io;
}

// Broadcast notification to appropriate clients
function broadcastNotification(io, notification) {
    const { targetType, targetId, data } = notification;

    switch (targetType) {
        case 'user':
            io.to(`user_${targetId}`).emit('notification', data);
            break;
        case 'organization':
            io.to(`org_${targetId}`).emit('notification', data);
            break;
        case 'userType':
            io.to(`type_${targetId}`).emit('notification', data);
            break;
        case 'broadcast':
            io.emit('notification', data);
            break;
        default:
            console.log('Unknown target type:', targetType);
    }
}

// Send pending notifications to newly connected user
async function sendPendingNotifications(socket, userId) {
    try {
        // Get pending notifications from database
        const db = require('../config/database');
        const notifications = await db.collection('notifications').find({
            userId: userId,
            read: false,
            createdAt: { $gte: new Date(Date.now() - 24 * 60 * 60 * 1000) } // Last 24 hours
        }).sort({ createdAt: -1 }).limit(50).toArray();

        if (notifications.length > 0) {
            socket.emit('pending_notifications', notifications);
        }
    } catch (error) {
        console.error('Error sending pending notifications:', error);
    }
}

// API Routes

// Send notification to specific user
router.post('/send-to-user', async (req, res) => {
    try {
        const { userId, title, message, data = {}, type = 'info' } = req.body;

        const notification = {
            targetType: 'user',
            targetId: userId,
            data: {
                id: Date.now().toString(),
                title,
                message,
                type,
                data,
                timestamp: new Date(),
                read: false
            }
        };

        // Store in database
        const db = require('../config/database');
        await db.collection('notifications').insertOne({
            userId,
            title,
            message,
            type,
            data,
            read: false,
            createdAt: new Date()
        });

        // Send via Redis if available, otherwise use in-memory
        if (redisClient) {
            await redisClient.publish('notifications', JSON.stringify(notification));
        } else {
            // Broadcast directly if Redis not available
            if (global.io) {
                broadcastNotification(global.io, notification);
            }
        }

        res.json({ success: true, message: 'Notification sent' });
    } catch (error) {
        console.error('Error sending notification:', error);
        res.status(500).json({ error: error.message });
    }
});

// Send notification to organization
router.post('/send-to-organization', async (req, res) => {
    try {
        const { organizationId, title, message, data = {}, type = 'info' } = req.body;

        const notification = {
            targetType: 'organization',
            targetId: organizationId,
            data: {
                id: Date.now().toString(),
                title,
                message,
                type,
                data,
                timestamp: new Date(),
                read: false
            }
        };

        // Store in database for all users in organization
        const db = require('../config/database');
        const orgUsers = await db.collection('users').find({ organizationId }).toArray();
        
        const notifications = orgUsers.map(user => ({
            userId: user._id,
            organizationId,
            title,
            message,
            type,
            data,
            read: false,
            createdAt: new Date()
        }));

        if (notifications.length > 0) {
            await db.collection('notifications').insertMany(notifications);
        }

        // Send via Redis if available
        if (redisClient) {
            await redisClient.publish('notifications', JSON.stringify(notification));
        } else {
            if (global.io) {
                broadcastNotification(global.io, notification);
            }
        }

        res.json({ success: true, message: 'Notification sent to organization' });
    } catch (error) {
        console.error('Error sending organization notification:', error);
        res.status(500).json({ error: error.message });
    }
});

// Send notification to user type (all admins, all drivers, etc.)
router.post('/send-to-user-type', async (req, res) => {
    try {
        const { userType, title, message, data = {}, type = 'info' } = req.body;

        const notification = {
            targetType: 'userType',
            targetId: userType,
            data: {
                id: Date.now().toString(),
                title,
                message,
                type,
                data,
                timestamp: new Date(),
                read: false
            }
        };

        // Store in database for all users of this type
        const db = require('../config/database');
        const users = await db.collection('users').find({ userType }).toArray();
        
        const notifications = users.map(user => ({
            userId: user._id,
            userType,
            title,
            message,
            type,
            data,
            read: false,
            createdAt: new Date()
        }));

        if (notifications.length > 0) {
            await db.collection('notifications').insertMany(notifications);
        }

        // Send via Redis if available
        if (redisClient) {
            await redisClient.publish('notifications', JSON.stringify(notification));
        } else {
            if (global.io) {
                broadcastNotification(global.io, notification);
            }
        }

        res.json({ success: true, message: `Notification sent to all ${userType}s` });
    } catch (error) {
        console.error('Error sending user type notification:', error);
        res.status(500).json({ error: error.message });
    }
});

// Broadcast notification to all connected clients
router.post('/broadcast', async (req, res) => {
    try {
        const { title, message, data = {}, type = 'info' } = req.body;

        const notification = {
            targetType: 'broadcast',
            targetId: null,
            data: {
                id: Date.now().toString(),
                title,
                message,
                type,
                data,
                timestamp: new Date(),
                read: false
            }
        };

        // Store in database for all users
        const db = require('../config/database');
        const users = await db.collection('users').find({}).toArray();
        
        const notifications = users.map(user => ({
            userId: user._id,
            title,
            message,
            type,
            data,
            read: false,
            createdAt: new Date()
        }));

        if (notifications.length > 0) {
            await db.collection('notifications').insertMany(notifications);
        }

        // Send via Redis if available
        if (redisClient) {
            await redisClient.publish('notifications', JSON.stringify(notification));
        } else {
            if (global.io) {
                broadcastNotification(global.io, notification);
            }
        }

        res.json({ success: true, message: 'Broadcast notification sent' });
    } catch (error) {
        console.error('Error broadcasting notification:', error);
        res.status(500).json({ error: error.message });
    }
});

// Get connected clients info (for debugging)
router.get('/connected-clients', (req, res) => {
    const clients = Array.from(connectedClients.values());
    res.json({
        totalConnected: clients.length,
        clients: clients.map(client => ({
            userId: client.userId,
            userType: client.userType,
            organizationId: client.organizationId,
            connectedAt: client.connectedAt
        }))
    });
});

// Server-Sent Events endpoint for web clients
router.get('/sse/:userId', (req, res) => {
    const userId = req.params.userId;
    
    // Set SSE headers
    res.writeHead(200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Cache-Control'
    });

    // Send initial connection message
    res.write(`data: ${JSON.stringify({ type: 'connected', message: 'SSE connection established' })}\n\n`);

    // Store SSE connection
    const sseId = `sse_${userId}_${Date.now()}`;
    
    // Set up periodic heartbeat
    const heartbeat = setInterval(() => {
        res.write(`data: ${JSON.stringify({ type: 'heartbeat', timestamp: new Date() })}\n\n`);
    }, 30000);

    // Handle client disconnect
    req.on('close', () => {
        clearInterval(heartbeat);
        console.log(`SSE client disconnected: ${userId}`);
    });

    // TODO: Subscribe to user-specific notifications and send via SSE
    // This would integrate with your existing notification system
});

// Mark notification as read
router.post('/mark-read', async (req, res) => {
    try {
        const { notificationId, userId } = req.body;
        
        const db = require('../config/database');
        await db.collection('notifications').updateOne(
            { _id: notificationId, userId },
            { $set: { read: true, readAt: new Date() } }
        );

        res.json({ success: true });
    } catch (error) {
        console.error('Error marking notification as read:', error);
        res.status(500).json({ error: error.message });
    }
});

// Get user notifications
router.get('/user/:userId', async (req, res) => {
    try {
        const userId = req.params.userId;
        const { page = 1, limit = 20, unreadOnly = false } = req.query;
        
        const db = require('../config/database');
        const query = { userId };
        
        if (unreadOnly === 'true') {
            query.read = false;
        }

        const notifications = await db.collection('notifications')
            .find(query)
            .sort({ createdAt: -1 })
            .skip((page - 1) * limit)
            .limit(parseInt(limit))
            .toArray();

        const total = await db.collection('notifications').countDocuments(query);
        const unreadCount = await db.collection('notifications').countDocuments({ userId, read: false });

        res.json({
            notifications,
            pagination: {
                page: parseInt(page),
                limit: parseInt(limit),
                total,
                pages: Math.ceil(total / limit)
            },
            unreadCount
        });
    } catch (error) {
        console.error('Error fetching notifications:', error);
        res.status(500).json({ error: error.message });
    }
});

// Initialize Redis when module loads
initializeRedis();

module.exports = {
    router,
    initializeWebSocket,
    broadcastNotification
};