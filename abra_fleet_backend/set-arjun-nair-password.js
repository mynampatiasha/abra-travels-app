// Script to set password for arjun.nair@wipro.com
const admin = require('./config/firebase.js');

async function setArjunNairPassword() {
  console.log('🔐 Setting password for arjun.nair@wipro.com...\n');

  try {
    const email = 'arjun.nair@wipro.com';
    const newPassword = 'arjun.nair';

    // First, try to get the user by email
    let userRecord;
    try {
      userRecord = await admin.auth().getUserByEmail(email);
      console.log('✅ User found in Firebase Auth:');
      console.log(`   UID: ${userRecord.uid}`);
      console.log(`   Email: ${userRecord.email}`);
      console.log(`   Display Name: ${userRecord.displayName || 'Not set'}`);
      console.log(`   Email Verified: ${userRecord.emailVerified}`);
      console.log(`   Created: ${userRecord.metadata.creationTime}`);
      console.log('');

      // Update the password
      await admin.auth().updateUser(userRecord.uid, {
        password: newPassword
      });

      console.log('✅ Password updated successfully!');
      console.log(`   Email: ${email}`);
      console.log(`   New Password: ${newPassword}`);
      console.log('');

    } catch (error) {
      if (error.code === 'auth/user-not-found') {
        console.log('⚠️  User not found in Firebase Auth. Creating new user...');
        
        // Create new user
        userRecord = await admin.auth().createUser({
          email: email,
          password: newPassword,
          displayName: 'Arjun Nair',
          emailVerified: true
        });

        console.log('✅ New user created successfully!');
        console.log(`   UID: ${userRecord.uid}`);
        console.log(`   Email: ${userRecord.email}`);
        console.log(`   Password: ${newPassword}`);
        console.log('');
      } else {
        throw error;
      }
    }

    // Also check if user exists in Firestore users collection
    const db = admin.firestore();
    const userDoc = await db.collection('users').doc(userRecord.uid).get();
    
    if (userDoc.exists) {
      console.log('✅ User found in Firestore users collection:');
      const userData = userDoc.data();
      console.log(`   Name: ${userData.name || 'Not set'}`);
      console.log(`   Email: ${userData.email || 'Not set'}`);
      console.log(`   Role: ${userData.role || 'Not set'}`);
      console.log(`   Company: ${userData.companyName || 'Not set'}`);
      console.log('');
    } else {
      console.log('⚠️  User not found in Firestore users collection');
      console.log('   Creating Firestore user document...');
      
      // Create user document in Firestore
      await db.collection('users').doc(userRecord.uid).set({
        name: 'Arjun Nair',
        email: email,
        role: 'Customer',
        companyName: 'Wipro',
        department: 'Testing',
        phone: '9876543220',
        status: 'Active',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      
      console.log('✅ Firestore user document created successfully!');
      console.log('');
    }

    // Test login credentials
    console.log('🧪 Login Credentials for Testing:');
    console.log('┌─────────────────────────────────────┐');
    console.log('│ Email:    arjun.nair@wipro.com      │');
    console.log('│ Password: arjun.nair                │');
    console.log('│ Role:     Customer                  │');
    console.log('│ Company:  Wipro                     │');
    console.log('└─────────────────────────────────────┘');
    console.log('');

    console.log('🎉 Password setup complete!');
    console.log('   The user can now login with the new credentials.');

  } catch (error) {
    console.error('❌ Error setting password:', error);
    
    if (error.code) {
      console.error(`   Error Code: ${error.code}`);
    }
    if (error.message) {
      console.error(`   Error Message: ${error.message}`);
    }
  }
}

// Run the script
setArjunNairPassword();