const { MongoClient } = require('mongodb');

async function createMissingDriverUser() {
    const client = new MongoClient('mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0');
    
    try {
        await client.connect();
        console.log('Connected to MongoDB');
        
        const db = client.db('abra_fleet');
        const usersCollection = db.collection('users');
        const driversCollection = db.collection('drivers');
        
        // Find the driver record
        const driver = await driversCollection.findOne({
            'personalInfo.email': 'rajesh.kumar@abrafleet.com'
        });
        
        if (!driver) {
            console.log('❌ Driver not found in drivers collection');
            return;
        }
        
        console.log('📋 Found driver record:');
        console.log('- Driver ID:', driver.driverId);
        console.log('- Name:', driver.personalInfo.firstName, driver.personalInfo.lastName);
        console.log('- Email:', driver.personalInfo.email);
        console.log('- uid:', driver.uid);
        console.log('- firebaseUid:', driver.firebaseUid);
        
        // Check if user already exists
        const existingUser = await usersCollection.findOne({
            email: 'rajesh.kumar@abrafleet.com'
        });
        
        if (existingUser) {
            console.log('✅ User already exists in users collection');
            return;
        }
        
        // Create the user record
        const newUser = {
            firebaseUid: driver.uid, // Use the uid from driver record as firebaseUid
            email: driver.personalInfo.email,
            name: `${driver.personalInfo.firstName} ${driver.personalInfo.lastName}`,
            role: 'driver',
            status: 'active',
            modules: [],
            permissions: {},
            fcmToken: null,
            createdAt: new Date(),
            updatedAt: new Date(),
            lastActive: new Date(),
            lastLogin: new Date()
        };
        
        console.log('\n🔧 Creating user record:');
        console.log('- firebaseUid:', newUser.firebaseUid);
        console.log('- email:', newUser.email);
        console.log('- name:', newUser.name);
        console.log('- role:', newUser.role);
        
        const userResult = await usersCollection.insertOne(newUser);
        
        if (userResult.insertedId) {
            console.log('✅ Successfully created user record with ID:', userResult.insertedId);
            
            // Now update the driver record to have the correct firebaseUid
            const driverUpdateResult = await driversCollection.updateOne(
                { _id: driver._id },
                { 
                    $set: { 
                        firebaseUid: driver.uid,
                        updatedAt: new Date()
                    }
                }
            );
            
            if (driverUpdateResult.modifiedCount > 0) {
                console.log('✅ Successfully updated driver firebaseUid');
            } else {
                console.log('⚠️  Driver firebaseUid was already set or update failed');
            }
            
            console.log('\n🎉 SOLUTION COMPLETE!');
            console.log('The driver rajesh.kumar@abrafleet.com should now be able to login and see their profile.');
            
        } else {
            console.log('❌ Failed to create user record');
        }
        
    } catch (error) {
        console.error('❌ Error creating missing driver user:', error);
    } finally {
        await client.close();
        console.log('\nDisconnected from MongoDB');
    }
}

// Run the fix
createMissingDriverUser();