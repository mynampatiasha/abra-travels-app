// Test script to verify driver name and phone are returned in assigned trips API
const { MongoClient } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function testDriverInfo() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db();
    
    // Find some assigned rosters
    const assignedRosters = await db.collection('rosters')
      .find({ 
        status: { $in: ['assigned', 'ongoing'] }
      })
      .limit(5)
      .toArray();
    
    console.log(`📋 Found ${assignedRosters.length} assigned rosters\n`);
    
    if (assignedRosters.length === 0) {
      console.log('⚠️  No assigned rosters found. Please assign some rosters first.');
      return;
    }
    
    // Check each roster for driver information
    for (const roster of assignedRosters) {
      console.log('='.repeat(80));
      console.log(`📝 Roster ID: ${roster._id}`);
      console.log(`   Customer: ${roster.customerName || 'Unknown'}`);
      console.log(`   Status: ${roster.status}`);
      console.log('');
      
      // Check all possible driver field names
      console.log('🔍 Driver Information Fields:');
      console.log(`   driverName: ${roster.driverName || '(not set)'}`);
      console.log(`   assignedDriverName: ${roster.assignedDriverName || '(not set)'}`);
      console.log(`   assignedDriver.name: ${roster.assignedDriver?.name || '(not set)'}`);
      console.log('');
      console.log(`   driverPhone: ${roster.driverPhone || '(not set)'}`);
      console.log(`   assignedDriverPhone: ${roster.assignedDriverPhone || '(not set)'}`);
      console.log(`   assignedDriver.phone: ${roster.assignedDriver?.phone || '(not set)'}`);
      console.log('');
      
      // Check vehicle information
      console.log('🚗 Vehicle Information Fields:');
      console.log(`   vehicleNumber: ${roster.vehicleNumber || '(not set)'}`);
      console.log(`   assignedVehicleReg: ${roster.assignedVehicleReg || '(not set)'}`);
      console.log(`   assignedVehicle.registrationNumber: ${roster.assignedVehicle?.registrationNumber || '(not set)'}`);
      console.log('');
      
      // Determine what would be returned by the API
      const driverName = roster.driverName || roster.assignedDriverName || roster.assignedDriver?.name || '';
      const driverPhone = roster.driverPhone || roster.assignedDriverPhone || roster.assignedDriver?.phone || '';
      const vehicleNumber = roster.vehicleNumber || roster.assignedVehicleReg || roster.assignedVehicle?.registrationNumber || '';
      
      console.log('✅ API Would Return:');
      console.log(`   Driver Name: ${driverName || '(EMPTY - THIS IS THE ISSUE!)'}`);
      console.log(`   Driver Phone: ${driverPhone || '(EMPTY - THIS IS THE ISSUE!)'}`);
      console.log(`   Vehicle Number: ${vehicleNumber || '(EMPTY)'}`);
      console.log('');
      
      if (!driverName || !driverPhone) {
        console.log('❌ PROBLEM FOUND: Driver information is missing!');
        console.log('   This roster needs to be reassigned to populate driver info.');
      } else {
        console.log('✅ Driver information is complete!');
      }
      console.log('');
    }
    
    console.log('='.repeat(80));
    console.log('\n📊 Summary:');
    console.log('   If you see empty driver names/phones above, the rosters need to be');
    console.log('   reassigned using the admin panel to populate the driver information.');
    console.log('\n   After reassigning, the driver name and phone will appear in the');
    console.log('   Trip Details dialog in the client roster management screen.');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

testDriverInfo();
