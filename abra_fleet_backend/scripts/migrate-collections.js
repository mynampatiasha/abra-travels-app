// scripts/migrate-collections.js
// ============================================================================
// MIGRATION SCRIPT - Separate admin_users into proper collections
// ============================================================================
// Run with: node scripts/migrate-collections.js
// Dry run: node scripts/migrate-collections.js --dry-run

const mongoose = require('mongoose');
require('dotenv').config();

const DRY_RUN = process.argv.includes('--dry-run');

// MongoDB connection string
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/your_database';

async function migrate() {
  console.log('\n╔══════════════════════════════════════════════════════════════════════════════╗');
  console.log('║                   COLLECTION MIGRATION SCRIPT                                 ║');
  console.log('╚══════════════════════════════════════════════════════════════════════════════╝\n');
  
  if (DRY_RUN) {
    console.log('🧪 DRY RUN MODE - No changes will be made to the database');
    console.log('   Remove --dry-run flag to perform actual migration\n');
  } else {
    console.log('⚠️  LIVE MODE - Changes will be made to the database');
    console.log('   Press Ctrl+C within 5 seconds to cancel...\n');
    await new Promise(resolve => setTimeout(resolve, 5000));
  }

  try {
    // Connect to MongoDB
    console.log('📡 Connecting to MongoDB...');
    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB\n');

    const db = mongoose.connection.db;

    // ========================================================================
    // STEP 1: Analyze current admin_users collection
    // ========================================================================
    console.log('═'.repeat(80));
    console.log('STEP 1: Analyzing admin_users collection');
    console.log('═'.repeat(80));

    const adminUsers = await db.collection('admin_users').find({}).toArray();
    console.log(`Found ${adminUsers.length} total users in admin_users\n`);

    // Group by role
    const usersByRole = {};
    adminUsers.forEach(user => {
      const role = user.role || 'unknown';
      if (!usersByRole[role]) {
        usersByRole[role] = [];
      }
      usersByRole[role].push(user);
    });

    console.log('Users by role:');
    Object.entries(usersByRole).forEach(([role, users]) => {
      console.log(`  ${role}: ${users.length} users`);
    });
    console.log('');

    // ========================================================================
    // STEP 2: Define migration mapping
    // ========================================================================
    console.log('═'.repeat(80));
    console.log('STEP 2: Migration mapping');
    console.log('═'.repeat(80));

    const migrationPlan = {
      employee_admins: ['employee', 'super_admin', 'admin', 'hr_manager', 'hrManager', 
                        'fleet_manager', 'fleetManager', 'finance', 'operations', 
                        'org_admin', 'superAdmin'],
      drivers: ['driver'],
      customers: ['customer'],
      clients: ['client']
    };

    console.log('Migration plan:');
    Object.entries(migrationPlan).forEach(([collection, roles]) => {
      console.log(`  ${collection} ← ${roles.join(', ')}`);
    });
    console.log('');

    // ========================================================================
    // STEP 3: Count users to migrate
    // ========================================================================
    console.log('═'.repeat(80));
    console.log('STEP 3: Counting users to migrate');
    console.log('═'.repeat(80));

    const migrationCounts = {
      employee_admins: 0,
      drivers: 0,
      customers: 0,
      clients: 0,
      unknown: 0
    };

    adminUsers.forEach(user => {
      const role = user.role || 'unknown';
      let found = false;

      for (const [targetCollection, roles] of Object.entries(migrationPlan)) {
        if (roles.includes(role)) {
          migrationCounts[targetCollection]++;
          found = true;
          break;
        }
      }

      if (!found) {
        migrationCounts.unknown++;
        console.log(`  ⚠️  Unknown role: ${role} (user: ${user.email})`);
      }
    });

    console.log('\nMigration counts:');
    Object.entries(migrationCounts).forEach(([collection, count]) => {
      console.log(`  ${collection}: ${count} users`);
    });
    console.log('');

    // ========================================================================
    // STEP 4: Perform migration
    // ========================================================================
    console.log('═'.repeat(80));
    console.log('STEP 4: Performing migration');
    console.log('═'.repeat(80));

    if (DRY_RUN) {
      console.log('🧪 DRY RUN - Skipping actual migration\n');
    } else {
      // Migrate employee admins
      console.log('\n📝 Migrating to employee_admins...');
      const employeeRoles = migrationPlan.employee_admins;
      const employeesToMigrate = adminUsers.filter(u => employeeRoles.includes(u.role));
      
      if (employeesToMigrate.length > 0) {
        // Transform data for employee_admins collection
        const employeeDocs = employeesToMigrate.map(user => ({
          name_parson: user.name || user.name_parson || user.email.split('@')[0],
          name: user.name || user.email.split('@')[0],
          email: user.email,
          phone: user.phone || '',
          pwd: user.password || user.pwd || '$2a$10$placeholder', // Placeholder if no password
          firebaseUid: user.firebaseUid,
          role: user.role === 'superAdmin' ? 'super_admin' : 
                user.role === 'hrManager' ? 'hr_manager' :
                user.role === 'fleetManager' ? 'fleet_manager' : user.role,
          isActive: user.isActive !== false && (!user.status || user.status === 'active'),
          permissions: new Map(Object.entries(user.permissions || {})),
          office: user.office || '',
          department: user.department || '',
          createdBy: user.createdBy,
          lastLogin: user.lastLogin || user.lastActive,
          loginAttempts: 0,
          createdAt: user.createdAt || new Date(),
          updatedAt: user.updatedAt || new Date()
        }));

        await db.collection('employee_admins').insertMany(employeeDocs);
        console.log(`  ✅ Migrated ${employeeDocs.length} employees to employee_admins`);
      } else {
        console.log(`  ℹ️  No employees to migrate`);
      }

      // Migrate drivers
      console.log('\n📝 Checking drivers collection...');
      const driverUsers = adminUsers.filter(u => u.role === 'driver');
      
      if (driverUsers.length > 0) {
        // Check if drivers already exist in drivers collection
        const existingDrivers = await db.collection('drivers').find({}).toArray();
        const existingDriverEmails = new Set(existingDrivers.map(d => d.email));
        
        const driversToAdd = driverUsers.filter(u => !existingDriverEmails.has(u.email));
        
        if (driversToAdd.length > 0) {
          await db.collection('drivers').insertMany(driversToAdd.map(user => ({
            ...user,
            _id: undefined, // Remove old _id
            createdAt: user.createdAt || new Date(),
            updatedAt: user.updatedAt || new Date()
          })));
          console.log(`  ✅ Added ${driversToAdd.length} drivers to drivers collection`);
        } else {
          console.log(`  ℹ️  All drivers already exist in drivers collection`);
        }
      } else {
        console.log(`  ℹ️  No drivers to migrate`);
      }

      // Migrate customers
      console.log('\n📝 Checking customers collection...');
      const customerUsers = adminUsers.filter(u => u.role === 'customer');
      
      if (customerUsers.length > 0) {
        const existingCustomers = await db.collection('customers').find({}).toArray();
        const existingCustomerEmails = new Set(existingCustomers.map(c => c.email));
        
        const customersToAdd = customerUsers.filter(u => !existingCustomerEmails.has(u.email));
        
        if (customersToAdd.length > 0) {
          await db.collection('customers').insertMany(customersToAdd.map(user => ({
            ...user,
            _id: undefined,
            createdAt: user.createdAt || new Date(),
            updatedAt: user.updatedAt || new Date()
          })));
          console.log(`  ✅ Added ${customersToAdd.length} customers to customers collection`);
        } else {
          console.log(`  ℹ️  All customers already exist in customers collection`);
        }
      } else {
        console.log(`  ℹ️  No customers to migrate`);
      }

      // Migrate clients
      console.log('\n📝 Checking clients collection...');
      const clientUsers = adminUsers.filter(u => u.role === 'client');
      
      if (clientUsers.length > 0) {
        const existingClients = await db.collection('clients').find({}).toArray();
        const existingClientEmails = new Set(existingClients.map(c => c.email));
        
        const clientsToAdd = clientUsers.filter(u => !existingClientEmails.has(u.email));
        
        if (clientsToAdd.length > 0) {
          await db.collection('clients').insertMany(clientsToAdd.map(user => ({
            ...user,
            _id: undefined,
            createdAt: user.createdAt || new Date(),
            updatedAt: user.updatedAt || new Date()
          })));
          console.log(`  ✅ Added ${clientsToAdd.length} clients to clients collection`);
        } else {
          console.log(`  ℹ️  All clients already exist in clients collection`);
        }
      } else {
        console.log(`  ℹ️  No clients to migrate`);
      }

      console.log('\n✅ Migration completed successfully!');
    }

    // ========================================================================
    // STEP 5: Verification
    // ========================================================================
    console.log('\n═'.repeat(80));
    console.log('STEP 5: Verification');
    console.log('═'.repeat(80));

    if (!DRY_RUN) {
      const employeeAdminsCount = await db.collection('employee_admins').countDocuments();
      const driversCount = await db.collection('drivers').countDocuments();
      const customersCount = await db.collection('customers').countDocuments();
      const clientsCount = await db.collection('clients').countDocuments();

      console.log('\nCurrent collection counts:');
      console.log(`  employee_admins: ${employeeAdminsCount}`);
      console.log(`  drivers: ${driversCount}`);
      console.log(`  customers: ${customersCount}`);
      console.log(`  clients: ${clientsCount}`);
      console.log(`  admin_users (original): ${adminUsers.length}`);
    }

    // ========================================================================
    // STEP 6: Backup recommendation
    // ========================================================================
    console.log('\n═'.repeat(80));
    console.log('STEP 6: Next steps');
    console.log('═'.repeat(80));

    if (DRY_RUN) {
      console.log('\n✅ Dry run completed successfully!');
      console.log('\nTo perform actual migration:');
      console.log('  node scripts/migrate-collections.js');
    } else {
      console.log('\n✅ Migration completed successfully!');
      console.log('\n⚠️  IMPORTANT: Keep admin_users collection as backup for now');
      console.log('   Test your application thoroughly before deleting it');
      console.log('\nTo rename admin_users to admin_users_backup:');
      console.log('  db.admin_users.renameCollection("admin_users_backup")');
    }

    console.log('\n╔══════════════════════════════════════════════════════════════════════════════╗');
    console.log('║                        MIGRATION COMPLETE                                     ║');
    console.log('╚══════════════════════════════════════════════════════════════════════════════╝\n');

  } catch (error) {
    console.error('\n❌ Migration failed!');
    console.error('Error:', error.message);
    console.error('\nStack trace:');
    console.error(error.stack);
    process.exit(1);
  } finally {
    await mongoose.connection.close();
    console.log('📡 Disconnected from MongoDB\n');
  }
}

// Run migration
migrate().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});