const { MongoClient } = require('mongodb');

async function fixDriverFirestoreUid() {
    const client = new MongoClient('mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0');
    
    try {
        await client.connect();
        console.log('Connected to MongoDB');
        
        const db = client.db('abra_fleet');
        const driversCollection = db.collection('drivers');
        
        // Find the driver with email rajesh.kumar@abrafleet.com
        const driver = await driversCollection.findOne({
            'personalInfo.email': 'rajesh.kumar@abrafleet.com'
        });
        
        if (!driver) {
            console.log('❌ Driver with email rajesh.kumar@abrafleet.com not found');
            return;
        }
        
        console.log('📋 Current driver data:');
        console.log('- Driver ID:', driver.driverId);
        console.log('- Name:', driver.personalInfo.firstName, driver.personalInfo.lastName);
        console.log('- Email:', driver.personalInfo.email);
        console.log('- Current firebaseUid:', driver.firebaseUid);
        console.log('- Current uid:', driver.uid);
        
        // Update the firebaseUid to match the uid
        if (driver.uid && !driver.firebaseUid) {
            const result = await driversCollection.updateOne(
                { _id: driver._id },
                { 
                    $set: { 
                        firebaseUid: driver.uid,
                        updatedAt: new Date()
                    }
                }
            );
            
            if (result.modifiedCount > 0) {
                console.log('✅ Successfully updated firebaseUid for driver');
                console.log('- New firebaseUid:', driver.uid);
                
                // Verify the update
                const updatedDriver = await driversCollection.findOne({
                    'personalInfo.email': 'rajesh.kumar@abrafleet.com'
                });
                
                console.log('📋 Updated driver data:');
                console.log('- firebaseUid:', updatedDriver.firebaseUid);
                console.log('- uid:', updatedDriver.uid);
                
            } else {
                console.log('❌ Failed to update driver firebaseUid');
            }
        } else if (driver.firebaseUid) {
            console.log('✅ Driver already has firebaseUid set:', driver.firebaseUid);
        } else {
            console.log('❌ Driver has no uid to copy to firebaseUid');
        }
        
    } catch (error) {
        console.error('❌ Error fixing driver firebaseUid:', error);
    } finally {
        await client.close();
        console.log('Disconnected from MongoDB');
    }
}

// Run the fix
fixDriverFirestoreUid();