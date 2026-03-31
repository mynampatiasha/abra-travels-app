// scripts/vehicle_location_archiver_cron.js
// ============================================================================
// BACKGROUND JOB: Archive location history and cleanup old data
// ============================================================================
// Runs every 10 minutes to archive GPS data from trips to archive collection
// ============================================================================

const mongoose = require('mongoose');
require('dotenv').config();

async function archiveLocationData() {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📦 ARCHIVING LOCATION DATA');
    console.log('='.repeat(80));
    console.log(`   Time: ${new Date().toISOString()}`);
    
    const db = mongoose.connection.db;
    
    // ========================================================================
    // STEP 1: Find all trips from last 6 days with location data
    // ========================================================================
    const sixDaysAgo = new Date();
    sixDaysAgo.setDate(sixDaysAgo.getDate() - 6);
    const sixDaysAgoStr = sixDaysAgo.toISOString().split('T')[0];
    
    const today = new Date().toISOString().split('T')[0];
    
    console.log(`\n🔍 Looking for trips from ${sixDaysAgoStr} to ${today}...`);
    
    const trips = await db.collection('roster-assigned-trips').find({
      scheduledDate: { $gte: sixDaysAgoStr, $lte: today },
      locationHistory: { $exists: true, $ne: [] }
    }).toArray();
    
    console.log(`📦 Found ${trips.length} trip(s) with location history`);
    
    let archivedCount = 0;
    let updatedCount = 0;
    
    // ========================================================================
    // STEP 2: Archive each trip's location history
    // ========================================================================
    for (const trip of trips) {
      try {
        const vehicleId = trip.vehicleId;
        const date = trip.scheduledDate;
        
        // Check if archive already exists for this vehicle/date
        const existingArchive = await db.collection('vehicle_location_archive').findOne({
          vehicleId: vehicleId,
          date: date
        });
        
        if (existingArchive) {
          // Update existing archive by merging locations
          const mergedLocations = [...existingArchive.locations];
          
          // Add new locations that don't exist
          for (const newLoc of trip.locationHistory) {
            const exists = mergedLocations.some(loc => 
              loc.timestamp === newLoc.timestamp
            );
            
            if (!exists) {
              mergedLocations.push(newLoc);
            }
          }
          
          // Sort by timestamp
          mergedLocations.sort((a, b) => 
            new Date(a.timestamp) - new Date(b.timestamp)
          );
          
          await db.collection('vehicle_location_archive').updateOne(
            { _id: existingArchive._id },
            {
              $set: {
                locations: mergedLocations,
                updatedAt: new Date(),
                tripGroupId: trip.tripGroupId
              }
            }
          );
          
          updatedCount++;
          
        } else {
          // Create new archive document
          const expiresAt = new Date(date);
          expiresAt.setDate(expiresAt.getDate() + 6); // Expire after 6 days
          
          await db.collection('vehicle_location_archive').insertOne({
            vehicleId: vehicleId,
            tripId: trip._id,
            tripGroupId: trip.tripGroupId,
            date: date,
            locations: trip.locationHistory,
            createdAt: new Date(),
            updatedAt: new Date(),
            expiresAt: expiresAt
          });
          
          archivedCount++;
        }
        
      } catch (tripError) {
        console.error(`⚠️  Error archiving trip ${trip._id}:`, tripError.message);
      }
    }
    
    console.log(`\n✅ Archiving complete:`);
    console.log(`   New archives: ${archivedCount}`);
    console.log(`   Updated archives: ${updatedCount}`);
    
    // ========================================================================
    // STEP 3: Cleanup - Remove old archives (>6 days)
    // ========================================================================
    console.log('\n🗑️  Cleaning up old archives...');
    
    const deleteResult = await db.collection('vehicle_location_archive').deleteMany({
      expiresAt: { $lt: new Date() }
    });
    
    console.log(`✅ Deleted ${deleteResult.deletedCount} expired archive(s)`);
    
    console.log('='.repeat(80) + '\n');
    
  } catch (error) {
    console.error('❌ Error in archiveLocationData:', error);
    console.error(error.stack);
  }
}

// ============================================================================
// CRON SETUP - Run every 10 minutes
// ============================================================================
async function startArchiveCron() {
  try {
    console.log('🚀 Starting Location Archive Cron Job');
    console.log('   Frequency: Every 10 minutes');
    console.log('   MongoDB URI:', process.env.MONGODB_URI ? 'Set' : 'NOT SET');
    
    // Connect to MongoDB
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected to MongoDB\n');
    
    const cron = require('node-cron');
    
    // Run every 10 minutes
    cron.schedule('*/10 * * * *', async () => {
      await archiveLocationData();
    });
    
    console.log('✅ Cron job scheduled - running every 10 minutes');
    
    // Run immediately on startup
    console.log('\n🏃 Running initial archive...');
    await archiveLocationData();
    
  } catch (error) {
    console.error('❌ Failed to start cron:', error);
    process.exit(1);
  }
}

// Start if running directly
if (require.main === module) {
  startArchiveCron();
}

module.exports = { archiveLocationData };