// check-user-storage-locations.js - Check where users are stored (Firebase Auth vs MongoDB)
const admin = require('firebase-admin');
const { MongoClient } = require('mongodb');
require('dotenv').config();

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'abrafleet-cec94',
  databaseURL: 'https://abrafleet-cec94-default-rtdb.firebaseio.com'
});

async function checkUserStorageLocations() {
  console.log('\n' + '='.repeat(80));
  console.log('🔍 CHECKING USER STORAGE LOCATIONS');
  console.log('='.repeat(80));
  
  let mongoClient;
  
  try {
    // Connect to MongoDB
    const mongoUri = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';
    mongoClient = new MongoClient(mongoUri);
    await mongoClient.connect();
    const db = mongoClient.db();
    
    console.log('✅ Connected to MongoDB\n');
    
    // ========== CHECK FIREBASE AUTH ==========
    console.log('📱 FIREBASE AUTHENTICATION:');
    console.log('-'.repeat(80));
    
    try {
      const listUsersResult = await admin.auth().listUsers(1000);
      const firebaseUsers = listUsersResult.users;
      
      console.log(`Total Firebase Auth Users: ${firebaseUsers.length}\n`);
      
      // Group by email domain to identify roles
      const usersByDomain = {};
      const usersByRole = {
        admin: [],
        customer: [],
        driver: [],
        client: [],
        unknown: []
      };
      
      firebaseUsers.forEach(user => {
        if (user.email) {
          const domain = user.email.split('@')[1] || 'no-domain';
          if (!usersByDomain[domain]) {
            usersByDomain[domain] = [];
          }
          usersByDomain[domain].push(user.email);
          
          // Try to guess role from email
          const email = user.email.toLowerCase();
          if (email.includes('admin')) {
            usersByRole.admin.push(user.email);
          } else if (email.includes('driver')) {
            usersByRole.driver.push(user.email);
          } else if (email.includes('client')) {
            usersByRole.client.push(user.email);
          } else {
            usersByRole.unknown.push(user.email);
          }
        }
      });
      
      console.log('📊 Firebase Users by Domain:');
      Object.keys(usersByDomain).forEach(domain => {
        console.log(`   ${domain}: ${usersByDomain[domain].length} users`);
        usersByDomain[domain].slice(0, 3).forEach(email => {
          console.log(`      - ${email}`);
        });
        if (usersByDomain[domain].length > 3) {
          console.log(`      ... and ${usersByDomain[domain].length - 3} more`);
        }
      });
      
      console.log('\n📊 Firebase Users by Guessed Role (from email):');
      Object.keys(usersByRole).forEach(role => {
        if (usersByRole[role].length > 0) {
          console.log(`   ${role}: ${usersByRole[role].length} users`);
          usersByRole[role].slice(0, 3).forEach(email => {
            console.log(`      - ${email}`);
          });
          if (usersByRole[role].length > 3) {
            console.log(`      ... and ${usersByRole[role].length - 3} more`);
          }
        }
      });
      
    } catch (fbError) {
      console.error('❌ Firebase Auth error:', fbError.message);
    }
    
    // ========== CHECK MONGODB USERS COLLECTION ==========
    console.log('\n\n💾 MONGODB "users" COLLECTION:');
    console.log('-'.repeat(80));
    
    const mongoUsers = await db.collection('users').find({}).toArray();
    console.log(`Total MongoDB Users: ${mongoUsers.length}\n`);
    
    // Group by role
    const mongoUsersByRole = {
      admin: [],
      customer: [],
      driver: [],
      client: [],
      unknown: []
    };
    
    mongoUsers.forEach(user => {
      const role = user.role || 'unknown';
      if (!mongoUsersByRole[role]) {
        mongoUsersByRole[role] = [];
      }
      mongoUsersByRole[role].push(user);
    });
    
    console.log('📊 MongoDB Users by Role:');
    Object.keys(mongoUsersByRole).forEach(role => {
      if (mongoUsersByRole[role].length > 0) {
        console.log(`\n   ${role.toUpperCase()}: ${mongoUsersByRole[role].length} users`);
        mongoUsersByRole[role].slice(0, 5).forEach(user => {
          console.log(`      - ${user.name || 'No Name'} (${user.email || 'No Email'})`);
          console.log(`        Firebase UID: ${user.firebaseUid || 'NOT LINKED'}`);
          console.log(`        Company: ${user.companyName || user.organizationName || 'N/A'}`);
        });
        if (mongoUsersByRole[role].length > 5) {
          console.log(`      ... and ${mongoUsersByRole[role].length - 5} more`);
        }
      }
    });
    
    // ========== CHECK MONGODB DRIVERS COLLECTION ==========
    console.log('\n\n🚗 MONGODB "drivers" COLLECTION:');
    console.log('-'.repeat(80));
    
    const mongoDrivers = await db.collection('drivers').find({}).toArray();
    console.log(`Total MongoDB Drivers: ${mongoDrivers.length}\n`);
    
    if (mongoDrivers.length > 0) {
      console.log('📊 Sample Drivers:');
      mongoDrivers.slice(0, 5).forEach(driver => {
        const name = `${driver.personalInfo?.firstName || ''} ${driver.personalInfo?.lastName || ''}`.trim();
        console.log(`   - ${name || 'No Name'}`);
        console.log(`     Email: ${driver.personalInfo?.email || 'N/A'}`);
        console.log(`     Driver ID: ${driver.driverId || 'N/A'}`);
        console.log(`     Status: ${driver.status || 'N/A'}`);
      });
      if (mongoDrivers.length > 5) {
        console.log(`   ... and ${mongoDrivers.length - 5} more`);
      }
    }
    
    // ========== CHECK MONGODB CLIENTS COLLECTION ==========
    console.log('\n\n🏢 MONGODB "clients" COLLECTION:');
    console.log('-'.repeat(80));
    
    const mongoClients = await db.collection('clients').find({}).toArray();
    console.log(`Total MongoDB Clients: ${mongoClients.length}\n`);
    
    if (mongoClients.length > 0) {
      console.log('📊 Sample Clients:');
      mongoClients.slice(0, 5).forEach(client => {
        console.log(`   - ${client.companyName || 'No Name'}`);
        console.log(`     Contact: ${client.contactPerson || 'N/A'}`);
        console.log(`     Email: ${client.email || 'N/A'}`);
        console.log(`     Status: ${client.status || 'N/A'}`);
      });
      if (mongoClients.length > 5) {
        console.log(`   ... and ${mongoClients.length - 5} more`);
      }
    }
    
    // ========== CROSS-REFERENCE CHECK ==========
    console.log('\n\n🔗 CROSS-REFERENCE CHECK:');
    console.log('-'.repeat(80));
    
    // Check how many MongoDB users have Firebase UIDs
    const usersWithFirebaseUid = mongoUsers.filter(u => u.firebaseUid);
    const usersWithoutFirebaseUid = mongoUsers.filter(u => !u.firebaseUid);
    
    console.log(`MongoDB users WITH Firebase UID: ${usersWithFirebaseUid.length}`);
    console.log(`MongoDB users WITHOUT Firebase UID: ${usersWithoutFirebaseUid.length}`);
    
    if (usersWithoutFirebaseUid.length > 0) {
      console.log('\n⚠️  Users without Firebase UID:');
      usersWithoutFirebaseUid.slice(0, 5).forEach(user => {
        console.log(`   - ${user.name} (${user.email}) - Role: ${user.role}`);
      });
    }
    
    // ========== SUMMARY ==========
    console.log('\n\n' + '='.repeat(80));
    console.log('📊 STORAGE SUMMARY');
    console.log('='.repeat(80));
    
    console.log('\n🔐 AUTHENTICATION (Firebase Auth):');
    console.log(`   Total Users: ${firebaseUsers.length}`);
    console.log(`   Purpose: Login authentication, password management`);
    
    console.log('\n💾 USER DATA (MongoDB "users" collection):');
    console.log(`   Total Users: ${mongoUsers.length}`);
    console.log(`   Admins: ${mongoUsersByRole.admin?.length || 0}`);
    console.log(`   Customers: ${mongoUsersByRole.customer?.length || 0}`);
    console.log(`   Drivers: ${mongoUsersByRole.driver?.length || 0}`);
    console.log(`   Clients: ${mongoUsersByRole.client?.length || 0}`);
    console.log(`   Purpose: User profiles, roles, organization data`);
    
    console.log('\n🚗 DRIVER DATA (MongoDB "drivers" collection):');
    console.log(`   Total Drivers: ${mongoDrivers.length}`);
    console.log(`   Purpose: Driver-specific data (license, documents, etc.)`);
    
    console.log('\n🏢 CLIENT DATA (MongoDB "clients" collection):');
    console.log(`   Total Clients: ${mongoClients.length}`);
    console.log(`   Purpose: Company/organization data, contracts, billing`);
    
    console.log('\n📋 ARCHITECTURE:');
    console.log('   ✅ Firebase Auth: Handles authentication (login/password)');
    console.log('   ✅ MongoDB "users": Stores user profiles and roles');
    console.log('   ✅ MongoDB "drivers": Stores driver-specific details');
    console.log('   ✅ MongoDB "clients": Stores client/company details');
    
    console.log('\n💡 KEY FINDINGS:');
    if (usersWithoutFirebaseUid.length > 0) {
      console.log(`   ⚠️  ${usersWithoutFirebaseUid.length} MongoDB users are NOT linked to Firebase Auth`);
      console.log('   → These users cannot log in!');
    }
    if (mongoUsers.length < firebaseUsers.length) {
      console.log(`   ⚠️  ${firebaseUsers.length - mongoUsers.length} Firebase users have NO MongoDB profile`);
      console.log('   → These users can log in but have no profile data!');
    }
    if (mongoUsers.length === usersWithFirebaseUid.length && mongoUsers.length === firebaseUsers.length) {
      console.log('   ✅ All users are properly linked between Firebase and MongoDB');
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ CHECK COMPLETE');
    console.log('='.repeat(80) + '\n');
    
  } catch (error) {
    console.error('\n❌ FATAL ERROR:', error);
    console.error(error.stack);
  } finally {
    if (mongoClient) {
      await mongoClient.close();
      console.log('✅ MongoDB connection closed');
    }
    process.exit(0);
  }
}

// Run the check
checkUserStorageLocations();
