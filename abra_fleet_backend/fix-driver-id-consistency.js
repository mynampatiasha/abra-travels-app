// fix-driver-id-consistency.js - Fix Driver ID Consistency Issues
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI;

async function fixDriverIdConsistency() {
  console.log('\n🔧 FIXING DRIVER ID CONSISTENCY ISSUES');
  console.log('═'.repeat(80));
  
  let client;
  
  try {
    // Connect to MongoDB
    console.log('📡 Connecting to MongoDB...');
    client = new MongoClient(MONGODB_URI);
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('✅ Connected to MongoDB');
    console.log('─'.repeat(80));
    
    // ========================================================================
    // STEP 1: Find the Rajesh Kumar Driver Record
    // ========================================================================
    console.log('\n📂 STEP 1: FINDING RAJESH KUMAR DRIVER RECORD');
    console.log('─'.repeat(40));
    
    // Look for Rajesh Kumar in drivers collection
    const rajeshDriver = await db.collection('drivers').findOne({
      $or: [
        { 'personalInfo.firstName': /rajesh/i },
        { 'personalInfo.lastName': /kumar/i },
        { name: /rajesh.*kumar/i },
        { email: /rajesh/i }
      ]
    });
    
    if (rajeshDriver) {
      console.log('✅ Found Rajesh Kumar driver:');
      console.log(`   _id: ${rajeshDriver._id}`);
      console.log(`   driverId: ${rajeshDriver.driverId}`);
      console.log(`   email: ${rajeshDriver.personalInfo?.email || rajeshDriver.email}`);
      console.log(`   name: ${rajeshDriver.personalInfo?.firstName || rajeshDriver.name} ${rajeshDriver.personalInfo?.lastName || ''}`);
    } else {
      console.log('❌ Rajesh Kumar driver not found in drivers collection');
      
      // Check if there's a user with ObjectId 694a7fcd0c69d7fbd556eae7
      const orphanedId = '694a7fcd0c69d7fbd556eae7';
      const orphanedDriver = await db.collection('drivers').findOne({
        _id: new ObjectId(orphanedId)
      });
      
      if (orphanedDriver) {
        console.log('✅ Found driver with orphaned ObjectId:');
        console.log(`   _id: ${orphanedDriver._id}`);
        console.log(`   driverId: ${orphanedDriver.driverId}`);
        console.log(`   name: ${orphanedDriver.personalInfo?.firstName || orphanedDriver.name}`);
      }
    }
    
    // ========================================================================
    // STEP 2: Fix Rosters Collection - Replace ObjectId with DRV-XXXXXX
    // ========================================================================
    console.log('\n\n🔄 STEP 2: FIXING ROSTERS COLLECTION');
    console.log('─'.repeat(40));
    
    const orphanedObjectId = '694a7fcd0c69d7fbd556eae7';
    
    // Find rosters using the orphaned ObjectId
    const rostersWithOrphanedId = await db.collection('rosters').find({
      driverId: orphanedObjectId
    }).toArray();
    
    console.log(`Found ${rostersWithOrphanedId.length} rosters with orphaned ObjectId`);
    
    if (rostersWithOrphanedId.length > 0 && rajeshDriver) {
      console.log(`Updating rosters to use proper driverId: ${rajeshDriver.driverId}`);
      
      const updateResult = await db.collection('rosters').updateMany(
        { driverId: orphanedObjectId },
        { 
          $set: { 
            driverId: rajeshDriver.driverId,
            updatedAt: new Date()
          } 
        }
      );
      
      console.log(`✅ Updated ${updateResult.modifiedCount} rosters`);
    }
    
    // ========================================================================
    // STEP 3: Check and Fix Trips Collection
    // ========================================================================
    console.log('\n\n🔄 STEP 3: CHECKING TRIPS COLLECTION');
    console.log('─'.repeat(40));
    
    // Find trips with orphaned driver IDs
    const allDriverIds = await db.collection('drivers').distinct('driverId');
    const tripsWithOrphanedIds = await db.collection('trips').find({
      driverId: { $nin: allDriverIds }
    }).toArray();
    
    console.log(`Found ${tripsWithOrphanedIds.length} trips with orphaned driver IDs`);
    
    if (tripsWithOrphanedIds.length > 0) {
      console.log('Orphaned trip driver IDs:');
      const orphanedTripIds = [...new Set(tripsWithOrphanedIds.map(trip => trip.driverId))];
      orphanedTripIds.forEach(id => {
        console.log(`   - ${id}`);
      });
      
      // Try to map orphaned IDs to existing drivers
      for (const orphanedId of orphanedTripIds) {
        if (orphanedId === orphanedObjectId && rajeshDriver) {
          console.log(`Fixing trips with ObjectId ${orphanedId} → ${rajeshDriver.driverId}`);
          
          const tripUpdateResult = await db.collection('trips').updateMany(
            { driverId: orphanedId },
            { 
              $set: { 
                driverId: rajeshDriver.driverId,
                updatedAt: new Date()
              } 
            }
          );
          
          console.log(`✅ Updated ${tripUpdateResult.modifiedCount} trips`);
        }
      }
    }
    
    // ========================================================================
    // STEP 4: Ensure All Drivers Have Proper DRV-XXXXXX Format
    // ========================================================================
    console.log('\n\n🔄 STEP 4: ENSURING PROPER DRIVER ID FORMAT');
    console.log('─'.repeat(40));
    
    // Find drivers without proper DRV-XXXXXX format
    const driversWithBadIds = await db.collection('drivers').find({
      $or: [
        { driverId: { $exists: false } },
        { driverId: null },
        { driverId: '' },
        { driverId: { $not: /^DRV-\d{6}$/ } }
      ]
    }).toArray();
    
    console.log(`Found ${driversWithBadIds.length} drivers with invalid driverId format`);
    
    if (driversWithBadIds.length > 0) {
      // Get the highest existing DRV number
      const existingDriverIds = await db.collection('drivers').find({
        driverId: /^DRV-\d{6}$/
      }).toArray();
      
      let maxNumber = 100000;
      existingDriverIds.forEach(driver => {
        const match = driver.driverId.match(/^DRV-(\d{6})$/);
        if (match) {
          const number = parseInt(match[1]);
          if (number > maxNumber) {
            maxNumber = number;
          }
        }
      });
      
      console.log(`Next available DRV number: ${maxNumber + 1}`);
      
      // Fix each driver with bad ID
      for (let i = 0; i < driversWithBadIds.length; i++) {
        const driver = driversWithBadIds[i];
        const newDriverId = `DRV-${String(maxNumber + 1 + i).padStart(6, '0')}`;
        
        console.log(`Fixing driver ${driver._id}: ${driver.driverId || 'MISSING'} → ${newDriverId}`);
        
        await db.collection('drivers').updateOne(
          { _id: driver._id },
          { 
            $set: { 
              driverId: newDriverId,
              updatedAt: new Date()
            } 
          }
        );
      }
      
      console.log(`✅ Fixed ${driversWithBadIds.length} driver IDs`);
    }
    
    // ========================================================================
    // STEP 5: Update JWT Router to Include DriverId
    // ========================================================================
    console.log('\n\n🔄 STEP 5: CHECKING JWT INTEGRATION');
    console.log('─'.repeat(40));
    
    console.log('💡 RECOMMENDATION: Update JWT token payload to include driverId');
    console.log('   - For driver role users, include driverId in JWT token');
    console.log('   - Frontend can use this for driver-specific operations');
    console.log('   - Backend routes can access via req.user.driverId');
    
    // ========================================================================
    // STEP 6: Verification - Re-run Consistency Check
    // ========================================================================
    console.log('\n\n✅ STEP 6: VERIFICATION');
    console.log('─'.repeat(40));
    
    // Count issues after fixes
    const finalTripDriverIds = await db.collection('trips').distinct('driverId');
    const finalRosterDriverIds = await db.collection('rosters').distinct('driverId');
    const finalDriverCollectionIds = await db.collection('drivers').distinct('driverId');
    
    const finalAllUsedDriverIds = [...new Set([...finalTripDriverIds, ...finalRosterDriverIds])];
    const finalOrphanedDriverIds = finalAllUsedDriverIds.filter(id => 
      id && !finalDriverCollectionIds.includes(id)
    );
    
    console.log('Final Status:');
    console.log(`   Driver IDs in trips: ${finalTripDriverIds.length}`);
    console.log(`   Driver IDs in rosters: ${finalRosterDriverIds.length}`);
    console.log(`   Driver IDs in drivers collection: ${finalDriverCollectionIds.length}`);
    console.log(`   Orphaned driver IDs: ${finalOrphanedDriverIds.length}`);
    
    if (finalOrphanedDriverIds.length === 0) {
      console.log('✅ NO ORPHANED DRIVER IDS - Consistency fixed!');
    } else {
      console.log('❌ Still have orphaned driver IDs:');
      finalOrphanedDriverIds.forEach(id => {
        console.log(`   - ${id}`);
      });
    }
    
    // Check driver ID formats
    const finalDriverIdFormats = {
      drvFormat: 0,
      objectId: 0,
      other: 0
    };
    
    const finalAllDriverIds = [...finalDriverCollectionIds, ...finalTripDriverIds, ...finalRosterDriverIds];
    const finalUniqueDriverIds = [...new Set(finalAllDriverIds)].filter(id => id);
    
    finalUniqueDriverIds.forEach(id => {
      if (typeof id === 'string') {
        if (/^DRV-\d{6}$/.test(id)) {
          finalDriverIdFormats.drvFormat++;
        } else if (/^[0-9a-fA-F]{24}$/.test(id)) {
          finalDriverIdFormats.objectId++;
        } else {
          finalDriverIdFormats.other++;
        }
      }
    });
    
    console.log('\nFinal Driver ID Format Distribution:');
    console.log(`   DRV-XXXXXX format: ${finalDriverIdFormats.drvFormat}`);
    console.log(`   ObjectId format: ${finalDriverIdFormats.objectId}`);
    console.log(`   Other formats: ${finalDriverIdFormats.other}`);
    
    console.log('\n═'.repeat(80));
    console.log('🎉 DRIVER ID CONSISTENCY FIX COMPLETED!');
    console.log('═'.repeat(80));
    
  } catch (error) {
    console.error('\n❌ ERROR FIXING DRIVER ID CONSISTENCY');
    console.error('═'.repeat(80));
    console.error('Error:', error.message);
    console.error('Stack:', error.stack);
  } finally {
    if (client) {
      await client.close();
      console.log('📡 MongoDB connection closed');
    }
  }
}

// Run the fix
if (require.main === module) {
  fixDriverIdConsistency().catch(console.error);
}

module.exports = { fixDriverIdConsistency };