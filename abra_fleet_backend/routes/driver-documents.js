// routes/driver-documents.js
const express = require('express');
const router = express.Router();
const multer = require('multer');
const { ObjectId } = require('mongodb');

// Configure multer for memory storage
const storage = multer.memoryStorage();
const upload = multer({
  storage: storage,
  limits: {
    fileSize: 5 * 1024 * 1024, // 5MB limit
  },
  fileFilter: (req, file, cb) => {
    console.log('File upload attempt:', {
      fieldname: file.fieldname,
      originalname: file.originalname,
      mimetype: file.mimetype,
      size: file.size
    });
    
    const isImage = file.mimetype.startsWith('image/');
    const hasImageExtension = /\.(jpg|jpeg|png|gif|webp|bmp)$/i.test(file.originalname);
    
    if (isImage || hasImageExtension) {
      cb(null, true);
    } else {
      console.error('Rejected file:', file.mimetype, file.originalname);
      cb(new Error('Only image files are allowed! Received: ' + file.mimetype), false);
    }
  },
});

// Helper function to convert buffer to base64
const bufferToBase64 = (buffer) => {
  return `data:image/jpeg;base64,${buffer.toString('base64')}`;
};

// Helper function to check if daily photo is required (based on calendar day, not 24-hour period)
const isDailyPhotoRequired = (lastUploadDate) => {
  if (!lastUploadDate) return true;
  
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  
  const lastUpload = new Date(lastUploadDate);
  lastUpload.setHours(0, 0, 0, 0);
  
  // Return true if lastUpload is not today
  return today.getTime() !== lastUpload.getTime();
};

// Helper to check if daily photo has expired (24 hours from upload time)
const hasPhotoExpired = (lastUploadDate) => {
  if (!lastUploadDate) return true;
  
  const now = new Date();
  const uploadTime = new Date(lastUploadDate);
  const twentyFourHoursLater = new Date(uploadTime.getTime() + 24 * 60 * 60 * 1000);
  
  console.log(`Upload time: ${uploadTime.toISOString()}`);
  console.log(`Now: ${now.toISOString()}`);
  console.log(`Expires at: ${twentyFourHoursLater.toISOString()}`);
  console.log(`Has expired: ${now > twentyFourHoursLater}`);
  
  return now > twentyFourHoursLater;
};

// Helper to clean up old daily photos (older than 24 hours)
const cleanupOldDailyPhotos = async (db, driverId) => {
  try {
    const driver = await findDriver(db, driverId);
    if (!driver) return;

    const now = new Date();
    const oneDayAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000);

    // Remove daily photos older than 24 hours from photoHistory
    const result = await db.collection('drivers').updateOne(
      { _id: driver._id },
      {
        $pull: {
          photoHistory: {
            uploadedAt: { $lt: oneDayAgo },
            type: 'daily_photo'
          }
        }
      }
    );

    console.log(`Cleaned up old photos. Modified: ${result.modifiedCount}`);
  } catch (err) {
    console.error('Error cleaning up old daily photos:', err);
  }
};

