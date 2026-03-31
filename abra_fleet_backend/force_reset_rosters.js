// Force reset specific rosters to pending_assignment
const { MongoClient, ObjectId } = require('mongodb');

// URI from .env
const MONGO_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function forceResetRosters() {
    const client = new MongoClient(MONGO_URI);

    try {
        console.log('Connecting to MongoDB Atlas...');
        await client.connect();
        const db = client.db('abra_fleet');
        console.log('✅ Connected!');

        // IDs from previous logs
        const rosterIds = [
            '694a8a867dad313c6ad8b992', // Rohit Menon
            '694a8a867dad313c6ad8b999', // Divya Rao
            '694a8a867dad313c6ad8b99d'  // Anitha Menon
        ];

        console.log(`\n🔄 Force Resetting ${rosterIds.length} Rosters to 'pending_assignment'...\n`);

        const result = await db.collection('rosters').updateMany(
            {
                _id: { $in: rosterIds.map(id => new ObjectId(id)) }
            },
            {
                $set: {
                    status: 'pending_assignment',
                    vehicleId: null,
                    driverId: null,
                    vehicleNumber: null,
                    driverName: null,
                    assignedAt: null,
                    assignedBy: null,
                    pickupSequence: null,
                    estimatedArrival: null,
                    pickupLocation: null,
                    routeDetails: null,
                    updatedAt: new Date()
                }
            }
        );

        console.log(`✅ Update Result:`);
        console.log(`   - Matched: ${result.matchedCount}`);
        console.log(`   - Modified: ${result.modifiedCount}`);

        if (result.modifiedCount > 0) {
            console.log('\n🎉 Rosters successfully reset! You can now assign them in the app.');
        } else {
            console.log('\n⚠️ No rosters were modified. Check if they were already reset.');
        }

    } catch (error) {
        console.error('Error:', error);
    } finally {
        await client.close();
    }
}

forceResetRosters();
