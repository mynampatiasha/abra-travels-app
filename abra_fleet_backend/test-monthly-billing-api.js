const { MongoClient } = require('mongodb');

const MONGODB_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function testMonthlyBillingAPI() {
  let client;
  
  try {
    console.log('='.repeat(60));
    console.log('TESTING MONTHLY BILLING API FOR CUSTOMER123');
    console.log('='.repeat(60));

    // Connect to MongoDB
    console.log('\n1. Connecting to MongoDB...');
    client = new MongoClient(MONGODB_URI);
    await client.connect();
    const db = client.db('abra_fleet');
    console.log('✓ Connected to MongoDB');

    const customerUID = 'b5aoloVR7xYI6SICibCIWecBaf82';
    
    // Get all trips for customer123
    console.log('\n2. Getting trips for customer123...');
    const allTrips = await db.collection('trips').find({ customerId: customerUID }).toArray();
    console.log(`✓ Found ${allTrips.length} trips`);

    // Calculate total distance
    let totalDistance = 0;
    allTrips.forEach(trip => {
      if (trip.actualDistance) {
        totalDistance += trip.actualDistance;
      } else if (trip.distance) {
        totalDistance += trip.distance;
      }
    });
    console.log(`✓ Total distance: ${totalDistance.toFixed(1)} km`);

    // Calculate today's distance
    const today = new Date();
    const todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate());
    const todayEnd = new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);
    
    const todayTrips = allTrips.filter(trip => {
      const tripDate = new Date(trip.scheduledDate || trip.createdAt);
      return tripDate >= todayStart && tripDate < todayEnd;
    });
    
    let todayDistance = 0;
    todayTrips.forEach(trip => {
      if (trip.actualDistance) {
        todayDistance += trip.actualDistance;
      } else if (trip.distance) {
        todayDistance += trip.distance;
      }
    });
    console.log(`✓ Today's distance: ${todayDistance.toFixed(1)} km (${todayTrips.length} trips)`);

    // Generate available months
    const monthsWithData = new Set();
    allTrips.forEach(trip => {
      const tripDate = new Date(trip.scheduledDate || trip.createdAt);
      if (!isNaN(tripDate.getTime())) {
        const monthKey = `${tripDate.getFullYear()}-${String(tripDate.getMonth() + 1).padStart(2, '0')}`;
        monthsWithData.add(monthKey);
      }
    });

    console.log('\n3. Available months with data:');
    const availableMonths = [];
    Array.from(monthsWithData).sort().forEach(monthKey => {
      const [year, month] = monthKey.split('-');
      const monthName = new Date(parseInt(year), parseInt(month) - 1).toLocaleDateString('en', { month: 'long', year: 'numeric' });
      const shortName = new Date(parseInt(year), parseInt(month) - 1).toLocaleDateString('en', { month: 'short' });
      availableMonths.push({
        key: monthKey,
        name: monthName,
        shortName: shortName
      });
      console.log(`   ${shortName} (${monthKey}) - ${monthName}`);
    });

    // Test specific month data (December 2024)
    const testMonth = '2024-12';
    console.log(`\n4. Testing specific month data for ${testMonth}:`);
    
    const [year, month] = testMonth.split('-');
    const monthStart = new Date(parseInt(year), parseInt(month) - 1, 1);
    const monthEnd = new Date(parseInt(year), parseInt(month), 0, 23, 59, 59);
    
    const monthTrips = allTrips.filter(trip => {
      const tripDate = new Date(trip.scheduledDate || trip.createdAt);
      return tripDate >= monthStart && tripDate <= monthEnd;
    });
    
    let monthDistance = 0;
    const dailyBreakdown = {};
    
    monthTrips.forEach(trip => {
      const distance = trip.actualDistance || trip.distance || 0;
      monthDistance += distance;
      
      const tripDate = new Date(trip.scheduledDate || trip.createdAt);
      const dayKey = tripDate.getDate();
      
      if (!dailyBreakdown[dayKey]) {
        dailyBreakdown[dayKey] = {
          day: dayKey,
          date: tripDate.toLocaleDateString('en-GB'),
          distance: 0,
          trips: 0
        };
      }
      
      dailyBreakdown[dayKey].distance += distance;
      dailyBreakdown[dayKey].trips += 1;
    });

    console.log(`   Month: ${testMonth}`);
    console.log(`   Total Distance: ${monthDistance.toFixed(1)} km`);
    console.log(`   Total Trips: ${monthTrips.length}`);
    console.log(`   Daily Breakdown:`);
    
    Object.values(dailyBreakdown).sort((a, b) => a.day - b.day).forEach(day => {
      console.log(`     Day ${day.day} (${day.date}): ${day.distance.toFixed(1)} km, ${day.trips} trips`);
    });

    console.log('\n' + '='.repeat(60));
    console.log('✅ MONTHLY BILLING API TEST COMPLETE!');
    console.log('='.repeat(60));
    console.log(`Total Distance: ${totalDistance.toFixed(1)} km`);
    console.log(`Today's Distance: ${todayDistance.toFixed(1)} km`);
    console.log(`Available Months: ${availableMonths.length}`);
    console.log(`Test Month (${testMonth}): ${monthDistance.toFixed(1)} km, ${monthTrips.length} trips`);

  } catch (error) {
    console.error('\n' + '='.repeat(60));
    console.error('❌ ERROR TESTING MONTHLY BILLING API:');
    console.error('='.repeat(60));
    console.error(error.message);
    console.error(error.stack);
  } finally {
    if (client) {
      await client.close();
    }
    process.exit(0);
  }
}

testMonthlyBillingAPI();