// Quick diagnostic script to check roster status
const { MongoClient, ObjectId } = require('mongodb');

// URI fram .env
const MONGO_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function checkRosters() {
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

        console.log('\n📋 Checking Roster Status:\n');

        for (const id of rosterIds) {
            let roster = null;
            try {
                roster = await db.collection('rosters').findOne(
                    { _id: new ObjectId(id) }
                );
            } catch (e) {
                console.log(`❌ Invalid ID format: ${id}`);
                continue;
            }

            if (roster) {
                console.log(`✅ ID: ${id}`);
                console.log(`   Customer: ${roster.customerName}`);
                console.log(`   Status: '${roster.status}'`); // Quote to see spaces
                console.log(`   VehicleId: ${roster.vehicleId} (${typeof roster.vehicleId})`);
                console.log(`   DriverId: ${roster.driverId} (${typeof roster.driverId})`);
                console.log(`   AssignedAt: ${roster.assignedAt}`);
                console.log('-----------------------------------');
            } else {
                console.log(`❌ Roster ${id} not found`);
            }
        }

        // Also check if there are any rosters with 'assigned' status but NO vehicle/driver
        // This would be a data inconsistency
        const inconsistent = await db.collection('rosters').countDocuments({
            status: 'assigned',
            $or: [
                { vehicleId: null },
                { vehicleId: { $exists: false } }
            ]
        });
        console.log(`\n⚠️ Inconsistent Rosters (status=assigned but no vehicle): ${inconsistent}`);

    } catch (error) {
        console.error('Error:', error);
    } finally {
        await client.close();
    }
}

checkRosters();
