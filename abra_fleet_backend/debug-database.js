// Debug script to inspect actual database content
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function inspectDatabase() {
  let client;
  
  try {
    console.log('🔍 Connecting to MongoDB...');
    client = new MongoClient(process.env.MONGODB_URI);
    await client.connect();
    
    const db = client.db('abra_fleet');
    const rostersCollection = db.collection('rosters');
    
    console.log('📊 Fetching sample rosters...');
    
    // Get total count
    const totalCount = await rostersCollection.countDocuments();
    console.log(`Total rosters in database: ${totalCount}`);
    
    // Get sample rosters
    const sampleRosters = await rostersCollection.find({}).limit(3).toArray();
    
    console.log('\n' + '='.repeat(80));
    console.log('📋 SAMPLE ROSTER DOCUMENTS:');
    console.log('='.repeat(80));
    
    sampleRosters.forEach((roster, index) => {
      console.log(`\n--- ROSTER ${index + 1} ---`);
      console.log('ID:', roster._id);
      console.log('All Keys:', Object.keys(roster));
      
      console.log('\n🏷️ NAME FIELDS:');
      console.log('  customerName:', roster.customerName);
      console.log('  employeeName:', roster.employeeName);
      
      console.log('\n📧 EMAIL FIELDS:');
      console.log('  customerEmail:', roster.customerEmail);
      console.log('  email:', roster.email);
      
      console.log('\n👤 EMPLOYEE DETAILS:');
      console.log('  employeeDetails:', roster.employeeDetails);
      console.log('  employeeDetails type:', typeof roster.employeeDetails);
      if (roster.employeeDetails) {
        console.log('  employeeDetails keys:', Object.keys(roster.employeeDetails));
      }
      
      console.log('\n👥 EMPLOYEE DATA:');
      console.log('  employeeData:', roster.employeeData);
      console.log('  employeeData type:', typeof roster.employeeData);
      if (roster.employeeData) {
        console.log('  employeeData keys:', Object.keys(roster.employeeData));
      }
      
      console.log('\n🏢 OTHER FIELDS:');
      console.log('  officeLocation:', roster.officeLocation);
      console.log('  rosterType:', roster.rosterType);
      console.log('  status:', roster.status);
      console.log('  createdAt:', roster.createdAt);
      console.log('  createdBy:', roster.createdBy);
      console.log('  createdByAdmin:', roster.createdByAdmin);
      
      console.log('\n📄 FULL DOCUMENT:');
      console.log(JSON.stringify(roster, null, 2));
      console.log('\n' + '-'.repeat(50));
    });
    
    // Check for rosters with specific status
    console.log('\n🔍 Checking rosters by status...');
    const pendingCount = await rostersCollection.countDocuments({ 
      status: { $in: ['pending_assignment', 'pending', 'created'] } 
    });
    console.log(`Pending rosters: ${pendingCount}`);
    
    const allStatuses = await rostersCollection.distinct('status');
    console.log('All status values in database:', allStatuses);
    
  } catch (error) {
    console.error('❌ Database inspection failed:', error);
  } finally {
    if (client) {
      await client.close();
      console.log('✅ Database connection closed');
    }
  }
}

inspectDatabase();