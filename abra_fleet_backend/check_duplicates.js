// Check for duplicates
const { MongoClient } = require('mongodb');

const MONGO_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function checkDuplicates() {
    const client = new MongoClient(MONGO_URI);

    try {
        await client.connect();
        const db = client.db('abra_fleet');

        const names = ['Rohit Menon', 'Divya Rao', 'Anitha Menon'];

        console.log('\n📋 Checking for Duplicates:\n');

        for (const name of names) {
            const rosters = await db.collection('rosters').find({ customerName: name }).toArray();

            console.log(`👤 Customer: ${name} (${rosters.length} rosters)`);
            if (rosters.length > 0) {
                rosters.forEach(r => {
                    console.log(`   - ID: ${r._id}`);
                    console.log(`     Status: ${r.status}`);
                    console.log(`     Date: ${r.startDate || r.date} ${r.startTime || r.time}`);
                    console.log(`     Vehicle: ${r.vehicleId ? 'Yes' : 'No'}`);
                    console.log('');
                });
            }
        }
    } catch (error) {
        console.error('Error:', error);
    } finally {
        await client.close();
    }
}

checkDuplicates();
