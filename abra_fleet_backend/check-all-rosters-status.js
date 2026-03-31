const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const uri = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const client = new MongoClient(uri);

async function checkAllRosters() {
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');

    const db = client.db('abra_fleet');
    const rostersCollection = db.collection('rosters');
    const driversCollection = db.collection('drivers');
    const usersCollection = db.collection('users');

    // Get all rosters
    const allRosters = await rostersCollection.find({}).toArray();
    console.log(`📊 TOTAL ROSTERS IN DATABASE: ${allRosters.length}\n`);

    if (allRosters.length === 0) {
      console.log('❌ NO ROSTERS FOUND IN DATABASE!\n');
      console.log('This explains why nothing is showing up.\n');
      console.log('SOLUTION: You need to assign rosters through the admin panel.\n');
      return;
    }

    // Group by status
    const byStatus = {};
    allRosters.forEach(roster => {
      const status = roster.status || 'unknown';
      if (!byStatus[status]) byStatus[status] = [];
      byStatus[status].push(roster);
    });

    console.log('📋 ROSTERS BY STATUS:');
    console.log('='.repeat(60));
    Object.keys(byStatus).forEach(status => {
      console.log(`\n${status.toUpperCase()}: ${byStatus[status].length} rosters`);
    });
    console.log('\n' + '='.repeat(60) + '\n');

    // Check pending rosters
    const pendingRosters = await rostersCollection.find({ 
      status: { $in: ['pending', 'assigned'] }
    }).toArray();
    
    console.log(`\n🔍 PENDING/ASSIGNED ROSTERS: ${pendingRosters.length}`);
    if (pendingRosters.length > 0) {
      console.log('\nDetails:');
      for (const roster of pendingRosters.slice(0, 5)) {
        console.log(`\n  Roster ID: ${roster._id}`);
        console.log(`  Status: ${roster.status}`);
        console.log(`  Assigned Driver: ${roster.assignedDriver || 'NONE'}`);
        console.log(`  User ID: ${roster.userId || 'NONE'}`);
        console.log(`  Start Date: ${roster.startDate}`);
        console.log(`  End Date: ${roster.endDate}`);
        
        // Check if driver exists
        if (roster.assignedDriver) {
          try {
            const driver = await driversCollection.findOne({ 
              _id: new ObjectId(roster.assignedDriver) 
            });
            if (driver) {
              console.log(`  ✅ Driver Found: ${driver.name} (${driver.email})`);
            } else {
              console.log(`  ❌ Driver NOT FOUND for ID: ${roster.assignedDriver}`);
            }
          } catch (e) {
            console.log(`  ❌ Invalid Driver ID format: ${roster.assignedDriver}`);
          }
        }
        
        // Check if customer exists
        if (roster.userId) {
          const customer = await usersCollection.findOne({ uid: roster.userId });
          if (customer) {
            console.log(`  ✅ Customer Found: ${customer.name} (${customer.email})`);
          } else {
            console.log(`  ❌ Customer NOT FOUND for UID: ${roster.userId}`);
          }
        }
      }
      if (pendingRosters.length > 5) {
        console.log(`\n  ... and ${pendingRosters.length - 5} more`);
      }
    }

    // Check approved rosters
    const approvedRosters = await rostersCollection.find({ 
      status: 'approved' 
    }).toArray();
    
    console.log(`\n\n✅ APPROVED ROSTERS: ${approvedRosters.length}`);
    if (approvedRosters.length > 0) {
      console.log('\nDetails:');
      for (const roster of approvedRosters.slice(0, 5)) {
        console.log(`\n  Roster ID: ${roster._id}`);
        console.log(`  Status: ${roster.status}`);
        console.log(`  Assigned Driver: ${roster.assignedDriver || 'NONE'}`);
        console.log(`  User ID: ${roster.userId || 'NONE'}`);
        console.log(`  Start Date: ${roster.startDate}`);
        console.log(`  End Date: ${roster.endDate}`);
        
        // Check if driver exists
        if (roster.assignedDriver) {
          try {
            const driver = await driversCollection.findOne({ 
              _id: new ObjectId(roster.assignedDriver) 
            });
            if (driver) {
              console.log(`  ✅ Driver Found: ${driver.name} (${driver.email})`);
            } else {
              console.log(`  ❌ Driver NOT FOUND for ID: ${roster.assignedDriver}`);
            }
          } catch (e) {
            console.log(`  ❌ Invalid Driver ID format: ${roster.assignedDriver}`);
          }
        }
        
        // Check if customer exists
        if (roster.userId) {
          const customer = await usersCollection.findOne({ uid: roster.userId });
          if (customer) {
            console.log(`  ✅ Customer Found: ${customer.name} (${customer.email})`);
          } else {
            console.log(`  ❌ Customer NOT FOUND for UID: ${roster.userId}`);
          }
        }
      }
      if (approvedRosters.length > 5) {
        console.log(`\n  ... and ${approvedRosters.length - 5} more`);
      }
    }

    // Check date ranges
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    
    const todayRosters = await rostersCollection.find({
      startDate: { $lte: today },
      endDate: { $gte: today }
    }).toArray();
    
    console.log(`\n\n📅 ROSTERS FOR TODAY (${today.toISOString().split('T')[0]}): ${todayRosters.length}`);
    if (todayRosters.length > 0) {
      console.log('\nDetails:');
      todayRosters.slice(0, 5).forEach(roster => {
        console.log(`\n  Roster ID: ${roster._id}`);
        console.log(`  Status: ${roster.status}`);
        console.log(`  Date Range: ${roster.startDate} to ${roster.endDate}`);
      });
    }

    // Check for rosters with missing fields
    console.log('\n\n🔍 CHECKING FOR DATA QUALITY ISSUES:');
    console.log('='.repeat(60));
    
    const missingDriver = await rostersCollection.countDocuments({ 
      assignedDriver: { $exists: false } 
    });
    console.log(`Rosters without assignedDriver: ${missingDriver}`);
    
    const missingUserId = await rostersCollection.countDocuments({ 
      userId: { $exists: false } 
    });
    console.log(`Rosters without userId: ${missingUserId}`);
    
    const missingStatus = await rostersCollection.countDocuments({ 
      status: { $exists: false } 
    });
    console.log(`Rosters without status: ${missingStatus}`);
    
    const missingDates = await rostersCollection.countDocuments({ 
      $or: [
        { startDate: { $exists: false } },
        { endDate: { $exists: false } }
      ]
    });
    console.log(`Rosters without dates: ${missingDates}`);

    // Summary
    console.log('\n\n📊 SUMMARY:');
    console.log('='.repeat(60));
    console.log(`Total Rosters: ${allRosters.length}`);
    console.log(`Pending/Assigned: ${pendingRosters.length}`);
    console.log(`Approved: ${approvedRosters.length}`);
    console.log(`For Today: ${todayRosters.length}`);
    console.log(`Data Quality Issues: ${missingDriver + missingUserId + missingStatus + missingDates}`);
    
    if (allRosters.length === 0) {
      console.log('\n❌ NO ROSTERS IN DATABASE');
      console.log('   Action: Assign rosters through admin panel');
    } else if (pendingRosters.length === 0 && approvedRosters.length === 0) {
      console.log('\n⚠️  NO PENDING OR APPROVED ROSTERS');
      console.log('   Check roster statuses - they might be in a different state');
    } else {
      console.log('\n✅ ROSTERS EXIST IN DATABASE');
      console.log('   If not showing in UI, check:');
      console.log('   1. Backend API endpoints');
      console.log('   2. Frontend API calls');
      console.log('   3. User authentication/permissions');
      console.log('   4. Organization filtering');
    }

  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

checkAllRosters();
