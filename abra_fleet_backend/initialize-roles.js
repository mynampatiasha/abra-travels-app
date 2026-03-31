// initialize-roles.js - Quick script to initialize Abra Travel roles
require('dotenv').config();
const mongoose = require('mongoose');
const Role = require('./models/Role');

const defaultRoles = [
  {
    id: 'superAdmin',
    title: 'Super Admin',
    icon: '👑',
    color: '#ff6b6b',
    permissions: {
      'Fleet Management': ['View all vehicles', 'Add/Edit/Delete vehicles', 'Assign vehicles to routes', 'Vehicle maintenance', 'Fleet analytics'],
      'Driver Management': ['View all drivers', 'Add/Edit/Delete drivers', 'Manage driver documents', 'Driver performance reports'],
      'Route Planning': ['View all routes', 'Create/Edit/Delete routes', 'Optimize routes', 'Route analytics'],
      'Customer/Employee': ['View all employees', 'Bulk operations', 'Manage rosters', 'Employee analytics'],
      'Billing & Finance': ['View all invoices', 'Generate invoices', 'Payment tracking', 'Audit reports'],
      'System Administration': ['User management', 'Role management', 'System settings', 'API access']
    }
  },
  {
    id: 'orgAdmin',
    title: 'Organization Admin',
    icon: '🏢',
    color: '#4ecdc4',
    permissions: {
      'Fleet Management': ['View all vehicles', 'Add/Edit vehicles', 'Assign vehicles', 'Fleet reports'],
      'Driver Management': ['View all drivers', 'Add/Edit drivers', 'Driver assignments'],
      'Route Planning': ['View all routes', 'Create/Edit routes', 'Route optimization'],
      'Customer/Employee': ['View employees', 'Manage rosters', 'Employee reports'],
      'User Management': ['Create users', 'Assign roles', 'Manage departments']
    }
  },
  {
    id: 'fleetManager',
    title: 'Fleet Manager',
    icon: '🚛',
    color: '#f093fb',
    permissions: {
      'Fleet Management': ['View vehicles', 'Add/Edit vehicles', 'Vehicle maintenance', 'Fleet reports'],
      'Driver Management': ['View drivers', 'Assign drivers', 'Driver performance'],
      'Route Planning': ['View routes', 'Vehicle-route assignment']
    }
  },
  {
    id: 'operations',
    title: 'Operations Manager',
    icon: '📊',
    color: '#4facfe',
    permissions: {
      'Route Planning': ['View routes', 'Create routes', 'Modify routes', 'Trip scheduling'],
      'Real-Time Tracking': ['Live tracking', 'Trip monitoring', 'Delay management'],
      'Driver Management': ['View drivers', 'Daily assignments']
    }
  },
  {
    id: 'hrManager',
    title: 'HR Manager',
    icon: '👥',
    color: '#43e97b',
    permissions: {
      'Customer/Employee': ['View employees', 'Manage rosters', 'Create schedules', 'Employee requests'],
      'Route Planning': ['View routes', 'Employee route assignment'],
      'Reports': ['Employee analytics', 'Attendance reports']
    }
  },
  {
    id: 'finance',
    title: 'Finance Admin',
    icon: '💰',
    color: '#30cfd0',
    permissions: {
      'Billing & Finance': ['View all invoices', 'Generate invoices', 'Payment tracking', 'Tax reports'],
      'Reports': ['Financial reports', 'Audit trails', 'Expense analysis']
    }
  }
];

async function initializeRoles() {
  try {
    console.log('\n🔧 Initializing Abra Travel Roles...');
    console.log('─'.repeat(80));
    
    // Connect to MongoDB
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected to MongoDB');
    
    // Delete existing roles
    const deleteResult = await Role.deleteMany({});
    console.log(`🗑️  Deleted ${deleteResult.deletedCount} existing roles`);
    
    // Insert default roles
    const insertResult = await Role.insertMany(defaultRoles);
    console.log(`✅ Inserted ${insertResult.length} new roles`);
    
    console.log('\n📋 Roles Created:');
    insertResult.forEach(role => {
      console.log(`   ${role.icon} ${role.title} (${role.id})`);
    });
    
    console.log('\n✅ Role initialization complete!');
    console.log('─'.repeat(80) + '\n');
    
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Error initializing roles:', error.message);
    console.error('─'.repeat(80) + '\n');
    process.exit(1);
  }
}

initializeRoles();
