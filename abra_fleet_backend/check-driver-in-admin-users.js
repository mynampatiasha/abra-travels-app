// Check if driver exists in admin_users collection
const { MongoClient } = require('mongodb');

const MONGODB_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0';
const DATABASE_NAME = 'abrafleet';

// Driver Firebase UID from credentials
const DRIVER_UID = 'wvm5wdXaWNOAqVOXX5l8fWbfYFz2';
const DRIVER_EMAIL = 'drivertest@gmail.com';

async function checkDriverInAdminUsers() {
    console.log('🔍 Checking driver in admin_users collection...');
    
    const client = new MongoClient(MONGODB_URI);
    
    try {
        await client.connect();
        console.log('✅ Connected to MongoDB');
        
        const db = client.db(DATABASE_NAME);
        
        // Check admin_users collection
        console.log('\n📋 Checking admin_users collection:');
        const adminUser = await db.collection('admin_users').findOne({
            $or: [
                { firebaseUid: DRIVER_UID },
                { email: DRIVER_EMAIL }
            ]
        });
        
        if (adminUser) {
            console.log('✅ Driver found in admin_users:');
            console.log('   ID:', adminUser._id);
            console.log('   Email:', adminUser.email);
            console.log('   Firebase UID:', adminUser.firebaseUid);
            console.log('   Role:', adminUser.role);
            console.log('   Status:', adminUser.status);
        } else {
            console.log('❌ Driver NOT found in admin_users');
            
            // Check if there are any users in admin_users
            const totalUsers = await db.collection('admin_users').countDocuments();
            console.log(`   Total users in admin_users: ${totalUsers}`);
            
            if (totalUsers > 0) {
                console.log('\n📋 Sample users in admin_users:');
                const sampleUsers = await db.collection('admin_users').find({}).limit(5).toArray();
                sampleUsers.forEach((user, index) => {
                    console.log(`   ${index + 1}. ${user.email} (${user.role}) - UID: ${user.firebaseUid || 'none'}`);
                });
            }
        }
        
        // Check drivers collection
        console.log('\n🚗 Checking drivers collection:');
        const driver = await db.collection('drivers').findOne({
            $or: [
                { firebaseUid: DRIVER_UID },
                { email: DRIVER_EMAIL },
                { 'personalInfo.email': DRIVER_EMAIL }
            ]
        });
        
        if (driver) {
            console.log('✅ Driver found in drivers collection:');
            console.log('   ID:', driver._id);
            console.log('   Email:', driver.email || driver.personalInfo?.email);
            console.log('   Firebase UID:', driver.firebaseUid);
            console.log('   Name:', driver.name || driver.personalInfo?.name);
            console.log('   Status:', driver.status);
        } else {
            console.log('❌ Driver NOT found in drivers collection');
        }
        
        // Check users collection
        console.log('\n👤 Checking users collection:');
        const user = await db.collection('users').findOne({
            $or: [
                { firebaseUid: DRIVER_UID },
                { email: DRIVER_EMAIL }
            ]
        });
        
        if (user) {
            console.log('✅ Driver found in users collection:');
            console.log('   ID:', user._id);
            console.log('   Email:', user.email);
            console.log('   Firebase UID:', user.firebaseUid);
            console.log('   Role:', user.role);
        } else {
            console.log('❌ Driver NOT found in users collection');
        }
        
        // Check notifications
        console.log('\n🔔 Checking notifications:');
        const notifications = await db.collection('notifications').find({
            userId: DRIVER_UID
        }).toArray();
        
        console.log(`📬 Found ${notifications.length} notifications for driver UID: ${DRIVER_UID}`);
        
        if (notifications.length > 0) {
            console.log('\n📋 Notification details:');
            notifications.forEach((notif, index) => {
                console.log(`   ${index + 1}. ${notif.title} (${notif.type}) - ${notif.isRead ? 'Read' : 'Unread'}`);
            });
        }
        
    } catch (error) {
        console.error('❌ Error:', error);
    } finally {
        await client.close();
        console.log('\n🔌 MongoDB connection closed');
    }
}

checkDriverInAdminUsers();