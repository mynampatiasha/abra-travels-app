const { MongoClient } = require('mongodb');
require('dotenv').config();

const uri = process.env.MONGODB_URI;
const client = new MongoClient(uri);

async function findStuckRosters() {
    try {
        await client.connect();
        const db = client.db('abra_fleet');

        console.log('\n🔍 Searching for "stuck" rosters (Assigned but no Trip Created)...');

        // Find rosters that are 'assigned' but might be stuck
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
            // Check if tripId is missing OR if the trip doesn't actually exist
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

        console.log(`\n📋 Found ${stuckRosters.length} POTENTIALLY STUCK assigned rosters:`);

        stuckRosters.forEach(roster => {
            console.log(`   - ID: ${roster._id}`);
            console.log(`     Customer: ${roster.customerName}`);
            console.log(`     Assigned At: ${roster.assignedAt}`);
            console.log(`     TripID: ${roster.tripId || 'MISSING'}`);
            console.log('---');
        });

        if (stuckRosters.length > 0) {
            console.log('\n💡 Recommendation: Run a cleanup script for these IDs.');
        } else {
            console.log('✅ No stuck rosters found. All assigned rosters have valid trips.');
        }

    } catch (error) {
        console.error('❌ Error:', error);
    } finally {
        await client.close();
    }
}

findStuckRosters();
