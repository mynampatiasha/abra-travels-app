// check-collections-status.js
// Quick script to check current collection status before migration

const mongoose = require('mongoose');
require('dotenv').config();

async function checkCollections() {
  console.log('\n╔══════════════════════════════════════════════════════════════════════════════╗');
  console.log('║                    COLLECTION STATUS CHECK                                    ║');
  console.log('╚══════════════════════════════════════════════════════════════════════════════╝\n');

  try {
    // Connect to MongoDB
    console.log('📡 Connecting to MongoDB...');
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected to MongoDB\n');

    const db = mongoose.connection.db;

    // Check all collections
    const collections = ['admin_users', 'employee_admins', 'drivers', 'customers', 'clients'];
    
    console.log('📊 COLLECTION COUNTS:');
    console.log('─'.repeat(50));
    
    for (const collectionName of collections) {
      try {
        const count = await db.collection(collectionName).countDocuments();
        console.log(`${collectionName.padEnd(20)}: ${count} documents`);
        
        if (count > 0) {
          // Show sample roles
          const sample = await db.collection(collectionName).find({}, { role: 1, email: 1 }).limit(3).toArray();
          sample.forEach(doc => {
            console.log(`  └─ ${doc.email} (${doc.role || 'no role'})`);
          });
        }
      } catch (error) {
        console.log(`${collectionName.padEnd(20)}: Collection doesn't exist`);
      }
    }

    console.log('\n📋 ADMIN_USERS BREAKDOWN:');
    console.log('─'.repeat(50));
    
    try {
      const adminUsers = await db.collection('admin_users').find({}).toArray();
      const roleCount = {};
      
      adminUsers.forEach(user => {
        const role = user.role || 'unknown';
        roleCount[role] = (roleCount[role] || 0) + 1;
      });
      
      Object.entries(roleCount).forEach(([role, count]) => {
        console.log(`${role.padEnd(20)}: ${count} users`);
      });
      
      console.log(`\nTotal in admin_users: ${adminUsers.length}`);
    } catch (error) {
      console.log('admin_users collection not found');
    }

    console.log('\n✅ Status check complete!');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await mongoose.connection.close();
  }
}

checkCollections().catch(console.error);