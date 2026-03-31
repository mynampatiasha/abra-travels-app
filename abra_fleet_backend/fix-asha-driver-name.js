// Fix Asha driver name - should be "Vikyath M" not "Asha Mynampati"
const { MongoClient } = require('mongodb');

const MONGODB_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function fixAshaDriverName() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('\n🔍 CHECKING DRIVER WITH EMAIL: ashamynampati2003@gmail.com');
    console.log('='.repeat(60));
    
    // Find driver by email
    const driver = await db.collection('drivers').findOne({
      email: 'ashamynampati2003@gmail.com'
    });
    
    if (!driver) {
      console.log('❌ Driver not found!');
      return;
    }
    
    console.log('\n📋 CURRENT DRIVER DATA:');
    console.log(`   Name: ${driver.name}`);
    console.log(`   Email: ${driver.email}`);
    console.log(`   Driver Code: ${driver.driverCode}`);
    console.log(`   MongoDB _id: ${driver._id}`);
    console.log(`   Firebase UID: ${driver.uid}`);
    
    // Update name to Vikyath M
    console.log('\n🔧 UPDATING NAME TO: Vikyath M');
    
    const result = await db.collection('drivers').updateOne(
      { email: 'ashamynampati2003@gmail.com' },
      { 
        $set: { 
          name: 'Vikyath M',
          updatedAt: new Date()
        } 
      }
    );
    
    if (result.modifiedCount > 0) {
      console.log('✅ Driver name updated successfully!');
      
      // Verify update
      const updatedDriver = await db.collection('drivers').findOne({
        email: 'ashamynampati2003@gmail.com'
      });
      
      console.log('\n✅ UPDATED DRIVER DATA:');
      console.log(`   Name: ${updatedDriver.name}`);
      console.log(`   Email: ${updatedDriver.email}`);
      console.log(`   Driver Code: ${updatedDriver.driverCode}`);
    } else {
      console.log('⚠️  No changes made');
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

fixAshaDriverName();
