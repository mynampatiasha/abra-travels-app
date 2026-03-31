const { MongoClient } = require('mongodb');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

async function cleanDriverEmploymentFields() {
  const mongoUri = process.env.MONGODB_URI || 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';
  const client = new MongoClient(mongoUri);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    // Find drivers that have employment field
    const driversWithEmployment = await db.collection('drivers').find({
      employment: { $exists: true }
    }).toArray();
    
    console.log(`\n🔍 Found ${driversWithEmployment.length} driver(s) with employment field\n`);
    
    if (driversWithEmployment.length === 0) {
      console.log('✅ No drivers have employment fields!');
      return;
    }
    
    console.log('📋 Drivers with employment fields:');
    console.log('='.repeat(80));
    
    driversWithEmployment.forEach((driver, index) => {
      const firstName = driver.personalInfo?.firstName || 'Unknown';
      const lastName = driver.personalInfo?.lastName || '';
      const fullName = `${firstName} ${lastName}`.trim();
      const employeeId = driver.employment?.employeeId || 'N/A';
      
      console.log(`\n${index + 1}. ${fullName}`);
      console.log(`   Driver ID: ${driver.driverId}`);
      console.log(`   Employee ID: ${employeeId}`);
    });
    
    console.log('\n' + '='.repeat(80));
    console.log('\n🧹 Removing employment fields from all drivers...\n');
    
    // Remove employment field from all drivers
    const result = await db.collection('drivers').updateMany(
      { employment: { $exists: true } },
      { 
        $unset: { employment: "" },
        $set: { updatedAt: new Date() }
      }
    );
    
    console.log(`✅ Removed employment field from ${result.modifiedCount} driver(s)`);
    console.log('\n' + '='.repeat(80));
    console.log('✅ Cleanup complete! Drivers no longer have employment/employee ID fields.');
    console.log('='.repeat(80));
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error.stack);
  } finally {
    await client.close();
  }
}

cleanDriverEmploymentFields();
