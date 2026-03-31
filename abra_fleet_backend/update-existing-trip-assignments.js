// Update existing assigned rosters with vehicle number and driver name
const { MongoClient, ObjectId } = require('mongodb');

async function updateExistingAssignments() {
  const client = new MongoClient('mongodb://localhost:27017');
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('abra_fleet');
    
    console.log('🔍 Finding rosters that need updating...\n');
    
    // Find all assigned rosters without vehicle/driver names
    const rostersToUpdate = await db.collection('rosters').find({
      status: { $in: ['assigned', 'scheduled', 'ongoing', 'in_progress', 'started', 'completed', 'done'] },
      vehicleId: { $exists: true, $ne: null },
      $or: [
        { vehicleNumber: { $exists: false } },
        { vehicleNumber: null },
        { vehicleNumber: '' }
      ]
    }).toArray();
    
    console.log(`📊 Found ${rostersToUpdate.length} rosters to update\n`);
    
    if (rostersToUpdate.length === 0) {
      console.log('✅ All rosters are already up to date!');
      return;
    }
    
    let updated = 0;
    let failed = 0;
    
    for (const roster of rostersToUpdate) {
      try {
        console.log(`\n📋 Processing: ${roster.customerName || 'Unknown'}`);
        console.log(`   Roster ID: ${roster._id}`);
        console.log(`   Status: ${roster.status}`);
        console.log(`   Vehicle ID: ${roster.vehicleId}`);
        console.log(`   Driver ID: ${roster.driverId || 'Not set'}`);
        
        // Get vehicle details
        const vehicle = await db.collection('vehicles').findOne({
          _id: new ObjectId(roster.vehicleId)
        });
        
        if (!vehicle) {
          console.log(`   ⚠️  Vehicle not found - skipping`);
          failed++;
          continue;
        }
        
        console.log(`   ✅ Vehicle found: ${vehicle.vehicleNumber || vehicle.name}`);
        
        // Get driver details
        let driver = null;
        if (roster.driverId) {
          try {
            driver = await db.collection('users').findOne({
              _id: new ObjectId(roster.driverId)
            });
            
            if (!driver) {
              // Try drivers collection
              driver = await db.collection('drivers').findOne({
                _id: new ObjectId(roster.driverId)
              });
              
              if (driver) {
                // Normalize driver data from drivers collection
                driver = {
                  name: `${driver.personalInfo?.firstName || ''} ${driver.personalInfo?.lastName || ''}`.trim() || 'Unknown Driver',
                  phone: driver.personalInfo?.phone || '',
                  phoneNumber: driver.personalInfo?.phone || ''
                };
              }
            }
          } catch (e) {
            console.log(`   ⚠️  Error finding driver: ${e.message}`);
          }
        }
        
        if (driver) {
          console.log(`   ✅ Driver found: ${driver.name}`);
        } else {
          console.log(`   ⚠️  Driver not found - will update vehicle only`);
        }
        
        // Prepare update data
        const updateData = {
          vehicleNumber: vehicle.vehicleNumber || vehicle.name || 'Unknown',
          updatedAt: new Date()
        };
        
        if (driver) {
          updateData.driverName = driver.name || 'Unknown Driver';
          updateData.driverPhone = driver.phone || driver.phoneNumber || '';
        }
        
        // Update roster
        await db.collection('rosters').updateOne(
          { _id: roster._id },
          { $set: updateData }
        );
        
        console.log(`   ✅ Updated successfully!`);
        console.log(`      Vehicle: ${updateData.vehicleNumber}`);
        if (updateData.driverName) {
          console.log(`      Driver: ${updateData.driverName}`);
        }
        
        updated++;
        
      } catch (error) {
        console.log(`   ❌ Error: ${error.message}`);
        failed++;
      }
    }
    
    console.log('\n' + '='.repeat(60));
    console.log('📊 MIGRATION SUMMARY');
    console.log('='.repeat(60));
    console.log(`Total rosters found: ${rostersToUpdate.length}`);
    console.log(`✅ Successfully updated: ${updated}`);
    console.log(`❌ Failed: ${failed}`);
    console.log(`📈 Success rate: ${((updated / rostersToUpdate.length) * 100).toFixed(1)}%`);
    console.log('='.repeat(60));
    
    if (updated > 0) {
      console.log('\n✅ Migration complete! Vehicle and driver data has been populated.');
      console.log('   You can now view the trips in the Trips Client screen.');
    }
    
  } catch (error) {
    console.error('❌ Fatal error:', error);
  } finally {
    await client.close();
    console.log('\n👋 Disconnected from MongoDB');
  }
}

// Run the migration
console.log('🚀 Starting migration to update existing trip assignments...\n');
updateExistingAssignments();
