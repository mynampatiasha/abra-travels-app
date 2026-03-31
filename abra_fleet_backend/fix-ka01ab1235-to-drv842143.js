// Fix KA01AB1235 to use driver DRV-842143 (John Doe)
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function fixVehicleDriver() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    
    // Find driver DRV-842143 in drivers collection
    const driver = await db.collection('drivers').findOne({
      driverId: 'DRV-842143'
    });
    
    if (!driver) {
      console.log('❌ Driver DRV-842143 not found');
      return;
    }
    
    console.log(`\n✅ Found driver DRV-842143:`);
    console.log(`   - Name: ${driver.personalInfo?.firstName} ${driver.personalInfo?.lastName}`);
    console.log(`   - Email: ${driver.personalInfo?.email}`);
    console.log(`   - Phone: ${driver.personalInfo?.phone}`);
    console.log(`   - Status: ${driver.status}`);
    
    // Update vehicle KA01AB1235
    const result = await db.collection('vehicles').updateOne(
      { registrationNumber: 'KA01AB1235' },
      {
        $set: {
          assignedDriver: 'DRV-842143',  // Store as string (driverId)
          updatedAt: new Date()
        }
      }
    );
    
    if (result.modifiedCount > 0) {
      console.log(`\n✅ SUCCESS! Vehicle KA01AB1235 updated`);
      console.log(`   - Now assigned to: DRV-842143 (John Doe)`);
      console.log(`   - The backend API will populate full driver details automatically`);
      
      // Verify
      const vehicle = await db.collection('vehicles').findOne({
        registrationNumber: 'KA01AB1235'
      });
      
      console.log(`\n📋 Verified vehicle data:`);
      console.log(`   - assignedDriver: ${vehicle.assignedDriver}`);
      console.log(`   - Capacity: ${vehicle.capacity?.passengers || vehicle.seatingCapacity} seats`);
      console.log(`   - Status: ${vehicle.status}`);
      
      console.log(`\n✅ Route optimization should now work!`);
    } else {
      console.log(`\n⚠️  No changes made (vehicle might already be correct)`);
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

fixVehicleDriver();
