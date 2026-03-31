// Check if customer and admin organizations match for address change notifications
// Run: node check-address-change-admin-match.js

require('dotenv').config();
const { MongoClient } = require('mongodb');

async function checkAdminMatch() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('\n' + '='.repeat(80));
    console.log('🔍 CHECKING ADMIN-CUSTOMER ORGANIZATION MATCH');
    console.log('='.repeat(80) + '\n');

    // 1. Find the customer who submitted the address change
    console.log('1️⃣ Finding customer who submitted address change...');
    const latestRequest = await db.collection('address_change_requests')
      .findOne({}, { sort: { createdAt: -1 } });

    if (!latestRequest) {
      console.log('❌ No address change requests found');
      console.log('   Submit an address change request first');
      return;
    }

    console.log(`✅ Latest request found:`);
    console.log(`   Request ID: ${latestRequest._id}`);
    console.log(`   Customer ID: ${latestRequest.customerId}`);
    console.log(`   Customer Name: ${latestRequest.customerName}`);
    console.log(`   Organization: ${latestRequest.organizationName || 'NONE'}`);
    console.log(`   Status: ${latestRequest.status}`);
    console.log(`   Created: ${latestRequest.createdAt.toISOString()}`);

    // 2. Find the customer in users collection
    console.log('\n2️⃣ Finding customer in users collection...');
    const customer = await db.collection('users').findOne({
      firebaseUid: latestRequest.customerId,
      role: 'customer'
    });

    if (!customer) {
      console.log('❌ Customer not found in users collection');
      return;
    }

    const customerOrg = customer.organizationName || customer.companyName || '';
    console.log(`✅ Customer found:`);
    console.log(`   Name: ${customer.name || customer.email}`);
    console.log(`   Email: ${customer.email}`);
    console.log(`   Organization Name: ${customer.organizationName || 'NOT SET'}`);
    console.log(`   Company Name: ${customer.companyName || 'NOT SET'}`);
    console.log(`   Using: ${customerOrg || 'NONE'}`);

    // 3. Find all admins
    console.log('\n3️⃣ Finding ALL admins in database...');
    const allAdmins = await db.collection('users').find({
      role: { $in: ['admin', 'client'] }
    }).toArray();

    console.log(`✅ Found ${allAdmins.length} total admin(s):`);
    allAdmins.forEach((admin, index) => {
      const adminOrg = admin.organizationName || admin.companyName || '';
      const matches = customerOrg && adminOrg && 
                     (adminOrg.toLowerCase() === customerOrg.toLowerCase());
      
      console.log(`\n   ${index + 1}. ${admin.name || admin.email}`);
      console.log(`      Role: ${admin.role}`);
      console.log(`      Email: ${admin.email}`);
      console.log(`      Organization Name: ${admin.organizationName || 'NOT SET'}`);
      console.log(`      Company Name: ${admin.companyName || 'NOT SET'}`);
      console.log(`      Using: ${adminOrg || 'NONE'}`);
      console.log(`      Match: ${matches ? '✅ YES' : '❌ NO'}`);
    });

    // 4. Find matching admins (exactly as the API does)
    console.log('\n4️⃣ Finding admins with MATCHING organization...');
    
    if (!customerOrg) {
      console.log('❌ Customer has NO organization set');
      console.log('   Cannot match with any admin');
      console.log('\n💡 FIX: Update customer with organization:');
      console.log(`   db.users.updateOne(`);
      console.log(`     { firebaseUid: "${customer.firebaseUid}" },`);
      console.log(`     { $set: { organizationName: "Your Organization Name" } }`);
      console.log(`   )`);
      return;
    }

    const matchingAdmins = await db.collection('users').find({
      role: { $in: ['admin', 'client'] },
      $or: [
        { companyName: customerOrg },
        { organizationName: customerOrg }
      ]
    }).toArray();

    if (matchingAdmins.length === 0) {
      console.log('❌ NO admins found with matching organization');
      console.log(`   Customer organization: "${customerOrg}"`);
      console.log('\n💡 FIX OPTIONS:');
      console.log('\n   Option 1: Update an existing admin:');
      if (allAdmins.length > 0) {
        console.log(`   db.users.updateOne(`);
        console.log(`     { firebaseUid: "${allAdmins[0].firebaseUid}" },`);
        console.log(`     { $set: { organizationName: "${customerOrg}" } }`);
        console.log(`   )`);
      }
      console.log('\n   Option 2: Create a new admin:');
      console.log(`   db.users.insertOne({`);
      console.log(`     firebaseUid: "admin-uid-here",`);
      console.log(`     role: "admin",`);
      console.log(`     name: "Admin User",`);
      console.log(`     email: "admin@example.com",`);
      console.log(`     organizationName: "${customerOrg}",`);
      console.log(`     createdAt: new Date()`);
      console.log(`   })`);
    } else {
      console.log(`✅ Found ${matchingAdmins.length} matching admin(s):`);
      matchingAdmins.forEach((admin, index) => {
        console.log(`\n   ${index + 1}. ${admin.name || admin.email}`);
        console.log(`      Role: ${admin.role}`);
        console.log(`      Email: ${admin.email}`);
        console.log(`      Firebase UID: ${admin.firebaseUid}`);
        console.log(`      Organization: ${admin.organizationName || admin.companyName}`);
      });

      // 5. Check if notifications were created
      console.log('\n5️⃣ Checking if notifications were created...');
      
      for (const admin of matchingAdmins) {
        const notification = await db.collection('notifications').findOne({
          userId: admin.firebaseUid,
          type: 'address_change_request',
          'data.requestId': latestRequest._id.toString()
        });

        if (notification) {
          console.log(`✅ Notification EXISTS for ${admin.name || admin.email}`);
          console.log(`   ID: ${notification._id}`);
          console.log(`   Read: ${notification.read}`);
          console.log(`   Created: ${notification.createdAt.toISOString()}`);
        } else {
          console.log(`❌ Notification NOT FOUND for ${admin.name || admin.email}`);
          console.log(`   This admin should have received a notification but didn't`);
        }
      }
    }

    // Summary
    console.log('\n' + '='.repeat(80));
    console.log('📊 SUMMARY');
    console.log('='.repeat(80));
    console.log(`Customer Organization: ${customerOrg || 'NONE'}`);
    console.log(`Total Admins: ${allAdmins.length}`);
    console.log(`Matching Admins: ${matchingAdmins.length}`);
    console.log(`Notifications Expected: ${matchingAdmins.length}`);
    
    if (matchingAdmins.length === 0) {
      console.log('\n❌ PROBLEM: No admins with matching organization');
      console.log('   This is why admin didn\'t receive notification');
    } else {
      console.log('\n✅ Admins with matching organization exist');
      console.log('   They should receive notifications');
    }
    console.log('='.repeat(80) + '\n');

  } catch (error) {
    console.error('❌ Error:', error);
    console.error(error.stack);
  } finally {
    await client.close();
  }
}

checkAdminMatch();
