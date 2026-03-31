// routes/hrm_employees.js
// ============================================================================
// HRM EMPLOYEE MANAGEMENT - Complete CRUD + Birthday Automation
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { GridFSBucket } = require('mongodb');
const cron = require('node-cron');

// ============================================================================
// MONGOOSE SCHEMAS
// ============================================================================

const EmployeeSchema = new mongoose.Schema({
  employeeId: { type: String, required: true, unique: true }, // AT0001, AT0002
  
  // Personal Information
  name: { type: String, required: true },
  gender: { type: String, enum: ['Male', 'Female', 'Other'], required: true },
  dob: { type: Date, required: true },
  bloodGroup: { type: String, required: true },
  personalEmail: { type: String, required: true },
  phone: { type: String, required: true },
  altPhone: { type: String, required: true },
  address: { type: String, required: true },
  country: { type: String, required: true },
  state: { type: String, required: true },
  
  // Identity Documents
  aadharCard: { type: String, required: true },
  panNumber: { type: String, required: true },
  
  // Emergency Contact
  contactName: { type: String, required: true },
  relationship: { type: String, required: true },
  contactPhone: { type: String, required: true },
  contactAltPhone: { type: String, required: true },
  
  // Education
  universityDegree: { type: String, required: true },
  yearCompletion: { type: String, required: true },
  percentageCgpa: { type: String, required: true },
  
  // Bank Details
  bankAccountNumber: { type: String, required: true },
  ifscCode: { type: String, required: true },
  bankBranch: { type: String, required: true },
  
  // Official Information
  email: { type: String, required: true },
  hireDate: { type: Date, required: true },
  department: { type: String, required: true },
  position: { type: String, required: true },
  reportingManager1: { type: String }, // Employee ID
  reportingManager2: { type: String }, // Employee ID
  employeeType: { type: String, enum: ['Probation period', 'Permanent Employee'], required: true },
  salary: { type: Number, required: true },
  workLocation: { type: String, required: true },
  timings: { type: String, required: true },
  companyName: { type: String, required: true },
  status: { type: String, enum: ['Active', 'Inactive', 'Terminated'], default: 'Active' },
  
  // Documents Array (stored in GridFS)
  documents: [{
    documentType: String,
    filename: String,
    fileId: mongoose.Schema.Types.ObjectId, // GridFS file ID
    uploadedAt: { type: Date, default: Date.now }
  }],
  
  // Metadata
  createdAt: { type: Date, default: Date.now },
  updatedAt: { type: Date, default: Date.now }
}, { 
  timestamps: true,
  collection: 'hr_employee' 
});

const Employee = mongoose.model('HREmployee', EmployeeSchema);

// ============================================================================
// GRIDFS STORAGE SETUP (MongoDB File Storage)
// ============================================================================

let gridFSBucket;

function initGridFS(db) {
  if (!gridFSBucket) {
    gridFSBucket = new GridFSBucket(db, {
      bucketName: 'employee_documents'
    });
    console.log('✅ GridFS initialized for employee documents');
  }
  return gridFSBucket;
}

// Multer memory storage (files go to GridFS, not disk)
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 5 * 1024 * 1024 // 5MB limit
  },
  fileFilter: (req, file, cb) => {
    const allowedTypes = /jpeg|jpg|png|pdf|doc|docx/;
    const extname = allowedTypes.test(path.extname(file.originalname).toLowerCase());
    const mimetype = allowedTypes.test(file.mimetype);
    
    if (extname && mimetype) {
      return cb(null, true);
    } else {
      cb(new Error('Invalid file type. Only JPG, PNG, PDF, DOC, DOCX allowed.'));
    }
  }
});

// ============================================================================
// MIDDLEWARE: Check Super Manager Permission (Delete Only)
// ============================================================================

function checkSuperManager(req, res, next) {
  const superManagerEmails = [
    'admin@abrafleet.com',
    'abishek.veeraswamy@abra-travels.com'
  ];
  
  const userEmail = req.user?.email?.toLowerCase();
  
  if (!userEmail || !superManagerEmails.includes(userEmail)) {
    return res.status(403).json({
      success: false,
      error: 'Access Denied',
      message: 'Only Super Managers can delete employees'
    });
  }
  
  next();
}

