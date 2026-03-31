// Check what real customers are available for roster assignment
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function checkAvailableCustomers() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    // Get all customers
    const customers = await db.collection('customers').find({
      status: { $ne: 'deleted' }
    }).toArray();
    
    console.log(`\n📋 Found ${customers.length} customers in database`);
    
    if (customers.length === 0) {
      console.log('\n❌ NO CUSTOMERS FOUND!');
      console.log('   You need to create customers first through the admin panel.');
      return;
    }
    
    // Group by organization
    const byOrg = {};
    for (const customer of customers) {
      const org = customer.organizationId || 'No Organization';
      if (!byOrg[org]) byOrg[org] = [];
      byOrg[org].push(customer);
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('👥 AVAILABLE CUSTOMERS BY ORGANIZATION');
    console.log('='.repeat(80));
    
    for (const [org, orgCustomers] of Object.entries(byOrg)) {
      console.log(`\n📁 ${org} (${orgCustomers.length} customers)`);
      console.log('─'.repeat(80));
      
      for (const customer of orgCustomers.slice(0, 10)) {
        console.log(`\n  ✓ ${customer.name || 'No Name'}`);
        console.log(`    Email: ${customer.email || 'N/A'}`);
        console.log(`    Phone: ${customer.phone || 'N/A'}`);
        console.log(`    UID: ${customer.uid || 'N/A'}`);
        console.log(`    Status: ${customer.status || 'N/A'}`);
        
        // Check if they have addresses
        const hasHome = customer.homeAddress || customer.pickupAddress || customer.loginPickupAddress;
        const hasOffice = customer.officeAddress || customer.dropAddress || customer.officeLocation;
        
        if (hasHome) {
          console.log(`    🏠 Home: ${hasHome}`);
        } else {
          console.log(`    ⚠️  No home address`);
        }
        
        if (hasOffice) {
          console.log(`    🏢 Office: ${hasOffice}`);
        } else {
          console.log(`    ⚠️  No office address`);
        }
      }
      
      if (orgCustomers.length > 10) {
        console.log(`\n  ... and ${orgCustomers.length - 10} more`);
      }
    }
    
    // Check for drivers
    console.log('\n' + '='.repeat(80));
    console.log('🚗 AVAILABLE DRIVERS');
    console.log('='.repeat(80));
    
    const drivers = await db.collection('drivers').find({
      status: { $ne: 'deleted' }
    }).toArray();
    
    console.log(`\nFound ${drivers.length} drivers`);
    
    for (const driver of drivers) {
      console.log(`\n  ✓ ${driver.name || 'No Name'}`);
      console.log(`    Email: ${driver.email}`);
      console.log(`    UID: ${driver.uid || 'N/A'}`);
      console.log(`    Status: ${driver.status || 'N/A'}`);
      console.log(`    Phone: ${driver.phone || 'N/A'}`);
    }
    
    // Check for vehicles
    console.log('\n' + '='.repeat(80));
    console.log('🚙 AVAILABLE VEHICLES');
    console.log('='.repeat(80));
    
    const vehicles = await db.collection('vehicles').find({
      status: { $in: ['available', 'active'] }
    }).toArray();
    
    console.log(`\nFound ${vehicles.length} available vehicles`);
    
    for (const vehicle of vehicles) {
      console.log(`\n  ✓ ${vehicle.registrationNumber}`);
      console.log(`    Model: ${vehicle.model || 'N/A'}`);
      console.log(`    Capacity: ${vehicle.capacity || 'N/A'} seats`);
      console.log(`    Status: ${vehicle.status}`);
      console.log(`    Organization: ${vehicle.organizationId || 'N/A'}`);
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('📝 SUMMARY');
    console.log('='.repeat(80));
    console.log(`Customers: ${customers.length}`);
    console.log(`Drivers: ${drivers.length}`);
    console.log(`Vehicles: ${vehicles.length}`);
    
    console.log('\n✅ TO ASSIGN ROSTERS:');
    console.log('   1. Login to admin panel');
    console.log('   2. Go to Customer Management');
    console.log('   3. Select customers from the list above');
    console.log('   4. Click "Route Optimization"');
    console.log('   5. Select driver: ashamynampati2003@gmail.com');
    console.log('   6. Select vehicle from the list above');
    console.log('   7. Set date and time');
    console.log('   8. Click "Assign Route"');
    console.log('   9. Driver will see rosters in their dashboard');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkAvailableCustomers();
