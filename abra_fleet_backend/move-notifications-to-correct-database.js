// Move notifications from abrafleet to abra_fleet database
const { MongoClient } = require('mongodb');

const MONGODB_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0';

// Driver Firebase UID from credentials
const DRIVER_UID = 'wvm5wdXaWNOAqVOXX5l8fWbfYFz2';

async function moveNotifications() {
    console.log('🔄 Moving notifications to correct database...');
    
    const client = new MongoClient(MONGODB_URI);
    
    try {
        await client.connect();
        console.log('✅ Connected to MongoDB');
        
        // Get notifications from abrafleet database
        console.log('\n📋 Reading notifications from "abrafleet" database...');
        const sourceDb = client.db('abrafleet');
        const notifications = await sourceDb.collection('notifications')
            .find({ userId: DRIVER_UID })
            .toArray();
        
        console.log(`📬 Found ${notifications.length} notifications to move`);
        
        if (notifications.length === 0) {
            console.log('❌ No notifications to move');
            return;
        }
        
        // Insert notifications into abra_fleet database
        console.log('\n📋 Inserting notifications into "abra_fleet" database...');
        const targetDb = client.db('abra_fleet');
        
        // Remove _id field to avoid conflicts
        const notificationsToInsert = notifications.map(notif => {
            const { _id, ...notifWithoutId } = notif;
            return notifWithoutId;
        });
        
        const result = await targetDb.collection('notifications')
            .insertMany(notificationsToInsert);
        
        console.log(`✅ Inserted ${result.insertedCount} notifications into abra_fleet database`);
        
        // Verify the move
        console.log('\n🔍 Verifying notifications in target database...');
        const verifyNotifications = await targetDb.collection('notifications')
            .find({ userId: DRIVER_UID })
            .toArray();
        
        console.log(`✅ Verified: ${verifyNotifications.length} notifications in abra_fleet database`);
        
        if (verifyNotifications.length > 0) {
            console.log('\n📋 Moved notifications:');
            verifyNotifications.forEach((notif, index) => {
                console.log(`   ${index + 1}. ${notif.title} (${notif.type}) - ${notif.isRead ? 'Read' : 'Unread'}`);
            });
        }
        
        // Optionally clean up source database
        console.log('\n🧹 Cleaning up source database...');
        const deleteResult = await sourceDb.collection('notifications')
            .deleteMany({ userId: DRIVER_UID });
        
        console.log(`✅ Deleted ${deleteResult.deletedCount} notifications from abrafleet database`);
        
        console.log('\n🎉 Migration completed successfully!');
        console.log('📱 Driver notifications should now work in the app');
        
    } catch (error) {
        console.error('❌ Error moving notifications:', error);
    } finally {
        await client.close();
        console.log('\n🔌 MongoDB connection closed');
    }
}

moveNotifications();