// ============================================================================
// HELPER: Generate Next Employee ID
// ============================================================================

async function generateEmployeeId() {
  try {
    const lastEmployee = await Employee.findOne()
      .sort({ employeeId: -1 })
      .select('employeeId')
      .lean();
    
    if (!lastEmployee) {
      return 'AT0001';
    }
    
    const lastId = lastEmployee.employeeId;
    const numericPart = parseInt(lastId.replace('AT', ''));
    const nextNumber = numericPart + 1;
    
    return 'AT' + String(nextNumber).padStart(4, '0');
  } catch (error) {
    console.error('❌ Error generating employee ID:', error);
    throw error;
  }
}

// ============================================================================
// ROUTE: GET ALL EMPLOYEES (with filters)
// ============================================================================

router.get('/employees', async (req, res) => {
  try {
    console.log('\n📋 GET /api/hrm/employees');
    console.log('Query params:', req.query);
    
    const {
      search,
      status,
      department,
      position,
      employeeType,
      workLocation,
      companyName,
      country,
      state,
      page = 1,
      limit = 50
    } = req.query;
    
    // Build filter object
    const filter = {};
    
    if (status) filter.status = status;
    if (department) filter.department = department;
    if (position) filter.position = position;
    if (employeeType) filter.employeeType = employeeType;
    if (workLocation) filter.workLocation = workLocation;
    if (companyName) filter.companyName = companyName;
    if (country) filter.country = country;
    if (state) filter.state = state;
    
    // Global search across multiple fields
    if (search) {
      filter.$or = [
        { employeeId: { $regex: search, $options: 'i' } },
        { name: { $regex: search, $options: 'i' } },
        { email: { $regex: search, $options: 'i' } },
        { phone: { $regex: search, $options: 'i' } },
        { personalEmail: { $regex: search, $options: 'i' } }
      ];
    }
    
    // Pagination
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    // Execute query
    const [employees, total] = await Promise.all([
      Employee.find(filter)
        .sort({ status: 1, createdAt: -1 }) // Active first, then newest
        .skip(skip)
        .limit(parseInt(limit))
        .lean(),
      Employee.countDocuments(filter)
    ]);
    
    // Populate reporting manager names
    for (let emp of employees) {
      if (emp.reportingManager1) {
        const manager1 = await Employee.findOne({ employeeId: emp.reportingManager1 })
          .select('name employeeId')
          .lean();
        emp.reportingManager1Name = manager1 ? `${manager1.name} (${manager1.employeeId})` : emp.reportingManager1;
      }
      
      if (emp.reportingManager2) {
        const manager2 = await Employee.findOne({ employeeId: emp.reportingManager2 })
          .select('name employeeId')
          .lean();
        emp.reportingManager2Name = manager2 ? `${manager2.name} (${manager2.employeeId})` : emp.reportingManager2;
      }
    }
    
    console.log(`✅ Found ${employees.length} employees (Total: ${total})`);
    
    res.json({
      success: true,
      data: employees,
      pagination: {
        total,
        page: parseInt(page),
        limit: parseInt(limit),
        pages: Math.ceil(total / parseInt(limit))
      }
    });
    
  } catch (error) {
    console.error('❌ Error fetching employees:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch employees',
      message: error.message
    });
  }
});

// ============================================================================
// ROUTE: GET SINGLE EMPLOYEE
// ============================================================================

router.get('/employees/:id', async (req, res) => {
  try {
    console.log('\n📄 GET /api/hrm/employees/:id');
    console.log('ID:', req.params.id);
    
    const employee = await Employee.findById(req.params.id).lean();
    
    if (!employee) {
      return res.status(404).json({
        success: false,
        error: 'Employee not found'
      });
    }
    
    // Populate reporting manager names
    if (employee.reportingManager1) {
      const manager1 = await Employee.findOne({ employeeId: employee.reportingManager1 })
        .select('name employeeId')
        .lean();
      employee.reportingManager1Name = manager1 ? `${manager1.name} (${manager1.employeeId})` : employee.reportingManager1;
    }
    
    if (employee.reportingManager2) {
      const manager2 = await Employee.findOne({ employeeId: employee.reportingManager2 })
        .select('name employeeId')
        .lean();
      employee.reportingManager2Name = manager2 ? `${manager2.name} (${manager2.employeeId})` : employee.reportingManager2;
    }
    
    console.log('✅ Employee found:', employee.employeeId);
    
    res.json({
      success: true,
      data: employee
    });
    
  } catch (error) {
    console.error('❌ Error fetching employee:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch employee',
      message: error.message
    });
  }
});

