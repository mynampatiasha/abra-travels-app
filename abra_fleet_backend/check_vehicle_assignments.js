const { MongoClient } = require('mongodb');
require('dotenv').config();

const uri = process.env.MONGODB_URI;
const client = new MongoClient(uri);

async function checkVehicleAssignments() {
    try {
        await client.connect();
        const db = client.db('abra_fleet');

        console.log('\n🔍 Checking Vehicle Assignments and Capacities...');
        console.log('='.repeat(80));
        console.log(`${'Vehicle Number'.padEnd(15)} | ${'Capacity'.padEnd(8)} | ${'Driver Name'.padEnd(25)} | ${'Driver ID'}`);
        console.log('-'.repeat(80));

        const vehicles = await db.collection('vehicles').find({}).toArray();

        // Sort by vehicle number for easier reading
        vehicles.sort((a, b) => (a.vehicleNumber || '').localeCompare(b.vehicleNumber || ''));

        for (const vehicle of vehicles) {
            let driverName = 'UNASSIGNED';
            let driverId = '-';

            // Check embedded driver object
            if (vehicle.driver && vehicle.driver.name) {
                driverName = vehicle.driver.name;
                driverId = vehicle.driver.id || vehicle.driver._id || 'Unknown ID';
            }
            // Check assignedDriverId field if embedded object is missing
            else if (vehicle.assignedDriverId) {
                const driver = await db.collection('drivers').findOne({ _id: vehicle.assignedDriverId });
                if (driver) {
                    driverName = driver.name;
                    driverId = driver._id.toString();
                } else {
                    driverName = 'ID Found but Driver Missing';
                    driverId = vehicle.assignedDriverId;
                }
            }

            console.log(`${(vehicle.vehicleNumber || 'N/A').padEnd(15)} | ${String(vehicle.seatCapacity || 'N/A').padEnd(8)} | ${driverName.padEnd(25)} | ${driverId}`);
        }
        console.log('='.repeat(80));
        console.log(`Total Vehicles: ${vehicles.length}`);

    } catch (error) {
        console.error('❌ Error:', error);
    } finally {
        await client.close();
    }
}

checkVehicleAssignments();