// Helper to find driver by Firebase UID, driverId, or MongoDB ObjectId
const findDriver = async (db, identifier) => {
  try {
    console.log('🔍 Looking for driver with identifier:', identifier);
    
    // Strategy 0: Check if it's a valid MongoDB ObjectId and look in admin_users collection FIRST
    if (identifier && identifier.length === 24 && /^[0-9a-fA-F]{24}$/.test(identifier)) {
      console.log('   Trying as MongoDB ObjectId in admin_users...');
      const adminUser = await db.collection('admin_users').findOne({
        _id: new ObjectId(identifier),
        role: 'driver'
      });
      if (adminUser) {
        console.log('✅ Found driver in admin_users by _id:', adminUser.email);
        // Get the corresponding driver record from drivers collection
        const driver = await db.collection('drivers').findOne({
          $or: [
            { firebaseUid: adminUser.firebaseUid },
            { email: adminUser.firebaseUid  },
            { driverId: adminUser.driverId },
            { 'personalInfo.email': adminUser.email }
          ]
        });
        if (driver) {
          console.log('✅ Found corresponding driver record:', driver.driverId);
          return driver;
        }
        // If no driver record found, create a minimal one for document uploads
        console.log('⚠️ No driver record found, using admin_users data');
        return {
          _id: adminUser._id,
          driverId: adminUser.driverId,
          firebaseUid: adminUser.firebaseUid,
          personalInfo: {
            name: adminUser.name,
            email: adminUser.email,
            phone: adminUser.phone
          },
          documents: {},
          isFromAdminUsers: true
        };
      }
    }
    
    // Strategy 1: Look in admin_users collection by firebaseUid (most common after migration)
    let adminUser = await db.collection('admin_users').findOne({
      firebaseUid: identifier,
      role: 'driver'
    });
    if (adminUser) {
      console.log('✅ Found driver in admin_users by firebaseUid:', adminUser.email);
      // Get the corresponding driver record from drivers collection
      const driver = await db.collection('drivers').findOne({
        $or: [
          { firebaseUid: identifier },
          { email: identifier  },
          { driverId: adminUser.driverId },
          { 'personalInfo.email': adminUser.email }
        ]
      });
      if (driver) {
        console.log('✅ Found corresponding driver record:', driver.driverId);
        return driver;
      }
      // If no driver record found, create a minimal one for document uploads
      console.log('⚠️ No driver record found, using admin_users data');
      return {
        _id: adminUser._id,
        driverId: adminUser.driverId,
        firebaseUid: adminUser.firebaseUid,
        personalInfo: {
          name: adminUser.name,
          email: adminUser.email,
          phone: adminUser.phone
        },
        documents: {},
        isFromAdminUsers: true
      };
    }
    
    // Strategy 2: Look in admin_users collection by driverId
    if (identifier && identifier !== 'undefined') {
      adminUser = await db.collection('admin_users').findOne({
        driverId: identifier,
        role: 'driver'
      });
      if (adminUser) {
        console.log('✅ Found driver in admin_users by driverId:', adminUser.driverId);
        const driver = await db.collection('drivers').findOne({
          $or: [
            { driverId: identifier },
            { firebaseUid: adminUser.firebaseUid },
            { 'personalInfo.email': adminUser.email }
          ]
        });
        if (driver) {
          return driver;
        }
        return {
          _id: adminUser._id,
          driverId: adminUser.driverId,
          firebaseUid: adminUser.firebaseUid,
          personalInfo: {
            name: adminUser.name,
            email: adminUser.email,
            phone: adminUser.phone
          },
          documents: {},
          isFromAdminUsers: true
        };
      }
    }
    
    // Strategy 3: Look in admin_users collection by email
    adminUser = await db.collection('admin_users').findOne({
      email: identifier.toLowerCase(),
      role: 'driver'
    });
    if (adminUser) {
      console.log('✅ Found driver in admin_users by email:', adminUser.email);
      const driver = await db.collection('drivers').findOne({
        $or: [
          { 'personalInfo.email': adminUser.email },
          { firebaseUid: adminUser.firebaseUid },
          { driverId: adminUser.driverId }
        ]
      });
      if (driver) {
        return driver;
      }
      return {
        _id: adminUser._id,
        driverId: adminUser.driverId,
        firebaseUid: adminUser.firebaseUid,
        personalInfo: {
          name: adminUser.name,
          email: adminUser.email,
          phone: adminUser.phone
        },
        documents: {},
        isFromAdminUsers: true
      };
    }
    
    // Strategy 4: Check if it's a valid MongoDB ObjectId and look in drivers collection
    if (identifier.length === 24 && /^[0-9a-fA-F]{24}$/.test(identifier)) {
      const driver = await db.collection('drivers').findOne({
        _id: new ObjectId(identifier)
      });
      if (driver) {
        console.log('✅ Found driver by ObjectId in drivers collection');
        return driver;
      }
    }
    
    // Strategy 5: Try to find by firebaseUid field in drivers collection (legacy)
    let driver = await db.collection('drivers').findOne({
      $or: [
        { firebaseUid: identifier },
        { email: identifier  }
      ]
    });
    if (driver) {
      console.log('✅ Found driver in drivers collection by firebaseUid');
      return driver;
    }
    
    // Strategy 6: Try to find by driverId field in drivers collection (legacy)
    driver = await db.collection('drivers').findOne({
      driverId: identifier
    });
    if (driver) {
      console.log('✅ Found driver in drivers collection by driverId');
      return driver;
    }
    
    // Strategy 7: Search in users collection (legacy fallback)
    const user = await db.collection('users').findOne({
      $or: [
        { firebaseUid: identifier },
        { _id: identifier.length === 24 && /^[0-9a-fA-F]{24}$/.test(identifier) ? new ObjectId(identifier) : identifier }
      ],
      role: 'driver'
    });
    if (user) {
      console.log('✅ Found driver in users collection (legacy)');
      const linkedDriver = await db.collection('drivers').findOne({
        'personalInfo.email': user.email
      });
      return linkedDriver || user;
    }
    
    console.log('❌ Driver not found with identifier:', identifier);
    return null;
  } catch (err) {
    console.error('❌ Error in findDriver:', err);
    return null;
  }
};

