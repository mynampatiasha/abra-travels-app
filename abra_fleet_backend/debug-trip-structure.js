// Debug trip data structure
const { MongoClient } = require('mongodb');
require('dotenv').config({ path: './.env' });

async function debugTripStructure() {
  console.log('🔍 Debugging Trip Data Structure...\n');
  
  let client;
  try {
    // Connect to MongoDB
    client = new MongoClient(process.env.MONGODB_URI);
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    
    // Get a sample trip to see its structure
    console.log('📋 Sample trip structure:');
    const sampleTrip = await db.collection('trips').findOne({});
    console.log(JSON.stringify(sampleTrip, null, 2));
    
    // Check customer data structure
    console.log('\n👥 Sample customer structure:');
    const sampleCustomer = await db.collection('users').findOne({ role: 'customer' });
    console.log(JSON.stringify(sampleCustomer, null, 2));
    
    // Check if trips have customer field or different structure
    console.log('\n🔍 Checking trip customer field variations...');
    const tripFields = await db.collection('trips').findOne({}, { projection: { _id: 1, customer: 1, customerId: 1, customerEmail: 1, userId: 1, user: 1 } });
    console.log('Trip customer fields:', JSON.stringify(tripFields, null, 2));
    
    // Check all unique field names in trips collection
    console.log('\n📊 All field names in trips collection:');
    const pipeline = [
      { $limit: 10 },
      { $project: { arrayofkeyvalue: { $objectToArray: "$$ROOT" } } },
      { $unwind: "$arrayofkeyvalue" },
      { $group: { _id: null, allkeys: { $addToSet: "$arrayofkeyvalue.k" } } }
    ];
    
    const result = await db.collection('trips').aggregate(pipeline).toArray();
    if (result.length > 0) {
      console.log('Available fields:', result[0].allkeys.sort());
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    if (client) {
      await client.close();
      console.log('\n✅ MongoDB connection closed');
    }
  }
}

// Run the debug
debugTripStructure();