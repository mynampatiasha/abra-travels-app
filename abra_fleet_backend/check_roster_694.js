require('dotenv').config();
const mongoose = require('mongoose');
const { ObjectId } = require('mongodb');

const rosterId = '694a8a867dad313c6ad8b976';

async function checkRoster() {
    try {
        await mongoose.connect(process.env.MONGODB_URI);
        console.log('✅ Connected to MongoDB');

        const collection = mongoose.connection.db.collection('rosters');
        const roster = await collection.findOne({ _id: new ObjectId(rosterId) });

        if (!roster) {
            console.log('❌ Roster not found with ID:', rosterId);
        } else {
            console.log('📋 Roster Details:');
            console.log(JSON.stringify(roster, null, 2));

            // Check query match manually
            const isStatusMatch = ['pending_assignment', 'pending'].includes(roster.status);
            const isVehicleEmpty = !roster.vehicleId || roster.vehicleId === '';
            const isDriverEmpty = !roster.driverId || roster.driverId === '';

            console.log('\n🔍 Match Analysis:');
            console.log('   - Status matches "pending/pending_assignment"?:', isStatusMatch ? '✅' : '❌ (' + roster.status + ')');
            console.log('   - Vehicle ID is empty?:', isVehicleEmpty ? '✅' : '❌ (' + roster.vehicleId + ')');
            console.log('   - Driver ID is empty?:', isDriverEmpty ? '✅' : '❌ (' + roster.driverId + ')');

            if (isStatusMatch && isVehicleEmpty && isDriverEmpty) {
                console.log('✅ SHOULD MATCH: Roster appears eligible for assignment.');
            } else {
                console.log('❌ NO MATCH: Roster is not in the expected state for assignment.');
            }
        }

    } catch (error) {
        console.error('Error:', error);
    } finally {
        await mongoose.disconnect();
    }
}

checkRoster();
