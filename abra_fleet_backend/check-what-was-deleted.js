// Check what Infosys rosters were deleted and what should be restored
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function checkDeletedRosters() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB Atlas');
    
    const db = client.db('abra_fleet');
    
    console.log('\n🔍 Checking current Infosys rosters in database...\n');
    
    // Check if any Infosys rosters still exist
    const remainingRosters = await db.collection('rosters')
      .find({
        customerEmail: { $regex: '@infosys\\.com', $options: 'i' }
      })
      .toArray();
    
    console.log(`📊 Current Infosys rosters in database: ${remainingRosters.length}\n`);
    
    if (remainingRosters.length > 0) {
      console.log('📋 Remaining rosters:');
      remainingRosters.forEach((roster, index) => {
        console.log(`\n${index + 1}. Customer: ${roster.customerName} (${roster.customerEmail})`);
        console.log(`   Vehicle: ${roster.vehicleNumber || 'N/A'}`);
        console.log(`   Status: ${roster.status}`);
      });
    } else {
      console.log('❌ ALL Infosys rosters were deleted!');
      console.log('\n📝 According to the deletion script, these 5 rosters were deleted:');
      console.log('   1. Rajesh Kumar (rajesh.kumar@infosys.com) - Vehicle: KA01AB1240');
      console.log('   2. Priya Sharma (priya.sharma@infosys.com) - Vehicle: KA01AB1240');
      console.log('   3. Amit Patel (amit.patel@infosys.com) - Vehicle: KA01AB1240');
      console.log('   4. Neha Gupta (neha.gupta@infosys.com) - No vehicle (SHOULD DELETE)');
      console.log('   5. Vikram Singh (vikram.singh@infosys.com) - No vehicle (SHOULD DELETE)');
      console.log('\n⚠️  PROBLEM: Only #4 and #5 should have been deleted!');
      console.log('   We need to RESTORE #1, #2, and #3');
    }
    
    // Check if these customers still exist in Firebase/users collection
    console.log('\n\n🔍 Checking if Infosys customers still exist in system...\n');
    
    const customers = await db.collection('users')
      .find({
        email: { $regex: '@infosys\\.com', $options: 'i' },
        role: 'customer'
      })
      .toArray();
    
    console.log(`📊 Found ${customers.length} Infosys customers in users collection:\n`);
    customers.forEach((customer, index) => {
      console.log(`${index + 1}. ${customer.name} (${customer.email})`);
    });
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

checkDeletedRosters();
