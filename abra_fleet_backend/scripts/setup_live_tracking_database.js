// scripts/setup_live_tracking_database.js
// ============================================================================
// DATABASE SETUP FOR LIVE TRACKING SYSTEM
// ============================================================================
// Run this once to create indexes and TTL collection
// Usage: node scripts/setup_live_tracking_database.js
// ============================================================================

const mongoose = require('mongoose');
require('dotenv').config();

async function setupLiveTrackingDatabase() {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🔧 SETTING UP LIVE TRACKING DATABASE');
    console.log('='.repeat(80));
    
    // Connect to MongoDB
    await mongoose.connect(process.env.MONGODB_URI);
    const db = mongoose.connection.db;
    
    console.log('✅ Connected to MongoDB');
    console.log(`   Database: ${db.databaseName}`);
    
    // ========================================================================
    // STEP 1: Create vehicle_location_archive collection
    // ========================================================================
    console.log('\n📦 Creating vehicle_location_archive collection...');
    
    const collections = await db.listCollections({ name: 'vehicle_location_archive' }).toArray();
    
    if (collections.length === 0) {
      await db.createCollection('vehicle_location_archive');
      console.log('✅ Collection created');
    } else {
      console.log('✅ Collection already exists');
    }
    
    // ========================================================================
    // STEP 2: Create indexes for fast queries
    // ========================================================================
    console.log('\n🔍 Creating indexes...');
    
    // Index 1: Compound index for vehicle + date queries
    await db.collection('vehicle_location_archive').createIndex(
      { vehicleId: 1, date: 1 },
      { name: 'vehicleId_date_idx' }
    );
    console.log('✅ Index created: vehicleId + date');
    
    // Index 2: TTL index for auto-cleanup after 6 days
    await db.collection('vehicle_location_archive').createIndex(
      { expiresAt: 1 },
      { 
        expireAfterSeconds: 0,
        name: 'ttl_idx'
      }
    );
    console.log('✅ Index created: TTL (6-day auto-delete)');
    
    // ========================================================================
    // STEP 3: Create indexes on roster-assigned-trips for live tracking
    // ========================================================================
    console.log('\n🔍 Creating indexes on roster-assigned-trips...');
    
    await db.collection('roster-assigned-trips').createIndex(
      { scheduledDate: 1, status: 1 },
      { name: 'live_tracking_idx' }
    );
    console.log('✅ Index created: scheduledDate + status');
    
    await db.collection('roster-assigned-trips').createIndex(
      { vehicleId: 1, scheduledDate: 1 },
      { name: 'vehicle_date_idx' }
    );
    console.log('✅ Index created: vehicleId + scheduledDate');
    
    await db.collection('roster-assigned-trips').createIndex(
      { 'currentLocation.timestamp': -1 },
      { name: 'location_timestamp_idx' }
    );
    console.log('✅ Index created: currentLocation.timestamp');
    
    // ========================================================================
    // STEP 4: Create indexes on notifications
    // ========================================================================
    console.log('\n🔍 Creating indexes on notifications...');
    
    await db.collection('notifications').createIndex(
      { type: 1, 'data.vehicleId': 1, createdAt: -1 },
      { name: 'notification_type_vehicle_idx' }
    );
    console.log('✅ Index created: type + vehicleId + createdAt');
    
    // ========================================================================
    // STEP 5: Verify indexes
    // ========================================================================
    console.log('\n📊 Verifying indexes...');
    
    const archiveIndexes = await db.collection('vehicle_location_archive').indexes();
    console.log(`✅ vehicle_location_archive: ${archiveIndexes.length} indexes`);
    archiveIndexes.forEach(idx => {
      console.log(`   - ${idx.name}`);
    });
    
    const tripsIndexes = await db.collection('roster-assigned-trips').indexes();
    console.log(`✅ roster-assigned-trips: ${tripsIndexes.length} indexes`);
    
    const notifIndexes = await db.collection('notifications').indexes();
    console.log(`✅ notifications: ${notifIndexes.length} indexes`);
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ DATABASE SETUP COMPLETE');
    console.log('='.repeat(80));
    console.log('\nNext steps:');
    console.log('1. Mount router in index.js:');
    console.log('   app.use(\'/api/admin/live-tracking\', verifyJWT, adminLiveTrackingRoutes);');
    console.log('');
    console.log('2. Start background cron job for location archiving');
    console.log('   (See vehicle_location_archiver_cron.js)');
    console.log('');
    console.log('3. Test the endpoints:');
    console.log('   GET /api/admin/live-tracking/vehicles?date=2026-02-08');
    console.log('='.repeat(80) + '\n');
    
    await mongoose.connection.close();
    process.exit(0);
    
  } catch (error) {
    console.error('\n❌ ERROR:', error.message);
    console.error(error.stack);
    process.exit(1);
  }
}

setupLiveTrackingDatabase();