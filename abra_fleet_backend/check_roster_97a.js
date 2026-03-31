const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const uri = process.env.MONGODB_URI;
const client = new MongoClient(uri);

async function checkRoster() {
    try {
        await client.connect();
        const db = client.db('abra_fleet');

        // Roster ID from logs: 694a8a867dad313c6ad8b97a
        const rosterId = new ObjectId('694a8a867dad313c6ad8b97a');

        console.log(`\n🔍 Checking Roster: ${rosterId}`);

        const roster = await db.collection('rosters').findOne({ _id: rosterId });

        if (!roster) {
            console.log('❌ Roster NOT FOUND');
        } else {
            console.log('✅ Roster FOUND');
            console.log('   Customer:', roster.customerName);
            console.log('   Status:', roster.status);
            console.log('   VehicleId:', roster.vehicleId);
            console.log('   DriverId:', roster.driverId);
            console.log('   AssignedAt:', roster.assignedAt);
        }

    } catch (error) {
        console.error('❌ Error:', error);
    } finally {
        await client.close();
    }
}

checkRoster();
