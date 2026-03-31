const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const uri = process.env.MONGODB_URI;
const client = new MongoClient(uri);

const rosterIds = [
    '694a8a867dad313c6ad8b997', // Kavitha Reddy
    '694a8a867dad313c6ad8b9a5', // Shruthi Hegde
    '694a8a867dad313c6ad8b977', // Suresh Reddy
    '694a8a867dad313c6ad8b975', // Rajesh Kumar
    '694a8a867dad313c6ad8b984', // Harish Iyer
    '694ab5b1469d9e474be2471c', // Deepak Nair
    '694ab5b1469d9e474be2471a'  // Arun Reddy
];

async function checkFailedRosters() {
    try {
        await client.connect();
        const db = client.db('abra_fleet');

        console.log('\n🔍 Checking Status of Failed Rosters...');

        const rosters = await db.collection('rosters').find({
            _id: { $in: rosterIds.map(id => new ObjectId(id)) }
        }).toArray();

        console.log('Found:', rosters.length, 'rosters');

        rosters.forEach(r => {
            console.log(`\n📋 ${r.customerName} (${r._id})`);
            console.log(`   Status: ${r.status}`);
            console.log(`   Vehicle: ${r.vehicleId || 'None'}`);
            console.log(`   Driver: ${r.driverId || 'None'}`);
            console.log(`   Trip: ${r.tripId || 'None'}`);
        });

    } catch (error) {
        console.error('❌ Error:', error);
    } finally {
        await client.close();
    }
}

checkFailedRosters();
