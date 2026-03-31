// Check what's in the admin_users collection
const { MongoClient } = require('mongodb');

async function checkAdminUsersCollection() {
  let client;
  
  try {
    console.log('🔍 Checking admin_users collection...');
    console.log('─'.repeat(80));
    
    // Connect to MongoDB
    client = new MongoClient('mongodb://localhost:27017');
    await client.connect();
    
    const db = client.db('abra_fleet');
    
    // Check admin_users collection
    console.log('\n1️⃣ Admin Users Collection:');
    const adminUsers = await db.collection('admin_users').find({}).toArray();
    console.log(`   Found ${adminUsers.length} admin users`);
    
    if (adminUsers.length > 0) {
      console.log('\n   Admin users:');
      adminUsers.forEach((user, index) => {
        console.log(`   ${index + 1}. ${user.name} (${user.email}) - Role: ${user.role}`);
      });
    } else {
      console.log('   ⚠️  No admin users found in admin_users collection');
    }
    
    // Check other collections for comparison
    console.log('\n2️⃣ Other Collections (for comparison):');
    
    const drivers = await db.collection('drivers').find({}).limit(3).toArray();
    console.log(`   Drivers: ${drivers.length} found (showing first 3)`);
    drivers.forEach((driver, index) => {
      console.log(`   ${index + 1}. ${driver.name} (${driver.email}) - Role: ${driver.role || 'driver'}`);
    });
    
    const customers = await db.collection('customers').find({}).limit(3).toArray();
    console.log(`   Customers: ${customers.length} found (showing first 3)`);
    customers.forEach((customer, index) => {
      console.log(`   ${index + 1}. ${customer.name} (${customer.email}) - Role: ${customer.role || 'customer'}`);
    });
    
    const clients = await db.collection('clients').find({}).limit(3).toArray();
    console.log(`   Clients: ${clients.length} found (showing first 3)`);
    clients.forEach((client, index) => {
      console.log(`   ${index + 1}. ${client.name} (${client.email}) - Role: ${client.role || 'client'}`);
    });
    
    // Check if there's a generic 'users' collection
    console.log('\n3️⃣ Generic Users Collection:');
    try {
      const genericUsers = await db.collection('users').find({}).limit(5).toArray();
      console.log(`   Generic users: ${genericUsers.length} found (showing first 5)`);
      genericUsers.forEach((user, index) => {
        console.log(`   ${index + 1}. ${user.name} (${user.email}) - Role: ${user.role}`);
      });
    } catch (error) {
      console.log('   No generic users collection found');
    }
    
    console.log('\n✅ Database check complete');
    console.log('─'.repeat(80));
    
  } catch (error) {
    console.error('❌ Database check failed:', error.message);
  } finally {
    if (client) {
      await client.close();
    }
  }
}

checkAdminUsersCollection();