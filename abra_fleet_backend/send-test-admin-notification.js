// send-test-admin-notification.js
// Send a test notification to admin for the existing approved leave

require('dotenv').config();
const { MongoClient } = require('mongodb');
const admin = require('./config/firebase'); // Initialize Firebase
const { createNotification } = require('./models/notification_model');

const MONGODB_URI = process.env.MONGODB_URI;
const DB_NAME = process.env.DB_NAME || 'abra_fleet';

async function sendTestAdminNotification() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    console.log('🔌 Connecting to MongoDB...');
    await client.connect();
    const db = client.db(DB_NAME);
    
    // Get the approved leave request
    const approvedLeave = await db.collection('leave_requests').findOne({
      status: 'approved'
    });
    
    if (!approvedLeave) {
      console.log('❌ No approved leave requests found.');
      return;
    }
    
    console.log('\n✅ Found approved leave request:');
    console.log(`   - Customer: ${approvedLeave.customerName}`);
    console.log(`   - Period: ${approvedLeave.startDate} to ${approvedLeave.endDate}`);
    
    // Get all admin users
    const adminUsers = await db.collection('users').find({ 
      role: 'admin' 
    }).toArray();
    
    console.log(`\n✅ Found ${adminUsers.length} admin user(s)`);
    
    console.log('\n🔔 Sending notification to all admins...\n');
    
    for (const admin of adminUsers) {
      try {
        console.log(`📤 Sending to: ${admin.email} (${admin.firebaseUid})`);
        
        const result = await createNotification(db, {
          userId: admin.firebaseUid,
          type: 'leave_approved_admin',
          title: 'Leave Request Approved - Action Required',
          body: `Leave request approved for ${approvedLeave.customerName} from ${approvedLeave.startDate.toDateString()} to ${approvedLeave.endDate.toDateString()}. Please cancel the associated trips.`,
          priority: 'urgent',
          category: 'leave_management',
          data: {
            leaveRequestId: approvedLeave._id.toString(),
            customerId: approvedLeave.customerId,
            customerName: approvedLeave.customerName,
            startDate: approvedLeave.startDate.toISOString(),
            endDate: approvedLeave.endDate.toISOString(),
            affectedTripsCount: approvedLeave.affectedTripsCount || 0,
            approvedBy: approvedLeave.approvedBy || 'System'
          }
        });
        
        console.log(`✅ Notification created with ID: ${result._id}\n`);
      } catch (error) {
        console.error(`❌ Failed to send to ${admin.email}:`, error.message);
      }
    }
    
    console.log('\n✅ DONE! Now check the admin dashboard notification bell.');
    
  } catch (error) {
    console.error('\n❌ ERROR:', error.message);
    console.error(error.stack);
  } finally {
    await client.close();
    console.log('\n🔌 Disconnected from MongoDB\n');
  }
}

sendTestAdminNotification();
