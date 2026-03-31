// Script to check and optionally reset roster status
const { MongoClient, ObjectId } = require('mongodb');

const MONGO_URI = 'mongodb://localhost:27017';
const DB_NAME = 'abra_fleet';

const rosterIds = [
    '694a8a867dad313c6ad8b992', // Rohit Menon
    '694a8a867dad313c6ad8b999', // Divya Rao
    '694a8a867dad313c6ad8b99d'  // Anitha Menon
];

async function checkAndResetRosters() {
    const client = new MongoClient(MONGO_URI);

    try {
        await client.connect();
        console.log('✅ Connected to MongoDB');

        const db = client.db(DB_NAME);
        const rostersCollection = db.collection('rosters');

        // Check current status
        console.log('\n📋 Current Roster Status:');
        console.log('='.repeat(80));

        for (const id of rosterIds) {
            const roster = await rostersCollection.findOne({ _id: new ObjectId(id) });

            if (roster) {
                console.log(`\n🔍 Roster: ${id}`);
                console.log(`   Customer: ${roster.customerName}`);
                console.log(`   Status: ${roster.status}`);
                console.log(`   VehicleId: ${roster.vehicleId || 'None'}`);
                console.log(`   DriverId: ${roster.driverId || 'None'}`);
                console.log(`   AssignedAt: ${roster.assignedAt || 'Never'}`);
            } else {
                console.log(`\n❌ Roster ${id} not found`);
            }
        }

        console.log('\n' + '='.repeat(80));
        console.log('\n⚠️  To reset these rosters to pending_assignment status, run:');
        console.log('   node reset_these_rosters.js\n');

    } catch (error) {
        console.error('❌ Error:', error);
    } finally {
        await client.close();
    }
}

checkAndResetRosters();
