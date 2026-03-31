// Find the specific driver DRV-842143
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function findSpecificDriver() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    
    console.log('\n🔍 Searching for driver DRV-842143 in ALL collections...\n');
    
    // Check users collection
    console.log('1️⃣ Checking "users" collection:');
    const userDriver = await db.collection('users').findOne({
      $or: [
        { _id: 'DRV-842143' },
        { driverId: 'DRV-842143' },
        { driverCode: 'DRV-842143' },
        { employeeId: 'DRV-842143' }
      ]
    });
    
    if (userDriver) {
      console.log('✅ Found in users collection!');
      console.log(JSON.stringify(userDriver, null, 2));
    } else {
      console.log('❌ Not found in users collection');
    }
    
    // Check drivers collection (if it exists)
    console.log('\n2️⃣ Checking "drivers" collection:');
    const collections = await db.listCollections().toArray();
    const hasDriversCollection = collections.some(c => c.name === 'drivers');
    
    if (hasDriversCollection) {
      const driver = await db.collection('drivers').findOne({
        $or: [
          { _id: 'DRV-842143' },
          { driverId: 'DRV-842143' },
          { driverCode: 'DRV-842143' },
          { employeeId: 'DRV-842143' }
        ]
      });
      
      if (driver) {
        console.log('✅ Found in drivers collection!');
        console.log(JSON.stringify(driver, null, 2));
      } else {
        console.log('❌ Not found in drivers collection');
      }
    } else {
      console.log('⚠️  No "drivers" collection exists');
    }
    
    // List all collections
    console.log('\n📋 All collections in database:');
    collections.forEach(c => console.log(`   - ${c.name}`));
    
    // Search in all documents that might have this ID
    console.log('\n3️⃣ Searching for "DRV-842143" in all text fields...');
    
    for (const collection of collections) {
      const count = await db.collection(collection.name).countDocuments({
        $or: [
          { _id: 'DRV-842143' },
          { driverId: 'DRV-842143' },
          { driverCode: 'DRV-842143' },
          { employeeId: 'DRV-842143' },
          { assignedDriver: 'DRV-842143' }
        ]
      });
      
      if (count > 0) {
        console.log(`   ✅ Found ${count} document(s) in "${collection.name}"`);
        
        const docs = await db.collection(collection.name).find({
          $or: [
            { _id: 'DRV-842143' },
            { driverId: 'DRV-842143' },
            { driverCode: 'DRV-842143' },
            { employeeId: 'DRV-842143' },
            { assignedDriver: 'DRV-842143' }
          ]
        }).limit(3).toArray();
        
        docs.forEach((doc, idx) => {
          console.log(`\n   Document ${idx + 1}:`);
          console.log(JSON.stringify(doc, null, 2));
        });
      }
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

findSpecificDriver();
