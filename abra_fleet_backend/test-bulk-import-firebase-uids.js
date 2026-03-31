const { MongoClient } = require('mongodb');

/**
 * Test script to verify Firebase UIDs are being created during bulk import
 */

async function testBulkImportFirebaseUids() {
  let client;
  
  try {
    // Connect to MongoDB
    console.log('🔌 Connecting to MongoDB...');
    const mongoUri = process.env.MONGODB_URI || 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';
    client = new MongoClient(mongoUri);
    await client.connect();
    
    const db = client.db();
    console.log('✅ Connected to MongoDB');
    
    console.log('\n🔍 ========== BULK IMPORT FIREBASE UID ANALYSIS ==========');
    
    // Check users created via roster import
    const bulkImportUsers = await db.collection('users').find({
      createdVia: 'roster_import'
    }).toArray();
    
    console.log(`\n📊 Users created via bulk import: ${bulkImportUsers.length}`);
    
    if (bulkImportUsers.length === 0) {
      console.log('ℹ️ No users found with createdVia: "roster_import"');
      console.log('   This might mean:');
      console.log('   1. No bulk imports have been done yet');
      console.log('   2. The createdVia field was added recently');
      console.log('\n🔍 Checking all users instead...');
      
      // Check all users
      const allUsers = await db.collection('users').find({}).toArray();
      console.log(`\n📊 Total users in database: ${allUsers.length}`);
      
      const usersWithFirebaseUid = allUsers.filter(user => user.firebaseUid);
      const usersWithoutFirebaseUid = allUsers.filter(user => !user.firebaseUid);
      
      console.log(`✅ Users WITH Firebase UID: ${usersWithFirebaseUid.length}`);
      console.log(`❌ Users WITHOUT Firebase UID: ${usersWithoutFirebaseUid.length}`);
      
      if (usersWithoutFirebaseUid.length > 0) {
        console.log('\n❌ Users missing Firebase UID:');
        usersWithoutFirebaseUid.slice(0, 10).forEach((user, index) => {
          console.log(`   ${index + 1}. ${user.name || 'Unknown'} (${user.email || 'No email'})`);
        });
        
        if (usersWithoutFirebaseUid.length > 10) {
          console.log(`   ... and ${usersWithoutFirebaseUid.length - 10} more`);
        }
      }
      
    } else {
      // Analyze bulk import users
      const withFirebaseUid = bulkImportUsers.filter(user => user.firebaseUid);
      const withoutFirebaseUid = bulkImportUsers.filter(user => !user.firebaseUid);
      
      console.log(`✅ Bulk import users WITH Firebase UID: ${withFirebaseUid.length}`);
      console.log(`❌ Bulk import users WITHOUT Firebase UID: ${withoutFirebaseUid.length}`);
      
      if (withFirebaseUid.length > 0) {
        console.log('\n✅ Sample users WITH Firebase UID:');
        withFirebaseUid.slice(0, 5).forEach((user, index) => {
          console.log(`   ${index + 1}. ${user.name} (${user.email})`);
          console.log(`      Firebase UID: ${user.firebaseUid}`);
          console.log(`      Created: ${user.createdAt}`);
        });
      }
      
      if (withoutFirebaseUid.length > 0) {
        console.log('\n❌ Bulk import users WITHOUT Firebase UID:');
        withoutFirebaseUid.forEach((user, index) => {
          console.log(`   ${index + 1}. ${user.name} (${user.email})`);
          console.log(`      Created: ${user.createdAt}`);
        });
      }
    }
    
    // Check rosters and their customer links
    console.log('\n🔍 ========== ROSTER CUSTOMER LINKS ==========');
    
    const rosters = await db.collection('rosters').find({
      createdByAdmin: { $exists: true }
    }).limit(10).toArray();
    
    console.log(`\n📊 Sample rosters created by admin: ${rosters.length}`);
    
    for (const roster of rosters) {
      console.log(`\n📋 Roster: ${roster.customerName} (${roster.customerEmail})`);
      console.log(`   Customer Firebase UID: ${roster.customerFirebaseUid || 'MISSING'}`);
      console.log(`   Created by: ${roster.createdByAdmin}`);
      console.log(`   Organization: ${roster.organizationName}`);
      
      // Check if corresponding user exists
      if (roster.customerEmail) {
        const correspondingUser = await db.collection('users').findOne({
          email: roster.customerEmail.toLowerCase()
        });
        
        if (correspondingUser) {
          console.log(`   ✅ User found in database`);
          console.log(`   User Firebase UID: ${correspondingUser.firebaseUid || 'MISSING'}`);
          
          if (roster.customerFirebaseUid && correspondingUser.firebaseUid) {
            if (roster.customerFirebaseUid === correspondingUser.firebaseUid) {
              console.log(`   ✅ Firebase UIDs match perfectly`);
            } else {
              console.log(`   ❌ Firebase UID mismatch!`);
            }
          }
        } else {
          console.log(`   ❌ No corresponding user found`);
        }
      }
    }
    
    // Summary
    console.log('\n📊 ========== SUMMARY ==========');
    
    const totalUsers = await db.collection('users').countDocuments();
    const usersWithUid = await db.collection('users').countDocuments({ firebaseUid: { $exists: true, $ne: null } });
    const usersWithoutUid = totalUsers - usersWithUid;
    
    console.log(`Total users: ${totalUsers}`);
    console.log(`Users with Firebase UID: ${usersWithUid} (${((usersWithUid/totalUsers)*100).toFixed(1)}%)`);
    console.log(`Users without Firebase UID: ${usersWithoutUid} (${((usersWithoutUid/totalUsers)*100).toFixed(1)}%)`);
    
    if (usersWithoutUid === 0) {
      console.log('\n🎉 EXCELLENT: All users have Firebase UIDs!');
      console.log('   Your bulk import system is working perfectly.');
    } else if (usersWithoutUid < totalUsers * 0.1) {
      console.log('\n✅ GOOD: Most users have Firebase UIDs.');
      console.log('   Only a small percentage are missing UIDs (likely historical data).');
      console.log('   Consider running the fix-all-missing-firebase-uids.js script.');
    } else {
      console.log('\n⚠️ ATTENTION: Significant number of users missing Firebase UIDs.');
      console.log('   This suggests the bulk import system may have issues.');
      console.log('   Recommend running fix-all-missing-firebase-uids.js script.');
    }
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    console.error(error.stack);
  } finally {
    if (client) {
      await client.close();
      console.log('🔌 MongoDB connection closed');
    }
  }
}

// Run the test
if (require.main === module) {
  testBulkImportFirebaseUids()
    .then(() => {
      console.log('\n✅ Test completed!');
      process.exit(0);
    })
    .catch((error) => {
      console.error('\n💥 Test failed:', error.message);
      process.exit(1);
    });
}

module.exports = { testBulkImportFirebaseUids };