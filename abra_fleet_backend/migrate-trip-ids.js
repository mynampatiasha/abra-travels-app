// File: migrate-trip-ids.js
// Migration script to convert existing trip IDs to new Trip-XXXXX format

const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function migrateTripIds() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    console.log('🔄 Starting trip ID migration...');
    await client.connect();
    const db = client.db();
    const tripsCollection = db.collection('trips');
    
    // Generate new Trip-XXXXX format ID
    function generateNewTripId() {
      const randomNumbers = Math.floor(Math.random() * 100000).toString().padStart(5, '0');
      return `Trip-${randomNumbers}`;
    }
    
    // Get all trips that don't have the new tripId format
    const tripsToMigrate = await tripsCollection.find({
      $or: [
        { tripId: { $exists: false } },
        { tripId: { $not: /^Trip-\d{5}$/ } }
      ]
    }).toArray();
    
    console.log(`📊 Found ${tripsToMigrate.length} trips to migrate`);
    
    if (tripsToMigrate.length === 0) {
      console.log('✅ No trips need migration');
      return;
    }
    
    let migratedCount = 0;
    let errorCount = 0;
    
    for (const trip of tripsToMigrate) {
      try {
        let newTripId;
        let attempts = 0;
        const maxAttempts = 10;
        
        // Generate unique trip ID (retry if collision)
        do {
          newTripId = generateNewTripId();
          attempts++;
          
          const existing = await tripsCollection.findOne({ tripId: newTripId });
          if (!existing) break;
          
          if (attempts >= maxAttempts) {
            throw new Error(`Failed to generate unique trip ID after ${maxAttempts} attempts`);
          }
        } while (attempts < maxAttempts);
        
        // Update the trip with new tripId
        const updateData = {
          tripId: newTripId,
          updatedAt: new Date(),
          migratedAt: new Date()
        };
        
        // Keep old tripNumber for backward compatibility if it exists
        if (trip.tripNumber) {
          updateData.oldTripNumber = trip.tripNumber;
        }
        
        await tripsCollection.updateOne(
          { _id: trip._id },
          { $set: updateData }
        );
        
        console.log(`✅ Migrated trip ${trip._id} -> ${newTripId}`);
        migratedCount++;
        
      } catch (error) {
        console.error(`❌ Error migrating trip ${trip._id}:`, error.message);
        errorCount++;
      }
    }
    
    console.log('\n📈 Migration Summary:');
    console.log(`✅ Successfully migrated: ${migratedCount} trips`);
    console.log(`❌ Errors: ${errorCount} trips`);
    console.log(`📊 Total processed: ${tripsToMigrate.length} trips`);
    
    // Update related collections that reference trip IDs
    await migrateRelatedCollections(db);
    
  } catch (error) {
    console.error('❌ Migration failed:', error);
    throw error;
  } finally {
    await client.close();
  }
}

async function migrateRelatedCollections(db) {
  console.log('\n🔄 Updating related collections...');
  
  try {
    // Update notifications that reference trip IDs
    const notificationsCollection = db.collection('notifications');
    const notifications = await notificationsCollection.find({
      'data.tripId': { $exists: true, $not: /^Trip-\d{5}$/ }
    }).toArray();
    
    for (const notification of notifications) {
      const oldTripId = notification.data.tripId;
      
      // Find the trip with the old ID to get the new ID
      const trip = await db.collection('trips').findOne({
        $or: [
          { tripNumber: oldTripId },
          { oldTripNumber: oldTripId }
        ]
      });
      
      if (trip && trip.tripId) {
        await notificationsCollection.updateOne(
          { _id: notification._id },
          { 
            $set: { 
              'data.tripId': trip.tripId,
              'data.oldTripId': oldTripId,
              updatedAt: new Date()
            }
          }
        );
        console.log(`✅ Updated notification ${notification._id} trip reference`);
      }
    }
    
    // Update vehicles that have currentTrip references
    const vehiclesCollection = db.collection('vehicles');
    const vehicles = await vehiclesCollection.find({
      currentTrip: { $exists: true, $ne: null, $not: /^Trip-\d{5}$/ }
    }).toArray();
    
    for (const vehicle of vehicles) {
      const oldTripId = vehicle.currentTrip;
      
      const trip = await db.collection('trips').findOne({
        $or: [
          { tripNumber: oldTripId },
          { oldTripNumber: oldTripId }
        ]
      });
      
      if (trip && trip.tripId) {
        await vehiclesCollection.updateOne(
          { _id: vehicle._id },
          { 
            $set: { 
              currentTrip: trip.tripId,
              updatedAt: new Date()
            }
          }
        );
        console.log(`✅ Updated vehicle ${vehicle._id} current trip reference`);
      }
    }
    
    // Update drivers that have currentTrip references
    const driversCollection = db.collection('drivers');
    const drivers = await driversCollection.find({
      currentTrip: { $exists: true, $ne: null, $not: /^Trip-\d{5}$/ }
    }).toArray();
    
    for (const driver of drivers) {
      const oldTripId = driver.currentTrip;
      
      const trip = await db.collection('trips').findOne({
        $or: [
          { tripNumber: oldTripId },
          { oldTripNumber: oldTripId }
        ]
      });
      
      if (trip && trip.tripId) {
        await driversCollection.updateOne(
          { _id: driver._id },
          { 
            $set: { 
              currentTrip: trip.tripId,
              updatedAt: new Date()
            }
          }
        );
        console.log(`✅ Updated driver ${driver._id} current trip reference`);
      }
    }
    
    console.log('✅ Related collections updated successfully');
    
  } catch (error) {
    console.error('❌ Error updating related collections:', error);
    throw error;
  }
}

// Run migration if called directly
if (require.main === module) {
  migrateTripIds()
    .then(() => {
      console.log('\n🎉 Trip ID migration completed successfully!');
      process.exit(0);
    })
    .catch((error) => {
      console.error('\n💥 Trip ID migration failed:', error);
      process.exit(1);
    });
}

module.exports = { migrateTripIds };