require('dotenv').config();
const mongoose = require('mongoose');
const { ObjectId } = require('mongodb');

const rosterId = '694a8a867dad313c6ad8b976';

async function resetRoster() {
    try {
        await mongoose.connect(process.env.MONGODB_URI);
        console.log('✅ Connected to MongoDB');

        const collection = mongoose.connection.db.collection('rosters');

        // Update the roster to reset it
        const result = await collection.updateOne(
            { _id: new ObjectId(rosterId) },
            {
                $set: {
                    status: 'pending_assignment',
                    vehicleId: null,
                    driverId: null,
                    tripId: null,
                    assignedAt: null,
                    routeDetails: null
                }
            }
        );

        console.log(`✅ Roster reset result: Matches: ${result.matchedCount}, Modified: ${result.modifiedCount}`);

        if (result.modifiedCount > 0) {
            console.log('🎉 Roster successfully reset to pending_assignment. You can now try assigning it again.');
        } else {
            console.log('⚠️  No changes made. Roster might already be pending or ID not found.');
        }

    } catch (error) {
        console.error('Error:', error);
    } finally {
        await mongoose.disconnect();
    }
}

resetRoster();
