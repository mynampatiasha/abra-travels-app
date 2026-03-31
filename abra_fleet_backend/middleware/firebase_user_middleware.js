const FirebaseUidManager = require('../utils/firebase_uid_manager');

/**
 * Middleware to ensure Firebase UID is generated for user creation/update operations
 */
class FirebaseUserMiddleware {
  constructor() {
    this.uidManager = null;
  }

  /**
   * Initialize with database connection
   */
  init(db) {
    this.uidManager = new FirebaseUidManager(db);
  }

  /**
   * Middleware for user creation - ensures Firebase UID is generated
   */
  ensureFirebaseUidOnCreate() {
    return async (req, res, next) => {
      try {
        // Skip if not a user creation request
        if (req.method !== 'POST') {
          return next();
        }

        // Skip if Firebase UID already provided
        if (req.body.firebaseUid) {
          return next();
        }

        // Skip if no email provided
        if (!req.body.email) {
          return next();
        }

        console.log('\n🔥 Firebase UID Middleware - Creating Firebase user');
        console.log('Email:', req.body.email);

        // Determine user role and display name
        const role = req.body.role || this.determineRoleFromPath(req.path);
        const displayName = req.body.displayName || 
                           req.body.name || 
                           req.body.name_parson ||
                           `${req.body.firstName || ''} ${req.body.lastName || ''}`.trim();

        // Create Firebase user
        const firebaseResult = await this.uidManager.createFirebaseUser({
          email: req.body.email,
          password: req.body.password || req.body.pwd,
          displayName: displayName,
          role: role,
          customClaims: req.body.customClaims
        });

        if (!firebaseResult.success) {
          return res.status(500).json({
            success: false,
            message: firebaseResult.error,
            error: 'Firebase user creation failed'
          });
        }

        // Add Firebase UID to request body
        req.body.firebaseUid = firebaseResult.firebaseUid;
        req.firebaseResult = firebaseResult;

        console.log('✅ Firebase UID added to request:', firebaseResult.firebaseUid);
        next();

      } catch (error) {
        console.error('❌ Firebase UID Middleware error:', error.message);
        return res.status(500).json({
          success: false,
          message: 'Failed to create Firebase user',
          error: error.message
        });
      }
    };
  }

  /**
   * Middleware for user updates - ensures Firebase UID exists
   */
  ensureFirebaseUidOnUpdate() {
    return async (req, res, next) => {
      try {
        // Skip if not an update request
        if (!['PUT', 'PATCH'].includes(req.method)) {
          return next();
        }

        // Skip if no email in request
        const email = req.body.email || req.params.email;
        if (!email) {
          return next();
        }

        console.log('\n🔥 Firebase UID Middleware - Ensuring Firebase UID exists');
        console.log('Email:', email);

        // Ensure Firebase UID exists
        const firebaseResult = await this.uidManager.ensureFirebaseUid(email, {
          displayName: req.body.displayName || req.body.name || req.body.name_parson,
          role: req.body.role || this.determineRoleFromPath(req.path)
        });

        if (!firebaseResult.success) {
          console.warn('⚠️ Could not ensure Firebase UID:', firebaseResult.error);
          // Don't fail the request, just log the warning
        } else {
          req.body.firebaseUid = firebaseResult.firebaseUid;
          req.firebaseResult = firebaseResult;
          console.log('✅ Firebase UID ensured:', firebaseResult.firebaseUid);
        }

        next();

      } catch (error) {
        console.error('❌ Firebase UID Middleware error:', error.message);
        // Don't fail the request for update operations
        next();
      }
    };
  }

