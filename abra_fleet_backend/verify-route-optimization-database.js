// verify-route-optimization-database.js - Verify Database Storage for Route Optimization
require('dotenv').config();
const { MongoClient, ObjectId } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI;

async function verifyDatabaseStorage() {
  console.log('🔍 VERIFYING ROUTE OPTIMIZATION DATABASE STORAGE');
  console.log('='.repeat(80));
  
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('\n✅ Connected to MongoDB\n');
    
    // ========== CHECK 1: Rosters Collection ==========
    console.log('📋 CHECK 1: Rosters Collection Structure');
    console.log('='.repeat(80));
    
    const sampleRoster = await db.collection('rosters').findOne({
      status: 'assigned'
    });
    
    if (sampleRoster) {
      console.log('✅ Found assigned roster with optimization data:');
      console.log('\nRoster ID:', sampleRoster._id);
      console.log('Status:', sampleRoster.status);
      console.log('Customer Name:', sampleRoster.customerName || 'N/A');
      console.log('Office Location:', sampleRoster.officeLocation || 'N/A');
      
      // Check optimization fields
      console.log('\n📊 Optimization Fields:');
      console.log('  ├─ Driver ID:', sampleRoster.driverId || '❌ MISSING');
      console.log('  ├─ Assigned At:', sampleRoster.assignedAt || '❌ MISSING');
      console.log('  ├─ Assigned By:', sampleRoster.assignedBy || '❌ MISSING');
      console.log('  ├─ Optimized Pickup Time:', sampleRoster.optimizedPickupTime || '❌ MISSING');
      console.log('  ├─ Optimized Office Time:', sampleRoster.optimizedOfficeTime || '❌ MISSING');
      console.log('  ├─ Estimated Distance:', sampleRoster.estimatedDistance || '❌ MISSING');
      console.log('  ├─ Estimated Travel Time:', sampleRoster.estimatedTravelTime || '❌ MISSING');
      console.log('  └─ Buffer Minutes:', sampleRoster.bufferMinutes || '❌ MISSING');
      
      // Verify all required fields are present
      const requiredFields = [
        'driverId',
        'assignedAt',
        'assignedBy',
        'optimizedPickupTime',
        'optimizedOfficeTime',
        'estimatedDistance',
        'estimatedTravelTime',
        'bufferMinutes'
      ];
      
      const missingFields = requiredFields.filter(field => !sampleRoster[field]);
      
      if (missingFields.length === 0) {
        console.log('\n✅ ALL OPTIMIZATION FIELDS PRESENT');
      } else {
        console.log('\n⚠️  MISSING FIELDS:', missingFields.join(', '));
      }
    } else {
      console.log('⚠️  No assigned rosters found. Create some assignments first.');
    }
    
    // ========== CHECK 2: Count Rosters by Status ==========
    console.log('\n\n📊 CHECK 2: Roster Status Distribution');
    console.log('='.repeat(80));
    
    const statusCounts = await db.collection('rosters').aggregate([
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 }
        }
      },
      {
        $sort: { count: -1 }
      }
    ]).toArray();
    
    console.log('\nRoster Status Counts:');
    statusCounts.forEach(status => {
      console.log(`  ${status._id || 'null'}: ${status.count}`);
    });
    
    // ========== CHECK 3: Notifications Collection ==========
    console.log('\n\n📬 CHECK 3: Notifications for Route Optimization');
    console.log('='.repeat(80));
    
    const optimizationNotifications = await db.collection('notifications')
      .find({
        $or: [
          { type: 'roster_assignment' },
          { type: 'driver_assignment' }
        ]
      })
      .sort({ createdAt: -1 })
      .limit(5)
      .toArray();
    
    if (optimizationNotifications.length > 0) {
      console.log(`✅ Found ${optimizationNotifications.length} route optimization notifications\n`);
      
      optimizationNotifications.forEach((notif, index) => {
        console.log(`Notification ${index + 1}:`);
        console.log(`  Type: ${notif.type}`);
        console.log(`  Title: ${notif.title}`);
        console.log(`  Message: ${notif.message}`);
        console.log(`  User ID: ${notif.userId}`);
        console.log(`  Created: ${notif.createdAt}`);
        console.log(`  Priority: ${notif.priority || 'normal'}`);
        console.log(`  Category: ${notif.category || 'general'}`);
        
        if (notif.data) {
          console.log('  Data:');
          console.log(`    ├─ Roster ID: ${notif.data.rosterId || 'N/A'}`);
          console.log(`    ├─ Driver ID: ${notif.data.driverId || 'N/A'}`);
          console.log(`    ├─ Driver Name: ${notif.data.driverName || 'N/A'}`);
          console.log(`    ├─ Customer Name: ${notif.data.customerName || 'N/A'}`);
          console.log(`    ├─ Pickup Time: ${notif.data.pickupTime || 'N/A'}`);
          console.log(`    ├─ Office Time: ${notif.data.officeTime || 'N/A'}`);
          console.log(`    ├─ Distance: ${notif.data.distance || 'N/A'} km`);
          console.log(`    └─ Travel Time: ${notif.data.travelTime || 'N/A'} min`);
        }
        console.log('');
      });
    } else {
      console.log('⚠️  No route optimization notifications found yet.');
    }
    
    // ========== CHECK 4: Users Collection (Drivers) ==========
    console.log('\n🚗 CHECK 4: Available Drivers');
    console.log('='.repeat(80));
    
    const availableDrivers = await db.collection('users')
      .find({
        role: 'driver',
        status: 'active'
      })
      .limit(5)
      .toArray();
    
    console.log(`\nFound ${availableDrivers.length} active drivers:\n`);
    
    availableDrivers.forEach((driver, index) => {
      console.log(`Driver ${index + 1}:`);
      console.log(`  ID: ${driver._id}`);
      console.log(`  Name: ${driver.name || 'N/A'}`);
      console.log(`  Email: ${driver.email || 'N/A'}`);
      console.log(`  Phone: ${driver.phone || 'N/A'}`);
      console.log(`  Available: ${driver.isAvailable !== false ? 'Yes' : 'No'}`);
      console.log(`  Status: ${driver.status || 'N/A'}`);
      
      if (driver.currentLocation) {
        console.log(`  Location: Lat ${driver.currentLocation.latitude}, Lng ${driver.currentLocation.longitude}`);
      } else {
        console.log('  Location: ❌ Not set');
      }
      console.log('');
    });
    
    // ========== CHECK 5: Assigned Rosters with Full Details ==========
    console.log('\n📋 CHECK 5: Recently Assigned Rosters (Full Details)');
    console.log('='.repeat(80));
    
    const recentAssignments = await db.collection('rosters')
      .find({
        status: 'assigned',
        optimizedPickupTime: { $exists: true }
      })
      .sort({ assignedAt: -1 })
      .limit(3)
      .toArray();
    
    if (recentAssignments.length > 0) {
      console.log(`\n✅ Found ${recentAssignments.length} recently optimized assignments:\n`);
      
      for (let i = 0; i < recentAssignments.length; i++) {
        const roster = recentAssignments[i];
        console.log(`Assignment ${i + 1}:`);
        console.log('='.repeat(60));
        console.log('Basic Info:');
        console.log(`  Roster ID: ${roster._id}`);
        console.log(`  Customer: ${roster.customerName || 'Unknown'}`);
        console.log(`  Email: ${roster.customerEmail || 'N/A'}`);
        console.log(`  Office: ${roster.officeLocation || 'N/A'}`);
        console.log(`  Type: ${roster.rosterType || 'N/A'}`);
        console.log(`  Status: ${roster.status}`);
        
        console.log('\nOptimization Data:');
        console.log(`  Driver ID: ${roster.driverId}`);
        console.log(`  Pickup Time: ${roster.optimizedPickupTime}`);
        console.log(`  Office Time: ${roster.optimizedOfficeTime}`);
        console.log(`  Distance: ${roster.estimatedDistance} km`);
        console.log(`  Travel Time: ${roster.estimatedTravelTime} min`);
        console.log(`  Buffer: ${roster.bufferMinutes} min`);
        
        console.log('\nTimestamps:');
        console.log(`  Assigned At: ${roster.assignedAt}`);
        console.log(`  Assigned By: ${roster.assignedBy}`);
        console.log(`  Updated At: ${roster.updatedAt || 'N/A'}`);
        
        // Fetch driver details
        if (roster.driverId) {
          const driver = await db.collection('users').findOne({
            _id: new ObjectId(roster.driverId)
          });
          
          if (driver) {
            console.log('\nAssigned Driver:');
            console.log(`  Name: ${driver.name || 'Unknown'}`);
            console.log(`  Email: ${driver.email || 'N/A'}`);
            console.log(`  Phone: ${driver.phone || 'N/A'}`);
          }
        }
        
        console.log('\n');
      }
    } else {
      console.log('\n⚠️  No optimized assignments found yet.');
    }
    
    // ========== CHECK 6: Database Indexes ==========
    console.log('\n🔍 CHECK 6: Database Indexes');
    console.log('='.repeat(80));
    
    const rosterIndexes = await db.collection('rosters').indexes();
    console.log('\nRosters Collection Indexes:');
    rosterIndexes.forEach(index => {
      console.log(`  - ${index.name}: ${JSON.stringify(index.key)}`);
    });
    
    const notificationIndexes = await db.collection('notifications').indexes();
    console.log('\nNotifications Collection Indexes:');
    notificationIndexes.forEach(index => {
      console.log(`  - ${index.name}: ${JSON.stringify(index.key)}`);
    });
    
    // ========== SUMMARY ==========
    console.log('\n\n📊 VERIFICATION SUMMARY');
    console.log('='.repeat(80));
    
    const totalRosters = await db.collection('rosters').countDocuments();
    const pendingRosters = await db.collection('rosters').countDocuments({ status: 'pending_assignment' });
    const assignedRosters = await db.collection('rosters').countDocuments({ status: 'assigned' });
    const optimizedRosters = await db.collection('rosters').countDocuments({ 
      status: 'assigned',
      optimizedPickupTime: { $exists: true }
    });
    const totalDrivers = await db.collection('users').countDocuments({ role: 'driver' });
    const availableDriversCount = await db.collection('users').countDocuments({ 
      role: 'driver',
      status: 'active',
      isAvailable: { $ne: false }
    });
    const totalNotifications = await db.collection('notifications').countDocuments({
      $or: [
        { type: 'roster_assignment' },
        { type: 'driver_assignment' }
      ]
    });
    
    console.log('\nDatabase Statistics:');
    console.log(`  Total Rosters: ${totalRosters}`);
    console.log(`  ├─ Pending: ${pendingRosters}`);
    console.log(`  ├─ Assigned: ${assignedRosters}`);
    console.log(`  └─ Optimized: ${optimizedRosters}`);
    console.log(`\n  Total Drivers: ${totalDrivers}`);
    console.log(`  └─ Available: ${availableDriversCount}`);
    console.log(`\n  Optimization Notifications: ${totalNotifications}`);
    
    // ========== VERIFICATION CHECKLIST ==========
    console.log('\n\n✅ VERIFICATION CHECKLIST');
    console.log('='.repeat(80));
    
    const checks = [
      { name: 'Rosters collection exists', passed: totalRosters > 0 },
      { name: 'Assigned rosters exist', passed: assignedRosters > 0 },
      { name: 'Optimization fields stored', passed: optimizedRosters > 0 },
      { name: 'Drivers collection exists', passed: totalDrivers > 0 },
      { name: 'Available drivers exist', passed: availableDriversCount > 0 },
      { name: 'Notifications created', passed: totalNotifications > 0 },
      { name: 'Database indexes present', passed: rosterIndexes.length > 0 }
    ];
    
    checks.forEach(check => {
      const icon = check.passed ? '✅' : '❌';
      console.log(`${icon} ${check.name}`);
    });
    
    const allPassed = checks.every(check => check.passed);
    
    if (allPassed) {
      console.log('\n🎉 ALL CHECKS PASSED! Database storage is working correctly.');
    } else {
      console.log('\n⚠️  Some checks failed. Review the details above.');
    }
    
    // ========== RECOMMENDATIONS ==========
    console.log('\n\n💡 RECOMMENDATIONS');
    console.log('='.repeat(80));
    
    if (pendingRosters === 0) {
      console.log('⚠️  No pending rosters. Create some rosters to test optimization.');
    }
    
    if (availableDriversCount === 0) {
      console.log('⚠️  No available drivers. Add drivers or set isAvailable: true.');
    }
    
    if (optimizedRosters === 0) {
      console.log('⚠️  No optimized assignments yet. Run route optimization to test.');
    }
    
    if (totalNotifications === 0) {
      console.log('⚠️  No notifications created. Verify notification system is working.');
    }
    
    console.log('\n✅ Verification Complete!');
    console.log('='.repeat(80));
    
  } catch (error) {
    console.error('\n❌ Verification Error:', error);
    console.error('Stack:', error.stack);
  } finally {
    await client.close();
    console.log('\n🔌 Database connection closed\n');
  }
}

// Run verification
verifyDatabaseStorage().catch(console.error);
