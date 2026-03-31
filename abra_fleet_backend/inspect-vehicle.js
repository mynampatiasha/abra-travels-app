require('dotenv').config();
const { MongoClient } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI;
const DB_NAME = 'abra_fleet';

async function inspectVehicle() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db(DB_NAME);
    
    const vehicle = await db.collection('vehicles').findOne();
    console.log('Vehicle structure:');
    console.log(JSON.stringify(vehicle, null, 2));
    
  } catch (error) {
    console.error('Error:', error.message);
  } finally {
    await client.close();
  }
}

inspectVehicle();
