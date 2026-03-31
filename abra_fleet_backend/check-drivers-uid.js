const { MongoClient } = require('mongodb');

async function checkAllDriversFirebaseUid() {
    const client = new MongoClient('mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0');
    
    try {
        await client.connect();
        console.log('Connected to MongoDB');
        
        const db = client.db('abra_fleet');
        const driversCollection = db.collection('drivers');
        
        // Get all drivers
        const drivers = await driversCollection.find({}).toArray();
        
        console.log(`\n📋 Found ${drivers.length} drivers in database:\n`);
        
        drivers.forEach((driver, index) => {
            console.log(`${index + 1}. Driver: ${driver.personalInfo?.firstName || 'N/A'} ${driver.personalInfo?.lastName || 'N/A'}`);
            console.log(`   - Driver ID: ${driver.driverId || 'N/A'}`);
            console.log(`   - Email: ${driver.personalInfo?.email || 'N/A'}`);
            console.log(`   - firebaseUid: ${driver.firebaseUid || 'NULL'}`);
            console.log(`   - uid: ${driver.uid || 'NULL'}`);
            console.log(`   - Status: ${driver.status || 'N/A'}`);
            
            // Check if there's a mismatch
            if (driver.uid && !driver.firebaseUid) {
                console.log(`   ⚠️  ISSUE: Has uid but no firebaseUid - needs fixing!`);
            } else if (driver.firebaseUid && driver.uid && driver.firebaseUid !== driver.uid) {
                console.log(`   ⚠️  ISSUE: firebaseUid and uid don't match!`);
            } else if (driver.firebaseUid) {
                console.log(`   ✅ Firebase UID is properly set`);
            } else {
                console.log(`   ❌ No Firebase UID found`);
            }
            console.log('');
        });
        
        // Summary
        const driversWithFirebaseUid = drivers.filter(d => d.firebaseUid);
        const driversWithUidButNoFirebaseUid = drivers.filter(d => d.uid && !d.firebaseUid);
        const driversWithMismatch = drivers.filter(d => d.firebaseUid && d.uid && d.firebaseUid !== d.uid);
        
        console.log('📊 SUMMARY:');
        console.log(`- Total drivers: ${drivers.length}`);
        console.log(`- Drivers with firebaseUid: ${driversWithFirebaseUid.length}`);
        console.log(`- Drivers with uid but no firebaseUid: ${driversWithUidButNoFirebaseUid.length}`);
        console.log(`- Drivers with mismatched UIDs: ${driversWithMismatch.length}`);
        
        if (driversWithUidButNoFirebaseUid.length > 0) {
            console.log('\n🔧 DRIVERS THAT NEED FIXING:');
            driversWithUidButNoFirebaseUid.forEach(driver => {
                console.log(`- ${driver.personalInfo?.email || driver.driverId}: uid=${driver.uid}`);
            });
        }
        
    } catch (error) {
        console.error('❌ Error checking drivers:', error);
    } finally {
        await client.close();
        console.log('\nDisconnected from MongoDB');
    }
}

// Run the check
checkAllDriversFirebaseUid();