// ============================================================================
// ROUTE: CREATE EMPLOYEE (with document upload)
// ============================================================================

router.post('/employees', upload.array('documents', 10), async (req, res) => {
  try {
    console.log('\n➕ POST /api/hrm/employees');
    console.log('Body:', req.body);
    console.log('Files:', req.files?.length || 0);
    
    // Initialize GridFS
    const bucket = initGridFS(req.db);
    
    // Generate employee ID
    const employeeId = await generateEmployeeId();
    console.log('Generated ID:', employeeId);
    
    // Parse document metadata (sent as JSON string)
    let documentMetadata = [];
    if (req.body.documentMetadata) {
      try {
        documentMetadata = JSON.parse(req.body.documentMetadata);
      } catch (e) {
        console.error('⚠️ Invalid documentMetadata JSON:', e);
      }
    }
    
    // Upload documents to GridFS
    const uploadedDocs = [];
    
    if (req.files && req.files.length > 0) {
      for (let i = 0; i < req.files.length; i++) {
        const file = req.files[i];
        const metadata = documentMetadata[i] || {};
        
        const uploadStream = bucket.openUploadStream(file.originalname, {
          metadata: {
            employeeId: employeeId,
            documentType: metadata.documentType || 'Other',
            contentType: file.mimetype,
            uploadedBy: req.user?.email || 'system',
            uploadedAt: new Date()
          }
        });
        
        uploadStream.end(file.buffer);
        
        await new Promise((resolve, reject) => {
          uploadStream.on('finish', () => {
            uploadedDocs.push({
              documentType: metadata.documentType || 'Other',
              filename: file.originalname,
              fileId: uploadStream.id,
              uploadedAt: new Date()
            });
            resolve();
          });
          uploadStream.on('error', reject);
        });
      }
      
      console.log(`✅ Uploaded ${uploadedDocs.length} documents to GridFS`);
    }
    
    // Create employee record
    const employeeData = {
      employeeId,
      name: req.body.name,
      gender: req.body.gender,
      dob: new Date(req.body.dob),
      bloodGroup: req.body.bloodGroup,
      personalEmail: req.body.personalEmail,
      phone: req.body.phone,
      altPhone: req.body.altPhone,
      address: req.body.address,
      country: req.body.country,
      state: req.body.state,
      aadharCard: req.body.aadharCard,
      panNumber: req.body.panNumber?.toUpperCase(),
      contactName: req.body.contactName,
      relationship: req.body.relationship,
      contactPhone: req.body.contactPhone,
      contactAltPhone: req.body.contactAltPhone,
      universityDegree: req.body.universityDegree,
      yearCompletion: req.body.yearCompletion,
      percentageCgpa: req.body.percentageCgpa,
      bankAccountNumber: req.body.bankAccountNumber,
      ifscCode: req.body.ifscCode?.toUpperCase(),
      bankBranch: req.body.bankBranch,
      email: req.body.email,
      hireDate: new Date(req.body.hireDate),
      department: req.body.department,
      position: req.body.position,
      reportingManager1: req.body.reportingManager1 || null,
      reportingManager2: req.body.reportingManager2 || null,
      employeeType: req.body.employeeType,
      salary: parseFloat(req.body.salary),
      workLocation: req.body.workLocation,
      timings: req.body.timings,
      companyName: req.body.companyName,
      status: req.body.status || 'Active',
      documents: uploadedDocs
    };
    
    const employee = new Employee(employeeData);
    await employee.save();
    
    console.log('✅ Employee created:', employeeId);
    
    res.status(201).json({
      success: true,
      message: 'Employee created successfully',
      data: employee
    });
    
  } catch (error) {
    console.error('❌ Error creating employee:', error);
    
    if (error.code === 11000) {
      return res.status(400).json({
        success: false,
        error: 'Duplicate employee',
        message: 'Employee ID already exists'
      });
    }
    
    res.status(500).json({
      success: false,
      error: 'Failed to create employee',
      message: error.message
    });
  }
});

