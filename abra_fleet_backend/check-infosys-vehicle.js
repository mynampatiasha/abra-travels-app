// Check what vehicle was assigned to Infosys employees
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function checkVehicle() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB Atlas');
    
    const db = client.db('abra_fleet');
    
    // Check all vehicles with Infosys organization
    console.log('\n🔍 Checking vehicles for Infosys organization...\n');
    
    const vehicles = await db.collection('vehicles')
      .find({ organization: '@infosys.com' })
      .toArray();
    
    console.log(`📊 Found ${vehicles.length} Infosys vehicles:\n`);
    
    vehicles.forEach((v, index) => {
      console.log(`${index + 1}. ${v.vehicleNumber}`);
      console.log(`   Driver: ${v.driverId || 'N/A'}`);
      console.log(`   Capacity: ${v.capacity || 'N/A'}`);
      console.log(`   Organization: ${v.organization || 'N/A'}`);
      console.log('');
    });
    
    // Also check if KA01AB1240 exists with different organization
    console.log('\n🔍 Checking if KA01AB1240 exists...\n');
    
    const ka01ab1240 = await db.collection('vehicles').findOne({ vehicleNumber: 'KA01AB1240' });
    
    if (ka01ab1240) {
      console.log('✅ Found KA01AB1240:');
      console.log(`   Organization: ${ka01ab1240.organization || 'N/A'}`);
      console.log(`   Driver: ${ka01ab1240.driverId || 'N/A'}`);
      console.log(`   Capacity: ${ka01ab1240.capacity || 'N/A'}`);
    } else {
      console.log('❌ KA01AB1240 not found in database');
    }
    
    // Check Infosys customers
    console.log('\n\n🔍 Checking Infosys customers...\n');
    
    const customers = await db.collection('users')
      .find({
        email: { $in: [
          'rajesh.kumar@infosys.com',
          'priya.sharma@infosys.com',
          'amit.patel@infosys.com'
        ]}
      })
      .toArray();
    
    console.log(`📊 Found ${customers.length} customers:\n`);
    
    customers.forEach((c, index) => {
      console.log(`${index + 1}. ${c.name} (${c.email})`);
      console.log(`   UID: ${c.uid || c._id}`);
      console.log(`   Phone: ${c.phone || 'N/A'}`);
      console.log('');
    });
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

checkVehicle();
