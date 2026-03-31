const { MongoClient } = require('mongodb');

async function checkUsersCollection() {
    const client = new MongoClient('mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0');
    
    try {
        await client.connect();
        console.log('Connected to MongoDB');
        
        const db = client.db('abra_fleet');
        const usersCollection = db.collection('users');
        
        // Check for both driver emails
        const driverEmails = ['drivertest@gmail.com', 'rajesh.kumar@abrafleet.com'];
        
        console.log('\n📋 Checking users collection for driver emails:\n');
        
        for (const email of driverEmails) {
            const user = await usersCollection.findOne({ email: email });
            
            console.log(`🔍 Email: ${email}`);
            if (user) {
                console.log(`   ✅ Found in users collection:`);
                console.log(`   - _id: ${user._id}`);
                console.log(`   - firebaseUid: ${user.firebaseUid || 'NULL'}`);
                console.log(`   - name: ${user.name || 'N/A'}`);
                console.log(`   - role: ${user.role || 'N/A'}`);
                console.log(`   - status: ${user.status || 'N/A'}`);
            } else {
                console.log(`   ❌ NOT found in users collection`);
            }
            console.log('');
        }
        
        // Also check all users with role 'driver'
        const allDriverUsers = await usersCollection.find({ role: 'driver' }).toArray();
        console.log(`\n📊 Found ${allDriverUsers.length} users with role 'driver':\n`);
        
        allDriverUsers.forEach((user, index) => {
            console.log(`${index + 1}. ${user.name || 'N/A'} (${user.email || 'N/A'})`);
            console.log(`   - firebaseUid: ${user.firebaseUid || 'NULL'}`);
            console.log(`   - status: ${user.status || 'N/A'}`);
            console.log('');
        });
        
    } catch (error) {
        console.error('❌ Error checking users collection:', error);
    } finally {
        await client.close();
        console.log('Disconnected from MongoDB');
    }
}

// Run the check
checkUsersCollection();