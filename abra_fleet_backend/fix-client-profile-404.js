// fix-client-profile-404.js - Fix the client profile 404 error
require('dotenv').config();
const { MongoClient, ObjectId } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function fixClientProfile() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db();
    
    console.log('═'.repeat(80));
    console.log('🔧 FIXING CLIENT PROFILE 404 ERROR');
    console.log('═'.repeat(80));
    
    // Find the problematic user in admin_users
    const adminUser = await db.collection('admin_users').findOne({
      email: 'client123@abrafleet.com'
    });
    
    if (!adminUser) {
      console.log('❌ User not found in admin_users');
      return;
    }
    
    console.log('\n✅ Found user in admin_users:');
    console.log('   Email:', adminUser.email);
    console.log('   Name:', adminUser.name);
    console.log('   Role:', adminUser.role);
    
    // Check if profile already exists
    const existingProfile = await db.collection('clients').findOne({
      email: adminUser.email.toLowerCase()
    });
    
    if (existingProfile) {
      console.log('\n✅ Profile already exists in clients collection');
      console.log('   No action needed!');
      return;
    }
    
    console.log('\n❌ No matching profile in clients collection');
    console.log('   Creating new profile...');
    
    // Create matching profile in clients collection
    const newClientProfile = {
      email: adminUser.email.toLowerCase(),
      name: adminUser.name || 'Abhishek',
      role: 'client',
      phone: adminUser.phone || adminUser.phoneNumber || '',
      phoneNumber: adminUser.phoneNumber || adminUser.phone || '',
      organizationName: adminUser.organizationName || adminUser.companyName || 'Abra Fleet',
      companyName: adminUser.companyName || adminUser.organizationName || 'Abra Fleet',
      address: adminUser.address || '',
      contactPerson: adminUser.contactPerson || adminUser.name || 'Abhishek',
      branch: adminUser.branch || '',
      department: adminUser.department || '',
      gstNumber: adminUser.gstNumber || null,
      panNumber: adminUser.panNumber || null,
      status: adminUser.status || 'active',
      modules: adminUser.modules || [],
      permissions: adminUser.permissions || {},
      totalCustomers: 0,
      location: adminUser.location || {
        country: '',
        state: '',
        city: '',
        area: ''
      },
      documents: adminUser.documents || [],
      createdAt: adminUser.createdAt || new Date(),
      updatedAt: new Date(),
      lastActive: new Date()
    };
    
    const result = await db.collection('clients').insertOne(newClientProfile);
    
    console.log('\n✅ Created new client profile:');
    console.log('   ID:', result.insertedId);
    console.log('   Email:', newClientProfile.email);
    console.log('   Name:', newClientProfile.name);
    
    // Update admin_users record with clientId reference
    await db.collection('admin_users').updateOne(
      { _id: adminUser._id },
      { 
        $set: { 
          clientId: result.insertedId.toString(),
          updatedAt: new Date()
        } 
      }
    );
    
    console.log('\n✅ Updated admin_users record with clientId reference');
    
    console.log('\n' + '═'.repeat(80));
    console.log('✅ FIX COMPLETE!');
    console.log('═'.repeat(80));
    console.log('\nThe client can now:');
    console.log('   1. Login with: client123@abrafleet.com');
    console.log('   2. View their profile successfully');
    console.log('   3. Access all client features');
    console.log('\n💡 Next step: Restart the backend and test the profile page');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

fixClientProfile();
