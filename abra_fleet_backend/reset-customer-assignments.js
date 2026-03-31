// Direct database reset for customer assignments
const { MongoClient, ObjectId } = require('mongodb');

const MONGODB_URI = 'mongodb://localhost:27017';
const DATABASE_NAME = 'abra_fleet';

async function resetCustomerAssignments() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    console.log('🔧 Connecting to MongoDB...');
    await client.connect();
    const db = client.db(DATABASE_NAME);
    
    console.log('✅ Connected to database');
    
    // Find Nisha Jain and Ramesh Naidu rosters
    const targetCustomers = ['Nisha Jain', 'Ramesh Naidu'];
    
    console.log('🔍 Finding target customer rosters...');
    const rosters = await db.collection('rosters').find({
      $or: [
        { customerName: { $in: targetCustomers } },
        { 'employeeDetails.name': { $in: targetCustomers } }
      ]
    }).toArray();
    
    console.log(`📋 Found ${rosters.length} rosters for target customers:`);
    rosters.forEach(roster => {
      const customerName = roster.customerName || roster.employeeDetails?.name;
      console.log(`   - ${customerName}: Status = ${roster.status}, Vehicle = ${roster.vehicleNumber || 'None'}`);
    });
    
    // Reset assigned rosters to pending_assignment
    const assignedRosters = rosters.filter(r => r.status === 'assigned');
    
    if (assignedRosters.length === 0) {
      console.log('✅ No assigned rosters found. Customers are already available for assignment.');
      return;
    }
    
    console.log(`\n🔄 Resetting ${assignedRosters.length} assigned rosters to pending_assignment...`);
    
    for (const roster of assignedRosters) {
      const customerName = roster.customerName || roster.employeeDetails?.name;
      
      // Update roster status
      const updateResult = await db.collection('rosters').updateOne(
        { _id: roster._id },
        {
          $set: {
            status: 'pending_assignment',
            updatedAt: new Date()
          },
          $unset: {
            vehicleId: '',
            vehicleNumber: '',
            driverId: '',
            driverName: '',
            driverPhone: '',
            assignedAt: '',
            assignedBy: '',
            pickupSequence: '',
            optimizedPickupTime: '',
            estimatedArrival: '',
            pickupLocation: '',
            routeDetails: '',
            tripId: ''
          }
        }
      );
      
      if (updateResult.modifiedCount > 0) {
        console.log(`   ✅ ${customerName} - Reset to pending_assignment`);
        
        // Also remove from vehicle's assignedCustomers array if it exists
        if (roster.vehicleId) {
          await db.collection('vehicles').updateOne(
            { _id: new ObjectId(roster.vehicleId) },
            {
              $pull: {
                assignedCustomers: {
                  rosterId: roster._id.toString()
                }
              },
              $set: {
                updatedAt: new Date()
              }
            }
          );
          console.log(`   ✅ ${customerName} - Removed from vehicle ${roster.vehicleNumber}`);
        }
        
        // Delete any associated trips
        if (roster.tripId) {
          await db.collection('trips').deleteOne({ _id: new ObjectId(roster.tripId) });
          console.log(`   ✅ ${customerName} - Deleted associated trip`);
        }
        
      } else {
        console.log(`   ❌ ${customerName} - Failed to reset`);
      }
    }
    
    console.log('\n✅ Reset complete! Customers are now available for assignment.');
    console.log('💡 You can now try the route assignment again in the UI.');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

resetCustomerAssignments();