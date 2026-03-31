const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const uri = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const client = new MongoClient(uri);

async function checkCustomersAndDrivers() {
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');

    const db = client.db('abra_fleet');
    const usersCollection = db.collection('users');
    const driversCollection = db.collection('drivers');
    const vehiclesCollection = db.collection('vehicles');

    // Check customers
    const customers = await usersCollection.find({ 
      role: 'customer' 
    }).toArray();
    
    console.log(`👥 CUSTOMERS: ${customers.length}`);
    if (customers.length > 0) {
      console.log('\nSample customers:');
      customers.slice(0, 5).forEach(customer => {
        console.log(`  - ${customer.name} (${customer.email})`);
        console.log(`    UID: ${customer.uid}`);
        console.log(`    Organization: ${customer.organizationId || 'NONE'}`);
        console.log(`    Status: ${customer.status || 'unknown'}`);
        console.log('');
      });
      if (customers.length > 5) {
        console.log(`  ... and ${customers.length - 5} more\n`);
      }
    } else {
      console.log('  ❌ No customers found!\n');
    }

    // Check drivers
    const drivers = await driversCollection.find({}).toArray();
    
    console.log(`\n🚗 DRIVERS: ${drivers.length}`);
    if (drivers.length > 0) {
      console.log('\nAll drivers:');
      drivers.forEach(driver => {
        console.log(`  - ${driver.name || 'NO NAME'} (${driver.email || 'NO EMAIL'})`);
        console.log(`    MongoDB ID: ${driver._id}`);
        console.log(`    Firebase UID: ${driver.uid || 'NONE'}`);
        console.log(`    Status: ${driver.status || 'unknown'}`);
        console.log(`    Organization: ${driver.organizationId || 'NONE'}`);
        console.log('');
      });
    } else {
      console.log('  ❌ No drivers found!\n');
    }

    // Check vehicles
    const vehicles = await vehiclesCollection.find({}).toArray();
    
    console.log(`\n🚙 VEHICLES: ${vehicles.length}`);
    if (vehicles.length > 0) {
      console.log('\nSample vehicles:');
      vehicles.slice(0, 5).forEach(vehicle => {
        console.log(`  - ${vehicle.registrationNumber} (${vehicle.model || 'Unknown'})`);
        console.log(`    Status: ${vehicle.status || 'unknown'}`);
        console.log(`    Organization: ${vehicle.organizationId || 'NONE'}`);
        console.log('');
      });
      if (vehicles.length > 5) {
        console.log(`  ... and ${vehicles.length - 5} more\n`);
      }
    } else {
      console.log('  ❌ No vehicles found!\n');
    }

    // Summary
    console.log('\n📊 SUMMARY:');
    console.log('='.repeat(60));
    console.log(`Customers: ${customers.length}`);
    console.log(`Drivers: ${drivers.length}`);
    console.log(`Vehicles: ${vehicles.length}`);
    console.log(`Rosters: 0 (checked earlier)`);
    
    console.log('\n\n💡 WHAT TO DO NEXT:');
    console.log('='.repeat(60));
    
    if (customers.length === 0) {
      console.log('❌ NO CUSTOMERS - Add customers first through admin panel');
    } else if (drivers.length === 0) {
      console.log('❌ NO DRIVERS - Add drivers first through admin panel');
    } else if (vehicles.length === 0) {
      console.log('❌ NO VEHICLES - Add vehicles first through admin panel');
    } else {
      console.log('✅ You have customers, drivers, and vehicles');
      console.log('\nTo assign rosters:');
      cons
ole.log('1. Login as admin');
      console.log('2. Go to Customer Management');
      console.log('3. Select customers to assign');
      console.log('4. Click "Assign Roster" or "Route Optimization"');
      console.log('5. Select driver and vehicle');
      console.log('6. Choose date range');
      console.log('7. Confirm assignment');
      console.log('\nThis will create rosters in the database.');
    }

  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

checkCustomersAndDrivers();
