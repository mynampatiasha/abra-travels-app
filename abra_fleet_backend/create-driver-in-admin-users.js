// Create driver in admin_users collection
const { MongoClient } = require('mongodb');

const MONGODB_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0';
const DATABASE_NAME = 'abrafleet';

// Driver Firebase UID from credentials
const DRIVER_UID = 'wvm5wdXaWNOAqVOXX5l8fWbfYFz2';
const DRIVER_EMAIL = 'drivertest@gmail.com';

async function createDriverInAdminUsers() {
    console.log('👤 Creating driver in admin_users collection...');
    
    const client = new MongoClient(MONGODB_URI);
    
    try {
        await client.connect();
        console.log('✅ Connected to MongoDB');
        
        const db = client.db(DATABASE_NAME);
        
        // Check if driver already exists
        const existingUser = await db.collection('admin_users').findOne({
            $or: [
                { firebaseUid: DRIVER_UID },
                { email: DRIVER_EMAIL }
            ]
        });
        
        if (existingUser) {
            console.log('✅ Driver already exists in admin_users');
            console.log('   ID:', existingUser._id);
            console.log('   Email:', existingUser.email);
            console.log('   Role:', existingUser.role);
            return;
        }
        
        // Create driver user
        const driverUser = {
            firebaseUid: DRIVER_UID,
            email: DRIVER_EMAIL,
            name: 'Rajesh Kumar',
            role: 'driver',
            status: 'active',
            modules: ['driver_dashboard', 'notifications', 'trips', 'routes'],
            permissions: {
                'Driver Dashboard': ['view_trips', 'update_status', 'view_routes'],
                'Notifications': ['view_all', 'mark_read'],
                'Trip Management': ['view_assigned', 'start_trip', 'end_trip', 'update_status'],
                'Route Management': ['view_assigned', 'view_customers']
            },
            fcmToken: null,
            mobileFcmToken: null,
            webFcmToken: null,
            organizationId: null,
            createdAt: new Date(),
            updatedAt: new Date(),
            lastActive: new Date(),
            lastLogin: new Date(),
            metadata: {
                source: 'manual_creation',
                createdBy: 'system',
                driverId: 'DRV-852306'
            }
        };
        
        const result = await db.collection('admin_users').insertOne(driverUser);
        console.log('✅ Driver created in admin_users collection');
        console.log('   MongoDB ID:', result.insertedId);
        console.log('   Firebase UID:', DRIVER_UID);
        console.log('   Email:', DRIVER_EMAIL);
        console.log('   Role:', driverUser.role);
        console.log('   Status:', driverUser.status);
        console.log('   Modules:', driverUser.modules);
        
        // Verify creation
        const createdUser = await db.collection('admin_users').findOne({ _id: result.insertedId });
        if (createdUser) {
            console.log('\n✅ Verification successful - driver exists in admin_users');
            console.log('📱 Driver should now be able to access notifications API');
        } else {
            console.log('❌ Verification failed - driver not found after creation');
        }
        
    } catch (error) {
        console.error('❌ Error creating driver:', error);
    } finally {
        await client.close();
        console.log('\n🔌 MongoDB connection closed');
    }
}

createDriverInAdminUsers();