// ============================================================================
// ROUTE: UPDATE EMPLOYEE (with new document upload)
// ============================================================================

router.put('/employees/:id', upload.array('documents', 10), async (req, res) => {
  try {
    console.log('\n✏️ PUT /api/hrm/employees/:id');
    console.log('ID:', req.params.id);
    console.log('Files:', req.files?.length || 0);
    
    const employee = await Employee.findById(req.params.id);
    
    if (!employee) {
      return res.status(404).json({
        success: false,
        error: 'Employee not found'
      });
    }
    
    // Initialize GridFS
    const bucket = initGridFS(req.db);
    
    // Parse document metadata
    let documentMetadata = [];
    if (req.body.documentMetadata) {
      try {
        documentMetadata = JSON.parse(req.body.documentMetadata);
      } catch (e) {
        console.error('⚠️ Invalid documentMetadata JSON:', e);
      }
    }
    
    // Upload new documents to GridFS
    const uploadedDocs = [];
    
    if (req.files && req.files.length > 0) {
      for (let i = 0; i < req.files.length; i++) {
        const file = req.files[i];
        const metadata = documentMetadata[i] || {};
        
        const uploadStream = bucket.openUploadStream(file.originalname, {
          metadata: {
            employeeId: employee.employeeId,
            documentType: metadata.documentType || 'Other',
            contentType: file.mimetype,
            uploadedBy: req.user?.email || 'system',
            uploadedAt: new Date()
          }
        });
        
        uploadStream.end(file.buffer);
        
        await new Promise((resolve, reject) => {
          uploadStream.on('finish', () => {
            uploadedDocs.push({
              documentType: metadata.documentType || 'Other',
              filename: file.originalname,
              fileId: uploadStream.id,
              uploadedAt: new Date()
            });
            resolve();
          });
          uploadStream.on('error', reject);
        });
      }
      
      console.log(`✅ Uploaded ${uploadedDocs.length} new documents to GridFS`);
    }
    
    // Update employee fields
    const updates = {
      name: req.body.name,
      gender: req.body.gender,
      dob: req.body.dob ? new Date(req.body.dob) : employee.dob,
      bloodGroup: req.body.bloodGroup,
      personalEmail: req.body.personalEmail,
      phone: req.body.phone,
      altPhone: req.body.altPhone,
      address: req.body.address,
      country: req.body.country,
      state: req.body.state,
      aadharCard: req.body.aadharCard,
      panNumber: req.body.panNumber?.toUpperCase(),
      contactName: req.body.contactName,
      relationship: req.body.relationship,
      contactPhone: req.body.contactPhone,
      contactAltPhone: req.body.contactAltPhone,
      universityDegree: req.body.universityDegree,
      yearCompletion: req.body.yearCompletion,
      percentageCgpa: req.body.percentageCgpa,
      bankAccountNumber: req.body.bankAccountNumber,
      ifscCode: req.body.ifscCode?.toUpperCase(),
      bankBranch: req.body.bankBranch,
      email: req.body.email,
      hireDate: req.body.hireDate ? new Date(req.body.hireDate) : employee.hireDate,
      department: req.body.department,
      position: req.body.position,
      reportingManager1: req.body.reportingManager1 || null,
      reportingManager2: req.body.reportingManager2 || null,
      employeeType: req.body.employeeType,
      salary: req.body.salary ? parseFloat(req.body.salary) : employee.salary,
      workLocation: req.body.workLocation,
      timings: req.body.timings,
      companyName: req.body.companyName,
      status: req.body.status || employee.status,
      updatedAt: new Date()
    };
    
    // Add new documents to existing ones
    if (uploadedDocs.length > 0) {
      updates.documents = [...(employee.documents || []), ...uploadedDocs];
    }
    
    Object.assign(employee, updates);
    await employee.save();
    
    console.log('✅ Employee updated:', employee.employeeId);
    
    res.json({
      success: true,
      message: 'Employee updated successfully',
      data: employee
    });
    
  } catch (error) {
    console.error('❌ Error updating employee:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to update employee',
      message: error.message
    });
  }
});

