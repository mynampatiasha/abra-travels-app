// Script to clean up incomplete rosters and trips with missing details
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function cleanupIncompleteRosters() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    
    // Find and remove rosters with missing critical details
    console.log('\n🔍 Finding incomplete rosters...');
    
    const incompleteRosters = await db.collection('rosters').find({
      $or: [
        // Missing dates
        { 'dateRange.from': { $in: [null, '', 'N/A'] } },
        { 'dateRange.to': { $in: [null, '', 'N/A'] } },
        { startDate: { $in: [null, '', 'N/A'] } },
        { endDate: { $in: [null, '', 'N/A'] } },
        { fromDate: { $in: [null, '', 'N/A'] } },
        { toDate: { $in: [null, '', 'N/A'] } },
        
        // Missing times
        { 'timeRange.from': { $in: [null, '', 'N/A'] } },
        { 'timeRange.to': { $in: [null, '', 'N/A'] } },
        { startTime: { $in: [null, '', 'N/A'] } },
        { endTime: { $in: [null, '', 'N/A'] } },
        
        // Missing office location
        { officeLocation: { $in: [null, '', 'N/A'] } },
        
        // Missing roster type
        { rosterType: { $in: [null, '', 'N/A'] } }
      ]
    }).toArray();
    
    console.log(`📊 Found ${incompleteRosters.length} incomplete rosters`);
    
    if (incompleteRosters.length > 0) {
      console.log('\n📋 Incomplete rosters details:');
      incompleteRosters.forEach((roster, index) => {
        console.log(`${index + 1}. Roster ID: ${roster.rosterId || roster._id}`);
        console.log(`   User: ${roster.userId}`);
        console.log(`   From Date: ${roster.dateRange?.from || roster.startDate || roster.fromDate || 'MISSING'}`);
        console.log(`   To Date: ${roster.dateRange?.to || roster.endDate || roster.toDate || 'MISSING'}`);
        console.log(`   Office: ${roster.officeLocation || 'MISSING'}`);
        console.log(`   Type: ${roster.rosterType || 'MISSING'}`);
        console.log('   ---');
      });
      
      // Get roster IDs for trip cleanup
      const rosterIds = incompleteRosters.map(r => r.rosterId || r._id.toString());
      
      // Remove associated trips first
      console.log('\n🗑️ Removing associated trips...');
      const tripDeleteResult = await db.collection('trips').deleteMany({
        rosterId: { $in: rosterIds }
      });
      console.log(`✅ Deleted ${tripDeleteResult.deletedCount} associated trips`);
      
      // Remove incomplete rosters
      console.log('\n🗑️ Removing incomplete rosters...');
      const rosterDeleteResult = await db.collection('rosters').deleteMany({
        _id: { $in: incompleteRosters.map(r => r._id) }
      });
      console.log(`✅ Deleted ${rosterDeleteResult.deletedCount} incomplete rosters`);
    }
    
    // Find and remove rosters with no associated trips
    console.log('\n🔍 Finding rosters with no daily trips...');
    
    const allRosters = await db.collection('rosters').find({}).toArray();
    const rostersWithNoTrips = [];
    
    for (const roster of allRosters) {
      const rosterId = roster.rosterId || roster._id.toString();
      const tripCount = await db.collection('trips').countDocuments({
        rosterId: rosterId
      });
      
      if (tripCount === 0) {
        rostersWithNoTrips.push(roster);
      }
    }
    
    console.log(`📊 Found ${rostersWithNoTrips.length} rosters with no daily trips`);
    
    if (rostersWithNoTrips.length > 0) {
      console.log('\n📋 Rosters with no trips:');
      rostersWithNoTrips.forEach((roster, index) => {
        console.log(`${index + 1}. Roster ID: ${roster.rosterId || roster._id}`);
        console.log(`   User: ${roster.userId}`);
        console.log(`   Type: ${roster.rosterType || 'N/A'}`);
        console.log(`   Status: ${roster.status || 'N/A'}`);
        console.log('   ---');
      });
      
      // Remove rosters with no trips
      console.log('\n🗑️ Removing rosters with no daily trips...');
      const emptyRosterDeleteResult = await db.collection('rosters').deleteMany({
        _id: { $in: rostersWithNoTrips.map(r => r._id) }
      });
      console.log(`✅ Deleted ${emptyRosterDeleteResult.deletedCount} empty rosters`);
    }
    
    // Summary
    console.log('\n📊 CLEANUP SUMMARY:');
    console.log(`✅ Removed ${incompleteRosters.length} incomplete rosters`);
    console.log(`✅ Removed ${rostersWithNoTrips.length} rosters with no trips`);
    console.log(`✅ Removed associated trips from incomplete rosters`);
    
    // Show remaining roster count
    const remainingRosters = await db.collection('rosters').countDocuments();
    const remainingTrips = await db.collection('trips').countDocuments();
    
    console.log(`\n📈 REMAINING DATA:`);
    console.log(`📋 Rosters: ${remainingRosters}`);
    console.log(`🚗 Trips: ${remainingTrips}`);
    
  } catch (error) {
    console.error('❌ Error during cleanup:', error);
  } finally {
    await client.close();
    console.log('\n🔌 Disconnected from MongoDB');
  }
}

// Run the cleanup
cleanupIncompleteRosters();