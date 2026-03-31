// Create pending rosters for testing route optimization
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function createPendingRosters() {
  console.log('🔗 Connecting to MongoDB...');
  const client = new MongoClient(MONGODB_URI);
  await client.connect();
  console.log('✅ Connected to MongoDB');
  
  const db = client.db();
  
  try {
    console.log('\n🎯 Creating 6 pending rosters for route optimization testing...');
    console.log('='.repeat(80));
    
    // Create 6 pending rosters from same organization for testing
    const pendingRosters = [
      {
        rosterId: 'RST-TEST-001',
        customerId: 'CUST-TEST-001',
        customerName: 'Arjun Sharma',
        customerEmail: 'arjun.sharma@techcorp.com',
        customerPhone: '+91-9876543210',
        organization: 'TechCorp Solutions',
        employeeDetails: {
          name: 'Arjun Sharma',
          email: 'arjun.sharma@techcorp.com',
          phone: '+91-9876543210',
          organization: 'TechCorp Solutions',
          department: 'Engineering',
          employeeId: 'TC001'
        },
        pickupLocation: {
          latitude: 12.9716,
          longitude: 77.5946,
          address: 'Koramangala, Bangalore'
        },
        dropLocation: {
          latitude: 12.9352,
          longitude: 77.6245,
          address: 'Whitefield, Bangalore'
        },
        status: 'pending_assignment',
        priority: 'high',
        requestedPickupTime: '08:00',
        createdAt: new Date(),
        updatedAt: new Date()
      },
      {
        rosterId: 'RST-TEST-002',
        customerId: 'CUST-TEST-002',
        customerName: 'Priya Nair',
        customerEmail: 'priya.nair@techcorp.com',
        customerPhone: '+91-9876543211',
        organization: 'TechCorp Solutions',
        employeeDetails: {
          name: 'Priya Nair',
          email: 'priya.nair@techcorp.com',
          phone: '+91-9876543211',
          organization: 'TechCorp Solutions',
          department: 'Marketing',
          employeeId: 'TC002'
        },
        pickupLocation: {
          latitude: 12.9698,
          longitude: 77.5986,
          address: 'HSR Layout, Bangalore'
        },
        dropLocation: {
          latitude: 12.9352,
          longitude: 77.6245,
          address: 'Whitefield, Bangalore'
        },
        status: 'pending_assignment',
        priority: 'medium',
        requestedPickupTime: '08:15',
        createdAt: new Date(),
        updatedAt: new Date()
      },
      {
        rosterId: 'RST-TEST-003',
        customerId: 'CUST-TEST-003',
        customerName: 'Vikram Singh',
        customerEmail: 'vikram.singh@techcorp.com',
        customerPhone: '+91-9876543212',
        organization: 'TechCorp Solutions',
        employeeDetails: {
          name: 'Vikram Singh',
          email: 'vikram.singh@techcorp.com',
          phone: '+91-9876543212',
          organization: 'TechCorp Solutions',
          department: 'Sales',
          employeeId: 'TC003'
        },
        pickupLocation: {
          latitude: 12.9667,
          longitude: 77.6000,
          address: 'BTM Layout, Bangalore'
        },
        dropLocation: {
          latitude: 12.9352,
          longitude: 77.6245,
          address: 'Whitefield, Bangalore'
        },
        status: 'pending_assignment',
        priority: 'high',
        requestedPickupTime: '08:30',
        createdAt: new Date(),
        updatedAt: new Date()
      },
      {
        rosterId: 'RST-TEST-004',
        customerId: 'CUST-TEST-004',
        customerName: 'Anita Reddy',
        customerEmail: 'anita.reddy@techcorp.com',
        customerPhone: '+91-9876543213',
        organization: 'TechCorp Solutions',
        employeeDetails: {
          name: 'Anita Reddy',
          email: 'anita.reddy@techcorp.com',
          phone: '+91-9876543213',
          organization: 'TechCorp Solutions',
          department: 'HR',
          employeeId: 'TC004'
        },
        pickupLocation: {
          latitude: 12.9634,
          longitude: 77.5855,
          address: 'Jayanagar, Bangalore'
        },
        dropLocation: {
          latitude: 12.9352,
          longitude: 77.6245,
          address: 'Whitefield, Bangalore'
        },
        status: 'pending_assignment',
        priority: 'medium',
        requestedPickupTime: '08:45',
        createdAt: new Date(),
        updatedAt: new Date()
      },
      {
        rosterId: 'RST-TEST-005',
        customerId: 'CUST-TEST-005',
        customerName: 'Rahul Gupta',
        customerEmail: 'rahul.gupta@innovate.com',
        customerPhone: '+91-9876543214',
        organization: 'Innovate Labs',
        employeeDetails: {
          name: 'Rahul Gupta',
          email: 'rahul.gupta@innovate.com',
          phone: '+91-9876543214',
          organization: 'Innovate Labs',
          department: 'Research',
          employeeId: 'IL001'
        },
        pickupLocation: {
          latitude: 12.9800,
          longitude: 77.5900,
          address: 'Indiranagar, Bangalore'
        },
        dropLocation: {
          latitude: 12.9100,
          longitude: 77.6400,
          address: 'Electronic City, Bangalore'
        },
        status: 'pending_assignment',
        priority: 'high',
        requestedPickupTime: '09:00',
        createdAt: new Date(),
        updatedAt: new Date()
      },
      {
        rosterId: 'RST-TEST-006',
        customerId: 'CUST-TEST-006',
        customerName: 'Sneha Patel',
        customerEmail: 'sneha.patel@innovate.com',
        customerPhone: '+91-9876543215',
        organization: 'Innovate Labs',
        employeeDetails: {
          name: 'Sneha Patel',
          email: 'sneha.patel@innovate.com',
          phone: '+91-9876543215',
          organization: 'Innovate Labs',
          department: 'Design',
          employeeId: 'IL002'
        },
        pickupLocation: {
          latitude: 12.9750,
          longitude: 77.5950,
          address: 'Domlur, Bangalore'
        },
        dropLocation: {
          latitude: 12.9100,
          longitude: 77.6400,
          address: 'Electronic City, Bangalore'
        },
        status: 'pending_assignment',
        priority: 'medium',
        requestedPickupTime: '09:15',
        createdAt: new Date(),
        updatedAt: new Date()
      }
    ];
    
    // Insert rosters
    for (const roster of pendingRosters) {
      await db.collection('rosters').insertOne(roster);
      console.log(`✅ Created roster ${roster.rosterId} - ${roster.customerName} (${roster.organization})`);
    }
    
    console.log('\n🚗 Ensuring vehicles have assigned drivers...');
    
    // Update vehicles to have assigned drivers
    const vehicles = await db.collection('vehicles').find({ status: 'ACTIVE' }).toArray();
    const drivers = await db.collection('drivers').find({}).toArray();
    
    if (vehicles.length > 0 && drivers.length > 0) {
      for (let i = 0; i < Math.min(vehicles.length, drivers.length); i++) {
        const vehicle = vehicles[i];
        const driver = drivers[i];
        
        await db.collection('vehicles').updateOne(
          { _id: vehicle._id },
          {
            $set: {
              assignedDriver: {
                _id: driver._id,
                driverId: driver.driverId,
                name: `${driver.personalInfo?.firstName || driver.firstName || ''} ${driver.personalInfo?.lastName || driver.lastName || ''}`.trim() || driver.name || 'Unknown Driver',
                email: driver.personalInfo?.email || driver.email || '',
                phone: driver.personalInfo?.phone || driver.phone || driver.phoneNumber || ''
              },
              updatedAt: new Date()
            }
          }
        );
        
        console.log(`✅ Assigned driver ${driver.driverId} to vehicle ${vehicle.registrationNumber || vehicle.name}`);
      }
    }
    
    console.log('\n📊 SUMMARY:');
    console.log('='.repeat(80));
    console.log(`✅ Created 6 pending rosters:`);
    console.log(`   - TechCorp Solutions: 4 customers (same organization - can share vehicle)`);
    console.log(`   - Innovate Labs: 2 customers (same organization - can share vehicle)`);
    console.log(`✅ Updated vehicles with assigned drivers`);
    console.log(`✅ Ready for route optimization testing!`);
    
    console.log('\n🧪 TO TEST:');
    console.log('1. Run: node test-multiple-trips-assignment.js');
    console.log('2. Or open Flutter app → Admin → Pending Rosters → Route Optimization');
    console.log('3. Select "Auto Mode" and enter "4" for TechCorp group');
    console.log('4. Or select "Auto Mode" and enter "2" for Innovate Labs group');
    
  } catch (error) {
    console.error('❌ Error creating test data:', error);
  } finally {
    await client.close();
    console.log('✅ Disconnected from MongoDB');
  }
}

// Run the script
createPendingRosters();