// ============================================================================
// ROUTE: DELETE EMPLOYEE (Super Manager Only)
// ============================================================================

router.delete('/employees/:id', checkSuperManager, async (req, res) => {
  try {
    console.log('\n🗑️ DELETE /api/hrm/employees/:id');
    console.log('ID:', req.params.id);
    console.log('User:', req.user.email);
    
    const employee = await Employee.findById(req.params.id);
    
    if (!employee) {
      return res.status(404).json({
        success: false,
        error: 'Employee not found'
      });
    }
    
    // Initialize GridFS
    const bucket = initGridFS(req.db);
    
    // Delete all employee documents from GridFS
    if (employee.documents && employee.documents.length > 0) {
      for (const doc of employee.documents) {
        try {
          await bucket.delete(doc.fileId);
        } catch (error) {
          console.error(`⚠️ Error deleting file ${doc.fileId}:`, error.message);
        }
      }
      console.log(`✅ Deleted ${employee.documents.length} documents from GridFS`);
    }
    
    // Delete employee record
    await Employee.findByIdAndDelete(req.params.id);
    
    console.log('✅ Employee deleted:', employee.employeeId);
    
    res.json({
      success: true,
      message: 'Employee and all associated documents deleted successfully'
    });
    
  } catch (error) {
    console.error('❌ Error deleting employee:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete employee',
      message: error.message
    });
  }
});

// ============================================================================
// ROUTE: DELETE SINGLE DOCUMENT (Super Manager Only)
// ============================================================================

router.delete('/employees/:id/documents/:docId', checkSuperManager, async (req, res) => {
  try {
    console.log('\n🗑️ DELETE /api/hrm/employees/:id/documents/:docId');
    
    const employee = await Employee.findById(req.params.id);
    
    if (!employee) {
      return res.status(404).json({
        success: false,
        error: 'Employee not found'
      });
    }
    
    const docIndex = employee.documents.findIndex(
      doc => doc._id.toString() === req.params.docId
    );
    
    if (docIndex === -1) {
      return res.status(404).json({
        success: false,
        error: 'Document not found'
      });
    }
    
    const document = employee.documents[docIndex];
    
    // Delete from GridFS
    const bucket = initGridFS(req.db);
    await bucket.delete(document.fileId);
    
    // Remove from employee record
    employee.documents.splice(docIndex, 1);
    await employee.save();
    
    console.log('✅ Document deleted:', document.filename);
    
    res.json({
      success: true,
      message: 'Document deleted successfully'
    });
    
  } catch (error) {
    console.error('❌ Error deleting document:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete document',
      message: error.message
    });
  }
});

// ============================================================================
// ROUTE: DOWNLOAD DOCUMENT
// ============================================================================

router.get('/employees/:id/documents/:docId/download', async (req, res) => {
  try {
    console.log('\n⬇️ GET /api/hrm/employees/:id/documents/:docId/download');
    
    const employee = await Employee.findById(req.params.id);
    
    if (!employee) {
      return res.status(404).json({
        success: false,
        error: 'Employee not found'
      });
    }
    
    const document = employee.documents.find(
      doc => doc._id.toString() === req.params.docId
    );
    
    if (!document) {
      return res.status(404).json({
        success: false,
        error: 'Document not found'
      });
    }
    
    const bucket = initGridFS(req.db);
    
    // Stream file from GridFS
    const downloadStream = bucket.openDownloadStream(document.fileId);
    
    res.setHeader('Content-Disposition', `attachment; filename="${document.filename}"`);
    
    downloadStream.pipe(res);
    
    downloadStream.on('error', (error) => {
      console.error('❌ Error streaming file:', error);
      if (!res.headersSent) {
        res.status(500).json({
          success: false,
          error: 'Failed to download document'
        });
      }
    });
    
  } catch (error) {
    console.error('❌ Error downloading document:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to download document',
      message: error.message
    });
  }
});

