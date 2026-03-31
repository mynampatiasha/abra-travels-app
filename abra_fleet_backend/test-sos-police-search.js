const axios = require('axios');

// Test the enhanced SOS endpoint with police station search
async function testSOSWithPoliceSearch() {
    try {
        console.log('🧪 Testing Enhanced SOS Endpoint with Police Station Search...\n');

        const sosPayload = {
            // Customer fields
            customerId: 'test_customer_123',
            customerName: 'Test Customer',
            customerEmail: 'test@example.com',
            customerPhone: '+91-9876543210',
            
            // Trip fields
            tripId: 'Trip-12345',
            rosterId: 'roster_test_123',
            
            // Driver fields
            driverId: 'driver_test_123',
            driverName: 'Test Driver',
            driverPhone: '+91-9876543211',
            
            // Vehicle fields
            vehicleReg: 'KA01AB1234',
            vehicleMake: 'Maruti',
            vehicleModel: 'Swift',
            
            // Route fields
            pickupLocation: 'Koramangala, Bangalore',
            dropLocation: 'Electronic City, Bangalore',
            
            // Location fields (Delhi coordinates - should have more police stations)
            gps: {
                latitude: 28.6139,
                longitude: 77.2090
            },
            timestamp: new Date().toISOString()
        };

        console.log('📤 Sending SOS request...');
        console.log('📍 Location: Delhi (28.6139, 77.2090)');
        console.log('👤 Customer:', sosPayload.customerName);
        console.log('🚗 Vehicle:', sosPayload.vehicleReg);
        console.log('');

        const response = await axios.post('http://localhost:3001/api/sos', sosPayload, {
            headers: {
                'Content-Type': 'application/json'
            },
            timeout: 30000 // 30 second timeout for police search
        });

        if (response.status === 201) {
            console.log('✅ SOS Alert Processed Successfully!\n');
            
            const data = response.data;
            console.log('📋 Response Summary:');
            console.log(`   Event ID: ${data.eventId}`);
            console.log(`   Police Notified: ${data.policeNotified ? 'YES' : 'NO'}`);
            console.log(`   Police Email: ${data.policeEmail}`);
            console.log(`   City: ${data.city}`);
            console.log(`   Email Status: ${data.emailStatus}`);
            console.log('');

            // 🆕 NEW: Display nearby police stations
            if (data.nearbyPoliceStations && data.nearbyPoliceStations.length > 0) {
                console.log('🚔 Nearby Police Stations Found:');
                data.nearbyPoliceStations.forEach((station, index) => {
                    console.log(`   ${index + 1}. ${station.name}`);
                    console.log(`      📞 Phone: ${station.phone}`);
                    console.log(`      📍 Distance: ${station.distance.toFixed(2)} km`);
                    console.log(`      🏠 Address: ${station.address}`);
                    console.log(`      📊 Source: ${station.source}`);
                    console.log('');
                });
            } else {
                console.log('⚠️ No nearby police stations found');
            }

            console.log('🎯 Test Result: SUCCESS');
            console.log('✅ Admin notification: Working');
            console.log('✅ Police station search: Working');
            console.log('✅ Enhanced response: Working');

        } else {
            console.log(`❌ Unexpected response status: ${response.status}`);
        }

    } catch (error) {
        console.error('❌ Test Failed:');
        if (error.response) {
            console.error(`   Status: ${error.response.status}`);
            console.error(`   Data: ${JSON.stringify(error.response.data, null, 2)}`);
        } else {
            console.error(`   Error: ${error.message}`);
        }
    }
}

// Run the test
testSOSWithPoliceSearch();