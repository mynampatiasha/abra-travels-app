// scripts/link-firebase-to-drivers.js
// Run this ONCE to link existing Firebase users to driver documents

require('dotenv').config();
const { MongoClient } = require('mongodb');
const admin = require('../config/firebase');

async function linkFirebaseToDrivers() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    // Get all Firebase users with driver role
    const firebaseUsers = await db.collection('users')
      .find({ role: 'driver' })
      .toArray();
    
    console.log(`Found ${firebaseUsers.length} Firebase driver users`);
    
    let linked = 0;
    let notFound = 0;
    
    for (const user of firebaseUsers) {
      const email = user.email;
      const firebaseUid = user.firebaseUid || user._id.toString();
      
      console.log(`\nProcessing: ${user.name} (${email})`);
      
      // Try to find matching driver in drivers collection by email
      const driver = await db.collection('drivers').findOne({
        'personalInfo.email': email
      });
      
      if (driver) {
        // Link Firebase UID to driver document
        await db.collection('drivers').updateOne(
          { _id: driver._id },
          {
            $set: {
              firebaseUid: firebaseUid,
              linkedEmail: email,
              linkedAt: new Date(),
              updatedAt: new Date()
            }
          }
        );
        console.log(`✅ Linked ${user.name} to driver ${driver.driverId}`);
        linked++;
      } else {
        console.log(`⚠️  No matching driver found for ${email}`);
        notFound++;
      }
    }
    
    console.log('\n📊 Summary:');
    console.log(`✅ Successfully linked: ${linked}`);
    console.log(`⚠️  Not found: ${notFound}`);
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n🔌 Disconnected from MongoDB');
  }
}

// Run the script
linkFirebaseToDrivers()
  .then(() => {
    console.log('\n✨ Done!');
    process.exit(0);
  })
  .catch(err => {
    console.error('Fatal error:', err);
    process.exit(1);
  });