// ============================================================================
// ROUTE: GET EMPLOYEE LIST FOR DROPDOWN (Reporting Managers)
// ============================================================================

router.get('/employees-list', async (req, res) => {
  try {
    console.log('\n📋 GET /api/hrm/employees-list');
    
    const employees = await Employee.find({ status: 'Active' })
      .select('employeeId name position department')
      .sort('name')
      .lean();
    
    console.log(`✅ Found ${employees.length} active employees`);
    
    res.json({
      success: true,
      data: employees
    });
    
  } catch (error) {
    console.error('❌ Error fetching employee list:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch employee list',
      message: error.message
    });
  }
});

// ============================================================================
// ROUTE: CSV EXPORT
// ============================================================================

router.get('/export/csv', async (req, res) => {
  try {
    console.log('\n📤 GET /api/hrm/export/csv');
    
    const employees = await Employee.find().sort({ employeeId: 1 }).lean();
    
    // CSV Headers
    const headers = [
      'Employee ID', 'Name', 'Gender', 'DOB', 'Blood Group', 'Personal Email', 'Phone', 'Alt Phone',
      'Address', 'Country', 'State', 'Aadhar', 'PAN', 'Emergency Contact', 'Relationship',
      'Emergency Phone', 'Emergency Alt Phone', 'Degree', 'Year', 'Percentage/CGPA',
      'Bank Account', 'IFSC', 'Bank Branch', 'Official Email', 'Hire Date', 'Department',
      'Position', 'Employee Type', 'Salary', 'Work Location', 'Timings', 'Company Name',
      'Reporting Manager 1', 'Reporting Manager 2', 'Status'
    ];
    
    // Build CSV
    let csv = headers.join(',') + '\n';
    
    for (const emp of employees) {
      const row = [
        emp.employeeId,
        `"${emp.name}"`,
        emp.gender,
        emp.dob?.toISOString().split('T')[0] || '',
        emp.bloodGroup,
        emp.personalEmail,
        emp.phone,
        emp.altPhone,
        `"${emp.address}"`,
        emp.country,
        emp.state,
        emp.aadharCard,
        emp.panNumber,
        emp.contactName,
        emp.relationship,
        emp.contactPhone,
        emp.contactAltPhone,
        emp.universityDegree,
        emp.yearCompletion,
        emp.percentageCgpa,
        emp.bankAccountNumber,
        emp.ifscCode,
        emp.bankBranch,
        emp.email,
        emp.hireDate?.toISOString().split('T')[0] || '',
        emp.department,
        emp.position,
        emp.employeeType,
        emp.salary,
        emp.workLocation,
        emp.timings,
        emp.companyName,
        emp.reportingManager1 || '',
        emp.reportingManager2 || '',
        emp.status
      ];
      
      csv += row.join(',') + '\n';
    }
    
    console.log(`✅ Exported ${employees.length} employees to CSV`);
    
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', `attachment; filename=employees_${Date.now()}.csv`);
    res.send(csv);
    
  } catch (error) {
    console.error('❌ Error exporting CSV:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to export CSV',
      message: error.message
    });
  }
});

// ============================================================================
// ROUTE: CSV IMPORT
// ============================================================================

