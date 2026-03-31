// Verify the route API will return correct customer data
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

async function verifyRouteAPIResponse() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    const driverId = 'AMATisPyRgQc39FXypD4iu7unVs1';
    
    // Get today's date range
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);
    
    console.log('\n🔍 Simulating API call for driver:', driverId);
    console.log('   Date:', today.toDateString());
    
    // Find rosters (same as API does)
    const rosters = await db.collection('rosters').find({
      driverId: driverId,
      scheduledDate: { $gte: today, $lt: tomorrow },
      status: { $in: ['active', 'assigned', 'in_progress', 'pending'] }
    }).toArray();
    
    console.log(`\n📋 Found ${rosters.length} rosters`);
    
    // Get vehicle
    const roster = rosters[0];
    const vehicle = roster?.vehicleId ? await db.collection('vehicles').findOne({
      _id: new ObjectId(roster.vehicleId)
    }) : null;
    
    console.log('\n🚗 Vehicle:');
    console.log(JSON.stringify({
      registrationNumber: vehicle?.registrationNumber,
      model: vehicle?.model,
      capacity: vehicle?.capacity
    }, null, 2));
    
    // Enrich customer data (same as API does)
    console.log('\n👥 Customers:');
    for (const roster of rosters) {
      // Try multiple ways to find customer
      let customer = null;
      
      // Try by uid
      if (roster.customerId) {
        customer = await db.collection('customers').findOne({
          uid: roster.customerId
        });
      }
      
      // Try by _id
      if (!customer && roster.customerId) {
        try {
          customer = await db.collection('customers').findOne({
            _id: new ObjectId(roster.customerId)
          });
        } catch (e) {}
      }
      
      // Try by email
      if (!customer && roster.customerEmail) {
        customer = await db.collection('customers').findOne({
          email: roster.customerEmail
        });
      }
      
      const enrichedCustomer = {
        id: roster._id.toString(),
        name: customer?.name || roster.customerName || 'Unknown Customer',
        phone: customer?.phone || roster.customerPhone || 'N/A',
        email: customer?.email || roster.customerEmail || 'N/A',
        pickupLocation: roster.pickupLocation || roster.loginPickupAddress || 'N/A',
        dropLocation: roster.dropLocation || roster.officeLocation || 'N/A',
        scheduledTime: roster.scheduledTime,
        distance: roster.distance || 0,
        status: roster.status
      };
      
      console.log('\n' + JSON.stringify(enrichedCustomer, null, 2));
      
      // Verify no "Unknown Customer" or "N/A"
      if (enrichedCustomer.name === 'Unknown Customer') {
        console.log('   ❌ WARNING: Customer name is "Unknown Customer"');
      } else {
        console.log('   ✅ Customer name is correct');
      }
      
      if (enrichedCustomer.phone === 'N/A') {
        console.log('   ❌ WARNING: Phone is "N/A"');
      } else {
        console.log('   ✅ Phone is correct');
      }
      
      if (enrichedCustomer.pickupLocation === 'N/A') {
        console.log('   ❌ WARNING: Pickup location is "N/A"');
      } else {
        console.log('   ✅ Pickup location is correct');
      }
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ API RESPONSE VERIFICATION COMPLETE');
    console.log('='.repeat(80));
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

verifyRouteAPIResponse();
