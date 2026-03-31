// Delete specific Infosys roster (Neha Gupta and Vikram Singh)
const admin = require('firebase-admin');

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(require('./serviceAccountKey.json')),
    databaseURL: 'https://abra-fleet-default-rtdb.firebaseio.com'
  });
}

const db = admin.firestore();

async function deleteSpecificRoster() {
  try {
    console.log('🔍 Finding rosters for Neha Gupta and Vikram Singh...\n');
    
    // Target emails
    const targetEmails = [
      'neha.gupta@infosys.com',
      'vikram.singh@infosys.com'
    ];
    
    // Get all rosters
    const rostersSnapshot = await db.collection('rosters').get();
    
    const rostersToDelete = [];
    rostersSnapshot.forEach(doc => {
      const roster = doc.data();
      const email = roster.customerEmail?.toLowerCase() || '';
      
      if (targetEmails.includes(email)) {
        rostersToDelete.push({
          id: doc.id,
          customerName: roster.customerName,
          customerEmail: roster.customerEmail,
          vehicleNumber: roster.vehicleNumber,
          status: roster.status,
          driverName: roster.driverName
        });
      }
    });
    
    console.log(`📊 Found ${rostersToDelete.length} rosters to delete\n`);
    
    if (rostersToDelete.length === 0) {
      console.log('✅ No matching rosters found');
      process.exit(0);
      return;
    }
    
    // Display rosters to be deleted
    console.log('📋 Rosters to be deleted:');
    rostersToDelete.forEach((roster, index) => {
      console.log(`   ${index + 1}. ${roster.customerName} (${roster.customerEmail})`);
      console.log(`      Vehicle: ${roster.vehicleNumber || 'N/A'}`);
      console.log(`      Driver: ${roster.driverName || 'N/A'}`);
      console.log(`      Status: ${roster.status}`);
      console.log('');
    });
    
    console.log('⚠️  Deleting rosters...\n');
    
    // Delete rosters
    const batch = db.batch();
    
    for (const roster of rostersToDelete) {
      const docRef = db.collection('rosters').doc(roster.id);
      batch.delete(docRef);
      console.log(`   ✓ Queued for deletion: ${roster.customerName}`);
    }
    
    // Commit the batch delete
    await batch.commit();
    
    console.log(`\n✅ Successfully deleted ${rostersToDelete.length} rosters!`);
    console.log('\n📝 Next Steps:');
    console.log('   1. Refresh the Client Roster Management page');
    console.log('   2. The roster will disappear from Active Rosters');
    console.log('   3. You can now reassign Neha Gupta and Vikram Singh');
    console.log('   4. Dashboard counts will update automatically\n');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    process.exit(0);
  }
}

deleteSpecificRoster();
