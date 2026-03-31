#!/usr/bin/env node

/**
 * Fix Super Admin Access Issues
 * This script resolves the role-based access issues for super admin login
 */

const { MongoClient } = require('mongodb');
require('dotenv').config();

async function fixSuperAdminAccess() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    console.log('🔧 Connecting to MongoDB...');
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('✅ Connected to MongoDB');
    
    // 1. Check if super admin exists
    console.log('\n📋 Checking super admin user...');
    const superAdmin = await db.collection('admin_users').findOne({ 
      email: 'admin@abrafleet.com' 
    });
    
    if (!superAdmin) {
      console.log('❌ Super admin not found, creating...');
      
      // Create super admin user
      const newSuperAdmin = {
        name: 'Super Admin',
        email: 'admin@abrafleet.com',
        phone: '+1234567890',
        role: 'superAdmin',
        roleTitle: 'Super Admin',
        modules: ['fleet', 'drivers', 'routes', 'customers', 'billing', 'users', 'system', 'tracking', 'reports'],
        permissions: {
          'Fleet Management': ['view_all', 'add', 'edit', 'delete', 'assign', 'maintenance', 'analytics'],
          'Driver Management': ['view_all', 'add', 'edit', 'delete', 'documents', 'performance'],
          'Route Planning': ['view_all', 'create', 'edit', 'delete', 'optimize', 'analytics'],
          'Customer/Employee': ['view_all', 'bulk_ops', 'rosters', 'analytics'],
          'Billing & Finance': ['view_invoices', 'generate', 'payment_tracking', 'audit'],
          'System Administration': ['user_management', 'role_management', 'settings', 'api_access'],
          'Tracking': ['live_tracking', 'monitoring', 'delays'],
          'Reports': ['all_reports', 'analytics', 'export']
        },
        status: 'active',
        firebaseUid: null, // Will be updated when they login
        lastActive: new Date().toISOString(),
        createdAt: new Date(),
        updatedAt: new Date()
      };
      
      await db.collection('admin_users').insertOne(newSuperAdmin);
      console.log('✅ Super admin created');
    } else {
      console.log('✅ Super admin exists');
      
      // Update super admin permissions to ensure they have all modules
      const updateResult = await db.collection('admin_users').updateOne(
        { email: 'admin@abrafleet.com' },
        {
          $set: {
            role: 'superAdmin',
            roleTitle: 'Super Admin',
            modules: ['fleet', 'drivers', 'routes', 'customers', 'billing', 'users', 'system', 'tracking', 'reports'],
            permissions: {
              'Fleet Management': ['view_all', 'add', 'edit', 'delete', 'assign', 'maintenance', 'analytics'],
              'Driver Management': ['view_all', 'add', 'edit', 'delete', 'documents', 'performance'],
              'Route Planning': ['view_all', 'create', 'edit', 'delete', 'optimize', 'analytics'],
              'Customer/Employee': ['view_all', 'bulk_ops', 'rosters', 'analytics'],
              'Billing & Finance': ['view_invoices', 'generate', 'payment_tracking', 'audit'],
              'System Administration': ['user_management', 'role_management', 'settings', 'api_access'],
              'Tracking': ['live_tracking', 'monitoring', 'delays'],
              'Reports': ['all_reports', 'analytics', 'export']
            },
            status: 'active',
            updatedAt: new Date()
          }
        }
      );
      
      console.log('✅ Super admin permissions updated');
    }
    
    // 2. Check if Firebase user exists in users collection
    console.log('\n📋 Checking Firebase user mapping...');
    const firebaseUser = await db.collection('users').findOne({ 
      email: 'admin@abrafleet.com' 
    });
    
    if (!firebaseUser) {
      console.log('❌ Firebase user mapping not found, creating...');
      
      const newFirebaseUser = {
        email: 'admin@abrafleet.com',
        name: 'Super Admin',
        role: 'admin', // This is for Firebase auth compatibility
        fcmToken: null,
        createdAt: new Date(),
        updatedAt: new Date(),
        lastLogin: new Date(),
        isActive: true,
        firebaseUid: null // Will be updated on login
      };
      
      await db.collection('users').insertOne(newFirebaseUser);
      console.log('✅ Firebase user mapping created');
    } else {
      console.log('✅ Firebase user mapping exists');
      
      // Update to ensure admin role
      await db.collection('users').updateOne(
        { email: 'admin@abrafleet.com' },
        {
          $set: {
            role: 'admin',
            isActive: true,
            updatedAt: new Date()
          }
        }
      );
      console.log('✅ Firebase user mapping updated');
    }
    
    // 3. Create missing collections if they don't exist
    console.log('\n📋 Ensuring required collections exist...');
    
    const collections = [
      'admin_users',
      'users', 
      'vehicles',
      'drivers',
      'customers',
      'trips',
      'rosters',
      'notifications',
      'sos_events'
    ];
    
    for (const collectionName of collections) {
      try {
        await db.createCollection(collectionName);
        console.log(`✅ Collection '${collectionName}' ensured`);
      } catch (error) {
        if (error.code === 48) {
          console.log(`✅ Collection '${collectionName}' already exists`);
        } else {
          console.log(`⚠️  Collection '${collectionName}' error:`, error.message);
        }
      }
    }
    
    console.log('\n🎉 Super admin access fix completed!');
    console.log('\n📋 Summary:');
    console.log('   ✅ Super admin user configured');
    console.log('   ✅ Firebase user mapping configured');
    console.log('   ✅ All required collections ensured');
    console.log('   ✅ Full permissions granted to super admin');
    
    console.log('\n🔐 Login Credentials:');
    console.log('   Email: admin@abrafleet.com');
    console.log('   Password: admin123');
    console.log('   Role: Super Admin (all modules access)');
    
  } catch (error) {
    console.error('❌ Error fixing super admin access:', error);
  } finally {
    await client.close();
  }
}

// Run the fix
fixSuperAdminAccess().catch(console.error);