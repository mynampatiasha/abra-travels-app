const { MongoClient } = require('mongodb');
require('dotenv').config();

const uri = process.env.MONGODB_URI;
const client = new MongoClient(uri);

async function checkKA02Structure() {
    try {
        await client.connect();
        const db = client.db('abra_fleet');

        console.log('\n🔍 Checking Structure of KA02CD5678...');

        // Find by registration number or part of it
        const vehicles = await db.collection('vehicles').find({
            $or: [
                { registrationNumber: /KA02CD5678/i },
                { vehicleNumber: /KA02CD5678/i },
                { name: /KA02CD5678/i }
            ]
        }).toArray();

        if (vehicles.length === 0) {
            console.log('❌ Vehicle KA02CD5678 not found!');
            return;
        }

        const vehicle = vehicles[0];
        console.log('✅ Vehicle Found:', vehicle.registrationNumber || vehicle.name);
        console.log('\n📄 Full Document Structure:');
        console.dir(vehicle, { depth: null });

        console.log('\n🎯 Field Analysis:');
        console.log(`1. capacity: ${JSON.stringify(vehicle.capacity)}`);
        if (vehicle.capacity) {
            console.log(`   - capacity.passengers: ${vehicle.capacity.passengers} (${typeof vehicle.capacity.passengers})`);
            console.log(`   - capacity.seating: ${vehicle.capacity.seating} (${typeof vehicle.capacity.seating})`);
        }
        console.log(`2. seatCapacity: ${vehicle.seatCapacity} (${typeof vehicle.seatCapacity})`);
        console.log(`3. seatingCapacity: ${vehicle.seatingCapacity} (${typeof vehicle.seatingCapacity})`);

    } catch (error) {
        console.error('❌ Error:', error);
    } finally {
        await client.close();
    }
}

checkKA02Structure();
