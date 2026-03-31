// routes/document_router.js
// MongoDB-based document storage (alternative to Firebase Storage)

const express = require('express');
const router = express.Router();
const multer = require('multer');
const { GridFSBucket, ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');

// Configure multer for memory storage
const storage = multer.memoryStorage();
const upload = multer({
  storage: storage,
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB limit
  },
  fileFilter: (req, file, cb) => {
    // Allow only specific file types
    const allowedExtensions = /\.(pdf|jpg|jpeg|png|doc|docx)$/i;
    const allowedMimeTypes = [
      'application/pdf',
      'image/jpeg',
      'image/jpg',
      'image/png',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/octet-stream', // Sometimes files come as this
    ];

    const hasValidExtension = allowedExtensions.test(file.originalname);
    const hasValidMimeType = allowedMimeTypes.includes(file.mimetype);

    console.log('File validation:', {
      filename: file.originalname,
      mimetype: file.mimetype,
      hasValidExtension,
      hasValidMimeType,
    });

    if (hasValidExtension || hasValidMimeType) {
      return cb(null, true);
    } else {
      cb(new Error(`File type not allowed. Filename: ${file.originalname}, MIME: ${file.mimetype}`));
    }
  },
});

// Upload vehicle document
router.post('/vehicles/:vehicleId/documents', verifyToken, upload.single('file'), async (req, res) => {
  try {
    const { vehicleId } = req.params;
    const { documentType, documentName, expiryDate, isDriverDoc } = req.body;
    const file = req.file;

    console.log('Upload request received:', {
      vehicleId,
      documentType,
      documentName,
      isDriverDoc,
      hasFile: !!file,
      hasDb: !!req.db,
    });

    if (!file) {
      return res.status(400).json({
        success: false,
        message: 'No file uploaded',
      });
    }

    // Get MongoDB database
    const db = req.db || req.app.locals.db;
    
    if (!db) {
      console.error('Database not available!');
      return res.status(500).json({
        success: false,
        message: 'Database connection not available',
      });
    }
    
    // Create GridFS bucket for file storage
    const bucket = new GridFSBucket(db, {
      bucketName: 'documents',
    });

    // Upload file to GridFS
    const uploadStream = bucket.openUploadStream(file.originalname, {
      metadata: {
        vehicleId,
        documentType,
        documentName,
        isDriverDoc: isDriverDoc === 'true',
        uploadedBy: req.user.email,
        uploadDate: new Date(),
        contentType: file.mimetype,
      },
    });

    uploadStream.end(file.buffer);

    uploadStream.on('finish', async () => {
      // Create document record
      const documentRecord = {
        id: uploadStream.id.toString(),
        documentType,
        documentName,
        documentUrl: `/api/documents/download/${uploadStream.id}`,
        uploadDate: new Date(),
        expiryDate: expiryDate ? new Date(expiryDate) : null,
        uploadedBy: req.user.email,
        fileId: uploadStream.id,
        fileName: file.originalname,
        fileSize: file.size,
        contentType: file.mimetype,
      };

      // Update vehicle with document
      const collection = db.collection('vehicles');
      const updateField = isDriverDoc === 'true' ? 'driverDocuments' : 'documents';
      
      await collection.updateOne(
        { _id: new ObjectId(vehicleId) },
        { $push: { [updateField]: documentRecord } }
      );

      res.json({
        success: true,
        message: 'Document uploaded successfully',
        data: documentRecord,
      });
    });

    uploadStream.on('error', (error) => {
      console.error('Upload error:', error);
      res.status(500).json({
        success: false,
        message: 'Error uploading document',
        error: error.message,
      });
    });
  } catch (error) {
    console.error('Error uploading document:', error);
    res.status(500).json({
      success: false,
      message: 'Error uploading document',
      error: error.message,
    });
  }
});

// Download document
router.get('/download/:fileId', async (req, res) => {
  try {
    const { fileId } = req.params;
    const db = req.db || req.app.locals.db;
    
    if (!db) {
      return res.status(500).json({
        success: false,
        message: 'Database connection not available',
      });
    }

    const bucket = new GridFSBucket(db, {
      bucketName: 'documents',
    });

    // Get file metadata
    const files = await bucket.find({ _id: new ObjectId(fileId) }).toArray();
    
    if (files.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'File not found',
      });
    }

    const file = files[0];

    // Set headers
    res.set('Content-Type', file.metadata.contentType);
    res.set('Content-Disposition', `inline; filename="${file.filename}"`);

    // Stream file to response
    const downloadStream = bucket.openDownloadStream(new ObjectId(fileId));
    downloadStream.pipe(res);

    downloadStream.on('error', (error) => {
      console.error('Download error:', error);
      res.status(500).json({
        success: false,
        message: 'Error downloading file',
      });
    });
  } catch (error) {
    console.error('Error downloading document:', error);
    res.status(500).json({
      success: false,
      message: 'Error downloading document',
      error: error.message,
    });
  }
});