router.post('/import/csv', upload.single('file'), async (req, res) => {
  try {
    console.log('\n📥 POST /api/hrm/import/csv');
    
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'No file uploaded'
      });
    }
    
    const csvData = req.file.buffer.toString('utf-8');
    const lines = csvData.split('\n').filter(line => line.trim());
    
    // Skip header
    const dataLines = lines.slice(1);
    
    let successCount = 0;
    let failedCount = 0;
    const errors = [];
    
    for (let i = 0; i < dataLines.length; i++) {
      const line = dataLines[i];
      const values = line.split(',').map(v => v.trim().replace(/^"|"$/g, ''));
      
      try {
        // Validate required fields
        if (!values[1] || !values[23] || !values[6]) {
          throw new Error('Missing required fields (name, email, or phone)');
        }
        
        const employeeData = {
          employeeId: values[0] || await generateEmployeeId(),
          name: values[1],
          gender: values[2],
          dob: values[3] ? new Date(values[3]) : null,
          bloodGroup: values[4],
          personalEmail: values[5],
          phone: values[6],
          altPhone: values[7],
          address: values[8],
          country: values[9],
          state: values[10],
          aadharCard: values[11],
          panNumber: values[12]?.toUpperCase(),
          contactName: values[13],
          relationship: values[14],
          contactPhone: values[15],
          contactAltPhone: values[16],
          universityDegree: values[17],
          yearCompletion: values[18],
          percentageCgpa: values[19],
          bankAccountNumber: values[20],
          ifscCode: values[21]?.toUpperCase(),
          bankBranch: values[22],
          email: values[23],
          hireDate: values[24] ? new Date(values[24]) : null,
          department: values[25],
          position: values[26],
          employeeType: values[27],
          salary: parseFloat(values[28]) || 0,
          workLocation: values[29],
          timings: values[30],
          companyName: values[31],
          reportingManager1: values[32] || null,
          reportingManager2: values[33] || null,
          status: values[34] || 'Active'
        };
        
        const employee = new Employee(employeeData);
        await employee.save();
        
        successCount++;
      } catch (error) {
        failedCount++;
        errors.push(`Row ${i + 2}: ${error.message}`);
      }
    }
    
    console.log(`✅ Import complete: ${successCount} success, ${failedCount} failed`);
    
    res.json({
      success: true,
      message: 'CSV import completed',
      data: {
        total: dataLines.length,
        success: successCount,
        failed: failedCount,
        errors: errors
      }
    });
    
  } catch (error) {
    console.error('❌ Error importing CSV:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to import CSV',
      message: error.message
    });
  }
});

// ============================================================================
// ROUTE: CSV TEMPLATE DOWNLOAD
// ============================================================================

router.get('/export/template', (req, res) => {
  try {
    console.log('\n📄 GET /api/hrm/export/template');
    
    const headers = [
      'Employee ID', 'Name', 'Gender', 'DOB', 'Blood Group', 'Personal Email', 'Phone', 'Alt Phone',
      'Address', 'Country', 'State', 'Aadhar', 'PAN', 'Emergency Contact', 'Relationship',
      'Emergency Phone', 'Emergency Alt Phone', 'Degree', 'Year', 'Percentage/CGPA',
      'Bank Account', 'IFSC', 'Bank Branch', 'Official Email', 'Hire Date', 'Department',
      'Position', 'Employee Type', 'Salary', 'Work Location', 'Timings', 'Company Name',
      'Reporting Manager 1', 'Reporting Manager 2', 'Status'
    ];
    
    const csv = headers.join(',') + '\n';
    
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', 'attachment; filename=employee_template.csv');
    res.send(csv);
    
  } catch (error) {
    console.error('❌ Error generating template:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to generate template'
    });
  }
});

// ============================================================================
// 🎂 BIRTHDAY AUTOMATION CRON JOB
// ============================================================================

// Find all HR users by role or email
async function findHRUsers(db) {
  const hrUsers = await db.collection('employee_admins').find({
    $or: [
      { role: 'hr_department' },
      { email: 'hr-admin@fleet.abra-travels.com' }
    ],
    status: 'active'
  }).toArray();
  
  return hrUsers;
}

