// Check notifications in both possible databases
const { MongoClient } = require('mongodb');

const MONGODB_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0';

// Driver Firebase UID from credentials
const DRIVER_UID = 'wvm5wdXaWNOAqVOXX5l8fWbfYFz2';

async function checkBothDatabases() {
    console.log('🔍 Checking notifications in both possible databases...');
    
    const client = new MongoClient(MONGODB_URI);
    
    try {
        await client.connect();
        console.log('✅ Connected to MongoDB');
        
        // Check abrafleet database
        console.log('\n📋 Checking "abrafleet" database:');
        const abrafleetDb = client.db('abrafleet');
        const abrafleetNotifications = await abrafleetDb.collection('notifications')
            .find({ userId: DRIVER_UID })
            .toArray();
        console.log(`   Found ${abrafleetNotifications.length} notifications`);
        
        // Check abra_fleet database
        console.log('\n📋 Checking "abra_fleet" database:');
        const abraFleetDb = client.db('abra_fleet');
        const abraFleetNotifications = await abraFleetDb.collection('notifications')
            .find({ userId: DRIVER_UID })
            .toArray();
        console.log(`   Found ${abraFleetNotifications.length} notifications`);
        
        // Show which database has the notifications
        if (abrafleetNotifications.length > 0) {
            console.log('\n✅ Notifications found in "abrafleet" database');
            console.log('❌ Backend uses "abra_fleet" database - MISMATCH!');
            console.log('\n🔧 Solution: Move notifications to "abra_fleet" database');
        } else if (abraFleetNotifications.length > 0) {
            console.log('\n✅ Notifications found in "abra_fleet" database');
            console.log('✅ Backend uses "abra_fleet" database - MATCH!');
            console.log('\n🤔 Backend should be finding these notifications...');
        } else {
            console.log('\n❌ No notifications found in either database');
        }
        
        // List all databases to see what's available
        console.log('\n📊 Available databases:');
        const adminDb = client.db().admin();
        const databases = await adminDb.listDatabases();
        databases.databases.forEach(db => {
            console.log(`   - ${db.name} (${(db.sizeOnDisk / 1024 / 1024).toFixed(2)} MB)`);
        });
        
    } catch (error) {
        console.error('❌ Error:', error);
    } finally {
        await client.close();
        console.log('\n🔌 MongoDB connection closed');
    }
}

checkBothDatabases();