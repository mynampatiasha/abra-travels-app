const axios = require('axios');

async function testDriverRoute() {
    const BASE_URL = 'http://localhost:3001';
    
    try {
        console.log('🧪 Testing Driver Route API with Fixed Data Structure');
        console.log('================================================\n');
        
        // We need to use Rajesh Kumar's Firebase UID since he's the only one with proper auth
        const firebaseUid = 'aVIF9Ahluig993fCNyZRrIDC3KO2';
        
        // For testing, we'll simulate the Firebase token
        // In real app, this comes from Firebase Auth
        console.log('📝 Using Firebase UID:', firebaseUid);
        console.log('   (This is Rajesh Kumar - the only driver with proper Firebase auth)\n');
        
        // Create a mock token for testing
        const mockToken = 'mock-token-for-testing';
        
        console.log('📡 Calling /api/driver/route/today...\n');
        
        // Make the API call
        const response = await axios.get(`${BASE_URL}/api/driver/route/today`, {
            headers: {
                'Authorization': `Bearer ${mockToken}`,
                'Content-Type': 'application/json',
                // Add a custom header to simulate the Firebase UID for testing
                'X-Test-Firebase-UID': firebaseUid
            }
        });
        
        console.log('✅ API Response Status:', response.status);
        console.log('📄 Response Data:\n');
        
        const data = response.data;
        
        if (data.status === 'success' && data.data.hasRoute) {
            console.log('🚗 Vehicle Info:');
            if (data.data.vehicle) {
                console.log(`   - Registration: ${data.data.vehicle.registrationNumber}`);
                console.log(`   - Model: ${data.data.vehicle.model}`);
                console.log(`   - Available Seats: ${data.data.vehicle.availableSeats}`);
            }
            
            console.log('\n📊 Route Summary:');
            console.log(`   - Total Customers: ${data.data.routeSummary.totalCustomers}`);
            console.log(`   - Total Distance: ${data.data.routeSummary.totalDistance} KM`);
            
            console.log('\n👥 Customer Details:');
            console.log('===================');
            
            data.data.customers.forEach((customer, index) => {
                console.log(`\n${index + 1}. ${customer.name}`);
                console.log(`   📞 Phone: ${customer.phone}`);
                console.log(`   📧 Email: ${customer.email}`);
                console.log(`   🏠 From: ${customer.fromLocation}`);
                console.log(`   🏢 To: ${customer.toLocation}`);
                console.log(`   ⏰ Time: ${customer.scheduledTime}`);
                console.log(`   📍 Status: ${customer.status}`);
                console.log(`   🚗 Trip Type: ${customer.tripTypeLabel}`);
            });
            
        } else {
            console.log('❌ No route found or API error');
            console.log('Response:', JSON.stringify(data, null, 2));
        }
        
    } catch (error) {
        console.error('❌ Error testing API:', error.message);
        if (error.response) {
            console.error('Response status:', error.response.status);
            console.error('Response data:', error.response.data);
        }
    }
}

// Run the test
testDriverRoute();