const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const admin = require('../config/firebase');

// Create uploads directory if it doesn't exist
const uploadsDir = path.join(__dirname, '../uploads/sos_resolutions');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}

// Configure multer for file upload
const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, uploadsDir);
  },
  filename: function (req, file, cb) {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, 'sos-' + uniqueSuffix + path.extname(file.originalname));
  }
});

const upload = multer({
  storage: storage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB limit
  fileFilter: function (req, file, cb) {
    const allowedTypes = /jpeg|jpg|png|gif/;
    const extname = allowedTypes.test(path.extname(file.originalname).toLowerCase());
    const mimetype = allowedTypes.test(file.mimetype);
    
    if (mimetype && extname) {
      return cb(null, true);
    } else {
      cb(new Error('Only image files are allowed!'));
    }
  }
});

// POST /api/sos/resolve - Resolve SOS with proof
router.post('/resolve', upload.single('photo'), async (req, res) => {
  try {
    console.log('📥 SOS Resolution Request received');
    console.log('   Body:', req.body);
    console.log('   File:', req.file ? 'Present' : 'Missing');
    
    // Check if body exists
    if (!req.body) {
      return res.status(400).json({
        status: 'error',
        message: 'Request body is missing',
        error: 'No form data received'
      });
    }
    
    const { sosId, resolutionNotes, latitude, longitude, resolvedBy } = req.body;
    
    if (!sosId || !resolutionNotes) {
      return res.status(400).json({
        status: 'error',
        message: 'SOS ID and resolution notes are required',
        received: { sosId, resolutionNotes }
      });
    }

    if (!req.file) {
      return res.status(400).json({
        status: 'error',
        message: 'Photo evidence is required'
      });
    }

    // Get the photo URL (relative path)
    const photoUrl = `/uploads/sos_resolutions/${req.file.filename}`;
    
    // Update SOS alert in Firebase Realtime Database
    const sosRef = admin.database().ref(`sos_events/${sosId}`);;
    const sosSnapshot = await sosRef.once('value');
    
    if (!sosSnapshot.exists()) {
      // Delete uploaded file if SOS not found
      fs.unlinkSync(req.file.path);
      return res.status(404).json({
        status: 'error',
        message: 'SOS alert not found'
      });
    }

    // Update SOS with resolution data
    const timestamp = new Date().toISOString();

await sosRef.update({
  status: 'Resolved',
  resolutionPhoto: photoUrl,
  resolutionPhotoPath: req.file.path,
  resolutionNotes: resolutionNotes,
  resolutionTimestamp: timestamp,
  resolvedBy: resolvedBy || 'Admin',
  resolutionLatitude: latitude ? parseFloat(latitude) : null,
  resolutionLongitude: longitude ? parseFloat(longitude) : null,
  resolvedAt: timestamp
});

    console.log('✅ SOS resolved successfully:', sosId);

    res.json({
      status: 'success',
      message: 'SOS alert resolved successfully',
      data: {
        sosId,
        photoUrl,
        resolvedAt: new Date().toISOString()
      }
    });

  } catch (error) {
    console.error('❌ Error resolving SOS:', error);
    
    // Delete uploaded file if there was an error
    if (req.file && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }
    
    res.status(500).json({
      status: 'error',
      message: 'Internal Server Error',
      error: error.message
    });
  }
});

// Error handling middleware for multer
router.use((error, req, res, next) => {
  if (error instanceof multer.MulterError) {
    console.error('❌ Multer Error:', error);
    return res.status(400).json({
      status: 'error',
      message: 'File upload error',
      error: error.message
    });
  } else if (error) {
    console.error('❌ Upload Error:', error);
    return res.status(500).json({
      status: 'error',
      message: 'Upload failed',
      error: error.message
    });
  }
  next();
});

// GET /api/sos/resolution-photo/:filename - Serve resolution photos
router.get('/resolution-photo/:filename', (req, res) => {
  const filename = req.params.filename;
  const filepath = path.join(uploadsDir, filename);
  
  if (fs.existsSync(filepath)) {
    res.sendFile(filepath);
  } else {
    res.status(404).json({
      status: 'error',
      message: 'Photo not found'
    });
  }
});

module.exports = router;
