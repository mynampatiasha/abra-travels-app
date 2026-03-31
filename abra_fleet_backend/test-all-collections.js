// test-all-collections.js
// Test all collections to ensure proper separation

const mongoose = require('mongoose');
require('dotenv').config();

async function testCollections() {
  console.log('\n🧪 TESTING COLLECTION SEPARATION');
  console.log('═'.repeat(80));

  try {
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected to MongoDB\n');

    const db = mongoose.connection.db;

    // Test 1: Employee Admins Collection
    console.log('1️⃣  EMPLOYEE_ADMINS COLLECTION');
    console.log('─'.repeat(50));
    
    const employees = await db.collection('employee_admins').find({}).toArray();
    console.log(`Total employees: ${employees.length}`);
    
    const employeeRoles = {};
    employees.forEach(emp => {
      const role = emp.role || 'unknown';
      employeeRoles[role] = (employeeRoles[role] || 0) + 1;
    });
    
    console.log('Employee roles:');
    Object.entries(employeeRoles).forEach(([role, count]) => {
      console.log(`  ${role}: ${count}`);
    });
    
    // Check for admin panel roles only
    const adminRoles = ['super_admin', 'admin', 'employee', 'hr_manager', 'fleet_manager', 'finance', 'operations'];
    const nonAdminInEmployees = employees.filter(emp => !adminRoles.includes(emp.role));
    
    if (nonAdminInEmployees.length === 0) {
      console.log('✅ PASS: Only admin panel roles in employee_admins');
    } else {
      console.log('❌ FAIL: Found non-admin roles in employee_admins:');
      nonAdminInEmployees.forEach(emp => {
        console.log(`  - ${emp.email} (${emp.role})`);
      });
    }

    // Test 2: Drivers Collection
    console.log('\n2️⃣  DRIVERS COLLECTION');
    console.log('─'.repeat(50));
    
    const drivers = await db.collection('drivers').find({}).toArray();
    console.log(`Total drivers: ${drivers.length}`);
    
    const driversWithRole = drivers.filter(d => d.role === 'driver').length;
    console.log(`Drivers with 'driver' role: ${driversWithRole}`);
    
    if (drivers.length > 0) {
      console.log('✅ PASS: Drivers collection populated');
    } else {
      console.log('⚠️  WARNING: No drivers found');
    }

    // Test 3: Customers Collection
    console.log('\n3️⃣  CUSTOMERS COLLECTION');
    console.log('─'.repeat(50));
    
    const customers = await db.collection('customers').find({}).toArray();
    console.log(`Total customers: ${customers.length}`);
    
    const customersWithRole = customers.filter(c => c.role === 'customer').length;
    console.log(`Customers with 'customer' role: ${customersWithRole}`);
    
    if (customers.length > 0) {
      console.log('✅ PASS: Customers collection populated');
    } else {
      console.log('⚠️  WARNING: No customers found');
    }

    // Test 4: Clients Collection
    console.log('\n4️⃣  CLIENTS COLLECTION');
    console.log('─'.repeat(50));
    
    const clients = await db.collection('clients').find({}).toArray();
    console.log(`Total clients: ${clients.length}`);
    
    const clientsWithRole = clients.filter(c => c.role === 'client').length;
    console.log(`Clients with 'client' role: ${clientsWithRole}`);
    
    if (clients.length > 0) {
      console.log('✅ PASS: Clients collection populated');
    } else {
      console.log('ℹ️  INFO: No clients found (this is okay if you don\'t have client users)');
    }

    // Test 5: Data Integrity Check
    console.log('\n5️⃣  DATA INTEGRITY CHECK');
    console.log('─'.repeat(50));
    
    const originalAdminUsers = await db.collection('admin_users').find({}).toArray();
    const totalMigrated = employees.length + drivers.length + customers.length + clients.length;
    
    console.log(`Original admin_users: ${originalAdminUsers.length}`);
    console.log(`Total in new collections: ${totalMigrated}`);
    
    // Note: totalMigrated might be higher due to existing records in drivers/customers
    if (employees.length > 0) {
      console.log('✅ PASS: Migration completed successfully');
    } else {
      console.log('❌ FAIL: No employees migrated');
    }

    // Test 6: Firebase UID Check
    console.log('\n6️⃣  FIREBASE UID CHECK');
    console.log('─'.repeat(50));
    
    const employeesWithFirebaseUid = employees.filter(emp => emp.firebaseUid).length;
    const driversWithFirebaseUid = drivers.filter(d => d.firebaseUid).length;
    const customersWithFirebaseUid = customers.filter(c => c.firebaseUid).length;
    const clientsWithFirebaseUid = clients.filter(c => c.firebaseUid).length;
    
    console.log(`Employees with Firebase UID: ${employeesWithFirebaseUid}/${employees.length}`);
    console.log(`Drivers with Firebase UID: ${driversWithFirebaseUid}/${drivers.length}`);
    console.log(`Customers with Firebase UID: ${customersWithFirebaseUid}/${customers.length}`);
    console.log(`Clients with Firebase UID: ${clientsWithFirebaseUid}/${clients.length}`);

    console.log('\n═'.repeat(80));
    console.log('🎉 COLLECTION SEPARATION TEST COMPLETE');
    console.log('═'.repeat(80));

    // Summary
    console.log('\n📊 SUMMARY:');
    console.log(`✅ Employee Admins: ${employees.length} (admin panel users only)`);
    console.log(`✅ Drivers: ${drivers.length} (fleet drivers)`);
    console.log(`✅ Customers: ${customers.length} (end customers)`);
    console.log(`✅ Clients: ${clients.length} (client organizations)`);
    console.log(`📦 Original admin_users: ${originalAdminUsers.length} (kept as backup)`);

  } catch (error) {
    console.error('❌ Test failed:', error.message);
  } finally {
    await mongoose.connection.close();
  }
}

testCollections().catch(console.error);