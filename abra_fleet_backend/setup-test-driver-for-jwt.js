// setup-test-driver-for-jwt.js - Setup Test Driver for JWT Testing
const { MongoClient } = require('mongodb');
const bcrypt = require('bcryptjs');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI;

async function setupTestDriver() {
  console.log('\n🔧 SETTING UP TEST DRIVER FOR JWT TESTING');
  console.log('═'.repeat(80));
  
  let client;
  
  try {
    // Connect to MongoDB
    console.log('📡 Connecting to MongoDB...');
    client = new MongoClient(MONGODB_URI);
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('✅ Connected to MongoDB');
    console.log('─'.repeat(80));
    
    // ========================================================================
    // STEP 1: Find Existing Driver
    // ========================================================================
    console.log('\n📂 STEP 1: FINDING EXISTING DRIVER');
    console.log('─'.repeat(40));
    
    const existingDriver = await db.collection('drivers').findOne({
      email: 'amit.singh@abrafleet.com'
    });
    
    if (existingDriver) {
      console.log('✅ Found existing driver:');
      console.log(`   _id: ${existingDriver._id}`);
      console.log(`   driverId: ${existingDriver.driverId}`);
      console.log(`   email: ${existingDriver.email || existingDriver.personalInfo?.email}`);
      console.log(`   name: ${existingDriver.name || existingDriver.personalInfo?.firstName}`);
      console.log(`   current password: ${existingDriver.password ? 'SET' : 'NOT SET'}`);
    } else {
      console.log('❌ Driver not found');
      return;
    }
    
    // ========================================================================
    // STEP 2: Set Known Password
    // ========================================================================
    console.log('\n\n🔑 STEP 2: SETTING KNOWN PASSWORD');
    console.log('─'.repeat(40));
    
    const testPassword = 'password123';
    console.log(`   Setting password: ${testPassword}`);
    
    // Hash the password
    const hashedPassword = await bcrypt.hash(testPassword, 12);
    console.log('   Password hashed successfully');
    
    // Update the driver with the new password
    const updateResult = await db.collection('drivers').updateOne(
      { _id: existingDriver._id },
      { 
        $set: { 
          password: hashedPassword,
          email: 'amit.singh@abrafleet.com', // Ensure email is set
          name: existingDriver.name || existingDriver.personalInfo?.firstName || 'Amit Singh',
          role: 'driver',
          status: 'active',
          isActive: true,
          updatedAt: new Date()
        } 
      }
    );
    
    console.log(`✅ Updated driver password (${updateResult.modifiedCount} document modified)`);
    
    // ========================================================================
    // STEP 3: Verify Driver Setup
    // ========================================================================
    console.log('\n\n✅ STEP 3: VERIFYING DRIVER SETUP');
    console.log('─'.repeat(40));
    
    const verifiedDriver = await db.collection('drivers').findOne({
      _id: existingDriver._id
    });
    
    console.log('Driver verification:');
    console.log(`   _id: ${verifiedDriver._id}`);
    console.log(`   driverId: ${verifiedDriver.driverId}`);
    console.log(`   email: ${verifiedDriver.email}`);
    console.log(`   name: ${verifiedDriver.name}`);
    console.log(`   role: ${verifiedDriver.role}`);
    console.log(`   password: ${verifiedDriver.password ? 'HASHED' : 'NOT SET'}`);
    console.log(`   status: ${verifiedDriver.status}`);
    console.log(`   isActive: ${verifiedDriver.isActive}`);
    
    // ========================================================================
    // STEP 4: Test Password Verification
    // ========================================================================
    console.log('\n\n🧪 STEP 4: TESTING PASSWORD VERIFICATION');
    console.log('─'.repeat(40));
    
    const passwordMatch = await bcrypt.compare(testPassword, verifiedDriver.password);
    console.log(`   Password verification: ${passwordMatch ? '✅ MATCH' : '❌ NO MATCH'}`);
    
    // ========================================================================
    // STEP 5: Setup Admin User for Testing
    // ========================================================================
    console.log('\n\n👑 STEP 5: SETTING UP ADMIN USER');
    console.log('─'.repeat(40));
    
    const adminEmail = 'admin@abrafleet.com';
    const adminPassword = 'admin123';
    
    const existingAdmin = await db.collection('admin_users').findOne({
      email: adminEmail
    });
    
    if (existingAdmin) {
      console.log('✅ Admin user already exists, updating password...');
      
      const hashedAdminPassword = await bcrypt.hash(adminPassword, 12);
      
      await db.collection('admin_users').updateOne(
        { _id: existingAdmin._id },
        { 
          $set: { 
            password: hashedAdminPassword,
            email: adminEmail,
            name: 'System Administrator',
            role: 'admin',
            status: 'active',
            isActive: true,
            updatedAt: new Date()
          } 
        }
      );
      
      console.log('✅ Admin password updated');
    } else {
      console.log('Creating new admin user...');
      
      const hashedAdminPassword = await bcrypt.hash(adminPassword, 12);
      
      const newAdmin = {
        email: adminEmail,
        password: hashedAdminPassword,
        name: 'System Administrator',
        role: 'admin',
        status: 'active',
        isActive: true,
        modules: ['fleet', 'drivers', 'routes', 'customers', 'billing', 'users', 'system'],
        permissions: {},
        createdAt: new Date(),
        updatedAt: new Date()
      };
      
      const insertResult = await db.collection('admin_users').insertOne(newAdmin);
      console.log(`✅ Admin user created with ID: ${insertResult.insertedId}`);
    }
    
    // ========================================================================
    // STEP 6: Test Credentials Summary
    // ========================================================================
    console.log('\n\n📋 TEST CREDENTIALS SUMMARY');
    console.log('═'.repeat(80));
    
    console.log('🚗 DRIVER CREDENTIALS:');
    console.log(`   Email: amit.singh@abrafleet.com`);
    console.log(`   Password: password123`);
    console.log(`   Driver ID: ${verifiedDriver.driverId}`);
    console.log(`   Role: driver`);
    
    console.log('\n👑 ADMIN CREDENTIALS:');
    console.log(`   Email: admin@abrafleet.com`);
    console.log(`   Password: admin123`);
    console.log(`   Role: admin`);
    
    console.log('\n🧪 READY FOR JWT TESTING!');
    console.log('   You can now run: node test-jwt-with-driver-id.js');
    console.log('═'.repeat(80));
    
  } catch (error) {
    console.error('\n❌ ERROR SETTING UP TEST DRIVER');
    console.error('═'.repeat(80));
    console.error('Error:', error.message);
    console.error('Stack:', error.stack);
  } finally {
    if (client) {
      await client.close();
      console.log('📡 MongoDB connection closed');
    }
  }
}

// Run the setup
if (require.main === module) {
  setupTestDriver().catch(console.error);
}

module.exports = { setupTestDriver };