// Helper to update driver by any identifier
const updateDriver = async (db, identifier, updateData) => {
  try {
    const driver = await findDriver(db, identifier);
    if (!driver) {
      console.log('❌ Driver not found for update:', identifier);
      return { matchedCount: 0 };
    }
    
    console.log('🔄 Updating driver:', driver.driverId || driver._id);
    
    // If this is from admin_users (no corresponding driver record), update both collections
    if (driver.isFromAdminUsers) {
      console.log('📝 Updating admin_users record and creating/updating driver record');
      
      // Update admin_users collection
      await db.collection('admin_users').updateOne(
        { _id: driver._id },
        { $set: { updatedAt: new Date() } }
      );
      
      // Create or update driver record for document storage
      const driverRecord = {
        driverId: driver.driverId,
        firebaseUid: driver.firebaseUid,
        personalInfo: driver.personalInfo,
        ...updateData.$set,
        updatedAt: new Date()
      };
      
      // Try to find existing driver record first
      const existingDriver = await db.collection('drivers').findOne({
        $or: [
          { driverId: driver.driverId },
          { firebaseUid: driver.firebaseUid },
          { 'personalInfo.email': driver.personalInfo.email }
        ]
      });
      
      if (existingDriver) {
        // Update existing driver record
        return await db.collection('drivers').updateOne(
          { _id: existingDriver._id },
          updateData
        );
      } else {
        // Create new driver record
        const insertResult = await db.collection('drivers').insertOne(driverRecord);
        return { matchedCount: 1, insertedId: insertResult.insertedId };
      }
    } else {
      // Update existing driver record
      return await db.collection('drivers').updateOne(
        { _id: driver._id },
        updateData
      );
    }
  } catch (err) {
    console.error('❌ Error in updateDriver:', err);
    return { matchedCount: 0 };
  }
};

