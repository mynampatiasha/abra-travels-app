// Script to check what phone number data exists in rosters
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function checkPhoneData() {
  let client;
  
  try {
    console.log('🔍 Connecting to MongoDB...');
    client = new MongoClient(process.env.MONGODB_URI);
    await client.connect();
    
    const db = client.db('abra_fleet');
    
    console.log('📊 Checking phone number fields in rosters...');
    
    // Get a few sample rosters to see what fields exist
    const sampleRosters = await db.collection('rosters').find({}).limit(5).toArray();
    
    console.log(`📋 Found ${sampleRosters.length} sample rosters`);
    
    sampleRosters.forEach((roster, index) => {
      console.log(`\n--- ROSTER ${index + 1} ---`);
      console.log('ID:', roster._id);
      console.log('All Keys:', Object.keys(roster));
      
      // Check for phone-related fields
      console.log('\n📱 PHONE FIELDS:');
      const phoneFields = ['phone', 'phoneNumber', 'employeePhone', 'customerPhone', 'mobile'];
      phoneFields.forEach(field => {
        if (roster[field]) {
          console.log(`  ✅ ${field}: ${roster[field]}`);
        } else {
          console.log(`  ❌ ${field}: not found`);
        }
      });
      
      // Check nested employee data
      if (roster.employeeDetails) {
        console.log('\n👤 EMPLOYEE DETAILS PHONE:');
        console.log('  employeeDetails:', roster.employeeDetails);
        phoneFields.forEach(field => {
          if (roster.employeeDetails[field]) {
            console.log(`  ✅ employeeDetails.${field}: ${roster.employeeDetails[field]}`);
          }
        });
      }
      
      if (roster.employeeData) {
        console.log('\n👥 EMPLOYEE DATA PHONE:');
        console.log('  employeeData:', roster.employeeData);
        phoneFields.forEach(field => {
          if (roster.employeeData[field]) {
            console.log(`  ✅ employeeData.${field}: ${roster.employeeData[field]}`);
          }
        });
      }
      
      // Check if there are any fields containing 'phone' or 'mobile'
      console.log('\n🔍 ALL FIELDS CONTAINING "PHONE" OR "MOBILE":');
      Object.keys(roster).forEach(key => {
        if (key.toLowerCase().includes('phone') || key.toLowerCase().includes('mobile')) {
          console.log(`  📱 ${key}: ${roster[key]}`);
        }
      });
    });
    
    // Check if phone numbers exist in the users collection (employees)
    console.log('\n📊 Checking phone numbers in users collection...');
    const sampleUsers = await db.collection('users').find({}).limit(3).toArray();
    
    sampleUsers.forEach((user, index) => {
      console.log(`\n--- USER ${index + 1} ---`);
      console.log('Email:', user.email);
      console.log('Name:', user.name);
      console.log('All Keys:', Object.keys(user));
      
      const phoneFields = ['phone', 'phoneNumber', 'mobile', 'contactNumber'];
      phoneFields.forEach(field => {
        if (user[field]) {
          console.log(`  ✅ ${field}: ${user[field]}`);
        }
      });
    });
    
  } catch (error) {
    console.error('❌ Error checking phone data:', error);
  } finally {
    if (client) {
      await client.close();
      console.log('✅ Database connection closed');
    }
  }
}

checkPhoneData();