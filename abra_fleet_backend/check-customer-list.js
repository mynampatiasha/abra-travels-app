// Script to check customer list and verify admin is not included
const admin = require('firebase-admin');

// Initialize Firebase Admin SDK
const serviceAccount = require('./serviceAccountKey.json.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: serviceAccount.project_id
});

const db = admin.firest
async function checkCustomerList() {
  try {
    console.log('🔍 Checking customer list in Firestore...');
    
    // Query for all users with role 'customer'
    const customerQuery = await db.collection('users')
      .where('role', '==', 'customer')
      .get();
    
    console.log(`📊 Total users with role 'customer': ${customerQuery.size}`);
    
    let adminFoundInCustomers = false;
    const adminEmail = 'admin@abrafleet.com';
    let customerWithoutOrg = [];
    
    console.log('\n📋 Customer list:');
    customerQuery.forEach((doc, index) => {
      const data = doc.data();
      const email = data.email || 'No email';
      const name = data.name || 'No name';
      const role = data.role || 'No role';
      const companyName = data.companyName || '';
      const organizationName = data.organizationName || '';
      
      console.log(`${index + 1}. ${name} (${email}) - Role: ${role}`);
      console.log(`   Company: ${companyName || 'NOT SET'}`);
      console.log(`   Organization: ${organizationName || 'NOT SET'}`);
      
      if (email.toLowerCase() === adminEmail.toLowerCase()) {
        adminFoundInCustomers = true;
        console.log('   ⚠️ ADMIN EMAIL FOUND IN CUSTOMERS!');
      }
      
      if (!companyName && !organizationName) {
        customerWithoutOrg.push({ id: doc.id, email, name, companyName: '', organizationName: '' });
        console.log('   ⚠️ NO ORGANIZATION SET!');
      } else if (!organizationName && companyName) {
        customerWithoutOrg.push({ id: doc.id, email, name, companyName, organizationName: '' });
        console.log('   ⚠️ ORGANIZATION NAME NOT SET (but has company)!');
      }
    });
    
    console.log('\n🔍 Checking all users by role...');
    
    // Check admin users
    const adminQuery = await db.collection('users')
      .where('role', '==', 'admin')
      .get();
    
    console.log(`👑 Admin users: ${adminQuery.size}`);
    adminQuery.forEach((doc) => {
      const data = doc.data();
      console.log(`   - ${data.name} (${data.email}) - Org: ${data.companyName || data.organizationName || 'NOT SET'}`);
    });
    
    // Check client users
    const clientQuery = await db.collection('users')
      .where('role', '==', 'client')
      .get();
    
    console.log(`🏢 Client users: ${clientQuery.size}`);
    clientQuery.forEach((doc) => {
      const data = doc.data();
      console.log(`   - ${data.name} (${data.email}) - Org: ${data.companyName || data.organizationName || 'NOT SET'}`);
    });
    
    // Check driver users
    const driverQuery = await db.collection('users')
      .where('role', '==', 'driver')
      .get();
    
    console.log(`🚗 Driver users: ${driverQuery.size}`);
    driverQuery.forEach((doc) => {
      const data = doc.data();
      console.log(`   - ${data.name} (${data.email})`);
    });
    
    // Check for @abrafleet.com users
    console.log('\n🔍 Checking @abrafleet.com domain users...');
    const allUsers = await db.collection('users').get();
    
    const abrafleetCustomers = [];
    const abrafleetClients = [];
    const abrafleetAdmins = [];
    
    allUsers.forEach((doc) => {
      const data = doc.data();
      if (data.email && data.email.toLowerCase().includes('@abrafleet.com')) {
        const userInfo = {
          name: data.name,
          email: data.email,
          role: data.role,
          company: data.companyName || data.organizationName || 'NOT SET'
        };
        
        if (data.role === 'customer') abrafleetCustomers.push(userInfo);
        else if (data.role === 'client') abrafleetClients.push(userInfo);
        else if (data.role === 'admin') abrafleetAdmins.push(userInfo);
      }
    });
    
    console.log(`\n📧 @abrafleet.com domain users:`);
    console.log(`   Customers: ${abrafleetCustomers.length}`);
    abrafleetCustomers.forEach(u => console.log(`      - ${u.name} (${u.email}) - ${u.company}`));
    console.log(`   Clients: ${abrafleetClients.length}`);
    abrafleetClients.forEach(u => console.log(`      - ${u.name} (${u.email}) - ${u.company}`));
    console.log(`   Admins: ${abrafleetAdmins.length}`);
    abrafleetAdmins.forEach(u => console.log(`      - ${u.name} (${u.email}) - ${u.company}`));
    
    console.log('\n📊 Summary:');
    console.log(`✅ Total customers: ${customerQuery.size}`);
    console.log(`🏢 Total clients: ${clientQuery.size}`);
    console.log(`👑 Total admins: ${adminQuery.size}`);
    console.log(`🚗 Total drivers: ${driverQuery.size}`);
    
    if (adminFoundInCustomers) {
      console.log('❌ ISSUE: Admin email found in customer list!');
      console.log('💡 The Flutter app should filter this out now.');
    } else {
      console.log('✅ Admin email not found in customer list - Good!');
    }
    
    // Check for customers without organization
    if (customerWithoutOrg.length > 0) {
      console.log(`\n⚠️ ISSUE: ${customerWithoutOrg.length} customer(s) without organization:`);
      customerWithoutOrg.forEach(c => {
        console.log(`   - ${c.name} (${c.email})`);
      });
      
      // Try to fix by getting organization from admin
      const adminDoc = await db.collection('users')
        .where('role', '==', 'admin')
        .limit(1)
        .get();
      
      if (!adminDoc.empty) {
        const adminData = adminDoc.docs[0].data();
        const orgName = adminData.companyName || adminData.organizationName || 'Infosys Limited';
        
        console.log(`\n🔧 Fixing customers...`);
        
        for (const customer of customerWithoutOrg) {
          const updateData = {};
          
          // If no company name, use the org from admin
          if (!customer.companyName) {
            updateData.companyName = orgName;
          } else {
            // Use their existing company name
            updateData.companyName = customer.companyName;
          }
          
          // Always set organizationName to match companyName
          updateData.organizationName = updateData.companyName;
          
          await db.collection('users').doc(customer.id).update(updateData);
          console.log(`   ✅ Updated ${customer.email} with org: ${updateData.organizationName}`);
        }
        
        console.log('✅ All customers updated with organization!');
      }
    } else {
      console.log('✅ All customers have organization set!');
    }
    
  } catch (error) {
    console.error('❌ Error checking customer list:', error);
  } finally {
    admin.app().delete();
    console.log('\n✅ Check complete');
  }
}

// Run the check
checkCustomerList();