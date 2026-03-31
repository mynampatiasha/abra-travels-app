// Update rosters with correct driver information
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function updateRostersWithDriver() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    const driver = await db.collection('drivers').findOne({ driverId: 'DRV-852306' });
    
    const driverName = `${driver.personalInfo.firstName} ${driver.personalInfo.lastName}`;
    const driverPhone = driver.personalInfo.phone;
    
    console.log(`✅ Driver: ${driverName} (${driverPhone})\n`);
    
    const result = await db.collection('rosters').updateMany(
      {
        customerEmail: { $in: [
          'rajesh.kumar@infosys.com',
          'priya.sharma@infosys.com',
          'amit.patel@infosys.com'
        ]}
      },
      {
        $set: {
          driverName: driverName,
          driverPhone: driverPhone,
          updatedAt: new Date()
        }
      }
    );
    
    console.log(`✅ Updated ${result.modifiedCount} rosters with driver details!\n`);
    
    // Verify
    const rosters = await db.collection('rosters')
      .find({
        customerEmail: { $in: [
          'rajesh.kumar@infosys.com',
          'priya.sharma@infosys.com',
          'amit.patel@infosys.com'
        ]}
      })
      .toArray();
    
    console.log('📊 Final Rosters:\n');
    rosters.forEach((r, i) => {
      console.log(`${i + 1}. ${r.customerName} (${r.customerEmail})`);
      console.log(`   Vehicle: ${r.vehicleNumber}`);
      console.log(`   Driver: ${r.driverName} (${r.driverPhone})`);
      console.log(`   Status: ${r.status}`);
      console.log('');
    });
    
    console.log('✅ COMPLETE! All 3 Infosys rosters are now properly assigned!');
    console.log('\n📱 Refresh your Client Roster Management page to see the changes!\n');
    
  } catch (error) {
    console.error('Error:', error.message);
  } finally {
    await client.close();
  }
}

updateRostersWithDriver();
