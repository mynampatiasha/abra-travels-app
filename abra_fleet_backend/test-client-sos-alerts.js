// Test script for Client SOS Alerts with Organization Filtering
const admin = require('firebase-admin');

// Initialize Firebase Admin
try {
    const serviceAccount = require('./config/firebase-service-account.json');
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
        databaseURL: process.env.FIREBASE_DATABASE_URL || 'https://abra-fleet-default-rtdb.firebaseio.com'
    });
    console.log('✅ Firebase Admin initialized');
} catch (error) {
    console.error('❌ Firebase initialization error:', error.message);
    process.exit(1);
}

async function testClientSOSAlerts() {
    console.log('');
    console.log('═══════════════════════════════════════════════════════');
    console.log('🚨 CLIENT SOS ALERTS TEST');
    console.log('═══════════════════════════════════════════════════════');
    console.log('');

    try {
        const db = admin.database();
        const sosRef = db.ref('sos_events');

        // Create test SOS alerts for different organizations
        const testAlerts = [
            {
                customerId: 'cust001',
                customerName: 'John Doe',
                customerEmail: 'john.doe@cognizant.com',
                assignedDriverId: 'drv001',
                gps: {
                    latitude: 12.9716,
                    longitude: 77.5946
                },
                address: 'MG Road, Bangalore, Karnataka, India',
                status: 'ACTIVE',
                timestamp: new Date().toISOString(),
                createdAt: new Date().toISOString()
            },
            {
                customerId: 'cust002',
                customerName: 'Jane Smith',
                customerEmail: 'jane.smith@cognizant.com',
                assignedDriverId: 'drv002',
                gps: {
                    latitude: 12.9352,
                    longitude: 77.6245
                },
                address: 'Whitefield, Bangalore, Karnataka, India',
                status: 'Pending',
                timestamp: new Date(Date.now() - 3600000).toISOString(), // 1 hour ago
                createdAt: new Date(Date.now() - 3600000).toISOString()
            },
            {
                customerId: 'cust003',
                customerName: 'Bob Johnson',
                customerEmail: 'bob.johnson@tcs.com',
                assignedDriverId: 'drv003',
                gps: {
                    latitude: 12.9141,
                    longitude: 77.6411
                },
                address: 'Electronic City, Bangalore, Karnataka, India',
                status: 'In Progress',
                timestamp: new Date(Date.now() - 7200000).toISOString(), // 2 hours ago
                createdAt: new Date(Date.now() - 7200000).toISOString()
            },
            {
                customerId: 'cust004',
                customerName: 'Alice Williams',
                customerEmail: 'alice.williams@abrafleet.com',
                assignedDriverId: 'drv004',
                gps: {
                    latitude: 12.9698,
                    longitude: 77.7500
                },
                address: 'Marathahalli, Bangalore, Karnataka, India',
                status: 'Resolved',
                timestamp: new Date(Date.now() - 86400000).toISOString(), // 1 day ago
                createdAt: new Date(Date.now() - 86400000).toISOString()
            },
            {
                customerId: 'cust005',
                customerName: 'Charlie Brown',
                customerEmail: 'charlie.brown@cognizant.com',
                assignedDriverId: 'drv005',
                gps: {
                    latitude: 13.0358,
                    longitude: 77.5970
                },
                address: 'Hebbal, Bangalore, Karnataka, India',
                status: 'Escalated',
                timestamp: new Date(Date.now() - 1800000).toISOString(), // 30 minutes ago
                createdAt: new Date(Date.now() - 1800000).toISOString()
            }
        ];

        console.log('📝 Creating test SOS alerts...');
        console.log('');

        for (const alert of testAlerts) {
            const newRef = sosRef.push();
            await newRef.set(alert);
            console.log(`✅ Created SOS alert for ${alert.customerName} (${alert.customerEmail})`);
            console.log(`   Status: ${alert.status}`);
            console.log(`   Location: ${alert.address}`);
            console.log(`   Alert ID: ${newRef.key}`);
            console.log('');
        }

        console.log('');
        console.log('═══════════════════════════════════════════════════════');
        console.log('📊 ORGANIZATION BREAKDOWN');
        console.log('═══════════════════════════════════════════════════════');
        console.log('');

        // Count by organization
        const cognizantAlerts = testAlerts.filter(a => a.customerEmail.endsWith('@cognizant.com'));
        const tcsAlerts = testAlerts.filter(a => a.customerEmail.endsWith('@tcs.com'));
        const abrafleetAlerts = testAlerts.filter(a => a.customerEmail.endsWith('@abrafleet.com'));

        console.log(`🏢 @cognizant.com: ${cognizantAlerts.length} alerts`);
        cognizantAlerts.forEach(a => console.log(`   - ${a.customerName} (${a.status})`));
        console.log('');

        console.log(`🏢 @tcs.com: ${tcsAlerts.length} alerts`);
        tcsAlerts.forEach(a => console.log(`   - ${a.customerName} (${a.status})`));
        console.log('');

        console.log(`🏢 @abrafleet.com: ${abrafleetAlerts.length} alerts`);
        abrafleetAlerts.forEach(a => console.log(`   - ${a.customerName} (${a.status})`));
        console.log('');

        console.log('');
        console.log('═══════════════════════════════════════════════════════');
        console.log('📋 STATUS BREAKDOWN');
        console.log('═══════════════════════════════════════════════════════');
        console.log('');

        const statusCounts = testAlerts.reduce((acc, alert) => {
            acc[alert.status] = (acc[alert.status] || 0) + 1;
            return acc;
        }, {});

        Object.entries(statusCounts).forEach(([status, count]) => {
            console.log(`${status}: ${count} alerts`);
        });

        console.log('');
        console.log('═══════════════════════════════════════════════════════');
        console.log('✅ TEST COMPLETE');
        console.log('═══════════════════════════════════════════════════════');
        console.log('');
        console.log('📱 Now you can:');
        console.log('   1. Login as a client user (e.g., client@cognizant.com)');
        console.log('   2. Navigate to SOS Alerts section');
        console.log('   3. You should see only alerts from your organization');
        console.log('   4. Test filters: Status, Time, Search');
        console.log('');
        console.log('🔍 Expected Results:');
        console.log('   - client@cognizant.com should see 3 alerts');
        console.log('   - client@tcs.com should see 1 alert');
        console.log('   - client@abrafleet.com should see 1 alert');
        console.log('');

    } catch (error) {
        console.error('❌ Error:', error);
    }

    process.exit(0);
}

testClientSOSAlerts();
