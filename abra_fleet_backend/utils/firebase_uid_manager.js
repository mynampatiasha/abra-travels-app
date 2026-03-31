const admin = require('firebase-admin');

/**
 * Firebase UID Management Utility
 * Handles Firebase UID generation, validation, and synchronization across collections
 */
class FirebaseUidManager {
  constructor(db) {
    this.db = db;
    this.collections = [
      'drivers',
      'employee_admins', 
      'admin_users',
      'customers',
      'users',
      'clients'
    ];
  }

  /**
   * Create Firebase user and return UID
   */
  async createFirebaseUser(userData) {
    const { email, password, displayName, role } = userData;
    
    try {
      // Generate temporary password if not provided
      const tempPassword = password || this.generateTempPassword();
      
      // Create Firebase Auth user
      const firebaseUser = await admin.auth().createUser({
        email: email.toLowerCase(),
        emailVerified: false,
        password: tempPassword,
        displayName: displayName,
        disabled: false
      });
      
      console.log('✅ Firebase user created:', firebaseUser.uid);
      
      // Set custom claims
      if (role) {
        await admin.auth().setCustomUserClaims(firebaseUser.uid, {
          role: role,
          ...(userData.customClaims || {})
        });
        console.log('✅ Custom claims set:', { role, ...userData.customClaims });
      }
      
      return {
        success: true,
        firebaseUid: firebaseUser.uid,
        tempPassword: password ? null : tempPassword
      };
      
    } catch (firebaseError) {
      console.error('❌ Firebase user creation failed:', firebaseError.message);
      
      // Handle existing user
      if (firebaseError.code === 'auth/email-already-exists') {
        console.log('⚠️ Firebase user already exists, fetching existing user...');
        try {
          const existingUser = await admin.auth().getUserByEmail(email.toLowerCase());
          return {
            success: true,
            firebaseUid: existingUser.uid,
            isExisting: true
          };
        } catch (fetchError) {
          console.error('❌ Failed to fetch existing Firebase user:', fetchError.message);
          return {
            success: false,
            error: 'Email already registered in Firebase but cannot retrieve user details'
          };
        }
      }
      
      return {
        success: false,
        error: `Failed to create Firebase user: ${firebaseError.message}`
      };
    }
  }

  /**
   * Find user across all collections by email
   */
  async findUserByEmail(email) {
    const normalizedEmail = email.toLowerCase();
    
    for (const collectionName of this.collections) {
      try {
        const user = await this.db.collection(collectionName).findOne({ 
          email: normalizedEmail 
        });
        
        if (user) {
          return {
            user,
            collection: collectionName
          };
        }
      } catch (error) {
        console.warn(`Warning: Could not search in collection ${collectionName}:`, error.message);
      }
    }
    
    return null;
  }

  /**
   * Update Firebase UID in user record
   */
  async updateFirebaseUid(collection, userId, firebaseUid) {
    try {
      const result = await this.db.collection(collection).updateOne(
        { _id: userId },
        { 
          $set: { 
            firebaseUid: firebaseUid,
            lastUpdated: new Date()
          } 
        }
      );
      
      console.log(`✅ Firebase UID updated in ${collection}:`, firebaseUid);
      return result;
    } catch (error) {
      console.error(`❌ Failed to update Firebase UID in ${collection}:`, error.message);
      throw error;
    }
  }

  /**
   * Ensure user has Firebase UID - create if missing
   */
  async ensureFirebaseUid(email, userData = {}) {
    console.log('\n🔍 ========== ENSURING FIREBASE UID ==========');
    console.log('Email:', email);
    
    // Find user in database
    const userResult = await this.findUserByEmail(email);
    if (!userResult) {
      throw new Error('User not found in any collection');
    }
    
    const { user, collection } = userResult;
    console.log('Found user in collection:', collection);
    console.log('Current Firebase UID:', user.firebaseUid || 'MISSING');
    
    // If user already has Firebase UID, validate it
    if (user.firebaseUid) {
      try {
        await admin.auth().getUser(user.firebaseUid);
        console.log('✅ Firebase UID is valid');
        return {
          success: true,
          firebaseUid: user.firebaseUid,
          isExisting: true
        };
      } catch (error) {
        console.warn('⚠️ Firebase UID is invalid, will create new one');
      }
    }
    
    // Create Firebase user
    const firebaseResult = await this.createFirebaseUser({
      email: email,
      displayName: userData.displayName || user.name || user.name_parson,
      role: userData.role || user.role || 'user',
      customClaims: userData.customClaims
    });
    
    if (!firebaseResult.success) {
      throw new Error(firebaseResult.error);
    }
    
    // Update database record
    await this.updateFirebaseUid(collection, user._id, firebaseResult.firebaseUid);
    
    return firebaseResult;
  }

  /**
   * Backfill Firebase UIDs for users missing them
   */
  async backfillMissingFirebaseUids(collectionName, limit = 50) {
    console.log(`\n🔄 ========== BACKFILLING ${collectionName.toUpperCase()} ==========`);
    
    try {
      // Find users without Firebase UID
      const usersWithoutUid = await this.db.collection(collectionName)
        .find({ 
          $or: [
            { firebaseUid: { $exists: false } },
            { firebaseUid: null },
            { firebaseUid: '' }
          ],
          email: { $exists: true, $ne: '' }
        })
        .limit(limit)
        .toArray();
      
      console.log(`Found ${usersWithoutUid.length} users without Firebase UID`);
      
      const results = {
        processed: 0,
        success: 0,
        failed: 0,
        errors: []
      };
      
      for (const user of usersWithoutUid) {
        results.processed++;
        
        try {
          console.log(`\nProcessing user ${results.processed}/${usersWithoutUid.length}:`);
          console.log('Email:', user.email);
          
          const firebaseResult = await this.ensureFirebaseUid(user.email, {
            displayName: user.name || user.name_parson,
            role: user.role || 'user'
          });
          
          if (firebaseResult.success) {
            results.success++;
            console.log('✅ Success');
          } else {
            results.failed++;
            results.errors.push({
              email: user.email,
              error: firebaseResult.error
            });
            console.log('❌ Failed:', firebaseResult.error);
          }
          
        } catch (error) {
          results.failed++;
          results.errors.push({
            email: user.email,
            error: error.message
          });
          console.error('❌ Error processing user:', error.message);
        }
      }
      
      console.log('\n📊 ========== BACKFILL RESULTS ==========');
      console.log('Processed:', results.processed);
      console.log('Success:', results.success);
      console.log('Failed:', results.failed);
      
      return results;
      
    } catch (error) {
      console.error(`❌ Backfill failed for ${collectionName}:`, error.message);
      throw error;
    }
  }

  /**
   * Generate temporary password
   */
  generateTempPassword() {
    return Math.random().toString(36).slice(-8) + 
           Math.random().toString(36).slice(-4).toUpperCase() + 
           '1!';
  }

  /**
   * Validate Firebase UID exists and is valid
   */
  async validateFirebaseUid(firebaseUid) {
    try {
      const user = await admin.auth().getUser(firebaseUid);
      return {
        valid: true,
        user: user
      };
    } catch (error) {
      return {
        valid: false,
        error: error.message
      };
    }
  }
}

module.exports = FirebaseUidManager;