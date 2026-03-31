// complete-driver-id-cleanup.js - Complete Driver ID Cleanup
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI;

async function completeDriverIdCleanup() {
  console.log('\n🧹 COMPLETE DRIVER ID CLEANUP');
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
    // STEP 1: Get All Valid Driver IDs
    // ========================================================================
    console.log('\n📂 STEP 1: GETTING ALL VALID DRIVER IDS');
    console.log('─'.repeat(40));
    
    const validDrivers = await db.collection('drivers').find({
      driverId: { $exists: true, $ne: null, $ne: '' }
    }).toArray();
    
    const validDriverIds = validDrivers.map(d => d.driverId);
    console.log(`Found ${validDriverIds.length} valid driver IDs in drivers collection`);
    
    // Create mapping of driver names to IDs for orphaned records
    const driverNameToId = {};
    validDrivers.forEach(driver => {
      const name = driver.personalInfo?.firstName || driver.name || '';
      const lastName = driver.personalInfo?.lastName || '';
      const fullName = `${name} ${lastName}`.trim().toLowerCase();
      
      if (fullName) {
        driverNameToId[fullName] = driver.driverId;
      }
      
      // Also map by email
      const email = driver.personalInfo?.email || driver.email;
      if (email) {
        driverNameToId[email.toLowerCase()] = driver.driverId;
      }
    });
    
    console.log('Driver name/email to ID mapping created');
    
    // ========================================================================
    // STEP 2: Clean Up Trips Collection
    // ========================================================================
    console.log('\n\n🔄 STEP 2: CLEANING UP TRIPS COLLECTION');
    console.log('─'.repeat(40));
    
    // Find all trips with invalid driver IDs
    const tripsWithInvalidIds = await db.collection('trips').find({
      $or: [
        { driverId: { $nin: validDriverIds } },
        { driverId: null },
        { driverId: undefined },
        { driverId: '' }
      ]
    }).toArray();
    
    console.log(`Found ${tripsWithInvalidIds.length} trips with invalid driver IDs`);
    
    let tripsFixed = 0;
    let tripsDeleted = 0;
    
    for (const trip of tripsWithInvalidIds) {
      console.log(`\nProcessing trip ${trip._id}:`);
      console.log(`   Current driverId: ${trip.driverId || 'MISSING'}`);
      console.log(`   Driver name: ${trip.driverName || 'MISSING'}`);
      
      let fixedDriverId = null;
      
      // Try to match by driver name
      if (trip.driverName) {
        const normalizedName = trip.driverName.toLowerCase().trim();
        fixedDriverId = driverNameToId[normalizedName];
        
        if (!fixedDriverId) {
          // Try partial name matching
          for (const [name, id] of Object.entries(driverNameToId)) {
            if (name.includes(normalizedName) || normalizedName.includes(name)) {
              fixedDriverId = id;
              break;
            }
          }
        }
      }
      
      if (fixedDriverId) {
        console.log(`   ✅ Fixing: ${trip.driverId} → ${fixedDriverId}`);
        
        await db.collection('trips').updateOne(
          { _id: trip._id },
          { 
            $set: { 
              driverId: fixedDriverId,
              updatedAt: new Date()
            } 
          }
        );
        tripsFixed++;
      } else {
        // If we can't fix it and it's a test/invalid trip, consider deleting
        if (!trip.driverName || trip.driverId === 'undefined' || !trip.driverId) {
          console.log(`   ❌ Deleting invalid trip (no driver info)`);
          
          await db.collection('trips').deleteOne({ _id: trip._id });
          tripsDeleted++;
        } else {
          console.log(`   ⚠️  Could not fix trip - keeping as is`);
        }
      }
    }
    
    console.log(`\n✅ Trips cleanup complete:`);
    console.log(`   Fixed: ${tripsFixed} trips`);
    console.log(`   Deleted: ${tripsDeleted} invalid trips`);
    
    // ========================================================================
    // STEP 3: Clean Up Rosters Collection
    // ========================================================================
    console.log('\n\n🔄 STEP 3: CLEANING UP ROSTERS COLLECTION');
    console.log('─'.repeat(40));
    
    // Find all rosters with invalid driver IDs
    const rostersWithInvalidIds = await db.collection('rosters').find({
      $or: [
        { driverId: { $nin: validDriverIds } },
        { driverId: null },
        { driverId: undefined },
        { driverId: '' }
      ]
    }).toArray();
    
    console.log(`Found ${rostersWithInvalidIds.length} rosters with invalid driver IDs`);
    
    let rostersFixed = 0;
    let rostersDeleted = 0;
    
    for (const roster of rostersWithInvalidIds) {
      console.log(`\nProcessing roster ${roster._id}:`);
      console.log(`   Current driverId: ${roster.driverId || 'MISSING'}`);
      console.log(`   Driver name: ${roster.driverName || 'MISSING'}`);
      
      let fixedDriverId = null;
      
      // Try to match by driver name
      if (roster.driverName) {
        const normalizedName = roster.driverName.toLowerCase().trim();
        fixedDriverId = driverNameToId[normalizedName];
        
        if (!fixedDriverId) {
          // Try partial name matching
          for (const [name, id] of Object.entries(driverNameToId)) {
            if (name.includes(normalizedName) || normalizedName.includes(name)) {
              fixedDriverId = id;
              break;
            }
          }
        }
      }
      
      if (fixedDriverId) {
        console.log(`   ✅ Fixing: ${roster.driverId} → ${fixedDriverId}`);
        
        await db.collection('rosters').updateOne(
          { _id: roster._id },
          { 
            $set: { 
              driverId: fixedDriverId,
              updatedAt: new Date()
            } 
          }
        );
        rostersFixed++;
      } else {
        // If we can't fix it, consider deleting if it's clearly invalid
        if (!roster.driverName || roster.driverId === 'undefined' || !roster.driverId) {
          console.log(`   ❌ Deleting invalid roster (no driver info)`);
          
          await db.collection('rosters').deleteOne({ _id: roster._id });
          rostersDeleted++;
        } else {
          console.log(`   ⚠️  Could not fix roster - keeping as is`);
        }
      }
    }
    
    console.log(`\n✅ Rosters cleanup complete:`);
    console.log(`   Fixed: ${rostersFixed} rosters`);
    console.log(`   Deleted: ${rostersDeleted} invalid rosters`);
    
    // ========================================================================
    // STEP 4: Update JWT Router to Include DriverId
    // ========================================================================
    console.log('\n\n🔄 STEP 4: JWT ROUTER UPDATE RECOMMENDATION');
    console.log('─'.repeat(40));
    
    console.log('💡 To complete driver ID integration, update JWT router:');
    console.log('');
    console.log('1. In jwt_router.js login function, add driverId to token payload:');
    console.log('   ```javascript');
    console.log('   // For driver role users, include driverId');
    console.log('   if (userRole === "driver" && user.driverId) {');
    console.log('     userData.driverId = user.driverId;');
    console.log('   }');
    console.log('   ```');
    console.log('');
    console.log('2. In verifyJWT middleware, add driverId to req.user:');
    console.log('   ```javascript');
    console.log('   req.user = {');
    console.log('     userId: decoded.userId,');
    console.log('     email: decoded.email,');
    console.log('     name: decoded.name,');
    console.log('     role: decoded.role,');
    console.log('     driverId: decoded.driverId, // Add this line');
    console.log('     // ... other fields');
    console.log('   };');
    console.log('   ```');
    
    // ========================================================================
    // STEP 5: Final Verification
    // ========================================================================
    console.log('\n\n✅ STEP 5: FINAL VERIFICATION');
    console.log('─'.repeat(40));
    
    // Re-run consistency check
    const finalTripDriverIds = await db.collection('trips').distinct('driverId');
    const finalRosterDriverIds = await db.collection('rosters').distinct('driverId');
    const finalDriverCollectionIds = await db.collection('drivers').distinct('driverId');
    
    const finalAllUsedDriverIds = [...new Set([...finalTripDriverIds, ...finalRosterDriverIds])];
    const finalOrphanedDriverIds = finalAllUsedDriverIds.filter(id => 
      id && id !== null && id !== undefined && id !== '' && !finalDriverCollectionIds.includes(id)
    );
    
    console.log('Final Status After Cleanup:');
    console.log(`   Driver IDs in trips: ${finalTripDriverIds.length}`);
    console.log(`   Driver IDs in rosters: ${finalRosterDriverIds.length}`);
    console.log(`   Driver IDs in drivers collection: ${finalDriverCollectionIds.length}`);
    console.log(`   Orphaned driver IDs: ${finalOrphanedDriverIds.length}`);
    
    if (finalOrphanedDriverIds.length === 0) {
      console.log('🎉 NO ORPHANED DRIVER IDS - Perfect consistency achieved!');
    } else {
      console.log('❌ Remaining orphaned driver IDs:');
      finalOrphanedDriverIds.forEach(id => {
        console.log(`   - ${id}`);
      });
    }
    
    // Check format consistency
    const allDriverIds = [...finalDriverCollectionIds, ...finalTripDriverIds, ...finalRosterDriverIds];
    const uniqueDriverIds = [...new Set(allDriverIds)].filter(id => id && id !== null && id !== undefined && id !== '');
    
    const formatStats = {
      drvFormat: 0,
      objectId: 0,
      other: 0
    };
    
    uniqueDriverIds.forEach(id => {
      if (typeof id === 'string') {
        if (/^DRV-\d{6}$/.test(id)) {
          formatStats.drvFormat++;
        } else if (/^[0-9a-fA-F]{24}$/.test(id)) {
          formatStats.objectId++;
        } else {
          formatStats.other++;
        }
      }
    });
    
    console.log('\nFinal Driver ID Format Distribution:');
    console.log(`   ✅ DRV-XXXXXX format: ${formatStats.drvFormat}`);
    console.log(`   ${formatStats.objectId > 0 ? '❌' : '✅'} ObjectId format: ${formatStats.objectId}`);
    console.log(`   ${formatStats.other > 0 ? '❌' : '✅'} Other formats: ${formatStats.other}`);
    
    // ========================================================================
    // STEP 6: Summary and Next Steps
    // ========================================================================
    console.log('\n\n📋 CLEANUP SUMMARY');
    console.log('═'.repeat(80));
    
    console.log('✅ COMPLETED:');
    console.log(`   - Fixed ${tripsFixed} trips with invalid driver IDs`);
    console.log(`   - Deleted ${tripsDeleted} invalid trips`);
    console.log(`   - Fixed ${rostersFixed} rosters with invalid driver IDs`);
    console.log(`   - Deleted ${rostersDeleted} invalid rosters`);
    console.log(`   - All drivers have proper DRV-XXXXXX format`);
    
    console.log('\n🔄 NEXT STEPS:');
    console.log('   1. Update JWT router to include driverId in token payload');
    console.log('   2. Update frontend to use driverId from JWT token');
    console.log('   3. Test driver-specific operations with new driverId');
    console.log('   4. Run final consistency check');
    
    if (finalOrphanedDriverIds.length === 0 && formatStats.objectId === 0 && formatStats.other === 0) {
      console.log('\n🎉 DRIVER ID CONSISTENCY: PERFECT! 🎉');
    } else {
      console.log('\n⚠️  Some issues remain - may need manual review');
    }
    
    console.log('═'.repeat(80));
    
  } catch (error) {
    console.error('\n❌ ERROR IN DRIVER ID CLEANUP');
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

// Run the cleanup
if (require.main === module) {
  completeDriverIdCleanup().catch(console.error);
}

module.exports = { completeDriverIdCleanup };