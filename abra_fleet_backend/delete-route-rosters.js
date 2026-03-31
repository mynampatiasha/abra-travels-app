// Delete rosters for Infosys employees (Neha Gupta and Vikram Singh)
require('dotenv').config();
const { MongoClient } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI;

async function deleteRouteRosters() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB Atlas');
    
    const db = client.db('abra_fleet');
    
    console.log('\n🔍 Finding all Infosys rosters...\n');
    
    // Find all rosters with Infosys emails
    const rostersSnapshot = await db.collection('rosters').get();
    
    const infosysRosters = [];
    rostersSnapshot.forEach(doc => {
      const roster = doc.data();
      const email = roster.customerEmail || '';
      
      if (email.toLowerCase().includes('@infosys.com')) {
        infosysRosters.push({
          id: doc.id,
          ...roster
        });
      }
    });
    
    console.log(`📊 Found ${infosysRosters.length} Infosys rosters\n`);
    
    if (infosysRosters.length === 0) {
      console.log('✅ No Infosys rosters to delete');
      return;
    }
    
    // Display rosters
    console.log('📋 Rosters to be deleted:');
    infosysRosters.forEach((roster, index) => {
      console.log(`\n${index + 1}. ID: ${roster.id}`);
      console.log(`   Customer: ${roster.customerName} (${roster.customerEmail})`);
      console.log(`   Vehicle: ${roster.vehicleNumber || 'N/A'}`);
      console.log(`   Driver: ${roster.driverName || 'N/A'}`);
      console.log(`   Status: ${roster.status}`);
      console.log(`   Route: ${roster.routeName || 'N/A'}`);
    });
    
    console.log('\n⚠️  Deleting rosters...\n');
    
    // Delete all Infosys rosters
    const batch = db.batch();
    let deleteCount = 0;
    
    for (const roster of infosysRosters) {
      const docRef = db.collection('rosters').doc(roster.id);
      batch.delete(docRef);
      deleteCount++;
      console.log(`   ✓ Queued for deletion: ${roster.customerName}`);
    }
    
    await batch.commit();
    
    console.log(`\n✅ Successfully deleted ${deleteCount} rosters!`);
    console.log('\n📝 Next Steps:');
    console.log('   1. Refresh the Client Roster Management page');
    console.log('   2. The rosters will disappear from Active Rosters');
    console.log('   3. You can now reassign these employees');
    console.log('   4. Dashboard counts will update automatically\n');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    process.exit(0);
  }
}

deleteRouteRosters();
