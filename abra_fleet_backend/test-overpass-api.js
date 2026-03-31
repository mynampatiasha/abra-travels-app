const axios = require('axios');

async function testOverpassAPI() {
    try {
        console.log('🧪 Testing Overpass API directly...\n');

        // Test coordinates for Delhi (should have police stations)
        const latitude = 28.6139;
        const longitude = 77.2090;
        const radiusKm = 5;

        const overpassQuery = `
            [out:json][timeout:25];
            (
              node["amenity"="police"](around:${radiusKm * 1000},${latitude},${longitude});
              way["amenity"="police"](around:${radiusKm * 1000},${latitude},${longitude});
              relation["amenity"="police"](around:${radiusKm * 1000},${latitude},${longitude});
            );
            out center meta;
        `;

        console.log('📍 Searching near Delhi:', latitude, longitude);
        console.log('🔍 Radius:', radiusKm, 'km');
        console.log('');

        const overpassUrl = 'https://overpass-api.de/api/interpreter';
        
        console.log('📤 Sending request to Overpass API...');
        const response = await axios.post(overpassUrl, overpassQuery, {
            headers: {
                'Content-Type': 'text/plain',
                'User-Agent': 'AbraFleetSOS/1.0'
            },
            timeout: 15000
        });

        console.log('✅ Response received!');
        console.log('Status:', response.status);
        console.log('Data type:', typeof response.data);
        
        if (response.data && response.data.elements) {
            console.log('📊 Elements found:', response.data.elements.length);
            
            if (response.data.elements.length > 0) {
                console.log('\n🚔 Police stations found:');
                response.data.elements.slice(0, 3).forEach((element, index) => {
                    const tags = element.tags || {};
                    const name = tags.name || tags['name:en'] || 'Police Station';
                    const phone = tags.phone || tags['contact:phone'] || 'N/A';
                    
                    let lat, lon;
                    if (element.type === 'node') {
                        lat = element.lat;
                        lon = element.lon;
                    } else if (element.center) {
                        lat = element.center.lat;
                        lon = element.center.lon;
                    }
                    
                    console.log(`   ${index + 1}. ${name}`);
                    console.log(`      📞 Phone: ${phone}`);
                    console.log(`      📍 Coordinates: ${lat}, ${lon}`);
                    console.log(`      🏷️ Tags:`, Object.keys(tags).length, 'properties');
                    console.log('');
                });
            } else {
                console.log('⚠️ No police stations found in this area');
            }
        } else {
            console.log('❌ No elements in response');
            console.log('Response data:', JSON.stringify(response.data, null, 2));
        }

    } catch (error) {
        console.error('❌ Error testing Overpass API:');
        if (error.response) {
            console.error('   Status:', error.response.status);
            console.error('   Status Text:', error.response.statusText);
            console.error('   Data:', error.response.data);
        } else if (error.request) {
            console.error('   No response received');
            console.error('   Request error:', error.message);
        } else {
            console.error('   Error:', error.message);
        }
    }
}

testOverpassAPI();