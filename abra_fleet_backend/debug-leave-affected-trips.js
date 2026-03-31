// debug-leave-affected-trips.js
// Debug why affected trips count is 0

require('dotenv').config();
const { MongoClient, ObjectId } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI;
const DB_NAME = process.env.DB_NAME || 'abra_fleet';

async function debugLeaveAffectedTrips() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    console.log('🔌 Connecting to MongoDB...');
    await client.connect();
    const db = client.db(DB_NAME);
    
    // Find the leave request for Asha
    const leaveRequest = await db.collection('leave_requests').findOne({
      customerEmail: 'asha123@cognizant.com'
    }, { sort: { createdAt: -1 } });
    
    if (!leaveRequest) {
      console.log('❌ No leave request found for asha123@cognizant.com');
      return;
    }
    
    console.log('\n📋 LEAVE REQUEST DETAILS:');
    console.log('  ID:', leaveRequest._id);
    console.log('  Customer:', leaveRequest.customerName);
    console.log('  Email:', leaveRequest.customerEmail);
    console.log('  Organization:', leaveRequest.organizationName);
    console.log('  Start Date:', leaveRequest.startDate);
    console.log('  End Date:', leaveRequest.endDate);
    console.log('  Status:', leaveRequest.status);
    console.log('  Affected Trips Count:', leaveRequest.affectedTripsCount);
    console.log('  Affected Trip IDs:', leaveRequest.affectedTripIds?.length || 0);
    
    // Now search for trips that SHOULD be affected
    const start = new Date(leaveRequest.startDate);
    const end = new Date(leaveRequest.endDate);
    
    console.log('\n🔍 SEARCHING FOR TRIPS THAT SHOULD BE AFFECTED:');
    console.log('  Date Range:', start.toISOString(), 'to', end.toISOString());
    
    // Search by email
    console.log('\n1️⃣ Searching by customer email...');
    const tripsByEmail = await db.collection('rosters').find({
      $or: [
        { 'customerEmail': leaveRequest.customerEmail },
        { 'employeeDetails.email': leaveRequest.customerEmail },
        { 'employeeData.email': leaveRequest.customerEmail }
      ]
    }).toArray();
    console.log(`   Found ${tripsByEmail.length} trips with this email`);
    
    if (tripsByEmail.length > 0) {
      console.log('\n   Trip Details:');
      tripsByEmail.forEach((trip, index) => {
        console.log(`   Trip ${index + 1}:`);
        console.log(`     ID: ${trip._id}`);
        console.log(`     Readable ID: ${trip.readableId || 'N/A'}`);
        console.log(`     Status: ${trip.status}`);
        console.log(`     From Date: ${trip.fromDate}`);
        console.log(`     To Date: ${trip.toDate}`);
        console.log(`     Customer Email: ${trip.customerEmail || 'N/A'}`);
        console.log(`     Employee Email: ${trip.employeeDetails?.email || trip.employeeData?.email || 'N/A'}`);
        console.log(`     Organization: ${trip.employeeDetails?.companyName || trip.employeeData?.companyName || trip.organizationName || 'N/A'}`);
        console.log('');
      });
    }
    
    // Search by organization
    console.log('\n2️⃣ Searching by organization...');
    const tripsByOrg = await db.collection('rosters').find({
      $or: [
        { 'employeeDetails.companyName': leaveRequest.organizationName },
        { 'employeeData.companyName': leaveRequest.organizationName },
        { 'organizationName': leaveRequest.organizationName }
      ]
    }).toArray();
    console.log(`   Found ${tripsByOrg.length} trips with this organization`);
    
    // Search with full criteria (as in the actual code)
    console.log('\n3️⃣ Searching with FULL criteria (FIXED - using startDate/endDate)...');
    const affectedTrips = await db.collection('rosters').find({
      $and: [
        {
          $or: [
            { createdBy: leaveRequest.customerId },
            { 'customerEmail': leaveRequest.customerEmail },
            { 'employeeDetails.email': leaveRequest.customerEmail },
            { 'employeeData.email': leaveRequest.customerEmail }
          ]
        },
        { status: { $in: ['pending_assignment', 'assigned', 'scheduled'] } },
        {
          $or: [
            {
              startDate: {
                $gte: start,
                $lte: end
              }
            },
            {
              endDate: {
                $gte: start,
                $lte: end
              }
            },
            {
              $and: [
                { startDate: { $lte: start } },
                { endDate: { $gte: end } }
              ]
            }
          ]
        }
      ]
    }).toArray();
    
    console.log(`   Found ${affectedTrips.length} trips matching FULL criteria`);
    
    if (affectedTrips.length > 0) {
      console.log('\n   ✅ AFFECTED TRIPS:');
      affectedTrips.forEach((trip, index) => {
        console.log(`   Trip ${index + 1}:`);
        console.log(`     ID: ${trip._id}`);
        console.log(`     Readable ID: ${trip.readableId || 'N/A'}`);
        console.log(`     Status: ${trip.status}`);
        console.log(`     From Date: ${trip.fromDate}`);
        console.log(`     To Date: ${trip.toDate}`);
        console.log(`     Customer Email: ${trip.customerEmail || 'N/A'}`);
        console.log(`     Employee Email: ${trip.employeeDetails?.email || trip.employeeData?.email || 'N/A'}`);
        console.log(`     Organization: ${trip.employeeDetails?.companyName || trip.employeeData?.companyName || trip.organizationName || 'N/A'}`);
        console.log('');
      });
    } else {
      console.log('\n   ❌ NO TRIPS FOUND!');
      console.log('\n   🔍 DEBUGGING WHY:');
      
      // Check each condition separately
      console.log('\n   Condition 1: Email/CreatedBy match');
      const cond1 = await db.collection('rosters').find({
        $or: [
          { createdBy: leaveRequest.customerId },
          { 'customerEmail': leaveRequest.customerEmail },
          { 'employeeDetails.email': leaveRequest.customerEmail },
          { 'employeeData.email': leaveRequest.customerEmail }
        ]
      }).toArray();
      console.log(`     Result: ${cond1.length} trips`);
      
      console.log('\n   Condition 2: Organization match');
      const cond2 = await db.collection('rosters').find({
        $or: [
          { 'employeeDetails.companyName': leaveRequest.organizationName },
          { 'employeeData.companyName': leaveRequest.organizationName },
          { 'organizationName': leaveRequest.organizationName }
        ]
      }).toArray();
      console.log(`     Result: ${cond2.length} trips`);
      
      console.log('\n   Condition 3: Status match');
      const cond3 = await db.collection('rosters').find({
        status: { $in: ['pending_assignment', 'assigned', 'scheduled'] }
      }).toArray();
      console.log(`     Result: ${cond3.length} trips`);
      
      console.log('\n   Condition 4: Date overlap');
      const cond4 = await db.collection('rosters').find({
        $or: [
          {
            fromDate: {
              $gte: start,
              $lte: end
            }
          },
          {
            toDate: {
              $gte: start,
              $lte: end
            }
          },
          {
            $and: [
              { fromDate: { $lte: start } },
              { toDate: { $gte: end } }
            ]
          }
        ]
      }).toArray();
      console.log(`     Result: ${cond4.length} trips`);
      
      // Check combination of conditions
      console.log('\n   Condition 1 + 2 (Email + Organization):');
      const cond12 = await db.collection('rosters').find({
        $and: [
          {
            $or: [
              { createdBy: leaveRequest.customerId },
              { 'customerEmail': leaveRequest.customerEmail },
              { 'employeeDetails.email': leaveRequest.customerEmail },
              { 'employeeData.email': leaveRequest.customerEmail }
            ]
          },
          {
            $or: [
              { 'employeeDetails.companyName': leaveRequest.organizationName },
              { 'employeeData.companyName': leaveRequest.organizationName },
              { 'organizationName': leaveRequest.organizationName }
            ]
          }
        ]
      }).toArray();
      console.log(`     Result: ${cond12.length} trips`);
      
      if (cond12.length > 0) {
        console.log('\n   Checking status of these trips:');
        cond12.forEach((trip, index) => {
          console.log(`     Trip ${index + 1}: Status = ${trip.status}, From = ${trip.fromDate}, To = ${trip.toDate}`);
        });
      }
    }
    
    console.log('\n📊 SUMMARY:');
    console.log(`  Leave Request Affected Trips Count: ${leaveRequest.affectedTripsCount}`);
    console.log(`  Actual Affected Trips Found: ${affectedTrips.length}`);
    console.log(`  Match: ${leaveRequest.affectedTripsCount === affectedTrips.length ? '✅' : '❌'}`);
    
    // Fix the leave request if counts don't match
    if (leaveRequest.affectedTripsCount !== affectedTrips.length) {
      console.log('\n🔧 FIXING LEAVE REQUEST...');
      
      await db.collection('leave_requests').updateOne(
        { _id: leaveRequest._id },
        { 
          $set: { 
            affectedTripIds: affectedTrips.map(trip => trip._id),
            affectedTripsCount: affectedTrips.length,
            updatedAt: new Date()
          }
        }
      );
      
      console.log(`✅ Updated leave request with correct affected trips count: ${affectedTrips.length}`);
      console.log('   Refresh the Leave Request Management screen to see the updated count');
    }
    
  } catch (error) {
    console.error('\n❌ ERROR:', error.message);
    console.error(error.stack);
  } finally {
    await client.close();
    console.log('\n🔌 Disconnected from MongoDB\n');
  }
}

debugLeaveAffectedTrips();
