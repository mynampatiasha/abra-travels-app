const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const uri = process.env.MONGODB_URI;
const client = new MongoClient(uri);

async function checkVehicleAssignments() {
    try {
        await client.connect();
        const db = client.db('abra_fleet');

        console.log('\n🔍 Checking Vehicle Assignments and Capacities...');
        console.log('='.repeat(100));
        console.log(`${'Vehicle Name'.padEnd(15)} | ${'Reg Number'.padEnd(15)} | ${'Cap'.padEnd(5)} | ${'Driver Name'.padEnd(25)} | ${'Driver ID'}`);
        console.log('-'.repeat(100));

        const vehicles = await db.collection('vehicles').find({}).toArray();

        // Sort by vehicle number for easier reading
        vehicles.sort((a, b) => (a.vehicleNumber || a.registrationNumber || '').localeCompare(b.vehicleNumber || b.registrationNumber || ''));

        for (const vehicle of vehicles) {
            // Normalize basic fields matching backend logic
            const vehicleName = vehicle.name || vehicle.vehicleNumber || vehicle.makeModel || vehicle.registrationNumber || 'Unknown';
            const regNumber = vehicle.vehicleNumber || vehicle.registrationNumber || 'N/A';
            const capacity = vehicle.capacity?.passengers || vehicle.seatCapacity || vehicle.seatingCapacity || 4;

            let driverName = 'UNASSIGNED';
            let driverId = '-';

            // Backend Logic for Driver Resolution:
            // 1. Check if assignedDriver is an object (embedded)
            if (vehicle.assignedDriver && typeof vehicle.assignedDriver === 'object' && vehicle.assignedDriver.name) {
                driverName = vehicle.assignedDriver.name;
                driverId = vehicle.assignedDriver.driverId || vehicle.assignedDriver._id || 'Embedded';
            }
            // 2. Check if assignedDriver is a string ID
            else if (vehicle.assignedDriver && typeof vehicle.assignedDriver === 'string') {
                const dId = vehicle.assignedDriver;
                // Lookup actual driver
                const driver = await db.collection('drivers').findOne({ driverId: dId });
                if (driver) {
                    const firstName = driver.personalInfo?.firstName || driver.firstName || '';
                    const lastName = driver.personalInfo?.lastName || driver.lastName || '';
                    driverName = `${firstName} ${lastName}`.trim() || driver.driverId;
                    driverId = driver.driverId;
                } else {
                    // Try looking up by _id if driverId failed
                    try {
                        const driverById = await db.collection('drivers').findOne({ _id: new ObjectId(dId) });
                        if (driverById) {
                            const firstName = driverById.personalInfo?.firstName || driverById.firstName || '';
                            const lastName = driverById.personalInfo?.lastName || driverById.lastName || '';
                            driverName = `${firstName} ${lastName}`.trim() || driverById.driverId;
                            driverId = driverById.driverId;
                        } else {
                            driverName = 'ID Found but Driver Missing';
                            driverId = dId;
                        }
                    } catch (e) {
                        driverName = 'Invalid Driver ID';
                        driverId = dId;
                    }
                }
            }
            // 3. Fallback: check nested 'driver' object (seen in some logs)
            else if (vehicle.driver && vehicle.driver.name) {
                driverName = vehicle.driver.name;
                driverId = vehicle.driver.id || '-';
            }

            console.log(`${vehicleName.padEnd(15).slice(0, 15)} | ${regNumber.padEnd(15)} | ${String(capacity).padEnd(5)} | ${driverName.padEnd(25).slice(0, 25)} | ${driverId}`);
        }
        console.log('='.repeat(100));
        console.log(`Total Vehicles: ${vehicles.length}`);

    } catch (error) {
        console.error('❌ Error:', error);
    } finally {
        await client.close();
    }
}

checkVehicleAssignments();
