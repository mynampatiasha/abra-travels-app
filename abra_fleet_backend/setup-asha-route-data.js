// Setup route data for Asha driver
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

async function setupAshaRouteData() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    // Asha's driver UID
    const driverUid = 'asha_driver_uid';
    const driverEmail = 'ashamynampati2003@gmail.com';
    
    console.log('\n🔍 Setting up route for:', driverEmail);
    
    // Find or create vehicle
    let vehicle = await db.collection('vehicles').findOne({ 
      registrationNumber: 'KA-01-AB-1234' 
    });
    
    if (!vehicle) {
      console.log('   Creating test vehicle...');
      const result = await db.collection('vehicles').insertOne({
        registrationNumber: 'KA-01-AB-1234',
        model: 'Toyota Innova',
        make: 'Toyota',
        year: 2023,
        capacity: 7,
        status: 'available',
        fuelType: 'Diesel',
        organizationId: 'wipro',
        createdAt: new Date()
      });
      vehicle = { _id: result.insertedId };
      console.log('   ✅ Vehicle created');
    } else {
      console.log('   ✅ Vehicle found:', vehicle.registrationNumber);
    }
    
    // Create test customers
    console.log('\n👥 Creating test customers...');
    const customers = [];
    const customerNames = [
      { name: 'Sarah Kumar', phone: '+91 98765 43210' },
      { name: 'Mike Rahman', phone: '+91 98765 43211' },
      { name: 'Priya Sharma', phone: '+91 98765 43212' },
      { name: 'Raj Patel', phone: '+91 98765 43213' }
    ];
    
    for (const customerData of customerNames) {
      let customer = await db.collection('customers').findOne({ 
        phone: customerData.phone 
      });
      
      if (!customer) {
        const result = await db.collection('customers').insertOne({
          name: customerData.name,
          email: `${customerData.name.toLowerCase().replace(' ', '.')}@wipro.com`,
          phone: customerData.phone,
          organizationId: 'wipro',
          status: 'active',
          createdAt: new Date()
        });
        customer = { _id: result.insertedId, ...customerData };
      }
      customers.push(customer);
    }
    console.log(`   ✅ ${customers.length} customers ready`);
    
    // Create today's rosters
    console.log('\n📋 Creating today\'s rosters...');
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    
    // Delete existing rosters for today
    await db.collection('rosters').deleteMany({
      driverId: driverUid,
      scheduledDate: { $gte: today }
    });
    
    const pickupLocations = [
      'Cyber City Hub, Gurgaon',
      'DLF Phase 2, Gurgaon',
      'Sector 29, Gurgaon',
      'MG Road, Gurgaon'
    ];
    
    const dropLocation = 'Wipro Office, Connaught Place, Delhi';
    const scheduledTimes = ['08:00 AM', '08:15 AM', '08:30 AM', '08:45 AM'];
    
    const rosters = [];
    for (let i = 0; i < customers.length; i++) {
      const roster = {
        customerId: customers[i]._id.toString(),
        driverId: driverUid,
        vehicleId: vehicle._id.toString(),
        rosterType: 'login',
        scheduledDate: today,
        scheduledTime: scheduledTimes[i],
        pickupLocation: pickupLocations[i],
        dropLocation: dropLocation,
        status: 'assigned',
        distance: 10 + Math.random() * 15,
        organizationId: 'wipro',
        createdAt: new Date()
      };
      rosters.push(roster);
    }
    
    await db.collection('rosters').insertMany(rosters);
    console.log(`   ✅ Created ${rosters.length} rosters for today`);
    
    console.log('\n' + '='.repeat(80));
    console.log('🎉 ROUTE DATA SETUP COMPLETE!');
    console.log('='.repeat(80));
    console.log('\n📝 Summary:');
    console.log(`   Driver: ${driverEmail}`);
    console.log(`   Vehicle: ${vehicle.registrationNumber}`);
    console.log(`   Customers: ${customers.length}`);
    console.log(`   Rosters: ${rosters.length}`);
    console.log('\n✅ The driver dashboard will now show today\'s route!');
    console.log('');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

setupAshaRouteData();
