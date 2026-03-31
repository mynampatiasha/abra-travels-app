// Script to check and fix user roles
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function checkUserRoles() {
  let client;
  
  try {
    console.log('🔍 Connecting to MongoDB...');
    client = new MongoClient(process.env.MONGODB_URI);
    await client.connect();
    
    const db = client.db('abra_fleet');
    
    console.log('👥 Checking all users and their roles...');
    
    // Get all users
    const users = await db.collection('users').find({}).toArray();
    
    console.log(`📊 Found ${users.length} users in database:`);
    console.log('='.repeat(80));
    
    users.forEach((user, index) => {
      console.log(`${index + 1}. Email: ${user.email}`);
      console.log(`   Name: ${user.name || 'N/A'}`);
      console.log(`   Role: ${user.role || 'NO ROLE ASSIGNED'}`);
      console.log(`   Company: ${user.companyName || 'N/A'}`);
      console.log(`   Organization: ${user.organizationName || 'N/A'}`);
      console.log(`   Firebase UID: ${user.firebaseUid || 'N/A'}`);
      console.log(`   Created: ${user.createdAt || 'N/A'}`);
      console.log('-'.repeat(50));
    });
    
    // Check specifically for admin users
    console.log('\n🔍 Admin users:');
    const adminUsers = users.filter(user => 
      user.email && (
        user.email.includes('admin') || 
        user.role === 'admin' || 
        user.role === 'manager'
      )
    );
    
    adminUsers.forEach(admin => {
      console.log(`👑 Admin: ${admin.email} (Role: ${admin.role || 'UNDEFINED'})`);
    });
    
    // Check for users with customer role
    console.log('\n👤 Customer users:');
    const customerUsers = users.filter(user => user.role === 'customer');
    console.log(`Found ${customerUsers.length} users with 'customer' role:`);
    
    customerUsers.forEach(customer => {
      console.log(`   📧 ${customer.email} (${customer.name || 'No name'})`);
    });
    
    // Check for users with no role
    console.log('\n❓ Users with no role assigned:');
    const noRoleUsers = users.filter(user => !user.role);
    console.log(`Found ${noRoleUsers.length} users with no role:`);
    
    noRoleUsers.forEach(user => {
      console.log(`   ❌ ${user.email} (${user.name || 'No name'})`);
    });
    
    // Fix ALL customers without organization
    console.log('\n🔧 Fixing customers without organization...');
    
    const customersWithoutOrg = users.filter(user => 
      user.role === 'customer' && 
      (!user.organizationName || !user.companyName)
    );
    
    console.log(`Found ${customersWithoutOrg.length} customers without organization`);
    
    for (const customer of customersWithoutOrg) {
      console.log(`\n📧 Fixing: ${customer.email}`);
      
      // Extract domain from email
      const emailDomain = customer.email.split('@')[1];
      let orgName = customer.companyName || 'Unknown Organization';
      
      // Map common domains to organization names
      if (emailDomain === 'abrafleet.com') {
        orgName = 'Abra Group';
      } else if (emailDomain === 'infosys.com') {
        orgName = 'Infosys Limited';
      } else if (emailDomain === 'cognizant.com') {
        orgName = 'Cognizant';
      } else if (emailDomain === 'tcs.com') {
        orgName = 'TCS';
      } else if (customer.companyName) {
        orgName = customer.companyName;
      }
      
      console.log(`   Setting organization to: ${orgName}`);
      
      const updateResult = await db.collection('users').updateOne(
        { email: customer.email },
        { 
          $set: { 
            companyName: orgName,
            organizationName: orgName
          } 
        }
      );
      
      console.log(`   ✅ Updated ${updateResult.modifiedCount} document(s)`);
    }
    
    console.log(`\n✅ Fixed ${customersWithoutOrg.length} customers`);
    
  } catch (error) {
    console.error('❌ Error checking user roles:', error);
  } finally {
    if (client) {
      await client.close();
      console.log('✅ Database connection closed');
    }
  }
}

checkUserRoles();

// Also sync customer counts to Firebase Realtime Database
async function syncCustomerCounts() {
  const admin = require('firebase-admin');
  
  // Initialize Firebase if not already done
  if (!admin.apps.length) {
    const serviceAccount = require('./serviceAccountKey.json.json');
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      databaseURL: `https://${serviceAccount.project_id}-default-rtdb.firebaseio.com`
    });
  }
  
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('\n🔄 Syncing customer counts to Firebase...');
    
    // Get all clients from Firebase Realtime Database
    const clientsRef = admin.database().ref('clients');
    const clientsSnapshot = await clientsRef.once('value');
    
    if (!clientsSnapshot.exists()) {
      console.log('No clients found in Firebase');
      return;
    }
    
    const clients = clientsSnapshot.val();
    
    // Get all customers from MongoDB
    const mongoCustomers = await db.collection('users')
      .find({ role: 'customer' })
      .toArray();
    
    // Get all customers from Firestore
    const firestoreCustomers = await admin.firestore().collection('users')
      .where('role', '==', 'customer')
      .get();
    
    // Combine customers from both databases (deduplicate by email)
    const allCustomersMap = new Map();
    
    // Add MongoDB customers
    mongoCustomers.forEach(customer => {
      if (customer.email) {
        allCustomersMap.set(customer.email.toLowerCase(), {
          email: customer.email,
          companyName: customer.companyName || customer.organizationName || '',
          source: 'mongodb'
        });
      }
    });
    
    // Add Firestore customers (don't overwrite if already in MongoDB)
    firestoreCustomers.forEach(doc => {
      const data = doc.data();
      if (data.email && !allCustomersMap.has(data.email.toLowerCase())) {
        allCustomersMap.set(data.email.toLowerCase(), {
          email: data.email,
          companyName: data.companyName || data.organizationName || '',
          source: 'firestore'
        });
      }
    });
    
    console.log(`📊 Total customers in MongoDB: ${mongoCustomers.length}`);
    console.log(`📊 Total customers in Firestore: ${firestoreCustomers.size}`);
    console.log(`📊 Total unique customers: ${allCustomersMap.size}`);
    
    const updates = {};
    
    // For each client, count matching customers
    for (const [clientId, clientData] of Object.entries(clients)) {
      const clientEmail = clientData.email || '';
      const clientOrg = clientData.organizationName || clientData.companyName || '';
      const clientDomain = clientEmail.split('@')[1];
      
      let customerCount = 0;
      
      for (const customer of allCustomersMap.values()) {
        const customerDomain = customer.email.split('@')[1];
        const customerOrg = customer.companyName;
        
        if (customerDomain === clientDomain || 
            (clientOrg && customerOrg && customerOrg.toLowerCase() === clientOrg.toLowerCase())) {
          customerCount++;
        }
      }
      
      console.log(`   ${clientData.name} (${clientDomain}): ${customerCount} customers`);
      updates[`${clientId}/totalCustomers`] = customerCount;
    }
    
    // Apply updates
    if (Object.keys(updates).length > 0) {
      await clientsRef.update(updates);
      console.log('✅ Customer counts synced to Firebase!');
    }
    
  } catch (error) {
    console.error('❌ Error syncing:', error);
  } finally {
    await client.close();
  }
}

// Run sync after checking roles
setTimeout(() => {
  syncCustomerCounts().then(() => process.exit(0));
}, 1000);