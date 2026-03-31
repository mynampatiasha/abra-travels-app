const mongoose = require('mongoose');
const AdminUser = require('./models/AdminUser');

async function checkAdminBillingPermissions() {
  try {
    console.log('🔍 Checking admin user billing permissions...\n');
    
    // Connect to MongoDB
    await mongoose.connect('mongodb://localhost:27017/abra_fleet_management', {
      useNewUrlParser: true,
      useUnifiedTopology: true
    });
    
    console.log('✅ Connected to MongoDB');
    
    // Find admin user
    const adminEmail = 'admin@abrafleet.com';
    const adminUser = await AdminUser.findOne({ email: adminEmail });
    
    if (!adminUser) {
      console.log('❌ Admin user not found');
      return;
    }
    
    console.log('📋 Admin User Details:');
    console.log('   Email:', adminUser.email);
    console.log('   Role:', adminUser.role);
    console.log('   Active:', adminUser.isActive);
    console.log('   Firebase UID:', adminUser.firebaseUid);
    
    console.log('\n🔐 Permissions:');
    if (adminUser.permissions) {
      if (adminUser.permissions instanceof Map) {
        console.log('   Permissions (Map):');
        for (const [key, value] of adminUser.permissions) {
          console.log(`     ${key}: ${value}`);
        }
      } else {
        console.log('   Permissions (Object):');
        Object.entries(adminUser.permissions).forEach(([key, value]) => {
          console.log(`     ${key}: ${value}`);
        });
      }
    } else {
      console.log('   No permissions found');
    }
    
    // Check specific billing permission
    console.log('\n🧾 Billing Permission Check:');
    const hasBilling = adminUser.hasPermission ? adminUser.hasPermission('billing') : false;
    console.log('   Has billing permission:', hasBilling);
    
    // Check if super admin
    if (adminUser.role === 'super_admin') {
      console.log('   ✅ Super admin - should have access to all features');
    }
    
    // Check for billing-related permissions
    if (adminUser.permissions) {
      const permissions = adminUser.permissions instanceof Map 
        ? Array.from(adminUser.permissions.keys())
        : Object.keys(adminUser.permissions);
      
      const billingPerms = permissions.filter(p => 
        p.includes('billing') || p.includes('invoice') || p.includes('payment')
      );
      
      console.log('   Billing-related permissions:', billingPerms);
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await mongoose.disconnect();
    console.log('\n🔌 Disconnected from MongoDB');
  }
}

checkAdminBillingPermissions();