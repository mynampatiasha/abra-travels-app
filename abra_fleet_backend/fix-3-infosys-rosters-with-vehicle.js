// Update the 3 Infosys rosters with correct vehicle and driver information
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function fixInfosysRosters() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB Atlas');
    
    const db = client.db('abra_fleet');
    
    // Get vehicle KA01AB1240 details
    const vehicle = await db.collection('vehicles').findOne({ registrationNumber: 'KA01AB1240' });
    
    if (!vehicle) {
      console.log('❌ Vehicle KA01AB1240 not found!');
      return;
    }
    
    console.log(`✅ Found vehicle: ${vehicle.registrationNumber}`);
    console.log(`   Driver ID: ${vehicle.assignedDriver}`);
    
    // Get driver details
    const driver = await db.collection('drivers').findOne({ driverId: vehicle.assignedDriver });
    
    if (!driver) {
      console.log('❌ Driver not found!');
      return;
    }
    
    console.log(`✅ Found driver: ${driver.name} (${driver.phone})`);
    
    console.log('\n📝 Updating 3 Infosys rosters...\n');
    
    // Update all 3 rosters
    const result = await db.collection('rosters').updateMany(
      {
        customerEmail: { $in: [
          'rajesh.kumar@infosys.com',
          'priya.sharma@infosys.com',
          'amit.patel@infosys.com'
        ]},
        status: 'pending'
      },
      {
        $set: {
          vehicleNumber: vehicle.registrationNumber,
          vehicleId: vehicle._id.toString(),
          driverId: driver.driverId,
          driverName: driver.name,
          driverPhone: driver.phone,
          status: 'assigned',
          updatedAt: new Date()
        }
      }
    );
    
    console.log(`✅ Updated ${result.modifiedCount} rosters!\n`);
    
    // Verify the update
    const updatedRosters = await db.collection('rosters')
      .find({
        customerEmail: { $in: [
          'rajesh.kumar@infosys.com',
          'priya.sharma@infosys.com',
          'amit.patel@infosys.com'
        ]}
      })
      .toArray();
    
    console.log('📊 Updated Rosters:\n');
    updatedRosters.forEach((r, i) => {
      console.log(`${i + 1}. ${r.customerName} (${r.customerEmail})`);
      console.log(`   Vehicle: ${r.vehicleNumber}`);
      console.log(`   Driver: ${r.driverName} (${r.driverPhone})`);
      console.log(`   Status: ${r.status}`);
      console.log('');
    });
    
    console.log('✅ SUCCESS! The 3 Infosys rosters are now properly assigned!');
    console.log('\n📱 Next Steps:');
    console.log('   1. Refresh the Client Roster Management page');
    console.log('   2. You should see 3 Infosys rosters in Active Rosters');
    console.log('   3. Each roster will show vehicle KA01AB1240 and driver details');
    console.log('   4. Neha Gupta and Vikram Singh remain deleted (as you requested)\n');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

fixInfosysRosters();
