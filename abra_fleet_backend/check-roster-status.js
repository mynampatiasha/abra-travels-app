const { MongoClient } = require('mongodb');

async function checkRosterStatus() {
  const client = new MongoClient('mongodb://localhost:27017');
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('🔍 Checking roster statuses...');
    
    // Get sample rosters
    const rosters = await db.collection('rosters').find({}).limit(10).toArray();
    
    console.log('\n📊 Sample roster statuses:');
    rosters.forEach((roster, i) => {
      const name = roster.customerName || roster.employeeDetails?.name || 'Unknown';
      console.log(`   ${i+1}. ${name} - Status: ${roster.status || 'undefined'}`);
    });
    
    // Get status distribution
    const statusCounts = await db.collection('rosters').aggregate([
      { $group: { _id: '$status', count: { $sum: 1 } } },
      { $sort: { count: -1 } }
    ]).toArray();
    
    console.log('\n📈 Status distribution:');
    statusCounts.forEach(stat => {
      console.log(`   ${stat._id || 'null/undefined'}: ${stat.count}`);
    });
    
    // Check for already assigned rosters
    const assignedCount = await db.collection('rosters').countDocuments({ status: 'assigned' });
    const pendingCount = await db.collection('rosters').countDocuments({ status: 'pending' });
    const pendingAssignmentCount = await db.collection('rosters').countDocuments({ status: 'pending_assignment' });
    
    console.log('\n🎯 Key status counts:');
    console.log(`   assigned: ${assignedCount}`);
    console.log(`   pending: ${pendingCount}`);
    console.log(`   pending_assignment: ${pendingAssignmentCount}`);
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkRosterStatus();