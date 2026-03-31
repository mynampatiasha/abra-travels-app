// check-driver-id-consistency.js - Check Driver ID Consistency Between Collections
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI;

async function checkDriverIdConsistency() {
  console.log('\n🔍 CHECKING DRIVER ID CONSISTENCY');
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
    // STEP 1: Check Drivers Collection Structure
    // ========================================================================
    console.log('\n📂 STEP 1: CHECKING DRIVERS COLLECTION');
    console.log('─'.repeat(40));
    
    const drivers = await db.collection('drivers').find({}).limit(10).toArray();
    console.log(`Found ${drivers.length} sample drivers:`);
    
    const driverIdIssues = [];
    
    drivers.forEach((driver, index) => {
      console.log(`\n${index + 1}. Driver:`);
      console.log(`   _id: ${driver._id}`);
      console.log(`   driverId: ${driver.driverId || '❌ MISSING'}`);
      console.log(`   email: ${driver.personalInfo?.email || driver.email || '❌ MISSING'}`);
      console.log(`   name: ${driver.personalInfo?.firstName || driver.name || ''} ${driver.personalInfo?.lastName || ''}`);
      console.log(`   status: ${driver.status || 'N/A'}`);
      
      // Check for issues
      if (!driver.driverId) {
        driverIdIssues.push({
          _id: driver._id,
          email: driver.personalInfo?.email || driver.email,
          issue: 'Missing driverId field'
        });
      }
    });
    
    // ========================================================================
    // STEP 2: Check Trips Collection for Driver ID Usage
    // ========================================================================
    console.log('\n\n📂 STEP 2: CHECKING TRIPS COLLECTION');
    console.log('─'.repeat(40));
    
    const trips = await db.collection('trips').find({}).limit(5).toArray();
    console.log(`Found ${trips.length} sample trips:`);
    
    const tripDriverIdIssues = [];
    
    trips.forEach((trip, index) => {
      console.log(`\n${index + 1}. Trip:`);
      console.log(`   _id: ${trip._id}`);
      console.log(`   driverId: ${trip.driverId || '❌ MISSING'}`);
      console.log(`   driverName: ${trip.driverName || '❌ MISSING'}`);
      console.log(`   status: ${trip.status || 'N/A'}`);
      
      if (!trip.driverId) {
        tripDriverIdIssues.push({
          _id: trip._id,
          issue: 'Missing driverId field'
        });
      }
    });
    
    // ========================================================================
    // STEP 3: Check Rosters Collection for Driver ID Usage
    // ========================================================================
    console.log('\n\n📂 STEP 3: CHECKING ROSTERS COLLECTION');
    console.log('─'.repeat(40));
    
    const rosters = await db.collection('rosters').find({}).limit(5).toArray();
    console.log(`Found ${rosters.length} sample rosters:`);
    
    const rosterDriverIdIssues = [];
    
    rosters.forEach((roster, index) => {
      console.log(`\n${index + 1}. Roster:`);
      console.log(`   _id: ${roster._id}`);
      console.log(`   driverId: ${roster.driverId || '❌ MISSING'}`);
      console.log(`   driverName: ${roster.driverName || '❌ MISSING'}`);
      console.log(`   status: ${roster.status || 'N/A'}`);
      
      if (!roster.driverId) {
        rosterDriverIdIssues.push({
          _id: roster._id,
          issue: 'Missing driverId field'
        });
      }
    });
    
    // ========================================================================
    // STEP 4: Cross-Reference Driver IDs
    // ========================================================================
    console.log('\n\n🔗 STEP 4: CROSS-REFERENCING DRIVER IDS');
    console.log('─'.repeat(40));
    
    // Get all unique driver IDs from trips and rosters
    const tripDriverIds = await db.collection('trips').distinct('driverId');
    const rosterDriverIds = await db.collection('rosters').distinct('driverId');
    const driverCollectionIds = await db.collection('drivers').distinct('driverId');
    
    console.log(`Driver IDs in trips: ${tripDriverIds.length}`);
    console.log(`Driver IDs in rosters: ${rosterDriverIds.length}`);
    console.log(`Driver IDs in drivers collection: ${driverCollectionIds.length}`);
    
    // Find orphaned driver IDs
    const allUsedDriverIds = [...new Set([...tripDriverIds, ...rosterDriverIds])];
    const orphanedDriverIds = allUsedDriverIds.filter(id => 
      id && !driverCollectionIds.includes(id)
    );
    
    console.log(`\n🔍 Orphaned Driver IDs (used in trips/rosters but not in drivers collection):`);
    if (orphanedDriverIds.length === 0) {
      console.log('   ✅ No orphaned driver IDs found');
    } else {
      orphanedDriverIds.forEach(id => {
        console.log(`   ❌ ${id}`);
      });
    }
    
    // ========================================================================
    // STEP 5: Check Driver ID Format Consistency
    // ========================================================================
    console.log('\n\n📋 STEP 5: CHECKING DRIVER ID FORMATS');
    console.log('─'.repeat(40));
    
    const driverIdFormats = {
      email: 0,
      drvFormat: 0, // DRV-XXXXXX
      objectId: 0,
      other: 0
    };
    
    const allDriverIds = [...driverCollectionIds, ...tripDriverIds, ...rosterDriverIds];
    const uniqueDriverIds = [...new Set(allDriverIds)].filter(id => id);
    
    uniqueDriverIds.forEach(id => {
      if (typeof id === 'string') {
        if (id.includes('@')) {
          driverIdFormats.email++;
        } else if (/^DRV-\d{6}$/.test(id)) {
          driverIdFormats.drvFormat++;
        } else if (/^[0-9a-fA-F]{24}$/.test(id)) {
          driverIdFormats.objectId++;
        } else {
          driverIdFormats.other++;
        }
      }
    });
    
    console.log('Driver ID Format Distribution:');
    console.log(`   Email format: ${driverIdFormats.email}`);
    console.log(`   DRV-XXXXXX format: ${driverIdFormats.drvFormat}`);
    console.log(`   ObjectId format: ${driverIdFormats.objectId}`);
    console.log(`   Other formats: ${driverIdFormats.other}`);
    
    // ========================================================================
    // STEP 6: Summary and Recommendations
    // ========================================================================
    console.log('\n\n📊 SUMMARY AND RECOMMENDATIONS');
    console.log('═'.repeat(80));
    
    const totalIssues = driverIdIssues.length + tripDriverIdIssues.length + rosterDriverIdIssues.length + orphanedDriverIds.length;
    
    if (totalIssues === 0) {
      console.log('✅ NO ISSUES FOUND - Driver ID consistency is good!');
    } else {
      console.log(`❌ FOUND ${totalIssues} ISSUES:`);
      
      if (driverIdIssues.length > 0) {
        console.log(`   - ${driverIdIssues.length} drivers missing driverId field`);
      }
      
      if (tripDriverIdIssues.length > 0) {
        console.log(`   - ${tripDriverIdIssues.length} trips missing driverId field`);
      }
      
      if (rosterDriverIdIssues.length > 0) {
        console.log(`   - ${rosterDriverIdIssues.length} rosters missing driverId field`);
      }
      
      if (orphanedDriverIds.length > 0) {
        console.log(`   - ${orphanedDriverIds.length} orphaned driver IDs`);
      }
    }
    
    console.log('\n💡 RECOMMENDATIONS:');
    
    if (driverIdFormats.email > 0) {
      console.log('   1. Convert email-based driver IDs to proper DRV-XXXXXX format');
    }
    
    if (driverIdFormats.objectId > 0) {
      console.log('   2. Convert ObjectId-based driver IDs to proper DRV-XXXXXX format');
    }
    
    if (orphanedDriverIds.length > 0) {
      console.log('   3. Clean up orphaned driver IDs in trips and rosters collections');
    }
    
    if (driverIdIssues.length > 0) {
      console.log('   4. Add missing driverId fields to drivers collection');
    }
    
    console.log('   5. Ensure frontend uses the same driverId format as backend');
    console.log('   6. Update JWT authentication to include consistent driverId');
    
    console.log('\n═'.repeat(80));
    
  } catch (error) {
    console.error('\n❌ ERROR CHECKING DRIVER ID CONSISTENCY');
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

// Run the check
if (require.main === module) {
  checkDriverIdConsistency().catch(console.error);
}

module.exports = { checkDriverIdConsistency };