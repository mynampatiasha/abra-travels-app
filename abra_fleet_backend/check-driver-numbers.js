const { MongoClient } = require('mongodb');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

async function checkDriverNumbers() {
  const mongoUri = process.env.MONGODB_URI || 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';
  const client = new MongoClient(mongoUri);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    // Get all drivers
    const drivers = await db.collection('drivers').find({}).toArray();
    
    console.log('\n📋 DRIVER LIST - Checking Driver Numbers vs Employee Numbers:\n');
    console.log('Total Drivers:', drivers.length);
    console.log('='.repeat(80));
    
    drivers.forEach((driver, index) => {
      const firstName = driver.personalInfo?.firstName || 'N/A';
      const lastName = driver.personalInfo?.lastName || 'N/A';
      const driverId = driver.driverId || 'N/A';
      const employeeId = driver.employment?.employeeId || 'N/A';
      
      console.log(`\n${index + 1}. ${firstName} ${lastName}`);
      console.log(`   Driver ID: ${driverId}`);
      console.log(`   Employee ID: ${employeeId}`);
      
      // Check if driverId matches employeeId (indicating it might be using employee number)
      if (driverId === employeeId) {
        console.log(`   ⚠️  WARNING: Driver ID matches Employee ID!`);
      }
    });
    
    console.log('\n' + '='.repeat(80));
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

checkDriverNumbers();
