// Script to find rosters with employee data
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function findEmployeeRosters() {
  let client;
  
  try {
    console.log('🔍 Connecting to MongoDB...');
    client = new MongoClient(process.env.MONGODB_URI);
    await client.connect();
    
    const db = client.db('abra_fleet');
    const rostersCollection = db.collection('rosters');
    
    console.log('📊 Searching for rosters with employee data...');
    
    // Search for rosters with customerName
    const rostersWithCustomerName = await rostersCollection.find({
      customerName: { $exists: true, $ne: null, $ne: '' }
    }).limit(5).toArray();
    
    console.log(`Found ${rostersWithCustomerName.length} rosters with customerName`);
    
    // Search for rosters with employeeDetails
    const rostersWithEmployeeDetails = await rostersCollection.find({
      employeeDetails: { $exists: true, $ne: null }
    }).limit(5).toArray();
    
    console.log(`Found ${rostersWithEmployeeDetails.length} rosters with employeeDetails`);
    
    // Search for rosters with employeeData
    const rostersWithEmployeeData = await rostersCollection.find({
      employeeData: { $exists: true, $ne: null }
    }).limit(5).toArray();
    
    console.log(`Found ${rostersWithEmployeeData.length} rosters with employeeData`);
    
    // Search for rosters created by admin (bulk import)
    const rostersWithAdmin = await rostersCollection.find({
      createdByAdmin: { $exists: true, $ne: null }
    }).limit(5).toArray();
    
    console.log(`Found ${rostersWithAdmin.length} rosters with createdByAdmin`);
    
    // Show any rosters with employee data
    if (rostersWithCustomerName.length > 0) {
      console.log('\n📋 ROSTERS WITH CUSTOMER NAME:');
      rostersWithCustomerName.forEach((roster, index) => {
        console.log(`--- Roster ${index + 1} ---`);
        console.log('ID:', roster._id);
        console.log('customerName:', roster.customerName);
        console.log('customerEmail:', roster.customerEmail);
        console.log('employeeDetails:', roster.employeeDetails);
        console.log('createdByAdmin:', roster.createdByAdmin);
        console.log('status:', roster.status);
      });
    }
    
    if (rostersWithEmployeeDetails.length > 0) {
      console.log('\n📋 ROSTERS WITH EMPLOYEE DETAILS:');
      rostersWithEmployeeDetails.forEach((roster, index) => {
        console.log(`--- Roster ${index + 1} ---`);
        console.log('ID:', roster._id);
        console.log('employeeDetails:', JSON.stringify(roster.employeeDetails, null, 2));
        console.log('status:', roster.status);
      });
    }
    
    // Check recent rosters (last 24 hours)
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    
    const recentRosters = await rostersCollection.find({
      createdAt: { $gte: yesterday }
    }).sort({ createdAt: -1 }).limit(10).toArray();
    
    console.log(`\n📅 Found ${recentRosters.length} rosters created in last 24 hours`);
    
    if (recentRosters.length > 0) {
      console.log('\n📋 RECENT ROSTERS:');
      recentRosters.forEach((roster, index) => {
        console.log(`--- Recent Roster ${index + 1} ---`);
        console.log('ID:', roster._id);
        console.log('createdAt:', roster.createdAt);
        console.log('customerName:', roster.customerName);
        console.log('customerEmail:', roster.customerEmail);
        console.log('employeeDetails exists:', !!roster.employeeDetails);
        console.log('employeeData exists:', !!roster.employeeData);
        console.log('createdByAdmin:', roster.createdByAdmin);
        console.log('status:', roster.status);
      });
    }
    
  } catch (error) {
    console.error('❌ Search failed:', error);
  } finally {
    if (client) {
      await client.close();
      console.log('✅ Database connection closed');
    }
  }
}

findEmployeeRosters();