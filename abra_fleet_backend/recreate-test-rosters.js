const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

async function recreateTestRosters() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('fleet_management');
    
    // Create test rosters for Electronic City Office (same organization)
    const testRosters = [
      {
        _id: new ObjectId(),
        readableId: 'RST-TEST001',
        customerName: 'Pooja Joshi',
        customerEmail: 'pooja.joshi@wipro.com',
        rosterType: 'both',
        officeLocation: 'Electronic City Office Bangalore',
        weekdays: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
        startDate: new Date('2025-12-14T18:30:00.000Z'),
        endDate: new Date('2026-01-14T18:30:00.000Z'),
        startTime: '09:30',
        endTime: '18:30',
        loginPickupAddress: '123 MG Road, Bangalore',
        logoutDropAddress: '123 MG Road, Bangalore',
        loginPickupLocation: {
          latitude: 12.8456,
          longitude: 77.6603,
          address: '123 MG Road, Bangalore'
        },
        logoutDropLocation: {
          latitude: 12.8456,
          longitude: 77.6603,
          address: '123 MG Road, Bangalore'
        },
        status: 'pending_assignment',
        createdAt: new Date(),
        employeeDetails: {
          name: 'Pooja Joshi',
          email: 'pooja.joshi@wipro.com',
          phone: '+91-9876543210',
          companyName: 'Infosys Limited'
        }
      },
      {
        _id: new ObjectId(),
        readableId: 'RST-TEST002',
        customerName: 'Arjun Nair',
        customerEmail: 'arjun.nair@wipro.com',
        rosterType: 'both',
        officeLocation: 'Electronic City Office Bangalore',
        weekdays: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
        startDate: new Date('2025-12-14T18:30:00.000Z'),
        endDate: new Date('2026-01-14T18:30:00.000Z'),
        startTime: '09:30',
        endTime: '18:30',
        loginPickupAddress: '456 Brigade Road, Bangalore',
        logoutDropAddress: '456 Brigade Road, Bangalore',
        loginPickupLocation: {
          latitude: 12.8456,
          longitude: 77.6603,
          address: '456 Brigade Road, Bangalore'
        },
        logoutDropLocation: {
          latitude: 12.8456,
          longitude: 77.6603,
          address: '456 Brigade Road, Bangalore'
        },
        status: 'pending_assignment',
        createdAt: new Date(),
        employeeDetails: {
          name: 'Arjun Nair',
          email: 'arjun.nair@wipro.com',
          phone: '+91-9876543211',
          companyName: 'Infosys Limited'
        }
      },
      {
        _id: new ObjectId(),
        readableId: 'RST-TEST003',
        customerName: 'Sneha Iyer',
        customerEmail: 'sneha.iyer@wipro.com',
        rosterType: 'both',
        officeLocation: 'Electronic City Office Bangalore',
        weekdays: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
        startDate: new Date('2025-12-14T18:30:00.000Z'),
        endDate: new Date('2026-01-14T18:30:00.000Z'),
        startTime: '09:30',
        endTime: '18:30',
        loginPickupAddress: '789 Indiranagar, Bangalore',
        logoutDropAddress: '789 Indiranagar, Bangalore',
        loginPickupLocation: {
          latitude: 12.8456,
          longitude: 77.6603,
          address: '789 Indiranagar, Bangalore'
        },
        logoutDropLocation: {
          latitude: 12.8456,
          longitude: 77.6603,
          address: '789 Indiranagar, Bangalore'
        },
        status: 'pending_assignment',
        createdAt: new Date(),
        employeeDetails: {
          name: 'Sneha Iyer',
          email: 'sneha.iyer@wipro.com',
          phone: '+91-9876543212',
          companyName: 'Infosys Limited'
        }
      }
    ];
    
    console.log('📝 Creating 3 test rosters...\n');
    
    const result = await db.collection('rosters').insertMany(testRosters);
    
    console.log(`✅ Created ${result.insertedCount} rosters:\n`);
    
    testRosters.forEach((roster, index) => {
      console.log(`${index + 1}. ${roster.customerName}`);
      console.log(`   ID: ${roster._id}`);
      console.log(`   Email: ${roster.customerEmail}`);
      console.log(`   Office: ${roster.officeLocation}`);
      console.log(`   Status: ${roster.status}`);
      console.log('');
    });
    
    console.log('✅ Test rosters created successfully!');
    console.log('\n💡 Now refresh the Pending Rosters screen in the app');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

recreateTestRosters();
