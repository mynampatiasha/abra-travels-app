const { MongoClient } = require('mongodb');

async function checkRajeshRosters() {
    const client = new MongoClient('mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0');
    
    try {
        await client.connect();
        console.log('Connected to MongoDB');
        
        const db = client.db('abra_fleet');
        
        // Find Rajesh Kumar driver
        const rajeshDriver = await db.collection('drivers').findOne({
            driverId: 'DRV-100001'
        });
        
        console.log('🚗 Rajesh Kumar Driver Info:');
        console.log(`   - Driver ID: ${rajeshDriver.driverId}`);
        console.log(`   - Firebase UID: ${rajeshDriver.firebaseUid}`);
        console.log(`   - Email: ${rajeshDriver.personalInfo?.email}`);
        
        // Find rosters assigned to Rajesh Kumar
        const rosters = await db.collection('rosters').find({
            driverId: 'DRV-100001'
        }).toArray();
        
        console.log(`\n📋 Found ${rosters.length} rosters assigned to Rajesh Kumar:\n`);
        
        for (let i = 0; i < rosters.length; i++) {
            const roster = rosters[i];
            console.log(`${i + 1}. Customer: ${roster.customerName || 'Unknown'}`);
            console.log(`   - Phone: ${roster.customerPhone || 'N/A'}`);
            console.log(`   - Email: ${roster.customerEmail || 'N/A'}`);
            console.log(`   - Pickup Location: ${roster.pickupLocation || 'N/A'}`);
            console.log(`   - Drop Location: ${roster.dropLocation || 'N/A'}`);
            console.log(`   - Status: ${roster.status || 'N/A'}`);
            console.log(`   - Vehicle: ${roster.vehicleNumber || 'N/A'}`);
            console.log(`   - User ID: ${roster.userId || 'N/A'}`);
            console.log('');
        }
        
        // Also check if there are any rosters with different driver assignment patterns
        console.log('🔍 Checking for rosters with other driver assignment patterns...');
        
        const otherRosters = await db.collection('rosters').find({
            $or: [
                { assignedDriver: { $exists: true } },
                { driverName: /rajesh/i }
            ]
        }).limit(5).toArray();
        
        if (otherRosters.length > 0) {
            console.log(`\n📋 Found ${otherRosters.length} rosters with other patterns:\n`);
            otherRosters.forEach((roster, index) => {
                console.log(`${index + 1}. Customer: ${roster.customerName || 'Unknown'}`);
                console.log(`   - assignedDriver: ${roster.assignedDriver || 'N/A'}`);
                console.log(`   - driverName: ${roster.driverName || 'N/A'}`);
                console.log(`   - driverId: ${roster.driverId || 'N/A'}`);
                console.log('');
            });
        }
        
    } catch (error) {
        console.error('❌ Error checking rosters:', error);
    } finally {
        await client.close();
        console.log('Disconnected from MongoDB');
    }
}

// Run the check
checkRajeshRosters();