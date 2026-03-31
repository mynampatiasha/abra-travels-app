const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const uri = process.env.MONGODB_URI;

async function fixAssignedRosters() {
  const client = new MongoClient(uri);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('abra_fleet');
    
    console.log('🔧 FIXING ASSIGNED ROSTERS - Adding Vehicle & Driver Details\n');
    console.log('='.repeat(80));
    
    // Get all assigned rosters
    const assignedRosters = await db.collection('rosters').find({
      status: 'assigned'
    }).toArray();
    
    console.log(`\n📋 Found ${assignedRosters.length} assigned rosters\n`);
    
    let fixed = 0;
    let errors = 0;
    
    for (const roster of assignedRosters) {
      try {
        console.log(`\n🔍 Processing: ${roster.customerName} (${roster._id})`);
        
        const updates = {};
        let needsUpdate = false;
        
        // Fix vehicle details
        if (roster.vehicleId) {
          const vehicle = await db.collection('vehicles').findOne({ 
            _id: new ObjectId(roster.vehicleId) 
          });
          
          if (vehicle) {
            const vehicleNumber = vehicle.registrationNumber || 
                                 vehicle.vehicleNumber || 
                                 vehicle.name || 
                                 vehicle.numberPlate ||
                                 'Unknown';
            
            if (roster.vehicleNumber === 'Unknown' || !roster.vehicleNumber) {
              updates.vehicleNumber = vehicleNumber;
              needsUpdate = true;
              console.log(`   ✅ Will update vehicleNumber: ${vehicleNumber}`);
            }
          }
        }
        
        // Fix driver details
        if (roster.driverId) {
          const driver = await db.collection('drivers').findOne({ 
            _id: new ObjectId(roster.driverId) 
          });
          
          if (driver) {
            // Extract driver name from nested structure
            const firstName = driver.personalInfo?.firstName || '';
            const lastName = driver.personalInfo?.lastName || '';
            const driverName = firstName && lastName 
              ? `${firstName} ${lastName}`.trim()
              : driver.personalInfo?.name || driver.name || 'Unknown Driver';
            
            // Extract driver phone from nested structure
            const driverPhone = driver.personalInfo?.phone || 
                               driver.personalInfo?.phoneNumber ||
                               driver.phone || 
                               driver.phoneNumber || 
                               driver.mobile ||
                               '';
            
            if (!roster.driverName || roster.driverName === 'Unknown Driver' || roster.driverName !== driverName) {
              updates.driverName = driverName;
              needsUpdate = true;
              console.log(`   ✅ Will update driverName: ${driverName}`);
            }
            
            if (!roster.driverPhone || roster.driverPhone !== driverPhone) {
              updates.driverPhone = driverPhone;
              needsUpdate = true;
              console.log(`   ✅ Will update driverPhone: ${driverPhone}`);
            }
          }
        }
        
        // Apply updates if needed
        if (needsUpdate) {
          updates.updatedAt = new Date();
          
          await db.collection('rosters').updateOne(
            { _id: roster._id },
            { $set: updates }
          );
          
          console.log(`   ✅ Updated successfully!`);
          fixed++;
        } else {
          console.log(`   ℹ️  No updates needed`);
        }
        
      } catch (error) {
        console.error(`   ❌ Error processing roster: ${error.message}`);
        errors++;
      }
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('\n📊 SUMMARY:');
    console.log(`   Total rosters processed: ${assignedRosters.length}`);
    console.log(`   Successfully fixed: ${fixed}`);
    console.log(`   Errors: ${errors}`);
    console.log('\n✅ Done! The assigned rosters now have correct vehicle and driver details.');
    console.log('   Refresh your app to see the changes.');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

fixAssignedRosters();
