// Script to check rosters created by admin
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function checkAdminRosters() {
  let client;
  
  try {
    console.log('🔍 Connecting to MongoDB...');
    client = new MongoClient(process.env.MONGODB_URI);
    await client.connect();
    
    const db = client.db('abra_fleet');
    
    console.log('📊 Checking rosters and their creators...');
    
    // Get unique createdBy values
    const creators = await db.collection('rosters').distinct('createdBy');
    console.log('👥 Unique roster creators:', creators);
    
    // Check rosters created by admin-like UIDs
    for (const creatorId of creators) {
      const rosterCount = await db.collection('rosters').countDocuments({ createdBy: creatorId });
      console.log(`📋 Creator ${creatorId}: ${rosterCount} rosters`);
      
      // Try to find this user in users collection
      const user = await db.collection('users').findOne({ firebaseUid: creatorId });
      if (user) {
        console.log(`   👤 User found: ${user.email} (${user.name}) - Role: ${user.role || 'NO ROLE'}`);
      } else {
        console.log(`   ❌ User not found in users collection`);
        
        // This might be the admin - let's check recent rosters
        const recentRosters = await db.collection('rosters')
          .find({ createdBy: creatorId })
          .sort({ createdAt: -1 })
          .limit(3)
          .toArray();
          
        console.log(`   📋 Recent rosters by this creator:`);
        recentRosters.forEach(roster => {
          console.log(`      - ${roster.customerName || 'Unknown'} (${roster.customerEmail || 'No email'})`);
        });
      }
    }
    
    // Check if admin email appears in any roster data
    console.log('\n🔍 Searching for admin@abrafleet.com in roster data...');
    const adminRosters = await db.collection('rosters').find({
      $or: [
        { customerEmail: 'admin@abrafleet.com' },
        { customerName: { $regex: /admin/i } },
        { createdByAdmin: { $regex: /admin/i } }
      ]
    }).toArray();
    
    console.log(`📧 Found ${adminRosters.length} rosters with admin email/name`);
    adminRosters.forEach(roster => {
      console.log(`   - ID: ${roster._id}`);
      console.log(`     Customer: ${roster.customerName} (${roster.customerEmail})`);
      console.log(`     Created by: ${roster.createdBy}`);
      console.log(`     Created by admin: ${roster.createdByAdmin}`);
    });
    
  } catch (error) {
    console.error('❌ Error checking admin rosters:', error);
  } finally {
    if (client) {
      await client.close();
      console.log('✅ Database connection closed');
    }
  }
}

checkAdminRosters();