// test-direct-notification-query.js - Direct MongoDB query to check notifications

const mongoose = require('mongoose');
require('dotenv').config({ path: './.env' });

async function testDirectQuery() {
  try {
    console.log('🔍 Testing Direct MongoDB Query\n');
    console.log('📡 Connecting to MongoDB...');
    if (process.env.MONGODB_URI) {
      console.log('  URI:', process.env.MONGODB_URI.replace(/\/\/([^:]+):([^@]+)@/, '//$1:****@'));
    } else {
      console.log('  ❌ MONGODB_URI not found in environment!');
      return;
    }
    console.log('');
    
    await mongoose.connect(process.env.MONGODB_URI);
    
    console.log('✅ Connected to MongoDB');
    console.log('  Database:', mongoose.connection.db.databaseName);
    console.log('  Host:', mongoose.connection.host);
    console.log('');
    
    const db = mongoose.connection.db;
    
    // Check if notifications collection exists
    const collections = await db.listCollections().toArray();
    const notificationCollection = collections.find(c => c.name === 'notifications');
    
    if (!notificationCollection) {
      console.log('❌ Notifications collection does NOT exist in this database!');
      console.log('');
      console.log('📋 Available collections:');
      collections.forEach(c => console.log('  -', c.name));
      await mongoose.connection.close();
      return;
    }
    
    console.log('✅ Notifications collection exists');
    console.log('');
    
    // Count total notifications
    const totalCount = await db.collection('notifications').countDocuments({});
    console.log('📊 Total notifications in database:', totalCount);
    console.log('');
    
    // Query by email
    const emailQuery = { userEmail: 'amit.singh@abrafleet.com' };
    const emailNotifications = await db.collection('notifications')
      .find(emailQuery)
      .sort({ createdAt: -1 })
      .limit(5)
      .toArray();
    
    console.log('🔍 Query by email (amit.singh@abrafleet.com):');
    console.log('  Found:', emailNotifications.length, 'notifications');
    
    if (emailNotifications.length > 0) {
      console.log('');
      console.log('📬 Latest notification:');
      const latest = emailNotifications[0];
      console.log('  _id:', latest._id);
      console.log('  userId:', latest.userId);
      console.log('  userEmail:', latest.userEmail);
      console.log('  type:', latest.type);
      console.log('  title:', latest.title);
      console.log('  tripNumber:', latest.tripNumber);
      console.log('  isRead:', latest.isRead);
      console.log('  createdAt:', latest.createdAt);
      console.log('');
      console.log('✅ NOTIFICATION FOUND IN DATABASE!');
      console.log('   This means the backend IS connected to the correct database.');
      console.log('   The issue must be in the query logic or JWT token.');
    } else {
      console.log('  ❌ No notifications found for this email');
      console.log('');
      console.log('🔍 Let me check what emails exist...');
      
      const allNotifications = await db.collection('notifications')
        .find({})
        .limit(10)
        .toArray();
      
      console.log('');
      console.log('📋 Sample notifications in database:');
      allNotifications.forEach((n, i) => {
        console.log(`  ${i + 1}. userEmail: ${n.userEmail}, userId: ${n.userId}, type: ${n.type}`);
      });
    }
    
    console.log('');
    console.log('🔍 Query by userId (694a7fcd0c69d7fbd556eae8):');
    const userIdQuery = { userId: '694a7fcd0c69d7fbd556eae8' };
    const userIdNotifications = await db.collection('notifications')
      .find(userIdQuery)
      .sort({ createdAt: -1 })
      .limit(5)
      .toArray();
    
    console.log('  Found:', userIdNotifications.length, 'notifications');
    
    if (userIdNotifications.length > 0) {
      console.log('');
      console.log('📬 Latest notification by userId:');
      const latest = userIdNotifications[0];
      console.log('  _id:', latest._id);
      console.log('  userId:', latest.userId);
      console.log('  userEmail:', latest.userEmail);
      console.log('  type:', latest.type);
      console.log('  title:', latest.title);
    }
    
    console.log('');
    console.log('🔍 Query with $or (email OR userId):');
    const orQuery = {
      $or: [
        { userId: '694a7fcd0c69d7fbd556eae8' },
        { userEmail: 'amit.singh@abrafleet.com' }
      ]
    };
    const orNotifications = await db.collection('notifications')
      .find(orQuery)
      .sort({ createdAt: -1 })
      .limit(5)
      .toArray();
    
    console.log('  Found:', orNotifications.length, 'notifications');
    
    if (orNotifications.length > 0) {
      console.log('');
      console.log('✅ $or query WORKS! Found notifications.');
      console.log('');
      console.log('🎯 CONCLUSION:');
      console.log('  - Database connection: ✅ Correct (Atlas cluster)');
      console.log('  - Notifications exist: ✅ Yes');
      console.log('  - Query logic: ✅ Works');
      console.log('');
      console.log('❓ WHY IS API RETURNING EMPTY?');
      console.log('  Possible reasons:');
      console.log('  1. JWT token has wrong userId/email');
      console.log('  2. Backend not restarted after router fix');
      console.log('  3. Different database being used by API');
    } else {
      console.log('  ❌ No notifications found with $or query');
    }
    
    await mongoose.connection.close();
    console.log('');
    console.log('✅ Connection closed');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    if (mongoose.connection.readyState) {
      await mongoose.connection.close();
    }
  }
}

testDirectQuery();
