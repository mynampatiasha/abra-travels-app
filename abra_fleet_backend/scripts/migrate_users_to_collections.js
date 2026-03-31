// scripts/migrate_users_to_collections.js - USER MIGRATION SCRIPT
// ============================================================================
// MIGRATES USERS TO CORRECT COLLECTIONS BASED ON ROLE
// ============================================================================
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function migrateUsers() {
  console.log('\n🔄 USER MIGRATION TO CORRECT COLLECTIONS');
  console.log('═'.repeat(80));
  
  let client;
  
  try {
    // Connect to MongoDB
    console.log('📡 Connecting to MongoDB...');
    client = new MongoClient(MONGODB_URI);
    await client.connect();
    const db = client.db();
    
    console.log('✅ Connected to MongoDB');
    console.log('─'.repeat(80));
    
    // Migration statistics
    const stats = {
      totalProcessed: 0,
      migrated: 0,
      alreadyInCorrectCollection: 0,
      errors: 0,
      collections: {
        admin_users: 0,
        drivers: 0,
        customers: 0,
        clients: 0,
        employee_admins: 0
      }
    };
    
    // Collections to check for users
    const sourceCollections = [
      'users', // Generic users collection
      'admin_users',
      'drivers', 
      'customers',
      'clients',
      'employee_admins'
    ];
    
    // Process each source collection
    for (const collectionName of sourceCollections) {
      console.log(`\n📂 Processing collection: ${collectionName}`);
      console.log('─'.repeat(40));
      
      try {
        const collection = db.collection(collectionName);
        const users = await collection.find({}).toArray();
        
        console.log(`   Found ${users.length} users in ${collectionName}`);
        
        for (const user of users) {
          stats.totalProcessed++;
          
          try {
            // Determine correct collection based on role
            let targetCollection;
            const userRole = user.role || 'customer';
            
            switch (userRole.toLowerCase()) {
              case 'admin':
              case 'super_admin':
                targetCollection = 'admin_users';
                break;
              case 'driver':
                targetCollection = 'drivers';
                break;
              case 'customer':
                targetCollection = 'customers';
                break;
              case 'client':
                targetCollection = 'clients';
                break;
              case 'employee':
                targetCollection = 'employee_admins';
                break;
              default:
                targetCollection = 'customers'; // Default fallback
            }
            
            console.log(`   User: ${user.email} (${userRole}) → ${targetCollection}`);
            
            // If user is already in correct collection, skip
            if (collectionName === targetCollection) {
              console.log(`     ✅ Already in correct collection`);
              stats.alreadyInCorrectCollection++;
              continue;
            }
            
            // Check if user already exists in target collection
            const existingUser = await db.collection(targetCollection).findOne({
              email: user.email
            });
            
            if (existingUser) {
              console.log(`     ⚠️  User already exists in ${targetCollection}, skipping`);
              continue;
            }
            
            // Prepare user document for target collection
            const migratedUser = {
              ...user,
              role: userRole,
              migratedFrom: collectionName,
              migratedAt: new Date(),
              updatedAt: new Date()
            };
            
            // Remove _id to let MongoDB generate new one
            delete migratedUser._id;
            
            // Insert into target collection
            const result = await db.collection(targetCollection).insertOne(migratedUser);
            
            if (result.insertedId) {
              console.log(`     ✅ Migrated to ${targetCollection} with ID: ${result.insertedId}`);
              stats.migrated++;
              stats.collections[targetCollection]++;
              
              // Remove from source collection if it's not the target collection
              if (collectionName !== targetCollection) {
                await db.collection(collectionName).deleteOne({ _id: user._id });
                console.log(`     🗑️  Removed from ${collectionName}`);
              }
            } else {
              console.log(`     ❌ Failed to migrate user`);
              stats.errors++;
            }
            
          } catch (userError) {
            console.error(`     ❌ Error migrating user ${user.email}:`, userError.message);
            stats.errors++;
          }
        }
        
      } catch (collectionError) {
        console.error(`❌ Error processing collection ${collectionName}:`, collectionError.message);
        stats.errors++;
      }
    }
    
    // Migration summary
    console.log('\n📊 MIGRATION SUMMARY');
    console.log('═'.repeat(80));
    console.log(`Total users processed: ${stats.totalProcessed}`);
    console.log(`Users migrated: ${stats.migrated}`);
    console.log(`Already in correct collection: ${stats.alreadyInCorrectCollection}`);
    console.log(`Errors: ${stats.errors}`);
    console.log('\nUsers per collection:');
    console.log(`  admin_users: ${stats.collections.admin_users}`);
    console.log(`  drivers: ${stats.collections.drivers}`);
    console.log(`  customers: ${stats.collections.customers}`);
    console.log(`  clients: ${stats.collections.clients}`);
    console.log(`  employee_admins: ${stats.collections.employee_admins}`);
    
    // Verify collections
    console.log('\n🔍 VERIFICATION - Current user counts:');
    console.log('─'.repeat(40));
    
    for (const collectionName of ['admin_users', 'drivers', 'customers', 'clients', 'employee_admins']) {
      try {
        const count = await db.collection(collectionName).countDocuments();
        console.log(`  ${collectionName}: ${count} users`);
      } catch (error) {
        console.log(`  ${collectionName}: Error counting - ${error.message}`);
      }
    }
    
    console.log('\n✅ USER MIGRATION COMPLETED');
    console.log('═'.repeat(80));
    
  } catch (error) {
    console.error('\n❌ MIGRATION FAILED');
    console.error('═'.repeat(80));
    console.error('Error:', error.message);
    console.error('Stack:', error.stack);
    process.exit(1);
  } finally {
    if (client) {
      await client.close();
      console.log('📡 MongoDB connection closed');
    }
  }
}

// Run migration if called directly
if (require.main === module) {
  migrateUsers().catch(console.error);
}

module.exports = { migrateUsers };