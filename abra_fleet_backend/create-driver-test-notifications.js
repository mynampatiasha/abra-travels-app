// Create test notifications for driver
const { MongoClient } = require('mongodb');

const MONGODB_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0';
const DATABASE_NAME = 'abrafleet';

// Driver Firebase UID from credentials
const DRIVER_UID = 'wvm5wdXaWNOAqVOXX5l8fWbfYFz2';

async function createDriverNotifications() {
    console.log('🔔 Creating test notifications for driver...');
    
    const client = new MongoClient(MONGODB_URI);
    
    try {
        await client.connect();
        console.log('✅ Connected to MongoDB');
        
        const db = client.db(DATABASE_NAME);
        const notificationsCollection = db.collection('notifications');
        
        // Create various driver-specific notifications
        const notifications = [
            {
                userId: DRIVER_UID,
                title: 'Route Assigned for Today',
                body: 'You have been assigned Route R-001 with 5 customers for pickup and drop-off.',
                type: 'route_assigned',
                priority: 'high',
                isRead: false,
                data: {
                    routeId: 'R-001',
                    customerCount: 5,
                    startTime: '08:00 AM',
                    endTime: '06:00 PM'
                },
                metadata: {
                    source: 'route_management',
                    category: 'assignment'
                },
                createdAt: new Date(Date.now() - 2 * 60 * 60 * 1000), // 2 hours ago
                updatedAt: new Date()
            },
            {
                userId: DRIVER_UID,
                title: 'Vehicle Assigned',
                body: 'Vehicle VH143864 has been assigned to you for today\'s routes.',
                type: 'vehicle_assigned',
                priority: 'normal',
                isRead: false,
                data: {
                    vehicleId: 'VH143864',
                    vehicleNumber: 'KA-01-AB-1234',
                    vehicleType: 'Sedan',
                    capacity: 4
                },
                metadata: {
                    source: 'vehicle_management',
                    category: 'assignment'
                },
                createdAt: new Date(Date.now() - 4 * 60 * 60 * 1000), // 4 hours ago
                updatedAt: new Date()
            },
            {
                userId: DRIVER_UID,
                title: 'Trip Updated',
                body: 'Trip T-12345 pickup time has been changed from 9:00 AM to 9:30 AM.',
                type: 'trip_updated',
                priority: 'normal',
                isRead: true,
                data: {
                    tripId: 'T-12345',
                    oldPickupTime: '09:00 AM',
                    newPickupTime: '09:30 AM',
                    customerName: 'John Doe',
                    reason: 'Customer request'
                },
                metadata: {
                    source: 'trip_management',
                    category: 'update'
                },
                createdAt: new Date(Date.now() - 6 * 60 * 60 * 1000), // 6 hours ago
                updatedAt: new Date()
            },
            {
                userId: DRIVER_UID,
                title: 'Shift Reminder',
                body: 'Your shift starts in 30 minutes. Please ensure you are ready for pickup.',
                type: 'shift_reminder',
                priority: 'high',
                isRead: false,
                data: {
                    shiftStartTime: '08:00 AM',
                    reminderTime: '07:30 AM',
                    firstPickupLocation: 'Koramangala, Bangalore'
                },
                metadata: {
                    source: 'schedule_management',
                    category: 'reminder'
                },
                createdAt: new Date(Date.now() - 30 * 60 * 1000), // 30 minutes ago
                updatedAt: new Date()
            },
            {
                userId: DRIVER_UID,
                title: 'Document Expiring Soon',
                body: 'Your driving license will expire in 15 days. Please renew it soon.',
                type: 'document_expiring_soon',
                priority: 'normal',
                isRead: false,
                data: {
                    documentType: 'Driving License',
                    expiryDate: '2025-01-15',
                    daysRemaining: 15,
                    renewalRequired: true
                },
                metadata: {
                    source: 'document_management',
                    category: 'alert'
                },
                createdAt: new Date(Date.now() - 1 * 24 * 60 * 60 * 1000), // 1 day ago
                updatedAt: new Date()
            },
            {
                userId: DRIVER_UID,
                title: 'Emergency Alert',
                body: 'Customer has triggered SOS alert. Please check your route immediately.',
                type: 'emergency_alert',
                priority: 'high',
                isRead: false,
                data: {
                    customerId: 'CUST-001',
                    customerName: 'Jane Smith',
                    location: 'Electronic City, Bangalore',
                    alertTime: new Date().toISOString(),
                    severity: 'high'
                },
                metadata: {
                    source: 'emergency_system',
                    category: 'alert'
                },
                createdAt: new Date(Date.now() - 10 * 60 * 1000), // 10 minutes ago
                updatedAt: new Date()
            },
            {
                userId: DRIVER_UID,
                title: 'Trip Cancelled',
                body: 'Trip T-67890 has been cancelled due to customer unavailability.',
                type: 'trip_cancelled',
                priority: 'normal',
                isRead: true,
                data: {
                    tripId: 'T-67890',
                    customerName: 'Mike Johnson',
                    reason: 'Customer unavailable',
                    cancellationTime: new Date().toISOString(),
                    refundStatus: 'processed'
                },
                metadata: {
                    source: 'trip_management',
                    category: 'cancellation'
                },
                createdAt: new Date(Date.now() - 3 * 60 * 60 * 1000), // 3 hours ago
                updatedAt: new Date()
            },
            {
                userId: DRIVER_UID,
                title: 'Roster Assigned',
                body: 'New roster for December 27, 2025 has been assigned to you.',
                type: 'roster_assigned',
                priority: 'normal',
                isRead: false,
                data: {
                    rosterId: 'RST-001',
                    date: '2025-12-27',
                    totalTrips: 8,
                    estimatedDuration: '10 hours',
                    route: 'Koramangala - Electronic City'
                },
                metadata: {
                    source: 'roster_management',
                    category: 'assignment'
                },
                createdAt: new Date(Date.now() - 12 * 60 * 60 * 1000), // 12 hours ago
                updatedAt: new Date()
            }
        ];
        
        // Insert notifications
        const result = await notificationsCollection.insertMany(notifications);
        console.log(`✅ Created ${result.insertedCount} notifications for driver`);
        
        // Show summary
        console.log('\n📋 Created Notifications:');
        notifications.forEach((notif, index) => {
            const status = notif.isRead ? '✅ Read' : '📬 Unread';
            console.log(`   ${index + 1}. ${notif.title} (${notif.type}) - ${status}`);
        });
        
        console.log(`\n🚗 Driver UID: ${DRIVER_UID}`);
        console.log('📱 These notifications should now appear in the driver notifications screen');
        
    } catch (error) {
        console.error('❌ Error creating notifications:', error);
    } finally {
        await client.close();
        console.log('🔌 MongoDB connection closed');
    }
}

createDriverNotifications();