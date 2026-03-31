// Check actual customer data structure
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function checkCustomerDataStructure() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    const customers = await db.collection('customers').find({}).limit(5).toArray();
    
    console.log('\n📋 Customer Data Structure:\n');
    console.log(JSON.stringify(customers, null, 2));
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkCustomerDataStructure();
