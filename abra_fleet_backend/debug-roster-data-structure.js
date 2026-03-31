require('dotenv').config();
const { MongoClient } = require('mongodb');

async function debugRosterDataStructure() {
    console.log('🔍 DEBUGGING ROSTER DATA STRUCTURE');
    console.log('==================================================');
    
    let client;
    
    try {
        // Connect to MongoDB Atlas
        client = new MongoClient(process.env.MONGODB_URI);
        await client.connect();
        console.log('✅ Connected to MongoDB Atlas');
        
        const db = client.db('abra_fleet');
        
        // Get a sample pending roster
        const sampleRoster = await db.collection('rosters')
            .findOne({ status: 'pending' });
        
        if (sampleRoster) {
            console.log('\n📋 SAMPLE ROSTER STRUCTURE:');
            console.log('==================================================');
            
            // Check all fields and their types
            for (const [key, value] of Object.entries(sampleRoster)) {
                const type = typeof value;
                const valuePreview = type === 'object' && value !== null 
                    ? JSON.stringify(value).substring(0, 100) + '...'
                    : String(value).substring(0, 50);
                    
                console.log(`${key}: ${type} = ${valuePreview}`);
            }
            
            // Check specifically for email-related fields
            console.log('\n📧 EMAIL-RELATED FIELDS:');
            console.log('==================================================');
            console.log('customerEmail:', typeof sampleRoster.customerEmail, '=', sampleRoster.customerEmail);
            console.log('email:', typeof sampleRoster.email, '=', sampleRoster.email);
            
            if (sampleRoster.employeeDetails) {
                console.log('employeeDetails.email:', typeof sampleRoster.employeeDetails.email, '=', sampleRoster.employeeDetails.email);
            }
            
            if (sampleRoster.employeeData) {
                console.log('employeeData.email:', typeof sampleRoster.employeeData.email, '=', sampleRoster.employeeData.email);
            }
            
            // Check for any numeric fields that might be confused with email
            console.log('\n🔢 NUMERIC FIELDS:');
            console.log('==================================================');
            for (const [key, value] of Object.entries(sampleRoster)) {
                if (typeof value === 'number') {
                    console.log(`${key}: ${value}`);
                }
            }
            
        } else {
            console.log('❌ No pending rosters found');
        }
        
    } catch (error) {
        console.error('❌ Error:', error.message);
    } finally {
        if (client) {
            await client.close();
            console.log('🔌 Database connection closed');
        }
    }
}

debugRosterDataStructure();