  /**
   * Middleware for bulk operations - handles multiple users
   */
  ensureFirebaseUidOnBulk() {
    return async (req, res, next) => {
      try {
        // Skip if not bulk operation
        if (!req.body.users && !req.body.employees && !req.body.drivers && !req.body.clients) {
          return next();
        }

        console.log('\n🔥 Firebase UID Middleware - Processing bulk operation');

        // Get users array from request
        const users = req.body.users || 
                     req.body.employees || 
                     req.body.drivers || 
                     req.body.clients || [];

        if (!Array.isArray(users) || users.length === 0) {
          return next();
        }

        console.log(`Processing ${users.length} users for Firebase UID generation`);

        const results = {
          processed: 0,
          success: 0,
          failed: 0,
          errors: []
        };

        // Process each user
        for (let i = 0; i < users.length; i++) {
          const user = users[i];
          results.processed++;

          try {
            // Skip if no email
            if (!user.email) {
              console.warn(`User ${i + 1}: No email provided, skipping Firebase UID generation`);
              continue;
            }

            // Skip if Firebase UID already exists
            if (user.firebaseUid) {
              console.log(`User ${i + 1}: Firebase UID already exists, skipping`);
              results.success++;
              continue;
            }

            console.log(`User ${i + 1}: Creating Firebase user for ${user.email}`);

            // Create Firebase user
            const firebaseResult = await this.uidManager.createFirebaseUser({
              email: user.email,
              password: user.password || user.pwd,
              displayName: user.displayName || user.name || user.name_parson,
              role: user.role || this.determineRoleFromPath(req.path)
            });

            if (firebaseResult.success) {
              user.firebaseUid = firebaseResult.firebaseUid;
              results.success++;
              console.log(`✅ User ${i + 1}: Firebase UID generated`);
            } else {
              results.failed++;
              results.errors.push({
                index: i,
                email: user.email,
                error: firebaseResult.error
              });
              console.error(`❌ User ${i + 1}: Firebase UID generation failed:`, firebaseResult.error);
            }

          } catch (error) {
            results.failed++;
            results.errors.push({
              index: i,
              email: user.email || 'unknown',
              error: error.message
            });
            console.error(`❌ User ${i + 1}: Error:`, error.message);
          }
        }

        // Add results to request for logging
        req.firebaseBulkResults = results;

        console.log('\n📊 Bulk Firebase UID Generation Results:');
        console.log('Processed:', results.processed);
        console.log('Success:', results.success);
        console.log('Failed:', results.failed);

        if (results.errors.length > 0) {
          console.log('Errors:');
          results.errors.forEach(error => {
            console.log(`  User ${error.index + 1} (${error.email}): ${error.error}`);
          });
        }

        next();

      } catch (error) {
        console.error('❌ Firebase UID Bulk Middleware error:', error.message);
        // Don't fail the request, just log the error
        next();
      }
    };
  }

  /**
   * Determine user role from request path
   */
  determineRoleFromPath(path) {
    if (path.includes('/driver')) return 'driver';
    if (path.includes('/employee')) return 'employee';
    if (path.includes('/client')) return 'client';
    if (path.includes('/admin')) return 'admin';
    if (path.includes('/customer')) return 'customer';
    return 'user';
  }

  /**
   * Response middleware to include Firebase UID information
   */
  addFirebaseInfoToResponse() {
    return (req, res, next) => {
      const originalJson = res.json;
      
      res.json = function(data) {
        // Add Firebase UID information if available
        if (req.firebaseResult) {
          if (data && typeof data === 'object') {
            data.firebaseInfo = {
              firebaseUid: req.firebaseResult.firebaseUid,
              isExisting: req.firebaseResult.isExisting || false,
              tempPassword: req.firebaseResult.tempPassword || null
            };
          }
        }

        // Add bulk results if available
        if (req.firebaseBulkResults) {
          if (data && typeof data === 'object') {
            data.firebaseBulkResults = req.firebaseBulkResults;
          }
        }

        return originalJson.call(this, data);
      };

      next();
    };
  }
}

// Create singleton instance
const firebaseUserMiddleware = new FirebaseUserMiddleware();

module.exports = firebaseUserMiddleware;