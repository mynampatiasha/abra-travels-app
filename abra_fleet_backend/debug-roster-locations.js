// Debug script to check roster location data structure
const { MongoClient } = require('mongodb');

const MONGODB_URI = 'mongodb://localhost:27017';
const DB_NAME = 'abra_fleet_management';

async function debugRosterLocations() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db(DB_NAME);
    const rostersCollection = db.collection('rosters');
    
    // Get a few sample rosters
    const rosters = await rostersCollection.find({
      status: { $in: ['pending_assignment', 'pending', 'created'] }
    }).limit(5).toArray();
    
    console.log(`\n📊 Found ${rosters.length} sample rosters`);
    console.log('='*60);
    
    for (let i = 0; i < rosters.length; i++) {
      const roster = rosters[i];
      console.log(`\n🔍 Roster ${i + 1}:`);
      console.log(`   ID: ${roster._id}`);
      console.log(`   Customer: ${roster.customerName || 'Unknown'}`);
      console.log(`   Type: ${roster.rosterType || 'Unknown'}`);
      console.log(`   Office: ${roster.officeLocation || 'Unknown'}`);
      
      // Check location data structure
      console.log('\n📍 Location Data:');
      
      if (roster.loginPickupAddress) {
        console.log(`   loginPickupAddress: "${roster.loginPickupAddress}"`);
      }
      
      if (roster.loginPickupLocation) {
        console.log(`   loginPickupLocation:`, roster.loginPickupLocation);
      }
      
      if (roster.locations) {
        console.log(`   locations:`, JSON.stringify(roster.locations, null, 4));
      }
      
      if (roster.logoutDropAddress) {
        console.log(`   logoutDropAddress: "${roster.logoutDropAddress}"`);
      }
      
      if (roster.logoutDropLocation) {
        console.log(`   logoutDropLocation:`, roster.logoutDropLocation);
      }
      
      console.log('-'.repeat(60));
    }
    
    // Check if any rosters have coordinates
    const rostersWithCoords = await rostersCollection.find({
      $or: [
        { 'locations.pickup.coordinates': { $exists: true } },
        { 'loginPickupLocation': { $exists: true, $ne: null } },
        { 'logoutDropLocation': { $exists: true, $ne: null } }
      ]
    }).limit(3).toArray();
    
    console.log(`\n🎯 Found ${rostersWithCoords.length} rosters with coordinates:`);
    
    for (const roster of rostersWithCoords) {
      console.log(`\n✅ ${roster.customerName || 'Unknown Customer'}:`);
      
      if (roster.locations?.pickup?.coordinates) {
        const coords = roster.locations.pickup.coordinates;
        console.log(`   Pickup: ${coords.latitude}, ${coords.longitude}`);
        console.log(`   Address: ${roster.locations.pickup.address || 'N/A'}`);
      }
      
      if (roster.loginPickupLocation) {
        console.log(`   loginPickupLocation:`, roster.loginPickupLocation);
      }
      
      if (roster.locations?.drop?.coordinates) {
        const coords = roster.locations.drop.coordinates;
        console.log(`   Drop: ${coords.latitude}, ${coords.longitude}`);
        console.log(`   Address: ${roster.locations.drop.address || 'N/A'}`);
      }
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

debugRosterLocations();