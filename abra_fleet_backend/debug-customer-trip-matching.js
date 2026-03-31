// Debug customer-trip matching
const { MongoClient } = require('mongodb');
require('dotenv').config({ path: './.env' });

async function debugCustomerTripMatching() {
  console.log('🔍 Debugging Customer-Trip Matching...\n');
  
  let client;
  try {
    // Connect to MongoDB
    client = new MongoClient(process.env.MONGODB_URI);
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    
    // Get sample customer data
    console.log('👥 Sample customer data:');
    const customers = await db.collection('users').find({ role: 'customer' }).limit(3).toArray();
    customers.forEach((customer, index) => {
      console.log(`Customer ${index + 1}:`);
      console.log('  _id:', customer._id);
      console.log('  _id as string:', customer._id.toString());
      console.log('  name:', customer.name);
      console.log('  email:', customer.email);
      console.log('  companyName:', customer.companyName);
    });
    
    // Get sample trip data
    console.log('\n🚗 Sample trip data:');
    const trips = await db.collection('trips').find({}).limit(5).toArray();
    trips.forEach((trip, index) => {
      console.log(`Trip ${index + 1}:`);
      console.log('  _id:', trip._id);
      console.log('  customerId:', trip.customerId);
      console.log('  customerName:', trip.customerName);
      console.log('  status:', trip.status);
      console.log('  fare:', trip.fare);
      console.log('  tripDate:', trip.tripDate);
      console.log('  completedAt:', trip.completedAt);
    });
    
    // Check if any customerId matches any customer _id
    console.log('\n🔍 Checking for matches...');
    const customerIds = customers.map(c => c._id.toString());
    const tripCustomerIds = trips.map(t => t.customerId).filter(id => id);
    
    console.log('Customer _ids (as strings):', customerIds);
    console.log('Trip customerIds:', tripCustomerIds);
    
    const matches = customerIds.filter(id => tripCustomerIds.includes(id));
    console.log('Matches found:', matches);
    
    if (matches.length === 0) {
      console.log('\n❌ No matches found! This explains why no trips are showing.');
      console.log('Let\'s check what customerIds exist in trips:');
      
      const uniqueCustomerIds = await db.collection('trips').distinct('customerId');
      console.log('Unique customerIds in trips:', uniqueCustomerIds);
      
      console.log('\nLet\'s check if these customerIds exist as users:');
      for (const customerId of uniqueCustomerIds.slice(0, 5)) {
        const user = await db.collection('users').findOne({ _id: customerId });
        console.log(`CustomerId "${customerId}":`, user ? `Found user: ${user.name}` : 'No matching user found');
      }
      
      // Try to find trips for the actual customer _ids
      console.log('\n🔄 Trying to find trips for actual customer _ids...');
      for (const customerId of customerIds) {
        const tripCount = await db.collection('trips').countDocuments({ customerId: customerId });
        console.log(`Customer ${customerId}: ${tripCount} trips`);
      }
    } else {
      console.log('\n✅ Matches found! The pipeline should work.');
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
debugCustomerTripMatching();