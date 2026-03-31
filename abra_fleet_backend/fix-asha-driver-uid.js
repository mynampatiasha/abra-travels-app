// Fix Asha's driver UID to match Firebase UID
const { MongoClient } = require('mongodb');
const admin = require('./config/firebase');
require('dotenv').config();

async function fixAshaDriverUID() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    const driverEmail = 'ashamynampati2003@gmail.com';
    
    console.log('\n🔍 Finding Firebase UID for:', driverEmail);
    
    // Get Firebase UID
    const userRecord = await admin.auth().getUserByEmail(driverEmail);
    const firebaseUID = userRecord.uid;
    
    console.log('✅ Firebase UID:', firebaseUID);
    
    // Update driver in drivers collection
    console.log('\n📝 Updating driver UID in drivers collection...');
    const driverResult = await db.collection('drivers').updateOne(
      { email: driverEmail },
      { $set: { uid: firebaseUID } }
    );
    console.log(`   Updated ${driverResult.modifiedCount} driver record(s)`);
    
    // Update rosters
    console.log('\n📋 Updating rosters...');
    const rosterResult = await db.collection('rosters').updateMany(
      { driverId: 'asha_driver_uid' },
      { $set: { driverId: firebaseUID } }
    );
    console.log(`   Updated ${rosterResult.modifiedCount} roster(s)`);
    
    // Verify
    console.log('\n✅ Verification:');
    const driver = await db.collection('drivers').findOne({ email: driverEmail });
    console.log('   Driver UID:', driver?.uid);
    
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);
    
    const rosters = await db.collection('rosters').find({
      driverId: firebaseUID,
      scheduledDate: { $gte: today, $lt: tomorrow }
    }).toArray();
    
    console.log(`   Rosters for today: ${rosters.length}`);
    
    console.log('\n🎉 Done! The driver UID has been updated.');
    console.log('   Firebase UID:', firebaseUID);
    console.log('   Now refresh the Flutter app to see the route!');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

fixAshaDriverUID();
