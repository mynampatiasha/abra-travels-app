require('dotenv').config();
const { MongoClient } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI;

async function fixPriyaRosterStatus() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    // Update roster to have proper status and show in My Trips
    const result = await db.collection('rosters').updateOne(
      { customerEmail: 'priya.sharma@infosys.com' },
      { 
        $set: { 
          status: 'assigned',  // Changed from 'ongoing' to 'assigned'
          driverName: 'Rajesh Kumar',
          driverPhone: '+91 9876543210',
          updatedAt: new Date()
        } 
      }
    );
    
    console.log('✅ Updated roster:', result.modifiedCount, 'document(s)');
    
    // Verify
    const roster = await db.collection('rosters').findOne({ 
      customerEmail: 'priya.sharma@infosys.com' 
    });
    
    console.log('\n📋 Roster Details:');
    console.log('  Customer:', roster.customerEmail);
    console.log('  Status:', roster.status);
    console.log('  Vehicle:', roster.vehicleNumber);
    console.log('  Driver:', roster.driverName);
    console.log('  Driver Phone:', roster.driverPhone);
    
    console.log('\n🎉 Roster is ready! Should now appear in "My Trips"');
    console.log('💡 Refresh the page to see the roster');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    process.exit(0);
  }
}

fixPriyaRosterStatus();
