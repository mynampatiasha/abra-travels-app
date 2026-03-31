// Script to initialize readable IDs for existing rosters
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function initializeRosterIds() {
  let client;
  
  try {
    console.log('🔍 Connecting to MongoDB...');
    client = new MongoClient(process.env.MONGODB_URI);
    await client.connect();
    
    const db = client.db('abra_fleet');
    
    console.log('📊 Initializing roster ID system...');
    
    // Initialize counter if it doesn't exist
    const counterExists = await db.collection('counters').findOne({ _id: 'roster_sequence' });
    if (!counterExists) {
      await db.collection('counters').insertOne({ _id: 'roster_sequence', sequence: 0 });
      console.log('✅ Counter initialized');
    } else {
      console.log('✅ Counter already exists with sequence:', counterExists.sequence);
    }
    
    // Get all rosters without readable IDs
    const rostersWithoutIds = await db.collection('rosters').find({
      readableId: { $exists: false }
    }).sort({ createdAt: 1 }).toArray();
    
    console.log(`📋 Found ${rostersWithoutIds.length} rosters without readable IDs`);
    
    if (rostersWithoutIds.length === 0) {
      console.log('✅ All rosters already have readable IDs');
      return;
    }
    
    // Reset counter to 0 first
    await db.collection('counters').updateOne(
      { _id: 'roster_sequence' },
      { $set: { sequence: 0 } }
    );
    
    // Generate readable IDs for existing rosters
    for (let i = 0; i < rostersWithoutIds.length; i++) {
      const roster = rostersWithoutIds[i];
      
      // Get next sequence number
      try {
        const counterResult = await db.collection('counters').findOneAndUpdate(
          { _id: 'roster_sequence' },
          { $inc: { sequence: 1 } },
          { 
            returnDocument: 'after',
            upsert: true
          }
        );
        
        console.log(`Debug - Counter result for ${i + 1}:`, counterResult);
        
        const sequenceNumber = counterResult?.value?.sequence || (i + 1);
        const readableId = `RST-${String(sequenceNumber).padStart(4, '0')}`;
        
        // Update roster with readable ID
        await db.collection('rosters').updateOne(
          { _id: roster._id },
          { $set: { readableId: readableId } }
        );
        
        console.log(`✅ ${i + 1}/${rostersWithoutIds.length}: ${roster._id} → ${readableId}`);
        
      } catch (error) {
        console.error(`❌ Error processing roster ${i + 1}:`, error);
        // Use fallback ID
        const fallbackId = `RST-${String(i + 1).padStart(4, '0')}`;
        await db.collection('rosters').updateOne(
          { _id: roster._id },
          { $set: { readableId: fallbackId } }
        );
        console.log(`🔄 ${i + 1}/${rostersWithoutIds.length}: ${roster._id} → ${fallbackId} (fallback)`);
      }
    }
    
    console.log('🎉 All rosters now have readable IDs!');
    
    // Show final counter value
    const finalCounter = await db.collection('counters').findOne({ _id: 'roster_sequence' });
    console.log(`📊 Final sequence number: ${finalCounter.sequence}`);
    
  } catch (error) {
    console.error('❌ Error initializing roster IDs:', error);
  } finally {
    if (client) {
      await client.close();
      console.log('✅ Database connection closed');
    }
  }
}

initializeRosterIds();