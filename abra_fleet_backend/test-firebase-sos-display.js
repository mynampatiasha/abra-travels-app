const admin = require('./config/firebase');

async function testFirebaseSOSDisplay() {
    try {
        console.log('🧪 Testing Firebase SOS Display...\n');

        const db = admin.database();
        const sosRef = db.ref('sos_events');

        // First, let's check existing SOS events
        console.log('📋 Checking existing SOS events...');
        const snapshot = await sosRef.once('value');
        const existingEvents = snapshot.val();

        if (existingEvents) {
            console.log(`✅ Found ${Object.keys(existingEvents).length} existing SOS events:`);
            Object.entries(existingEvents).forEach(([key, value]) => {
                const event = value;
                console.log(`   ${key}:`);
                console.log(`     Customer: ${event.customerName || 'N/A'}`);
                console.log(`     Status: ${event.status || 'N/A'}`);
                console.log(`     Timestamp: ${event.timestamp || 'N/A'}`);
                console.log(`     Driver: ${event.driverName || 'N/A'}`);
                console.log(`     Vehicle: ${event.vehicleReg || 'N/A'}`);
                console.log(`     Police Notified: ${event.emailSentStatus || 'N/A'}`);
                console.log('');
            });
        } else {
            console.log('⚠️ No existing SOS events found');
        }

        // Create a test SOS event to verify admin dashboard display
        console.log('🆕 Creating test SOS event for admin dashboard...');
        
        const testEventId = 'test_' + Date.now();
        const testSOSEvent = {
            // Customer fields
            customerId: 'test_customer_admin_display',
            customerName: 'Test Customer (Admin Display)',
            customerEmail: 'test.admin@example.com',
            customerPhone: '+91-9876543210',
            
            // Trip fields
            tripId: 'Trip-99999',
            rosterId: 'roster_test_admin',
            
            // Driver fields
            driverId: 'driver_test_admin',
            driverName: 'Test Driver (Admin)',
            driverPhone: '+91-9876543211',
            
            // Vehicle fields
            vehicleReg: 'TEST1234',
            vehicleMake: 'Test',
            vehicleModel: 'Vehicle',
            
            // Route fields
            pickupLocation: 'Test Pickup Location',
            dropLocation: 'Test Drop Location',
            
            // Location fields
            gps: {
                latitude: 28.6139,
                longitude: 77.2090
            },
            address: 'Test Location, New Delhi, India',
            
            // Status fields
            status: 'ACTIVE',
            timestamp: new Date().toISOString(),
            adminNotes: '',
            
            // Police notification fields (from enhanced backend)
            policeEmailContacted: null,
            emailSentStatus: 'no_contact_found',
            policeCity: 'Delhi',
            
            // MongoDB reference
            mongoId: 'test_mongo_id_' + Date.now()
        };

        await sosRef.child(testEventId).set(testSOSEvent);
        console.log(`✅ Test SOS event created with ID: ${testEventId}`);
        console.log('📱 This should now appear in the admin dashboard!');
        console.log('');

        // Verify the event was created
        console.log('🔍 Verifying test event creation...');
        const verifySnapshot = await sosRef.child(testEventId).once('value');
        const createdEvent = verifySnapshot.val();
        
        if (createdEvent) {
            console.log('✅ Test event verified in Firebase:');
            console.log(`   Customer: ${createdEvent.customerName}`);
            console.log(`   Status: ${createdEvent.status}`);
            console.log(`   Driver: ${createdEvent.driverName}`);
            console.log(`   Vehicle: ${createdEvent.vehicleReg}`);
            console.log(`   Location: ${createdEvent.address}`);
            console.log(`   Police Status: ${createdEvent.emailSentStatus}`);
            console.log('');
            
            console.log('🎯 ADMIN DASHBOARD TEST:');
            console.log('1. ✅ SOS event created in Firebase');
            console.log('2. 📱 Should appear in admin dashboard immediately');
            console.log('3. 🔔 Should trigger audio alert (if enabled)');
            console.log('4. 📊 Should show in SOS alerts counter');
            console.log('5. 🗺️ Should be clickable to view on map');
            console.log('');
            
            console.log('🧹 Cleanup: To remove test event, run:');
            console.log(`   firebase database:remove /sos_events/${testEventId}`);
            
        } else {
            console.log('❌ Failed to verify test event creation');
        }

    } catch (error) {
        console.error('❌ Error testing Firebase SOS display:', error);
    }
}

// Run the test
testFirebaseSOSDisplay();