const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const uri = process.env.MONGODB_URI;

async function checkDriverStructure() {
  const client = new MongoClient(uri);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('abra_fleet');
    
    const driverId = '693815916f67e02c30df26a6';
    
    const driver = await db.collection('drivers').findOne({ _id: new ObjectId(driverId) });
    
    if (driver) {
      console.log('📋 FULL DRIVER STRUCTURE:\n');
      console.log(JSON.stringify(driver, null, 2));
    } else {
      console.log('❌ Driver not found');
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkDriverStructure();
