// Test notifications directly from database
const { MongoClient } = require('mongodb');

const MONGODB_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0';
const DATABASE_NAME = 'abrafleet';

// Driver Firebase UID from credentials
const DRIVER_UID = 'wvm5wdXaWNOAqVOXX5l8fWbfYFz2';

async function testNotificationsDirectly() {
    console.log('🔍 Testing notifications directly from database...');
    
    const client = new MongoClient(MONGODB_URI);
    
    try {
        await client.connect();
        console.log('✅ Connected to MongoDB');
        
        const db = client.db(DATABASE_NAME);
        
        // Test the exact query the backend uses
        const query = { userId: DRIVER_UID };
        console.log('\n📋 Query:', JSON.stringify(query));
        
        const notifications = await db.collection('notifications')
            .find(query)
            .sort({ createdAt: -1 })
            .limit(20)
            .toArray();
        
        console.log(`📬 Found ${notifications.length} notifications`);
        
        if (notifications.length > 0) {
            console.log('\n📋 Notifications found:');
            notifications.forEach((notif, index) => {
                console.log(`   ${index + 1}. ${notif.title} (${notif.type})`);
                console.log(`      User ID: ${notif.userId}`);
                console.log(`      Created: ${notif.createdAt}`);
                console.log(`      Read: ${notif.isRead}`);
                console.log('');
            });
        } else {
            console.log('\n❌ No notifications found with query:', query);
            
            // Check if there are any notifications at all
            const totalNotifications = await db.collection('notifications').countDocuments();
            console.log(`📊 Total notifications in collection: ${totalNotifications}`);
            
            if (totalNotifications > 0) {
                console.log('\n📋 Sample notifications in database:');
                const sampleNotifications = await db.collection('notifications').find({}).limit(5).toArray();
                sampleNotifications.forEach((notif, index) => {
                    console.log(`   ${index + 1}. ${notif.title} (User: ${notif.userId})`);
                });
                
                // Check for different userId formats
                console.log('\n🔍 Checking for different userId formats:');
                const userIdVariations = [
                    DRIVER_UID,
                    `"${DRIVER_UID}"`,
                    { $regex: DRIVER_UID },
                ];
                
                for (const variation of userIdVariations) {
                    const count = await db.collection('notifications').countDocuments({ userId: variation });
                    console.log(`   userId: ${JSON.stringify(variation)} -> ${count} notifications`);
                }
            }
        }
        
        // Test total count query
        const total = await db.collection('notifications').countDocuments(query);
        console.log(`\n📊 Total count for query: ${total}`);
        
    } catch (error) {
        console.error('❌ Error:', error);
    } finally {
        await client.close();
        console.log('\n🔌 MongoDB connection closed');
    }
}

testNotificationsDirectly();