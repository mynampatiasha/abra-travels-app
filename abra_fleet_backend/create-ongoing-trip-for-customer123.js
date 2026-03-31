// Script to create/update an ongoing trip for customer123@abrafleet.com
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const DB_NAME = process.env.MONGODB_DB_NAME || 'abra_fleet';

async function createOngoingTrip() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db(DB_NAME);
    
    // 1. Find customer
    const customer = await db.collection('users').findOne({
      email: 'customer123@abrafleet.com'
    });
    
    if (!customer) {
      console.log('❌ Customer not found: customer123@abrafleet.com');
      return;
    }
    
    console.log(`✅ Found customer: ${customer.name || customer.email}`);
    console.log(`   Firebase UID: ${customer.firebaseUid}`);
    console.log(`   Organization: ${customer.companyName || 'Abra Group'}\n`);
    
    // 2. Find an available vehicle (any active vehicle)
    const vehicle = await db.collection('vehicles').findOne({
      status: 'ACTIVE'
    });
    
    if (!vehicle) {
      console.log('❌ No active vehicle found');
      return;
    }
    
    console.log(`✅ Found vehicle: ${vehicle.registrationNumber}`);
    console.log(`   Type: ${vehicle.type}`);
    console.log(`   Capacity: ${vehicle.capacity?.passengers || vehicle.seatingCapacity}\n`);
    
    // 3. Find an available driver (any driver)
    const driver = await db.collection('users').findOne({
      role: 'driver'
    });
    
    if (!driver) {
      console.log('❌ No driver found');
      return;
    }
    
    console.log(`✅ Found driver: ${driver.name || driver.email}`);
    console.log(`   Email: ${driver.email}`);
    console.log(`   Phone: ${driver.phoneNumber || 'N/A'}\n`);
    
    // 4. Find existing roster or create new one
    let roster = await db.collection('rosters').findOne({
      customerEmail: 'customer123@abrafleet.com'
    });
    
    const today = new Date();
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);
    
    if (roster) {
      console.log(`✅ Found existing roster: ${roster._id}`);
      console.log(`   Current Status: ${roster.status}\n`);
      
      // Update existing roster
      const updateResult = await db.collection('rosters').updateOne(
        { _id: roster._id },
        {
          $set: {
            status: 'ongoing',
            vehicleId: vehicle._id.toString(),
            vehicleNumber: vehicle.registrationNumber,
            vehicleType: vehicle.type,
            seatCapacity: vehicle.capacity?.passengers || vehicle.seatingCapacity || 20,
            driverId: driver.firebaseUid,
            driverName: driver.name || driver.email,
            driverEmail: driver.email,
            driverPhone: driver.phoneNumber || '',
            tripStartTime: new Date(),
            lastUpdated: new Date(),
            startDate: today.toISOString().split('T')[0],
            endDate: tomorrow.toISOString().split('T')[0]
          }
        }
      );
      
      console.log(`✅ Updated roster to ONGOING status (${updateResult.modifiedCount} modified)\n`);
      
    } else {
      console.log('📝 Creating new roster...\n');
      
      // Create new roster
      const newRoster = {
        customerEmail: customer.email,
        customerName: customer.name || 'Customer',
        customerPhone: customer.phoneNumber || '',
        customerId: customer.firebaseUid,
        companyName: customer.companyName || 'Abra Group',
        
        vehicleId: vehicle._id.toString(),
        vehicleNumber: vehicle.registrationNumber,
        vehicleType: vehicle.type,
        seatCapacity: vehicle.capacity?.passengers || vehicle.seatingCapacity || 20,
        
        driverId: driver.firebaseUid,
        driverName: driver.name || driver.email,
        driverEmail: driver.email,
        driverPhone: driver.phoneNumber || '',
        
        status: 'ongoing',
        tripType: 'both',
        
        pickupLocation: customer.address || 'Bangalore',
        pickupCoordinates: customer.location || { lat: 12.9716, lng: 77.5946 },
        
        dropLocation: 'Office Location',
        dropCoordinates: { lat: 12.9352, lng: 77.6245 },
        
        startDate: today.toISOString().split('T')[0],
        endDate: tomorrow.toISOString().split('T')[0],
        
        pickupTime: '09:00',
        dropTime: '18:00',
        
        tripStartTime: new Date(),
        createdAt: new Date(),
        lastUpdated: new Date(),
        
        readableId: `RST-TEST-${Date.now().toString().slice(-4)}`
      };
      
      const insertResult = await db.collection('rosters').insertOne(newRoster);
      roster = { _id: insertResult.insertedId, ...newRoster };
      
      console.log(`✅ Created new ONGOING roster: ${insertResult.insertedId}\n`);
    }
    
    // 5. Verify the final state
    const finalRoster = await db.collection('rosters').findOne({
      _id: roster._id
    });
    
    console.log('═══════════════════════════════════════════════════════');
    console.log('📋 ONGOING TRIP DETAILS');
    console.log('═══════════════════════════════════════════════════════');
    console.log(`Roster ID: ${finalRoster._id}`);
    console.log(`Readable ID: ${finalRoster.readableId || 'N/A'}`);
    console.log(`Status: ${finalRoster.status}`);
    console.log(`\nCustomer: ${finalRoster.customerName} (${finalRoster.customerEmail})`);
    console.log(`Vehicle: ${finalRoster.vehicleNumber} (${finalRoster.vehicleType})`);
    console.log(`Driver: ${finalRoster.driverName} (${finalRoster.driverEmail})`);
    console.log(`\nTrip Type: ${finalRoster.tripType}`);
    console.log(`Pickup: ${finalRoster.pickupLocation}`);
    console.log(`Drop: ${finalRoster.dropLocation}`);
    console.log(`Date: ${finalRoster.startDate}`);
    console.log(`Trip Started: ${finalRoster.tripStartTime}`);
    console.log('═══════════════════════════════════════════════════════\n');
    
    console.log('✅ TESTING INSTRUCTIONS:');
    console.log('   1. Login as: customer123@abrafleet.com');
    console.log('   2. Navigate to "My Trips" or "Active Trips"');
    console.log('   3. You should see this ONGOING trip');
    console.log('   4. The trip should show:');
    console.log('      - Vehicle details');
    console.log('      - Driver information');
    console.log('      - Real-time tracking (if implemented)');
    console.log('      - Trip status as ONGOING\n');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error);
  } finally {
    await client.close();
    console.log('✅ Database connection closed');
  }
}

// Run the script
createOngoingTrip().catch(console.error);
