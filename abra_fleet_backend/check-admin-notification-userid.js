// check-admin-notification-userid.js
// Check if admin notifications have the correct userId field

require('dotenv').config();
const { MongoClient } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI;
const DB_NAME = process.env.DB_NAME || 'abra_fleet';
const ADMIN_UID = 'FCxbtU52hQYSATfNDIadNhptkWq2'; // admin@abrafleet.com

async function checkAdminNotificationUserId() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    console.log('🔌 Connecting to MongoDB...');
    await client.connect();
    const db = client.db(DB_NAME);
    
    console.log('\n🔍 CHECKING ADMIN NOTIFICATIONS');
    console.log('='.repeat(80));
    console.log(`Admin UID: ${ADMIN_UID}\n`);
    
    // Get all leave_approved_admin notifications
    const notifications = await db.collection('notifications').find({
      type: 'leave_approved_admin'
    }).sort({ createdAt: -1 }).toArray();
    
    console.log(`📊 Total leave_approved_admin notifications: ${notifications.length}\n`);
    
    if (notifications.length === 0) {
  