// Upload driver document
router.post('/drivers/:driverId/documents', verifyToken, upload.single('file'), async (req, res) => {
  try {
    const { driverId } = req.params;
    const { documentType, documentName, expiryDate } = req.body;
    const file = req.file;

    console.log('Driver document upload request:', {
      driverId,
      documentType,
      documentName,
      hasFile: !!file,
    });

    if (!file) {
      return res.status(400).json({
        success: false,
        message: 'No file uploaded',
      });
    }

    const db = req.db || req.app.locals.db;
    
    if (!db) {
      console.error('Database not available!');
      return res.status(500).json({
        success: false,
        message: 'Database connection not available',
      });
    }
    
    // Create GridFS bucket for file storage
    const bucket = new GridFSBucket(db, {
      bucketName: 'documents',
    });

    // Upload file to GridFS
    const uploadStream = bucket.openUploadStream(file.originalname, {
      metadata: {
        driverId,
        documentType,
        documentName,
        uploadedBy: req.user.email,
        uploadDate: new Date(),
        contentType: file.mimetype,
      },
    });

    uploadStream.end(file.buffer);

    uploadStream.on('finish', async () => {
      // Create document record
      const documentRecord = {
        id: uploadStream.id.toString(),
        documentType,
        documentName,
        documentUrl: `/api/documents/download/${uploadStream.id}`,
        uploadDate: new Date(),
        expiryDate: expiryDate ? new Date(expiryDate) : null,
        uploadedBy: req.user.email,
        fileId: uploadStream.id,
        fileName: file.originalname,
        fileSize: file.size,
        contentType: file.mimetype,
      };

      // Update driver with document
      const collection = db.collection('drivers');
      
      await collection.updateOne(
        { driverId: driverId },
        { $push: { documents: documentRecord } }
      );

      res.json({
        success: true,
        message: 'Document uploaded successfully',
        data: documentRecord,
      });
    });

    uploadStream.on('error', (error) => {
      console.error('Upload error:', error);
      res.status(500).json({
        success: false,
        message: 'Error uploading document',
        error: error.message,
      });
    });
  } catch (error) {
    console.error('Error uploading driver document:', error);
    res.status(500).json({
      success: false,
      message: 'Error uploading document',
      error: error.message,
    });
  }
});

// Delete driver document
router.delete('/drivers/:driverId/documents/:documentId', verifyToken, async (req, res) => {
  try {
    const { driverId, documentId } = req.params;
    const db = req.db || req.app.locals.db;
    
    if (!db) {
      return res.status(500).json({
        success: false,
        message: 'Database connection not available',
      });
    }

    // Get document to find fileId
    const collection = db.collection('drivers');
    const driver = await collection.findOne({ driverId: driverId });

    if (!driver) {
      return res.status(404).json({
        success: false,
        message: 'Driver not found',
      });
    }

    const documents = driver.documents || [];
    const document = documents.find(doc => doc.id === documentId);

    if (!document) {
      return res.status(404).json({
        success: false,
        message: 'Document not found',
      });
    }

    // Delete file from GridFS
    if (document.fileId) {
      const bucket = new GridFSBucket(db, {
        bucketName: 'documents',
      });
      await bucket.delete(new ObjectId(document.fileId));
    }

    // Remove document from driver
    await collection.updateOne(
      { driverId: driverId },
      { $pull: { documents: { id: documentId } } }
    );

    res.json({
      success: true,
      message: 'Document deleted successfully',
    });
  } catch (error) {
    console.error('Error deleting driver document:', error);
    res.status(500).json({
      success: false,
      message: 'Error deleting document',
      error: error.message,
    });
  }
});

// Delete document
router.delete('/vehicles/:vehicleId/documents/:documentId', verifyToken, async (req, res) => {
  try {
    const { vehicleId, documentId } = req.params;
    const { isDriverDoc } = req.query;
    const db = req.db || req.app.locals.db;
    
    if (!db) {
      return res.status(500).json({
        success: false,
        message: 'Database connection not available',
      });
    }

    // Get document to find fileId
    const collection = db.collection('vehicles');
    const vehicle = await collection.findOne({ _id: new ObjectId(vehicleId) });

    if (!vehicle) {
      return res.status(404).json({
        success: false,
        message: 'Vehicle not found',
      });
    }

    const documents = isDriverDoc === 'true' ? vehicle.driverDocuments : vehicle.documents;
    const document = documents.find(doc => doc.id === documentId);

    if (!document) {
      return res.status(404).json({
        success: false,
        message: 'Document not found',
      });
    }

    // Delete file from GridFS
    if (document.fileId) {
      const bucket = new GridFSBucket(db, {
        bucketName: 'documents',
      });
      await bucket.delete(new ObjectId(document.fileId));
    }

    // Remove document from vehicle
    const updateField = isDriverDoc === 'true' ? 'driverDocuments' : 'documents';
    await collection.updateOne(
      { _id: new ObjectId(vehicleId) },
      { $pull: { [updateField]: { id: documentId } } }
    );

    res.json({
      success: true,
      message: 'Document deleted successfully',
    });
  } catch (error) {
    console.error('Error deleting document:', error);
    res.status(500).json({
      success: false,
      message: 'Error deleting document',
      error: error.message,
    });
  }
});

module.exports = router;
