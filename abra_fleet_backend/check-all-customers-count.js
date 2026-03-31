const { MongoClient } = require('mongodb');
const admin = require('firebase-admin');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: 'https://abra-fleet-default-rtdb.firebaseio.com'
});

const MONGODB_URI = 'mongodb://localhost:27017';
const DB_NAME = 'fleet_management';

async function checkCustomerCounts() {
  const mongoClient = new MongoClient(MONGODB_URI);
  
  try {
    await mongoClient.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = mongoClient.db(DB_NAME);
    
    // 1. Check Firestore customers
    console.log('\n📊 FIRESTORE CUSTOMERS:');
    console.log('='.repeat(60));
    
    const firestoreSnapshot = await admin.firestore()
      .collection('users')
      .where('role', '==', 'customer')
      .get();
    
    console.log(`Total Firestore customers: ${firestoreSnapshot.size}`);
    
    const firestoreCustomers = [];
    firestoreSnapshot.forEach(doc => {
      const data = doc.data();
      firestoreCustomers.push({
        id: doc.id,
        email: data.email,
        name: data.name,
        company: data.companyName || data.organizationName,
        status: data.status,
        createdAt: data.createdAt
      });
    });
    
    // Group by company
    const byCompany = {};
    firestoreCustomers.forEach(c => {
      const company = c.company || 'No Company';
      if (!byCompany[company]) byCompany[company] = [];
      byCompany[company].push(c);
    });
    
    console.log('\nCustomers by Company:');
    Object.keys(byCompany).sort().forEach(company => {
      console.log(`  ${company}: ${byCompany[company].length} customers`);
      byCompany[company].forEach(c => {
        console.log(`    - ${c.name} (${c.email}) - Status: ${c.status || 'N/A'}`);
      });
    });
    
    // 2. Check MongoDB customers
    console.log('\n📊 MONGODB CUSTOMERS:');
    console.log('='.repeat(60));
    
    const mongoCustomers = await db.collection('users')
      .find({ role: 'customer' })
      .toArray();
    
    console.log(`Total MongoDB customers: ${mongoCustomers.length}`);
    
    if (mongoCustomers.length > 0) {
      const mongoByCompany = {};
      mongoCustomers.forEach(c => {
        const company = c.companyName || c.organizationName || 'No Company';
        if (!mongoByCompany[company]) mongoByCompany[company] = [];
        mongoByCompany[company].push(c);
      });
      
      console.log('\nCustomers by Company:');
      Object.keys(mongoByCompany).sort().forEach(company => {
        console.log(`  ${company}: ${mongoByCompany[company].length} customers`);
        mongoByCompany[company].forEach(c => {
          console.log(`    - ${c.name} (${c.email}) - Status: ${c.status || 'N/A'}`);
        });
      });
    }
    
    // 3. Check for duplicates
    console.log('\n🔍 CHECKING FOR DUPLICATES:');
    console.log('='.repeat(60));
    
    const emailCounts = {};
    firestoreCustomers.forEach(c => {
      const email = c.email.toLowerCase();
      emailCounts[email] = (emailCounts[email] || 0) + 1;
    });
    
    const duplicates = Object.entries(emailCounts).filter(([_, count]) => count > 1);
    if (duplicates.length > 0) {
      console.log('⚠️  Found duplicate emails in Firestore:');
      duplicates.forEach(([email, count]) => {
        console.log(`  ${email}: ${count} entries`);
      });
    } else {
      console.log('✅ No duplicate emails found');
    }
    
    // 4. Check rosters for these customers
    console.log('\n📋 ROSTER STATUS FOR CUSTOMERS:');
    console.log('='.repeat(60));
    
    const rosters = await db.collection('rosters').find({}).toArray();
    console.log(`Total rosters in database: ${rosters.length}`);
    
    const rostersByStatus = {};
    const rostersByCustomer = {};
    
    rosters.forEach(r => {
      const status = r.status || 'unknown';
      rostersByStatus[status] = (rostersByStatus[status] || 0) + 1;
      
      const email = r.customerEmail || r.email;
      if (email) {
        if (!rostersByCustomer[email]) {
          rostersByCustomer[email] = {
            total: 0,
            byStatus: {}
          };
        }
        rostersByCustomer[email].total++;
        rostersByCustomer[email].byStatus[status] = 
          (rostersByCustomer[email].byStatus[status] || 0) + 1;
      }
    });
    
    console.log('\nRosters by Status:');
    Object.entries(rostersByStatus).sort().forEach(([status, count]) => {
      console.log(`  ${status}: ${count}`);
    });
    
    console.log('\nCustomers with Rosters:');
    Object.entries(rostersByCustomer).sort().forEach(([email, data]) => {
      console.log(`  ${email}: ${data.total} rosters`);
      Object.entries(data.byStatus).forEach(([status, count]) => {
        console.log(`    - ${status}: ${count}`);
      });
    });
    
    // 5. Find customers without rosters
    console.log('\n👤 CUSTOMERS WITHOUT ROSTERS:');
    console.log('='.repeat(60));
    
    const customersWithoutRosters = firestoreCustomers.filter(c => 
      !rostersByCustomer[c.email]
    );
    
    console.log(`Found ${customersWithoutRosters.length} customers without rosters:`);
    customersWithoutRosters.forEach(c => {
      console.log(`  - ${c.name} (${c.email}) - ${c.company || 'No Company'}`);
    });
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await mongoClient.close();
    process.exit(0);
  }
}

checkCustomerCounts();
