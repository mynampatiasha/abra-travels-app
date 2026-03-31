require('dotenv').config();
const { MongoClient } = require('mongodb');

async function testPendingRostersAtlas() {
    console.log('🧪 TESTING PENDING ROSTERS WITH ATLAS');
    console.log('==================================================');
    
    let client;
    
    try {
        // Connect to MongoDB Atlas
        console.log('🔌 Connecting to MongoDB Atlas...');
        console.log('MongoDB URI:', process.env.MONGODB_URI ? 'SET' : 'NOT SET');
        
        client = new MongoClient(process.env.MONGODB_URI);
        await client.connect();
        console.log('✅ Connected to MongoDB Atlas');
        
        const db = client.db('abra_fleet');
        
        // Test 1: Check if rosters collection exists
        console.log('\n📋 Test 1: Checking rosters collection...');
        const collections = await db.listCollections().toArray();
        const rosterCollection = collections.find(col => col.name === 'rosters');
        
        if (rosterCollection) {
            console.log('✅ Rosters collection exists');
        } else {
            console.log('❌ Rosters collection not found');
            console.log('Available collections:', collections.map(c => c.name));
        }
        
        // Test 2: Count total rosters
        console.log('\n📊 Test 2: Counting rosters...');
        const totalRosters = await db.collection('rosters').countDocuments();
        console.log(`📈 Total rosters: ${totalRosters}`);
        
        // Test 3: Count pending rosters
        console.log('\n⏳ Test 3: Counting pending rosters...');
        const pendingRosters = await db.collection('rosters').countDocuments({ status: 'pending' });
        console.log(`⏳ Pending rosters: ${pendingRosters}`);
        
        // Test 4: Get sample pending rosters
        console.log('\n📋 Test 4: Getting sample pending rosters...');
        const sampleRosters = await db.collection('rosters')
            .find({ status: 'pending' })
            .limit(3)
            .toArray();
        
        console.log(`📋 Sample pending rosters (${sampleRosters.length}):`);
        sampleRosters.forEach((roster, index) => {
            console.log(`  ${index + 1}. ID: ${roster._id}, Organization: ${roster.organization || 'N/A'}`);
        });
        
        // Test 5: Test the actual query used by the API
        console.log('\n🔍 Test 5: Testing API query logic...');
        const page = 1;
        const limit = 10;
        const skip = (page - 1) * limit;
        
        const apiQuery = { status: 'pending' };
        const apiRosters = await db.collection('rosters')
            .find(apiQuery)
            .skip(skip)
            .limit(limit)
            .sort({ createdAt: -1 })
            .toArray();
        
        console.log(`🔍 API query returned ${apiRosters.length} rosters`);
        
        // Test 6: Check for any errors in roster structure
        console.log('\n🔧 Test 6: Checking roster structure...');
        if (apiRosters.length > 0) {
            const firstRoster = apiRosters[0];
            console.log('📋 First roster structure:');
            console.log('  - _id:', firstRoster._id ? '✅' : '❌');
            console.log('  - status:', firstRoster.status || 'N/A');
            console.log('  - organization:', firstRoster.organization || 'N/A');
            console.log('  - createdAt:', firstRoster.createdAt ? '✅' : '❌');
        }
        
        console.log('\n✅ All tests completed successfully!');
        
    } catch (error) {
        console.error('❌ Test failed:', error.message);
        console.error('Stack trace:', error.stack);
    } finally {
        if (client) {
            await client.close();
            console.log('🔌 Database connection closed');
        }
    }
}

testPendingRostersAtlas();