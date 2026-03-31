const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const uri = process.env.MONGODB_URI;
const client = new MongoClient(uri);

async function resetRoster() {
    try {
        await client.connect();
        const db = client.db('abra_fleet');

        // Roster ID to reset: 694a8a867dad313c6ad8b97a
        const rosterId = new ObjectId('694a8a867dad313c6ad8b97a');

        console.log(`\n🔄 Resetting Roster: ${rosterId}`);

        // Update to pending_assignment and remove assignment details
        const result = await db.collection('rosters').updateOne(
            { _id: rosterId },
            {
                $set: {
                    status: 'pending_assignment'
                },
                $unset: {
                    vehicleId: "",
                    driverId: "",
                    tripId: "",
                    assignedAt: "",
                    routeDetails: ""
                }
            }
        );

        console.log(`✅ Roster reset result: Matches: ${result.matchedCount}, Modified: ${result.modifiedCount}`);

        if (result.modifiedCount > 0) {
            console.log('🎉 Roster successfully reset to pending_assignment. You can now try assigning it again.');
        } else {
            console.log('⚠️ Roster was not modified (maybe already pending?)');
        }

    } catch (error) {
        console.error('❌ Error:', error);
    } finally {
        await client.close();
    }
}

resetRoster();
