// Check if driver email exists in database
require('dotenv').config();
const { MongoClient } = require('mongodb');

const uri = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const client = new MongoClient(uri);

async function checkDriverEmail() {
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');

    const db = client.db('abraFleet');
    
    const email = 'ashamynampati24@gmail.com'; // Changed from .co to .com
    
    console.log(`\n🔍 Searching for driver with email: ${email}`);
    console.log('='.repeat(80));
    
    // Search in drivers collection
    const driver = await db.collection('drivers').findOne({
      $or: [
        { email: email },
        { 'personalInfo.email': email }
      ]
    });
    
    if (driver) {
      console.log('\n✅ DRIVER FOUND!');
      console.log('='.repeat(80));
      console.log('\nDriver Details:');
      console.log('  Driver ID:', driver.driverId || 'N/A');
      console.log('  Name:', driver.name || `${driver.personalInfo?.firstName} ${driver.personalInfo?.lastName}` || 'N/A');
      console.log('  Email (root):', driver.email || 'N/A');
      console.log('  Email (personalInfo):', driver.personalInfo?.email || 'N/A');
      console.log('  Phone:', driver.phone || driver.personalInfo?.phone || 'N/A');
      console.log('  Status:', driver.status || 'N/A');
      console.log('  Created At:', driver.createdAt || 'N/A');
      console.log('  Updated At:', driver.updatedAt || 'N/A');
      
      if (driver.assignedVehicle) {
        console.log('\n🚗 Assigned Vehicle:');
        console.log('  Vehicle ID:', driver.assignedVehicle.vehicleId || driver.assignedVehicle._id || 'N/A');
        console.log('  Registration:', driver.assignedVehicle.registrationNumber || 'N/A');
      } else {
        console.log('\n🚗 No vehicle assigned');
      }
      
      // Check for rosters
      const rosterCount = await db.collection('rosters').countDocuments({
        driverId: driver.driverId
      });
      console.log('\n📋 Rosters assigned:', rosterCount);
      
      // Check for trips
      const tripCount = await db.collection('trips').countDocuments({
        driverId: driver.driverId
      });
      console.log('🚕 Trips assigned:', tripCount);
      
      console.log('\n' + '='.repeat(80));
      console.log('\n📄 Full Driver Document:');
      console.log(JSON.stringify(driver, null, 2));
      
    } else {
      console.log('\n❌ DRIVER NOT FOUND');
      console.log('='.repeat(80));
      console.log('\nNo driver found with email:', email);
      
      // Search for similar emails
      console.log('\n🔍 Searching for similar emails...');
      const similarDrivers = await db.collection('drivers').find({
        $or: [
          { email: { $regex: 'asha', $options: 'i' } },
          { 'personalInfo.email': { $regex: 'asha', $options: 'i' } }
        ]
      }).limit(10).toArray();
      
      if (similarDrivers.length > 0) {
        console.log(`\n📧 Found ${similarDrivers.length} driver(s) with similar email:`);
        similarDrivers.forEach((d, index) => {
          console.log(`\n${index + 1}. Driver ID: ${d.driverId}`);
          console.log(`   Name: ${d.name || `${d.personalInfo?.firstName} ${d.personalInfo?.lastName}`}`);
          console.log(`   Email (root): ${d.email || 'N/A'}`);
          console.log(`   Email (personalInfo): ${d.personalInfo?.email || 'N/A'}`);
          console.log(`   Status: ${d.status}`);
        });
      } else {
        console.log('   No similar emails found');
      }
    }
    
    // Also check all drivers count
    const totalDrivers = await db.collection('drivers').countDocuments();
    console.log(`\n📊 Total drivers in database: ${totalDrivers}`);
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

checkDriverEmail();
