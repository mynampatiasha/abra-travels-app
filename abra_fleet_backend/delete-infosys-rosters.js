// Delete all Infosys rosters so they can be reassigned
const admin = require('firebase-admin');

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(require('./serviceAccountKey.json')),
    databaseURL: 'https://abra-fleet-default-rtdb.firebaseio.com'
  });
}

const db = admin.firestore();

async function deleteInfosysRosters() {
  try {
    console.log('🔍 Finding Infosys rosters to delete...\n');
    
    // Get all rosters with Infosys customers
    const rostersSnapshot = await db.collection('rosters').get();
    
    const infosysRosters = [];
    rostersSnapshot.forEach(doc => {
      const roster = doc.data();
      const email = roster.customerEmail || '';
      
      if (email.endsWith('@infosys.com')) {
        infosysRosters.push({
          id: doc.id,
          customerName: roster.customerName,
          customerEmail: email,
          vehicleNumber: roster.vehicleNumber,
          status: roster.status
        });
      }
    });
    
    console.log(`📊 Found ${infosysRosters.length} Infosys rosters\n`);
    
    if (infosysRosters.length === 0) {
      console.log('✅ No Infosys rosters to delete');
      process.exit(0);
      return;
    }
    
    // Display rosters to be deleted
    console.log('📋 Rosters to be deleted:');
    infosysRosters.forEach((roster, index) => {
      console.log(`   ${index + 1}. ${roster.customerName} (${roster.customerEmail})`);
      console.log(`      Vehicle: ${roster.vehicleNumber}, Status: ${roster.status}`);
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
    
    // Commit the batch delete
    await batch.commit();
    
    console.log(`\n✅ Successfully deleted ${deleteCount} Infosys rosters!`);
    console.log('\n📝 Next Steps:');
    console.log('   1. Refresh the Client Roster Management page');
    console.log('   2. Use bulk import or manual assignment to reassign these employees');
    console.log('   3. Dashboard counts will update automatically\n');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    process.exit(0);
  }
}

deleteInfosysRosters();
