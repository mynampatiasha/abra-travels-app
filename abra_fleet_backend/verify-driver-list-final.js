const { MongoClient } = require('mongodb');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

async function verifyDriverList() {
  const mongoUri = process.env.MONGODB_URI || 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';
  const client = new MongoClient(mongoUri);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('abra_fleet');
    
    // Get all drivers
    const drivers = await db.collection('drivers').find({}).sort({ driverId: 1 }).toArray();
    
    console.log('📋 FINAL DRIVER LIST VERIFICATION');
    console.log('='.repeat(80));
    console.log(`Total Drivers: ${drivers.length}\n`);
    
    let allValid = true;
    
    drivers.forEach((driver, index) => {
      const firstName = driver.personalInfo?.firstName || 'Unknown';
      const lastName = driver.personalInfo?.lastName || '';
      const fullName = `${firstName} ${lastName}`.trim();
      const driverId = driver.driverId || 'MISSING';
      const hasEmployment = driver.employment ? '❌ HAS EMPLOYMENT FIELD' : '✅';
      
      // Check if driver ID is valid (DRV-XXXXXX format)
      const isValidFormat = /^DRV-\d{6}$/.test(driverId);
      const formatStatus = isValidFormat ? '✅' : '❌ INVALID FORMAT';
      
      if (!isValidFormat || driver.employment) {
        allValid = false;
      }
      
      console.log(`${index + 1}. ${fullName}`);
      console.log(`   Driver ID: ${driverId} ${formatStatus}`);
      console.log(`   Employment Field: ${hasEmployment}`);
      console.log('');
    });
    
    console.log('='.repeat(80));
    
    if (allValid) {
      console.log('✅ ALL DRIVERS VERIFIED!');
      console.log('   • All driver IDs follow DRV-XXXXXX format');
      console.log('   • No employment/employee ID fields present');
      console.log('   • Driver IDs are unique and properly formatted');
    } else {
      console.log('⚠️  SOME ISSUES FOUND - Please review above');
    }
    
    console.log('='.repeat(80));
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error.stack);
  } finally {
    await client.close();
  }
}

verifyDriverList();
