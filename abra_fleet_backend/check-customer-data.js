const { MongoClient } = require('mongodb');

async function checkCustomerData() {
    const client = new MongoClient('mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0');
    
    try {
        await client.connect();
        console.log('Connected to MongoDB');
        
        const db = client.db('abra_fleet');
        
        // Check the users collection for customer data
        const customerEmails = [
            'suresh.kumar@abrafleet.com',
            'priya.menon@abrafleet.com',
            'arun.reddy@abrafleet.com',
            'kavitha.sharma@abrafleet.com',
            'deepak.nair@abrafleet.com'
        ];
        
        console.log('🔍 Checking users collection for customer data:\n');
        
        for (const email of customerEmails) {
            const user = await db.collection('users').findOne({
                email: email
            });
            
            if (user) {
                console.log(`✅ Found user: ${user.name || 'Unknown'}`);
                console.log(`   - Email: ${user.email}`);
                console.log(`   - Phone: ${user.phone || 'N/A'}`);
                console.log(`   - UID: ${user.uid || 'N/A'}`);
                console.log(`   - Address: ${user.address || 'N/A'}`);
                console.log(`   - Home Address: ${user.homeAddress || 'N/A'}`);
                console.log(`   - Office Address: ${user.officeAddress || 'N/A'}`);
            } else {
                console.log(`❌ User not found: ${email}`);
            }
            console.log('');
        }
        
        // Also check if there's a separate customers collection
        console.log('🔍 Checking customers collection...\n');
        const customers = await db.collection('customers').find({}).limit(5).toArray();
        
        if (customers.length > 0) {
            console.log(`Found ${customers.length} customers in customers collection:`);
            customers.forEach((customer, index) => {
                console.log(`${index + 1}. ${customer.name || 'Unknown'}`);
                console.log(`   - Email: ${customer.email || 'N/A'}`);
                console.log(`   - Phone: ${customer.phone || 'N/A'}`);
                console.log(`   - Address: ${customer.address || 'N/A'}`);
                console.log('');
            });
        } else {
            console.log('No customers collection found or empty.');
        }
        
        // Check roster structure to understand what fields are available
        console.log('🔍 Checking roster structure...\n');
        const sampleRoster = await db.collection('rosters').findOne({
            driverId: 'DRV-100001'
        });
        
        if (sampleRoster) {
            console.log('Sample roster fields:');
            console.log(JSON.stringify(sampleRoster, null, 2));
        }
        
    } catch (error) {
        console.error('❌ Error checking customer data:', error);
    } finally {
        await client.close();
        console.log('\nDisconnected from MongoDB');
    }
}

// Run the check
checkCustomerData();