// Birthday check function
async function checkBirthdays(db) {
  try {
    console.log('\n🎂 BIRTHDAY CHECK - Running...');
    console.log('Time:', new Date().toISOString());
    
    // Get tomorrow's date (month-day)
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    const tomorrowMonth = tomorrow.getMonth() + 1;
    const tomorrowDay = tomorrow.getDate();
    
    // Find employees with birthday tomorrow
    const birthdayEmployees = await Employee.find({
      status: 'Active',
      $expr: {
        $and: [
          { $eq: [{ $month: '$dob' }, tomorrowMonth] },
          { $eq: [{ $dayOfMonth: '$dob' }, tomorrowDay] }
        ]
      }
    }).lean();
    
    console.log(`Found ${birthdayEmployees.length} birthdays tomorrow`);
    
    if (birthdayEmployees.length === 0) {
      console.log('✅ No birthdays tomorrow - skipping ticket creation');
      return;
    }
    
    // Get all HR users
    const hrUsers = await findHRUsers(db);
    
    if (hrUsers.length === 0) {
      console.error('❌ No HR users found to assign birthday tickets');
      return;
    }
    
    console.log(`Found ${hrUsers.length} HR users to notify`);
    
    const currentYear = new Date().getFullYear();
    
    // Create ticket for each birthday employee
    for (const emp of birthdayEmployees) {
      const refTag = `[Auto-Birthday: ${emp.employeeId}-${currentYear}]`;
      
      // Check if ticket already exists for this year
      const existingTicket = await db.collection('tickets').findOne({
        message: { $regex: refTag }
      });
      
      if (existingTicket) {
        console.log(`⚠️ Ticket already exists for ${emp.employeeId} - skipping`);
        continue;
      }
      
      // Calculate age
      const birthYear = new Date(emp.dob).getFullYear();
      const age = currentYear - birthYear;
      
      // Format display date
      const displayDate = tomorrow.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric'
      });
      
      // Assign to all HR users
      for (const hrUser of hrUsers) {
        const ticketNumber = `BDAY-${Date.now()}-${Math.floor(Math.random() * 10000)}`;
        
        const subject = `🎂 Birthday Alert: ${emp.name} - Tomorrow ${displayDate} (Turning ${age})`;
        
        const message = `🎉 **UPCOMING BIRTHDAY NOTIFICATION**
========================================
👤 Employee: **${emp.name}** (${emp.employeeId})
🏢 Department: ${emp.department}
📅 Birthday Date: Tomorrow - ${displayDate} (Turning ${age})
📧 Email: ${emp.email}
📱 Phone: ${emp.phone}
========================================
ℹ️ ACTION REQUIRED:
- Send birthday wishes email/message
- Arrange for cake/celebration if applicable
- Update internal birthday calendar
- Coordinate with team for any surprises

This is an automated notification generated by the HR system.

${refTag}`;
        
        const ticket = {
          ticketNumber,
          subject,
          message,
          status: 'Open',
          priority: 'Low',
          assignedTo: hrUser.email,
          assignedToName: hrUser.name,
          createdBy: 'System - Birthday Bot',
          createdAt: new Date(),
          updatedAt: new Date()
        };
        
        await db.collection('tickets').insertOne(ticket);
        
        console.log(`✅ Birthday ticket created: ${ticketNumber} → ${hrUser.email}`);
      }
    }
    
    console.log('🎂 BIRTHDAY CHECK - Complete\n');
    
  } catch (error) {
    console.error('❌ Birthday check failed:', error);
  }
}

// Schedule cron job - Daily at 9:00 AM
let birthdayCronJob = null;

function initializeBirthdayCron(db) {
  if (birthdayCronJob) {
    console.log('⚠️ Birthday cron already initialized');
    return;
  }
  
  birthdayCronJob = cron.schedule('0 9 * * *', () => {
    checkBirthdays(db);
  }, {
    timezone: 'Asia/Kolkata'
  });
  
  console.log('✅ Birthday cron job scheduled (daily at 9:00 AM IST)');
  
  // Optional: Run immediately on startup (after 30 seconds)
  setTimeout(() => {
    console.log('🚀 Running initial birthday check...');
    checkBirthdays(db);
  }, 30000);
}

// Export initialization function
router.initializeBirthdayCron = initializeBirthdayCron;

// ============================================================================
// MANUAL BIRTHDAY CHECK TRIGGER (for testing)
// ============================================================================

router.post('/trigger-birthday-check', async (req, res) => {
  try {
    console.log('\n🧪 MANUAL BIRTHDAY CHECK TRIGGERED');
    await checkBirthdays(req.db);
    
    res.json({
      success: true,
      message: 'Birthday check completed. Check server logs for details.'
    });
  } catch (error) {
    console.error('❌ Manual birthday check failed:', error);
    res.status(500).json({
      success: false,
      error: 'Birthday check failed',
      message: error.message
    });
  }
});

module.exports = router;