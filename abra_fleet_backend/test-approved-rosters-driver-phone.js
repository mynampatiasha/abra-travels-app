// Test script to verify approved rosters endpoint returns driver phone
const { MongoClient } = require('mongodb');

const MONGODB_URI = 'mongodb://localhost:27017';
const DB_NAME = 'abra_fleet';

async function testApprovedRostersDriverPhone() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db(DB_NAME);
    
    // Simulate the approved rosters endpoint query
    const query = { 
      requestType: 'customer_roster',
      status: { $in: ['assigned', 'in_progress', 'completed'] }
    };
    
    console.log('🔍 Fetching approved rosters with driver phone...\n');
    
    const approvedRosters = await db.collection('rosters')
      .aggregate([
        { $match: query },
        {
          $addFields: {
            driverObjectId: {
              $cond: [
                { $eq: [{ $type: "$assignedDriver" }, "objectId"] },
                "$assignedDriver",
                {
                  $cond: [
                    { $eq: [{ $type: "$assignedDriver.driverId" }, "objectId"] },
                    "$assignedDriver.driverId",
                    {
                      $cond: [
                        { $eq: [{ $type: "$assignedDriver.driverId" }, "string"] },
                        { $toObjectId: "$assignedDriver.driverId" },
                        null
                      ]
                    }
                  ]
                }
              ]
            },
            vehicleObjectId: {
              $cond: [
                { $eq: [{ $type: "$assignedVehicle" }, "objectId"] },
                "$assignedVehicle",
                {
                  $cond: [
                    { $eq: [{ $type: "$assignedVehicle.vehicleId" }, "objectId"] },
                    "$assignedVehicle.vehicleId",
                    {
                      $cond: [
                        { $eq: [{ $type: "$assignedVehicle.vehicleId" }, "string"] },
                        { $toObjectId: "$assignedVehicle.vehicleId" },
                        null
                      ]
                    }
                  ]
                }
              ]
            }
          }
        },
        {
          $lookup: {
            from: 'drivers',
            localField: 'driverObjectId',
            foreignField: '_id',
            as: 'driverDetails'
          }
        },
        {
          $lookup: {
            from: 'vehicles',
            localField: 'vehicleObjectId',
            foreignField: '_id',
            as: 'vehicleDetails'
          }
        },
        {
          $addFields: {
            assignedDriverName: { 
              $ifNull: [
                { $arrayElemAt: ['$driverDetails.name', 0] },
                'Not assigned'
              ]
            },
            driverPhone: { 
              $ifNull: [
                { $arrayElemAt: ['$driverDetails.phone', 0] },
                ''
              ]
            },
            assignedVehicleReg: { 
              $ifNull: [
                { $arrayElemAt: ['$vehicleDetails.registrationNumber', 0] },
                'Not assigned'
              ]
            }
          }
        },
        { 
          $project: { 
            driverDetails: 0, 
            vehicleDetails: 0,
            driverObjectId: 0,
            vehicleObjectId: 0
          } 
        },
        { $sort: { startDate: -1, createdAt: -1 } }
      ])
      .toArray();
    
    console.log(`📊 Found ${approvedRosters.length} approved rosters\n`);
    
    if (approvedRosters.length === 0) {
      console.log('⚠️  No approved rosters found');
      return;
    }
    
    // Display first 3 rosters with driver phone
    approvedRosters.slice(0, 3).forEach((roster, index) => {
      console.log(`\n${'='.repeat(60)}`);
      console.log(`📋 Roster ${index + 1}: ${roster.customerName}`);
      console.log(`${'='.repeat(60)}`);
      console.log(`👤 Customer: ${roster.customerName}`);
      console.log(`📧 Email: ${roster.customerEmail || 'N/A'}`);
      console.log(`🏢 Office: ${roster.officeLocation || 'N/A'}`);
      console.log(`📅 Dates: ${roster.startDate} to ${roster.endDate}`);
      console.log(`⏰ Times: ${roster.startTime} - ${roster.endTime}`);
      console.log(`\n🚗 Assignment Details:`);
      console.log(`   Driver: ${roster.assignedDriverName || roster.driverName || 'Not assigned'}`);
      console.log(`   📞 Driver Phone: ${roster.driverPhone || 'Not available'}`);
      console.log(`   Vehicle: ${roster.assignedVehicleReg || roster.vehicleNumber || 'Not assigned'}`);
      console.log(`   Status: ${roster.status}`);
      
      if (roster.driverPhone) {
        console.log(`\n✅ Driver phone is present: ${roster.driverPhone}`);
      } else {
        console.log(`\n❌ Driver phone is MISSING`);
      }
    });
    
    // Summary
    const rostersWithPhone = approvedRosters.filter(r => r.driverPhone && r.driverPhone !== '');
    console.log(`\n${'='.repeat(60)}`);
    console.log(`📊 SUMMARY`);
    console.log(`${'='.repeat(60)}`);
    console.log(`Total approved rosters: ${approvedRosters.length}`);
    console.log(`Rosters with driver phone: ${rostersWithPhone.length}`);
    console.log(`Rosters without driver phone: ${approvedRosters.length - rostersWithPhone.length}`);
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

testApprovedRostersDriverPhone();