// GET - Check if driver needs to upload daily photo
router.get('/check-daily-photo/:driverId', async (req, res) => {
  try {
    const { driverId } = req.params;
    
    const driver = await findDriver(req.db, driverId);

    if (!driver) {
      return res.status(404).json({
        status: 'error',
        message: 'Driver not found'
      });
    }

    const isRequired = isDailyPhotoRequired(driver.lastDailyPhotoUpload);
    
    res.json({
      status: 'success',
      data: {
        isRequired,
        lastUploadDate: driver.lastDailyPhotoUpload || null,
        hasProfilePhoto: !!driver.profilePhoto
      }
    });
  } catch (error) {
    console.error('Error checking daily photo:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// POST - Upload daily profile photo
router.post('/upload-daily-photo/:driverId', upload.single('photo'), async (req, res) => {
  try {
    const { driverId } = req.params;
    
    if (!req.file) {
      return res.status(400).json({
        status: 'error',
        message: 'No photo file provided'
      });
    }

    const photoBase64 = bufferToBase64(req.file.buffer);
    const now = new Date();
    
    // Clean up old daily photos first
    await cleanupOldDailyPhotos(req.db, driverId);
    
    const result = await updateDriver(req.db, driverId, {
      $set: {
        profilePhoto: photoBase64,
        lastDailyPhotoUpload: now,
        updatedAt: now
      },
      $push: {
        photoHistory: {
          photo: photoBase64,
          uploadedAt: now,
          type: 'daily_photo',
          fileSize: req.file.size,
          mimeType: req.file.mimetype
        }
      }
    });

    if (result.matchedCount === 0) {
      return res.status(404).json({
        status: 'error',
        message: 'Driver not found'
      });
    }

    res.json({
      status: 'success',
      message: 'Daily photo uploaded successfully',
      data: {
        uploadedAt: now,
        expiresAt: new Date(now.getTime() + 24 * 60 * 60 * 1000),
        photoUrl: photoBase64.substring(0, 50) + '...'
      }
    });
  } catch (error) {
    console.error('Error uploading daily photo:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// POST - Upload profile photo
router.post('/upload-profile-photo/:driverId', upload.single('photo'), async (req, res) => {
  try {
    const { driverId } = req.params;
    
    if (!req.file) {
      return res.status(400).json({
        status: 'error',
        message: 'No photo file provided'
      });
    }

    const photoBase64 = bufferToBase64(req.file.buffer);
    
    const result = await updateDriver(req.db, driverId, {
      $set: {
        profilePhoto: photoBase64,
        updatedAt: new Date()
      }
    });

    if (result.matchedCount === 0) {
      return res.status(404).json({
        status: 'error',
        message: 'Driver not found'
      });
    }

    res.json({
      status: 'success',
      message: 'Profile photo uploaded successfully',
      data: {
        photoUrl: photoBase64.substring(0, 50) + '...'
      }
    });
  } catch (error) {
    console.error('Error uploading profile photo:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// POST - Upload license document
router.post('/upload-license/:driverId', upload.single('license'), async (req, res) => {
  try {
    const { driverId } = req.params;
    const { licenseNumber, expiryDate } = req.body;
    
    if (!req.file) {
      return res.status(400).json({
        status: 'error',
        message: 'No license document provided'
      });
    }

    const licenseBase64 = bufferToBase64(req.file.buffer);
    
    const updateData = {
      'documents.license': {
        documentUrl: licenseBase64,
        licenseNumber: licenseNumber || null,
        expiryDate: expiryDate ? new Date(expiryDate) : null,
        uploadedAt: new Date(),
        verified: false,
        fileSize: req.file.size,
        mimeType: req.file.mimetype
      },
      updatedAt: new Date()
    };

    if (licenseNumber) {
      updateData['license.number'] = licenseNumber;
    }

    const result = await updateDriver(req.db, driverId, { $set: updateData });

    if (result.matchedCount === 0) {
      return res.status(404).json({
        status: 'error',
        message: 'Driver not found'
      });
    }

    res.json({
      status: 'success',
      message: 'License document uploaded successfully',
      data: {
        licenseNumber,
        expiryDate,
        uploadedAt: new Date()
      }
    });
  } catch (error) {
    console.error('Error uploading license:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// POST - Upload medical certificate
router.post('/upload-medical-certificate/:driverId', upload.single('certificate'), async (req, res) => {
  try {
    const { driverId } = req.params;
    const { expiryDate, certificateNumber } = req.body;
    
    if (!req.file) {
      return res.status(400).json({
        status: 'error',
        message: 'No medical certificate provided'
      });
    }

    const certificateBase64 = bufferToBase64(req.file.buffer);
    
    const result = await updateDriver(req.db, driverId, {
      $set: {
        'documents.medicalCertificate': {
          documentUrl: certificateBase64,
          certificateNumber: certificateNumber || null,
          expiryDate: expiryDate ? new Date(expiryDate) : null,
          uploadedAt: new Date(),
          verified: false,
          fileSize: req.file.size,
          mimeType: req.file.mimetype
        },
        updatedAt: new Date()
      }
    });

    if (result.matchedCount === 0) {
      return res.status(404).json({
        status: 'error',
        message: 'Driver not found'
      });
    }

    res.json({
      status: 'success',
      message: 'Medical certificate uploaded successfully',
      data: {
        certificateNumber,
        expiryDate,
        uploadedAt: new Date()
      }
    });
  } catch (error) {
    console.error('Error uploading medical certificate:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// GET - Retrieve all driver documents
router.get('/documents/:driverId', async (req, res) => {
  try {
    const { driverId } = req.params;
    
    const driver = await findDriver(req.db, driverId);

    if (!driver) {
      return res.status(404).json({
        status: 'error',
        message: 'Driver not found'
      });
    }

    // Check if daily photo has expired (24 hours from upload)
    let profilePhoto = driver.profilePhoto;
    if (driver.lastDailyPhotoUpload && hasPhotoExpired(driver.lastDailyPhotoUpload)) {
      profilePhoto = null; // Photo has expired
    }

    res.json({
      status: 'success',
      data: {
        profilePhoto,
        lastDailyPhotoUpload: driver.lastDailyPhotoUpload || null,
        needsDailyPhoto: isDailyPhotoRequired(driver.lastDailyPhotoUpload),
        documents: driver.documents || {},
        photoHistory: (driver.photoHistory || []).slice(-10)
      }
    });
  } catch (error) {
    console.error('Error retrieving documents:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// GET - Get document status summary (with 24-hour daily photo expiry)
router.get('/status/:driverId', async (req, res) => {
  try {
    const { driverId } = req.params;
    console.log('Getting status for driver:', driverId);
    
    const driver = await findDriver(req.db, driverId);

    if (!driver) {
      console.log('Driver not found:', driverId);
      return res.status(404).json({
        status: 'error',
        message: 'Driver not found'
      });
    }

    console.log('Found driver:', driver.driverId, driver.personalInfo?.name);

    // Check if daily photo has expired (24 hours from upload)
    let dailyPhotoUploaded = !!driver.profilePhoto;
    let dailyPhotoUrl = null;
    
    if (driver.profilePhoto && driver.lastDailyPhotoUpload) {
      if (hasPhotoExpired(driver.lastDailyPhotoUpload)) {
        dailyPhotoUploaded = false; // Photo expired
        dailyPhotoUrl = null;
      } else {
        dailyPhotoUrl = driver.profilePhoto;
      }
    }

    const status = {
      dailyVerificationPhoto: {
        uploaded: dailyPhotoUploaded,
        isRequired: true,
        verified: true,
        lastUpload: driver.lastDailyPhotoUpload,
        expiryDate: driver.lastDailyPhotoUpload 
          ? new Date(new Date(driver.lastDailyPhotoUpload).getTime() + 24 * 60 * 60 * 1000)
          : null,
        dailyPhotoUrl: dailyPhotoUrl
      },
      license: {
        uploaded: !!(driver.documents?.license?.documentUrl),
        isRequired: true,
        verified: driver.documents?.license?.verified || false,
        expiryDate: driver.documents?.license?.expiryDate || null
      },
      medicalCertificate: {
        uploaded: !!(driver.documents?.medicalCertificate?.documentUrl),
        isRequired: true,
        verified: driver.documents?.medicalCertificate?.verified || false,
        expiryDate: driver.documents?.medicalCertificate?.expiryDate || null
      }
    };

    res.json({
      status: 'success',
      data: status
    });
  } catch (error) {
    console.error('Error getting document status:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// DELETE - Remove a document
router.delete('/remove-document/:driverId/:documentType', async (req, res) => {
  try {
    const { driverId, documentType } = req.params;
    
    const validTypes = ['license', 'medicalCertificate'];
    if (!validTypes.includes(documentType)) {
      return res.status(400).json({
        status: 'error',
        message: 'Invalid document type'
      });
    }

    const result = await updateDriver(req.db, driverId, {
      $unset: { [`documents.${documentType}`]: "" },
      $set: { updatedAt: new Date() }
    });

    if (result.matchedCount === 0) {
      return res.status(404).json({
        status: 'error',
        message: 'Driver not found'
      });
    }

    res.json({
      status: 'success',
      message: `${documentType} removed successfully`
    });
  } catch (error) {
    console.error('Error removing document:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// AUTO-LINK - Link Firebase UID to driver by email
router.post('/auto-link', async (req, res) => {
  try {
    const { firebaseUid, email } = req.body;
    
    if (!firebaseUid || !email) {
      return res.status(400).json({
        status: 'error',
        message: 'Firebase UID and email are required'
      });
    }

    console.log('🔗 Auto-linking:', { firebaseUid, email });

    // First check admin_users collection (post-migration)
    const adminUser = await req.db.collection('admin_users').findOne({
      email: email.toLowerCase(),
      role: 'driver'
    });

    if (adminUser) {
      console.log('✅ Found driver in admin_users:', adminUser.email);
      
      // Update admin_users with Firebase UID if not already set
      if (!adminUser.firebaseUid || adminUser.firebaseUid !== firebaseUid) {
        await req.db.collection('admin_users').updateOne(
          { _id: adminUser._id },
          {
            $set: {
              firebaseUid: firebaseUid,
              linkedAt: new Date(),
              updatedAt: new Date()
            }
          }
        );
        console.log('✅ Updated admin_users with Firebase UID');
      }

      // Also update corresponding driver record if it exists
      const driver = await req.db.collection('drivers').findOne({
        $or: [
          { driverId: adminUser.driverId },
          { 'personalInfo.email': email }
        ]
      });

      if (driver) {
        await req.db.collection('drivers').updateOne(
          { _id: driver._id },
          {
            $set: {
              firebaseUid: firebaseUid,
              linkedEmail: email,
              linkedAt: new Date(),
              updatedAt: new Date()
            }
          }
        );
        console.log('✅ Updated driver record with Firebase UID');
      }

      return res.json({
        status: 'success',
        message: 'Linked to admin account',
        driverInfo: {
          driverId: adminUser.driverId,
          name: adminUser.name,
          email: adminUser.email
        }
      });
    }

    // Fallback: Check drivers collection (legacy)
    const driver = await req.db.collection('drivers').findOne({
      'personalInfo.email': email
    });

    if (driver) {
      await req.db.collection('drivers').updateOne(
        { _id: driver._id },
        {
          $set: {
            firebaseUid: firebaseUid,
            linkedEmail: email,
            linkedAt: new Date(),
            updatedAt: new Date()
          }
        }
      );

      console.log('✅ Linked Firebase UID to legacy driver:', driver.driverId);

      return res.json({
        status: 'success',
        message: 'Linked to driver account',
        driverInfo: {
          driverId: driver.driverId,
          name: driver.personalInfo?.name,
          email: driver.personalInfo?.email
        }
      });
    }

    // Fallback: Check users collection (legacy)
    const userDriver = await req.db.collection('users').findOne({
      email: email,
      role: 'driver'
    });

    if (userDriver) {
      await req.db.collection('users').updateOne(
        { _id: userDriver._id },
        {
          $set: {
            firebaseUid: firebaseUid,
            linkedAt: new Date(),
            updatedAt: new Date()
          }
        }
      );

      return res.json({
        status: 'success',
        message: 'Linked to legacy user account',
        driverInfo: {
          name: userDriver.name,
          email: userDriver.email
        }
      });
    }

    // No driver found anywhere
    return res.status(404).json({
      status: 'error',
      message: 'No driver found with this email. Please contact admin.'
    });
  } catch (error) {
    console.error('❌ Error auto-linking Firebase UID:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// ADMIN ONLY - Link Firebase UID to existing driver
router.post('/link-firebase/:driverId', async (req, res) => {
  try {
    const { driverId } = req.params;
    const { firebaseUid, email } = req.body;
    
    if (!firebaseUid) {
      return res.status(400).json({
        status: 'error',
        message: 'Firebase UID is required'
      });
    }

    const result = await updateDriver(req.db, driverId, {
      $set: {
        firebaseUid: firebaseUid,
        linkedEmail: email,
        linkedAt: new Date(),
        updatedAt: new Date()
      }
    });

    if (result.matchedCount === 0) {
      return res.status(404).json({
        status: 'error',
        message: 'Driver not found'
      });
    }

    res.json({
      status: 'success',
      message: 'Firebase UID linked successfully'
    });
  } catch (error) {
    console.error('Error linking Firebase UID:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

module.exports = router;