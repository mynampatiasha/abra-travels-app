const { MongoClient } = require('mongodb');
require('dotenv').config();

const uri = process.env.MONGODB_URI;
const client = new MongoClient(uri);

async function bulkResetStuckRosters() {
    try {
        await client.connect();
        const db = client.db('abra_fleet');

        console.log('\n🧹 Starting Bulk Reset of "Stuck" Rosters...');

        // 1. Identify the stuck rosters (Assigned but no Trip)
        const stuckRosters = await db.collection('rosters').aggregate([
            {
                $match: {
                    status: 'assigned'
                }
            },
            {
                $lookup: {
                    from: 'trips',
                    localField: 'tripId',
                    foreignField: '_id',
                    as: 'tripData'
                }
            },
            {
                $match: {
                    $or: [
                        { tripId: { $exists: false } },
                        { tripId: null },
                        { tripData: { $size: 0 } }
                    ]
                }
            }
        ]).toArray();

        const count = stuckRosters.length;
        console.log(`📋 Found ${count} rosters to reset.`);

        if (count === 0) {
            console.log('✅ No action needed.');
            return;
        }

        const stuckIds = stuckRosters.map(r => r._id);

        // 2. Perform Bulk Update
        const result = await db.collection('rosters').updateMany(
            { _id: { $in: stuckIds } },
            {
                $set: { status: 'pending_assignment' },
                $unset: {
                    vehicleId: "",
                    driverId: "",
                    tripId: "",
                    assignedAt: "",
                    routeDetails: ""
                }
            }
        );

        console.log(`✅ Bulk Reset Complete:`);
        console.log(`   - Matched: ${result.matchedCount}`);
        console.log(`   - Modified: ${result.modifiedCount}`);
        console.log(`🎉 All ${result.modifiedCount} stuck rosters are now "Pending Assignment" and ready to be processed.`);

    } catch (error) {
        console.error('❌ Error:', error);
    } finally {
        await client.close();
    }
}

bulkResetStuckRosters();
