// Quick diagnostic script to check roster status
const { MongoClient, ObjectId } = require('mongodb');

async function checkRosters() {
    const client = new MongoClient('mongodb://localhost:27017');

    try {
        await client.connect();
        const db = client.db('abra_fleet');

        const rosterIds = [
            '694a8a867dad313c6ad8b992',
            '694a8a867dad313c6ad8b999',
            '694a8a867dad313c6ad8b99d'
        ];

        console.log('\n📋 Checking Roster Status:\n');

        for (const id of rosterIds) {
            const roster = await db.collection('rosters').findOne(
                { _id: new ObjectId(id) },
                { projection: { customerName: 1, status: 1, vehicleId: 1, driverId: 1, assignedAt: 1 } }
            );

            if (roster) {
                console.log(`✅ ${roster.customerName}`);
                console.log(`   Status: ${roster.status}`);
                console.log(`   VehicleId: ${roster.vehicleId ? 'ASSIGNED' : 'NULL'}`);
                console.log(`   DriverId: ${roster.driverId ? 'ASSIGNED' : 'NULL'}`);
                console.log('');
            }
        }

        console.log('💡 Solution: These rosters are already assigned.');
        console.log('   Either:');
        console.log('   1. Select DIFFERENT rosters that are pending');
        console.log('   2. Unassign these rosters first\n');

    } catch (error) {
        console.error('Error:', error.message);
    } finally {
        await client.close();
    }
}

checkRosters();
