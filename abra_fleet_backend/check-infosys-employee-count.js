// Check actual employee count for Infosys organization
const admin = require('firebase-admin');

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(require('./serviceAccountKey.json')),
    databaseURL: 'https://abra-fleet-default-rtdb.firebaseio.com'
  });
}

const db = admin.firestore();

async function checkInfosysEmployeeCount() {
  try {
    console.log('🔍 Checking Infosys employee count...\n');
    
    // Get all assigned trips
    const tripsSnapshot = await db.collection('rosters')
      .where('status', 'in', ['assigned', 'ongoing', 'completed', 'cancelled'])
      .get();
    
    console.log(`📊 Total trips in database: ${tripsSnapshot.size}`);
    
    // Filter by Infosys organization and count unique employees
    const infosysEmails = new Set();
    const infosysTrips = [];
    
    tripsSnapshot.forEach(doc => {
      const trip = doc.data();
      const email = trip.customerEmail || '';
      
      if (email.endsWith('@infosys.com')) {
        infosysEmails.add(email);
        infosysTrips.push({
          customerName: trip.customerName,
          customerEmail: email,
          status: trip.status,
          vehicleNumber: trip.vehicleNumber
        });
      }
    });
    
    console.log(`\n✅ Infosys Organization (@infosys.com):`);
    console.log(`   Total Trips: ${infosysTrips.length}`);
    console.log(`   Unique Employees: ${infosysEmails.size}`);
    
    console.log(`\n📋 Unique Infosys Employees:`);
    Array.from(infosysEmails).sort().forEach((email, index) => {
      const employeeTrips = infosysTrips.filter(t => t.customerEmail === email);
      console.log(`   ${index + 1}. ${email} (${employeeTrips.length} trips)`);
    });
    
    // Count by status
    const statusCounts = {
      assigned: 0,
      ongoing: 0,
      completed: 0,
      cancelled: 0
    };
    
    infosysTrips.forEach(trip => {
      const status = trip.status?.toLowerCase() || 'unknown';
      if (statusCounts[status] !== undefined) {
        statusCounts[status]++;
      }
    });
    
    console.log(`\n📊 Trips by Status:`);
    console.log(`   Assigned: ${statusCounts.assigned}`);
    console.log(`   Ongoing: ${statusCounts.ongoing}`);
    console.log(`   Completed: ${statusCounts.completed}`);
    console.log(`   Cancelled: ${statusCounts.cancelled}`);
    
    // Count unique vehicles
    const uniqueVehicles = new Set(infosysTrips.map(t => t.vehicleNumber));
    console.log(`\n🚗 Unique Vehicles: ${uniqueVehicles.size}`);
    
    // Active rosters count (assigned or ongoing)
    const activeTrips = infosysTrips.filter(t => {
      const status = t.status?.toLowerCase() || '';
      return status === 'assigned' || status === 'ongoing';
    });
    const activeVehicles = new Set(activeTrips.map(t => t.vehicleNumber));
    console.log(`🟢 Active Rosters: ${activeVehicles.size}`);
    
    console.log(`\n✅ Dashboard Card Values:`);
    console.log(`   Pending: (check pending rosters API)`);
    console.log(`   Active: ${activeVehicles.size}`);
    console.log(`   Emp: ${infosysEmails.size}`);
    console.log(`   Routes: ${uniqueVehicles.size}`);
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    process.exit(0);
  }
}

checkInfosysEmployeeCount();
