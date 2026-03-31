// fix-admin-firebase-uid.js
// Fix Firebase UID mismatch for admin user

require('dotenv').config();
const mongoose = require('mongoose');
const admin = require('firebase-admin');

// Initialize Firebase Admin (if credentials are available)
let firebaseInitialized = false;
try {
  if (process.env.FIREBASE_PROJECT_ID && process.env.FIREBASE_CLIENT_EMAIL && process.env.FIREBASE_PRIVATE_KEY) {
    if (!admin.apps.length) {
      admin.initializeApp({
        credential: admin.credential.cert({
          projectId: process.env.FIREBASE_PROJECT_ID,
          clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
          privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
        }),
      });
    }
    firebaseInitialized = true;
  }
} catch (error) {
  console.log('⚠️  Firebase Admin not initialized (credentials missing)');
}

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

const userSchema = new mongoose.Schema({
  firebaseUid: String,
  email: String,
  name: String,
  role: String,
  phone: String,
  organizationId: String,
  createdAt: Date,
  updatedAt: Date,
});

const User = mongoose.model('User', userSchema);

async function fixAdminFirebaseUID() {
  try {
    console.log('🔧 Fixing Admin Firebase UID...\n');

    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB\n');

    const adminEmail = 'admin@abrafleet.com';

    // Find the admin user in MongoDB
    const adminUser = await User.findOne({ email: adminEmail });
    if (!adminUser) {
      console.log('❌ Admin user not found in MongoDB');
      process.exit(1);
    }

    console.log('📧 Found admin user:', adminUser.email);
    console.log('🔑 Current role:', adminUser.role);
    console.log('🔥 Current Firebase UID:', adminUser.firebaseUid);

    if (firebaseInitialized) {
      try {
        // Get the actual Firebase user
        const firebaseUser = await admin.auth().getUserByEmail(adminEmail);
        console.log('🔥 Actual Firebase UID:', firebaseUser.uid);

        if (adminUser.firebaseUid !== firebaseUser.uid) {
          console.log('🔄 Updating Firebase UID in MongoDB...');
          
          await User.findOneAndUpdate(
            { email: adminEmail },
            { 
              firebaseUid: firebaseUser.uid,
              updatedAt: new Date()
            }
          );
          
          console.log('✅ Firebase UID updated successfully!');
        } else {
          console.log('✅ Firebase UID already matches');
        }
      } catch (firebaseError) {
        console.log('⚠️  Firebase user not found, creating...');
        
        try {
          const newFirebaseUser = await admin.auth().createUser({
            uid: adminUser.firebaseUid, // Use existing UID from MongoDB
            email: adminEmail,
            password: 'admin123',
            displayName: 'Admin User',
            emailVerified: true,
          });
          
          console.log('✅ Firebase user created with UID:', newFirebaseUser.uid);
        } catch (createError) {
          console.log('❌ Error creating Firebase user:', createError.message);
        }
      }
    } else {
      console.log('⚠️  Firebase not initialized, skipping Firebase UID sync');
    }

    // Ensure role is correct
    if (adminUser.role !== 'super_admin') {
      console.log('🔄 Updating role to super_admin...');
      await User.findOneAndUpdate(
        { email: adminEmail },
        { 
          role: 'super_admin',
          updatedAt: new Date()
        }
      );
      console.log('✅ Role updated to super_admin');
    }

    // Final verification
    const updatedUser = await User.findOne({ email: adminEmail });
    console.log('\n═══════════════════════════════════════════════════════');
    console.log('🎉 ADMIN USER VERIFICATION:');
    console.log('═══════════════════════════════════════════════════════');
    console.log('📧 Email:        ', updatedUser.email);
    console.log('👤 Name:         ', updatedUser.name);
    console.log('🔑 Role:         ', updatedUser.role);
    console.log('🔥 Firebase UID: ', updatedUser.firebaseUid);
    console.log('📅 Updated:      ', updatedUser.updatedAt);
    console.log('═══════════════════════════════════════════════════════');

    await mongoose.connection.close();
    console.log('\n✅ Fix completed successfully!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error fixing admin Firebase UID:', error);
    await mongoose.connection.close();
    process.exit(1);
  }
}

fixAdminFirebaseUID();