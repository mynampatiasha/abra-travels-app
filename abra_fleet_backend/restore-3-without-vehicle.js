// Restore the 3 Infosys rosters WITHOUT vehicle assignment
// User can then reassign all 5 via bulk import
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function restoreRosters() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB Atlas');
    
    const db = client.db('abra_fleet');
    
    // Get customer data from MongoDB users collection
    console.log('\n🔍 Getting customer data...\n');
    
    const customers = await db.collection('users')
      .find({
        email: { $in: [
          'rajesh.kumar@infosys.com',
          'priya.sharma@infosys.com',
          'amit.patel@infosys.com'
        ]}
      })
      .toArray();
    
    console.log(`✅ Found ${customers.length} customers to restore\n`);
    
    const rostersToRestore = [
      {
        email: 'rajesh.kumar@infosys.com',
        pickupLocation: 'Electronic City, Bangalore',
        pickupLatitude: 12.8456,
        pickupLongitude: 77.6603,
      },
      {
        email: 'priya.sharma@infosys.com',
        pickupLocation: 'Whitefield, Bangalore',
        pickupLatitude: 12.9698,
        pickupLongitude: 77.7500,
      },
      {
        email: 'amit.patel@infosys.com',
        pickupLocation: 'Koramangala, Bangalore',
        pickupLatitude: 12.9352,
        pickupLongitude: 77.6245,
      },
    ];
    
    console.log('📝 Restoring 3 rosters (without vehicle assignment)...\n');
    
    const now = new Date();
    const tomorrow = new Date(now);
    tomorrow.setDate(tomorrow.getDate() + 1);
    tomorrow.setHours(8, 0, 0, 0);
    
    for (const rosterData of rostersToRestore) {
      const customer = customers.find(c => c.email === rosterData.email);
      
      if (!customer) {
        console.log(`❌ Customer not found: ${rosterData.email}`);
        continue;
      }
      
      const roster = {
        customerUid: customer.uid || customer._id.toString(),
        customerName: customer.name,
        customerEmail: customer.email,
        customerPhone: customer.phone || '+91 9876543210',
        pickupLocation: rosterData.pickupLocation,
        pickupLatitude: rosterData.pickupLatitude,
        pickupLongitude: rosterData.pickupLongitude,
        dropLocation: 'Infosys Campus, Electronic City',
        dropLatitude: 12.8456,
        dropLongitude: 77.6603,
        vehicleNumber: null,
        vehicleId: null,
        driverId: null,
        driverName: null,
        driverPhone: null,
        tripDate: tomorrow,
        pickupTime: '08:00',
        shift: 'morning',
        status: 'pending', // Set as pending since no vehicle assigned
        tripType: 'pickup',
        createdAt: now,
        updatedAt: now,
      };
      
      const result = await db.collection('rosters').insertOne(roster);
      console.log(`✅ Restored: ${customer.name} - Status: pending (no vehicle)`);
    }
    
    console.log('\n✅ Successfully restored 3 rosters!');
    console.log('\n📝 Summary:');
    console.log('   ✅ Rajesh Kumar - Restored as PENDING (no vehicle)');
    console.log('   ✅ Priya Sharma - Restored as PENDING (no vehicle)');
    console.log('   ✅ Amit Patel - Restored as PENDING (no vehicle)');
    console.log('   ❌ Neha Gupta - Still deleted');
    console.log('   ❌ Vikram Singh - Still deleted');
    console.log('\n📱 Next Steps:');
    console.log('   1. Now you have 3 pending rosters restored');
    console.log('   2. You can use bulk import to assign vehicles to all 5 Infosys employees:');
    console.log('      - Rajesh Kumar');
    console.log('      - Priya Sharma');
    console.log('      - Amit Patel');
    console.log('      - Neha Gupta');
    console.log('      - Vikram Singh');
    console.log('   3. This way you can properly assign them all together\n');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error);
  } finally {
    await client.close();
  }
}

restoreRosters();
