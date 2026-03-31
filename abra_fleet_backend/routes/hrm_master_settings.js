// ============================================================================
// HRM MASTER SETTINGS - COMPLETE BACKEND
// ============================================================================
// Features: Departments, Positions, Locations, Timings, Companies, Leave Hierarchy
// Author: Abra Fleet Management System
// Database: abra_fleet
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

// ============================================================================
// MONGOOSE SCHEMAS (Inline)
// ============================================================================

// Department Schema
const departmentSchema = new mongoose.Schema({
  name: {
    type: String,
    required: true,
    unique: true,
    trim: true
  },
  createdAt: {
    type: Date,
    default: Date.now
  },
  updatedAt: {
    type: Date,
    default: Date.now
  }
});

// Position Schema
const positionSchema = new mongoose.Schema({
  title: {
    type: String,
    required: true,
    trim: true
  },
  departmentId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Department',
    required: true
  },
  createdAt: {
    type: Date,
    default: Date.now
  },
  updatedAt: {
    type: Date,
    default: Date.now
  }
});

// Work Location Schema
const workLocationSchema = new mongoose.Schema({
  locationName: {
    type: String,
    required: true,
    trim: true
  },
  latitude: {
    type: String,
    default: ''
  },
  longitude: {
    type: String,
    default: ''
  },
  createdAt: {
    type: Date,
    default: Date.now
  },
  updatedAt: {
    type: Date,
    default: Date.now
  }
});

// Office Timing Schema
const officeTimingSchema = new mongoose.Schema({
  startTime: {
    type: String,
    required: true
  },
  endTime: {
    type: String,
    required: true
  },
  createdAt: {
    type: Date,
    default: Date.now
  },
  updatedAt: {
    type: Date,
    default: Date.now
  }
});

// Company Schema
const companySchema = new mongoose.Schema({
  companyName: {
    type: String,
    required: true,
    unique: true,
    trim: true
  },
  logoPath: {
    type: String,
    default: ''
  },
  createdAt: {
    type: Date,
    default: Date.now
  },
  updatedAt: {
    type: Date,
    default: Date.now
  }
});

// Leave Hierarchy Schema
const leaveHierarchySchema = new mongoose.Schema({
  positionId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Position',
    required: true,
    unique: true
  },
  approver1Id: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Position',
    default: null
  },
  approver2Id: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Position',
    default: null
  },
  createdAt: {
    type: Date,
    default: Date.now
  },
  updatedAt: {
    type: Date,
    default: Date.now
  }
});

// Create Models
const Department = mongoose.model('Department', departmentSchema, 'hr_departments');
const Position = mongoose.model('Position', positionSchema, 'hr_positions');
const WorkLocation = mongoose.model('WorkLocation', workLocationSchema, 'hr_work_locations');
const OfficeTiming = mongoose.model('OfficeTiming', officeTimingSchema, 'hr_office_timings');
const Company = mongoose.model('Company', companySchema, 'hr_companies');
const LeaveHierarchy = mongoose.model('LeaveHierarchy', leaveHierarchySchema, 'hr_leave_hierarchy');

// ============================================================================
// MULTER CONFIGURATION FOR LOGO UPLOAD
// ============================================================================

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const uploadDir = 'uploads/company_logos';
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    const uniqueName = `company_${Date.now()}${path.extname(file.originalname)}`;
    cb(null, uniqueName);
  }
});

const upload = multer({
  storage: storage,
  limits: { fileSize: 2 * 1024 * 1024 }, // 2MB
  fileFilter: (req, file, cb) => {
    const allowedTypes = /jpeg|jpg|png|gif|webp/;
    const extname = allowedTypes.test(path.extname(file.originalname).toLowerCase());
    const mimetype = allowedTypes.test(file.mimetype);
    
    if (extname && mimetype) {
      cb(null, true);
    } else {
      cb(new Error('Only image files (jpg, png, gif, webp) are allowed!'));
    }
  }
});

// ============================================================================
// PERMISSION MIDDLEWARE
// ============================================================================

const checkDeletePermission = (req, res, next) => {
  const user = req.user;
  
  // Allow super_admin or users with 'system' module
  if (user.role === 'super_admin' || (user.modules && user.modules.includes('system'))) {
    return next();
  }
  
  return res.status(403).json({
    success: false,
    error: 'Insufficient permissions',
    message: 'Only super admins can delete records'
  });
};

// ============================================================================
// DEPARTMENT ROUTES
// ============================================================================

// GET all departments with position count
router.get('/departments', async (req, res) => {
  try {
    console.log('📋 Fetching all departments...');
    
    const departments = await Department.find().sort({ name: 1 }).lean();
    
    // Get position count for each department
    const departmentsWithCount = await Promise.all(
      departments.map(async (dept) => {
        const positionCount = await Position.countDocuments({ departmentId: dept._id });
        return {
          ...dept,
          positionCount
        };
      })
    );
    
    console.log(`✅ Found ${departmentsWithCount.length} departments`);
    
    res.json({
      success: true,
      data: departmentsWithCount,
      count: departmentsWithCount.length
    });
  } catch (error) {
    console.error('❌ Error fetching departments:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch departments',
      message: error.message
    });
  }
});

// GET single department by ID
router.get('/departments/:id', async (req, res) => {
  try {
    const department = await Department.findById(req.params.id);
    
    if (!department) {
      return res.status(404).json({
        success: false,
        error: 'Department not found'
      });
    }
    
    res.json({
      success: true,
      data: department
    });
  } catch (error) {
    console.error('❌ Error fetching department:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch department',
      message: error.message
    });
  }
});

// POST create new department
router.post('/departments', async (req, res) => {
  try {
    console.log('➕ Creating new department:', req.body);
    
    const { name } = req.body;
    
    if (!name || name.trim() === '') {
      return res.status(400).json({
        success: false,
        error: 'Department name is required'
      });
    }
    
    // Check for duplicate
    const existing = await Department.findOne({ name: name.trim() });
    if (existing) {
      return res.status(400).json({
        success: false,
        error: 'Department name already exists'
      });
    }
    
    const department = new Department({
      name: name.trim()
    });
    
    await department.save();
    
    console.log('✅ Department created:', department._id);
    
    res.status(201).json({
      success: true,
      message: 'Department created successfully',
      data: department
    });
  } catch (error) {
    console.error('❌ Error creating department:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to create department',
      message: error.message
    });
  }
});

// PUT update department
router.put('/departments/:id', async (req, res) => {
  try {
    console.log('✏️ Updating department:', req.params.id);
    
    const { name } = req.body;
    
    if (!name || name.trim() === '') {
      return res.status(400).json({
        success: false,
        error: 'Department name is required'
      });
    }
    
    // Check for duplicate (excluding current)
    const existing = await Department.findOne({
      name: name.trim(),
      _id: { $ne: req.params.id }
    });
    
    if (existing) {
      return res.status(400).json({
        success: false,
        error: 'Department name already exists'
      });
    }
    
    const department = await Department.findByIdAndUpdate(
      req.params.id,
      { name: name.trim(), updatedAt: Date.now() },
      { new: true }
    );
    
    if (!department) {
      return res.status(404).json({
        success: false,
        error: 'Department not found'
      });
    }
    
    console.log('✅ Department updated:', department._id);
    
    res.json({
      success: true,
      message: 'Department updated successfully',
      data: department
    });
  } catch (error) {
    console.error('❌ Error updating department:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to update department',
      message: error.message
    });
  }
});

// DELETE department (with permission check)
router.delete('/departments/:id', checkDeletePermission, async (req, res) => {
  try {
    console.log('🗑️ Deleting department:', req.params.id);
    
    // Check if department has positions
    const positionCount = await Position.countDocuments({ departmentId: req.params.id });
    
    if (positionCount > 0) {
      return res.status(400).json({
        success: false,
        error: 'Cannot delete department',
        message: `This department has ${positionCount} position(s). Please delete positions first.`
      });
    }
    
    const department = await Department.findByIdAndDelete(req.params.id);
    
    if (!department) {
      return res.status(404).json({
        success: false,
        error: 'Department not found'
      });
    }
    
    console.log('✅ Department deleted:', department._id);
    
    res.json({
      success: true,
      message: 'Department deleted successfully'
    });
  } catch (error) {
    console.error('❌ Error deleting department:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete department',
      message: error.message
    });
  }
});

// ============================================================================
// POSITION ROUTES
// ============================================================================

// GET all positions
router.get('/positions', async (req, res) => {
  try {
    console.log('📋 Fetching all positions...');
    
    const positions = await Position.find()
      .populate('departmentId', 'name')
      .sort({ title: 1 })
      .lean();
    
    console.log(`✅ Found ${positions.length} positions`);
    
    res.json({
      success: true,
      data: positions,
      count: positions.length
    });
  } catch (error) {
    console.error('❌ Error fetching positions:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch positions',
      message: error.message
    });
  }
});

// GET positions by department
router.get('/departments/:deptId/positions', async (req, res) => {
  try {
    console.log('📋 Fetching positions for department:', req.params.deptId);
    
    const positions = await Position.find({ departmentId: req.params.deptId })
      .sort({ title: 1 })
      .lean();
    
    console.log(`✅ Found ${positions.length} positions`);
    
    res.json({
      success: true,
      data: positions,
      count: positions.length
    });
  } catch (error) {
    console.error('❌ Error fetching positions:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch positions',
      message: error.message
    });
  }
});

// POST create new position
router.post('/positions', async (req, res) => {
  try {
    console.log('➕ Creating new position:', req.body);
    
    const { title, departmentId } = req.body;
    
    if (!title || title.trim() === '') {
      return res.status(400).json({
        success: false,
        error: 'Position title is required'
      });
    }
    
    if (!departmentId) {
      return res.status(400).json({
        success: false,
        error: 'Department is required'
      });
    }
    
    // Verify department exists
    const department = await Department.findById(departmentId);
    if (!department) {
      return res.status(404).json({
        success: false,
        error: 'Department not found'
      });
    }
    
    const position = new Position({
      title: title.trim(),
      departmentId
    });
    
    await position.save();
    
    // Populate department before sending response
    await position.populate('departmentId', 'name');
    
    console.log('✅ Position created:', position._id);
    
    res.status(201).json({
      success: true,
      message: 'Position created successfully',
      data: position
    });
  } catch (error) {
    console.error('❌ Error creating position:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to create position',
      message: error.message
    });
  }
});

// PUT update position
router.put('/positions/:id', async (req, res) => {
  try {
    console.log('✏️ Updating position:', req.params.id);
    
    const { title, departmentId } = req.body;
    
    if (!title || title.trim() === '') {
      return res.status(400).json({
        success: false,
        error: 'Position title is required'
      });
    }
    
    if (!departmentId) {
      return res.status(400).json({
        success: false,
        error: 'Department is required'
      });
    }
    
    // Verify department exists
    const department = await Department.findById(departmentId);
    if (!department) {
      return res.status(404).json({
        success: false,
        error: 'Department not found'
      });
    }
    
    const position = await Position.findByIdAndUpdate(
      req.params.id,
      { 
        title: title.trim(), 
        departmentId,
        updatedAt: Date.now() 
      },
      { new: true }
    ).populate('departmentId', 'name');
    
    if (!position) {
      return res.status(404).json({
        success: false,
        error: 'Position not found'
      });
    }
    
    console.log('✅ Position updated:', position._id);
    
    res.json({
      success: true,
      message: 'Position updated successfully',
      data: position
    });
  } catch (error) {
    console.error('❌ Error updating position:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to update position',
      message: error.message
    });
  }
});

// DELETE position (with permission check)
router.delete('/positions/:id', checkDeletePermission, async (req, res) => {
  try {
    console.log('🗑️ Deleting position:', req.params.id);
    
    // Delete associated hierarchy
    await LeaveHierarchy.deleteOne({ positionId: req.params.id });
    
    // Also remove this position from being an approver in other hierarchies
    await LeaveHierarchy.updateMany(
      { $or: [{ approver1Id: req.params.id }, { approver2Id: req.params.id }] },
      { $set: { approver1Id: null, approver2Id: null } }
    );
    
    const position = await Position.findByIdAndDelete(req.params.id);
    
    if (!position) {
      return res.status(404).json({
        success: false,
        error: 'Position not found'
      });
    }
    
    console.log('✅ Position deleted:', position._id);
    
    res.json({
      success: true,
      message: 'Position deleted successfully'
    });
  } catch (error) {
    console.error('❌ Error deleting position:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete position',
      message: error.message
    });
  }
});

// ============================================================================
// WORK LOCATION ROUTES
// ============================================================================

// GET all locations
router.get('/locations', async (req, res) => {
  try {
    console.log('📍 Fetching all locations...');
    
    const locations = await WorkLocation.find().sort({ locationName: 1 }).lean();
    
    console.log(`✅ Found ${locations.length} locations`);
    
    res.json({
      success: true,
      data: locations,
      count: locations.length
    });
  } catch (error) {
    console.error('❌ Error fetching locations:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch locations',
      message: error.message
    });
  }
});

// POST create new location
router.post('/locations', async (req, res) => {
  try {
    console.log('➕ Creating new location:', req.body);
    
    const { locationName, latitude, longitude } = req.body;
    
    if (!locationName || locationName.trim() === '') {
      return res.status(400).json({
        success: false,
        error: 'Location name is required'
      });
    }
    
    const location = new WorkLocation({
      locationName: locationName.trim(),
      latitude: latitude || '',
      longitude: longitude || ''
    });
    
    await location.save();
    
    console.log('✅ Location created:', location._id);
    
    res.status(201).json({
      success: true,
      message: 'Location created successfully',
      data: location
    });
  } catch (error) {
    console.error('❌ Error creating location:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to create location',
      message: error.message
    });
  }
});

// PUT update location
router.put('/locations/:id', async (req, res) => {
  try {
    console.log('✏️ Updating location:', req.params.id);
    
    const { locationName, latitude, longitude } = req.body;
    
    if (!locationName || locationName.trim() === '') {
      return res.status(400).json({
        success: false,
        error: 'Location name is required'
      });
    }
    
    const location = await WorkLocation.findByIdAndUpdate(
      req.params.id,
      { 
        locationName: locationName.trim(),
        latitude: latitude || '',
        longitude: longitude || '',
        updatedAt: Date.now() 
      },
      { new: true }
    );
    
    if (!location) {
      return res.status(404).json({
        success: false,
        error: 'Location not found'
      });
    }
    
    console.log('✅ Location updated:', location._id);
    
    res.json({
      success: true,
      message: 'Location updated successfully',
      data: location
    });
  } catch (error) {
    console.error('❌ Error updating location:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to update location',
      message: error.message
    });
  }
});

// DELETE location (with permission check)
router.delete('/locations/:id', checkDeletePermission, async (req, res) => {
  try {
    console.log('🗑️ Deleting location:', req.params.id);
    
    const location = await WorkLocation.findByIdAndDelete(req.params.id);
    
    if (!location) {
      return res.status(404).json({
        success: false,
        error: 'Location not found'
      });
    }
    
    console.log('✅ Location deleted:', location._id);
    
    res.json({
      success: true,
      message: 'Location deleted successfully'
    });
  } catch (error) {
    console.error('❌ Error deleting location:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete location',
      message: error.message
    });
  }
});

// ============================================================================
// OFFICE TIMING ROUTES
// ============================================================================

// GET all timings
router.get('/timings', async (req, res) => {
  try {
    console.log('⏰ Fetching all timings...');
    
    const timings = await OfficeTiming.find().sort({ startTime: 1 }).lean();
    
    console.log(`✅ Found ${timings.length} timings`);
    
    res.json({
      success: true,
      data: timings,
      count: timings.length
    });
  } catch (error) {
    console.error('❌ Error fetching timings:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch timings',
      message: error.message
    });
  }
});

// POST create new timing
router.post('/timings', async (req, res) => {
  try {
    console.log('➕ Creating new timing:', req.body);
    
    const { startTime, endTime } = req.body;
    
    if (!startTime || startTime.trim() === '') {
      return res.status(400).json({
        success: false,
        error: 'Start time is required'
      });
    }
    
    if (!endTime || endTime.trim() === '') {
      return res.status(400).json({
        success: false,
        error: 'End time is required'
      });
    }
    
    const timing = new OfficeTiming({
      startTime: startTime.trim(),
      endTime: endTime.trim()
    });
    
    await timing.save();
    
    console.log('✅ Timing created:', timing._id);
    
    res.status(201).json({
      success: true,
      message: 'Timing created successfully',
      data: timing
    });
  } catch (error) {
    console.error('❌ Error creating timing:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to create timing',
      message: error.message
    });
  }
});

// PUT update timing
router.put('/timings/:id', async (req, res) => {
  try {
    console.log('✏️ Updating timing:', req.params.id);
    
    const { startTime, endTime } = req.body;
    
    if (!startTime || startTime.trim() === '') {
      return res.status(400).json({
        success: false,
        error: 'Start time is required'
      });
    }
    
    if (!endTime || endTime.trim() === '') {
      return res.status(400).json({
        success: false,
        error: 'End time is required'
      });
    }
    
    const timing = await OfficeTiming.findByIdAndUpdate(
      req.params.id,
      { 
        startTime: startTime.trim(),
        endTime: endTime.trim(),
        updatedAt: Date.now() 
      },
      { new: true }
    );
    
    if (!timing) {
      return res.status(404).json({
        success: false,
        error: 'Timing not found'
      });
    }
    
    console.log('✅ Timing updated:', timing._id);
    
    res.json({
      success: true,
      message: 'Timing updated successfully',
      data: timing
    });
  } catch (error) {
    console.error('❌ Error updating timing:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to update timing',
      message: error.message
    });
  }
});

// DELETE timing (with permission check)
router.delete('/timings/:id', checkDeletePermission, async (req, res) => {
  try {
    console.log('🗑️ Deleting timing:', req.params.id);
    
    const timing = await OfficeTiming.findByIdAndDelete(req.params.id);
    
    if (!timing) {
      return res.status(404).json({
        success: false,
        error: 'Timing not found'
      });
    }
    
    console.log('✅ Timing deleted:', timing._id);
    
    res.json({
      success: true,
      message: 'Timing deleted successfully'
    });
  } catch (error) {
    console.error('❌ Error deleting timing:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete timing',
      message: error.message
    });
  }
});

// ============================================================================
// COMPANY ROUTES (WITH LOGO UPLOAD)
// ============================================================================

// GET all companies
router.get('/companies', async (req, res) => {
  try {
    console.log('🏢 Fetching all companies...');
    
    const companies = await Company.find().sort({ companyName: 1 }).lean();
    
    // Add full logo URL
    const companiesWithUrl = companies.map(company => ({
      ...company,
      logoUrl: company.logoPath ? `${req.protocol}://${req.get('host')}/${company.logoPath}` : null
    }));
    
    console.log(`✅ Found ${companiesWithUrl.length} companies`);
    
    res.json({
      success: true,
      data: companiesWithUrl,
      count: companiesWithUrl.length
    });
  } catch (error) {
    console.error('❌ Error fetching companies:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch companies',
      message: error.message
    });
  }
});

// POST create new company (with logo upload)
router.post('/companies', upload.single('logo'), async (req, res) => {
  try {
    console.log('➕ Creating new company:', req.body);
    
    const { companyName } = req.body;
    
    if (!companyName || companyName.trim() === '') {
      // Delete uploaded file if validation fails
      if (req.file) {
        fs.unlinkSync(req.file.path);
      }
      return res.status(400).json({
        success: false,
        error: 'Company name is required'
      });
    }
    
    // Check for duplicate
    const existing = await Company.findOne({ companyName: companyName.trim() });
    if (existing) {
      // Delete uploaded file if duplicate
      if (req.file) {
        fs.unlinkSync(req.file.path);
      }
      return res.status(400).json({
        success: false,
        error: 'Company name already exists'
      });
    }
    
    const company = new Company({
      companyName: companyName.trim(),
      logoPath: req.file ? req.file.path : ''
    });
    
    await company.save();
    
    console.log('✅ Company created:', company._id);
    
    res.status(201).json({
      success: true,
      message: 'Company created successfully',
      data: {
        ...company.toObject(),
        logoUrl: company.logoPath ? `${req.protocol}://${req.get('host')}/${company.logoPath}` : null
      }
    });
  } catch (error) {
    // Delete uploaded file on error
    if (req.file) {
      fs.unlinkSync(req.file.path);
    }
    console.error('❌ Error creating company:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to create company',
      message: error.message
    });
  }
});

// PUT update company (with logo upload)
router.put('/companies/:id', upload.single('logo'), async (req, res) => {
  try {
    console.log('✏️ Updating company:', req.params.id);
    
    const { companyName } = req.body;
    
    if (!companyName || companyName.trim() === '') {
      // Delete uploaded file if validation fails
      if (req.file) {
        fs.unlinkSync(req.file.path);
      }
      return res.status(400).json({
        success: false,
        error: 'Company name is required'
      });
    }
    
    // Check for duplicate (excluding current)
    const existing = await Company.findOne({
      companyName: companyName.trim(),
      _id: { $ne: req.params.id }
    });
    
    if (existing) {
      // Delete uploaded file if duplicate
      if (req.file) {
        fs.unlinkSync(req.file.path);
      }
      return res.status(400).json({
        success: false,
        error: 'Company name already exists'
      });
    }
    
    // Get existing company
    const existingCompany = await Company.findById(req.params.id);
    
    if (!existingCompany) {
      // Delete uploaded file if company not found
      if (req.file) {
        fs.unlinkSync(req.file.path);
      }
      return res.status(404).json({
        success: false,
        error: 'Company not found'
      });
    }
    
    // If new logo uploaded, delete old logo
    if (req.file && existingCompany.logoPath) {
      if (fs.existsSync(existingCompany.logoPath)) {
        fs.unlinkSync(existingCompany.logoPath);
      }
    }
    
    const updateData = {
      companyName: companyName.trim(),
      updatedAt: Date.now()
    };
    
    // Update logo path only if new file uploaded
    if (req.file) {
      updateData.logoPath = req.file.path;
    }
    
    const company = await Company.findByIdAndUpdate(
      req.params.id,
      updateData,
      { new: true }
    );
    
    console.log('✅ Company updated:', company._id);
    
    res.json({
      success: true,
      message: 'Company updated successfully',
      data: {
        ...company.toObject(),
        logoUrl: company.logoPath ? `${req.protocol}://${req.get('host')}/${company.logoPath}` : null
      }
    });
  } catch (error) {
    // Delete uploaded file on error
    if (req.file) {
      fs.unlinkSync(req.file.path);
    }
    console.error('❌ Error updating company:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to update company',
      message: error.message
    });
  }
});

// DELETE company (with permission check)
router.delete('/companies/:id', checkDeletePermission, async (req, res) => {
  try {
    console.log('🗑️ Deleting company:', req.params.id);
    
    const company = await Company.findById(req.params.id);
    
    if (!company) {
      return res.status(404).json({
        success: false,
        error: 'Company not found'
      });
    }
    
    // Delete logo file if exists
    if (company.logoPath && fs.existsSync(company.logoPath)) {
      fs.unlinkSync(company.logoPath);
    }
    
    await Company.findByIdAndDelete(req.params.id);
    
    console.log('✅ Company deleted:', company._id);
    
    res.json({
      success: true,
      message: 'Company deleted successfully'
    });
  } catch (error) {
    console.error('❌ Error deleting company:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete company',
      message: error.message
    });
  }
});

// ============================================================================
// LEAVE HIERARCHY ROUTES
// ============================================================================

// GET all leave hierarchies
router.get('/leave-hierarchy', async (req, res) => {
  try {
    console.log('👥 Fetching all leave hierarchies...');
    
    // Get all positions with their departments
    const positions = await Position.find()
      .populate('departmentId', 'name')
      .sort({ title: 1 })
      .lean();
    
    // Get all hierarchies
    const hierarchies = await LeaveHierarchy.find()
      .populate('positionId', 'title departmentId')
      .populate('approver1Id', 'title')
      .populate('approver2Id', 'title')
      .lean();
    
    // Merge data
    const hierarchyData = positions.map(position => {
      const hierarchy = hierarchies.find(h => h.positionId && h.positionId._id.toString() === position._id.toString());
      
      return {
        _id: position._id,
        title: position.title,
        departmentName: position.departmentId ? position.departmentId.name : 'N/A',
        approver1: hierarchy?.approver1Id || null,
        approver2: hierarchy?.approver2Id || null
      };
    });
    
    console.log(`✅ Found ${hierarchyData.length} positions with hierarchy data`);
    
    res.json({
      success: true,
      data: hierarchyData,
      count: hierarchyData.length
    });
  } catch (error) {
    console.error('❌ Error fetching hierarchies:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch hierarchies',
      message: error.message
    });
  }
});

// POST/PUT create or update leave hierarchy
router.post('/leave-hierarchy', async (req, res) => {
  try {
    console.log('💾 Saving leave hierarchy:', req.body);
    
    const { positionId, approver1Id, approver2Id } = req.body;
    
    if (!positionId) {
      return res.status(400).json({
        success: false,
        error: 'Position ID is required'
      });
    }
    
    // Verify position exists
    const position = await Position.findById(positionId);
    if (!position) {
      return res.status(404).json({
        success: false,
        error: 'Position not found'
      });
    }
    
    // Prevent self-approval
    if (approver1Id && approver1Id === positionId) {
      return res.status(400).json({
        success: false,
        error: 'A position cannot approve its own leave requests (Approver 1)'
      });
    }
    
    if (approver2Id && approver2Id === positionId) {
      return res.status(400).json({
        success: false,
        error: 'A position cannot approve its own leave requests (Approver 2)'
      });
    }
    
    // Verify approvers exist if provided
    if (approver1Id) {
      const approver1 = await Position.findById(approver1Id);
      if (!approver1) {
        return res.status(404).json({
          success: false,
          error: 'Approver 1 position not found'
        });
      }
    }
    
    if (approver2Id) {
      const approver2 = await Position.findById(approver2Id);
      if (!approver2) {
        return res.status(404).json({
          success: false,
          error: 'Approver 2 position not found'
        });
      }
    }
    
    // Update or create hierarchy
    const hierarchy = await LeaveHierarchy.findOneAndUpdate(
      { positionId },
      {
        positionId,
        approver1Id: approver1Id || null,
        approver2Id: approver2Id || null,
        updatedAt: Date.now()
      },
      { upsert: true, new: true }
    ).populate('approver1Id approver2Id', 'title');
    
    console.log('✅ Hierarchy saved:', hierarchy._id);
    
    res.json({
      success: true,
      message: 'Leave hierarchy saved successfully',
      data: hierarchy
    });
  } catch (error) {
    console.error('❌ Error saving hierarchy:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to save hierarchy',
      message: error.message
    });
  }
});

// DELETE clear leave hierarchy (with permission check)
router.delete('/leave-hierarchy/:positionId', checkDeletePermission, async (req, res) => {
  try {
    console.log('🗑️ Clearing hierarchy for position:', req.params.positionId);
    
    const result = await LeaveHierarchy.deleteOne({ positionId: req.params.positionId });
    
    if (result.deletedCount === 0) {
      return res.status(404).json({
        success: false,
        error: 'Hierarchy not found'
      });
    }
    
    console.log('✅ Hierarchy cleared');
    
    res.json({
      success: true,
      message: 'Hierarchy cleared successfully'
    });
  } catch (error) {
    console.error('❌ Error clearing hierarchy:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to clear hierarchy',
      message: error.message
    });
  }
});

// ============================================================================
// CSV EXPORT ROUTES
// ============================================================================

// Export departments
router.get('/export/departments', async (req, res) => {
  try {
    console.log('📥 Exporting departments to CSV...');
    
    const departments = await Department.find().sort({ name: 1 }).lean();
    
    // Create CSV
    let csv = 'Department ID,Department Name\n';
    departments.forEach(dept => {
      csv += `${dept._id},"${dept.name}"\n`;
    });
    
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', `attachment; filename=departments_export_${Date.now()}.csv`);
    res.send(csv);
    
    console.log('✅ Departments exported');
  } catch (error) {
    console.error('❌ Error exporting departments:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to export departments',
      message: error.message
    });
  }
});

// Export positions
router.get('/export/positions', async (req, res) => {
  try {
    console.log('📥 Exporting positions to CSV...');
    
    const positions = await Position.find()
      .populate('departmentId', 'name')
      .sort({ title: 1 })
      .lean();
    
    // Create CSV
    let csv = 'Position ID,Position Title,Department ID,Department Name\n';
    positions.forEach(pos => {
      csv += `${pos._id},"${pos.title}",${pos.departmentId?._id || ''},"${pos.departmentId?.name || 'N/A'}"\n`;
    });
    
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', `attachment; filename=positions_export_${Date.now()}.csv`);
    res.send(csv);
    
    console.log('✅ Positions exported');
  } catch (error) {
    console.error('❌ Error exporting positions:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to export positions',
      message: error.message
    });
  }
});

// Export locations
router.get('/export/locations', async (req, res) => {
  try {
    console.log('📥 Exporting locations to CSV...');
    
    const locations = await WorkLocation.find().sort({ locationName: 1 }).lean();
    
    // Create CSV
    let csv = 'Location ID,Location Name,Latitude,Longitude\n';
    locations.forEach(loc => {
      csv += `${loc._id},"${loc.locationName}","${loc.latitude}","${loc.longitude}"\n`;
    });
    
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', `attachment; filename=locations_export_${Date.now()}.csv`);
    res.send(csv);
    
    console.log('✅ Locations exported');
  } catch (error) {
    console.error('❌ Error exporting locations:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to export locations',
      message: error.message
    });
  }
});

// Export timings
router.get('/export/timings', async (req, res) => {
  try {
    console.log('📥 Exporting timings to CSV...');
    
    const timings = await OfficeTiming.find().sort({ startTime: 1 }).lean();
    
    // Create CSV
    let csv = 'Timing ID,Start Time,End Time\n';
    timings.forEach(timing => {
      csv += `${timing._id},"${timing.startTime}","${timing.endTime}"\n`;
    });
    
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', `attachment; filename=timings_export_${Date.now()}.csv`);
    res.send(csv);
    
    console.log('✅ Timings exported');
  } catch (error) {
    console.error('❌ Error exporting timings:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to export timings',
      message: error.message
    });
  }
});

// Export companies
router.get('/export/companies', async (req, res) => {
  try {
    console.log('📥 Exporting companies to CSV...');
    
    const companies = await Company.find().sort({ companyName: 1 }).lean();
    
    // Create CSV
    let csv = 'Company ID,Company Name,Logo Path\n';
    companies.forEach(company => {
      csv += `${company._id},"${company.companyName}","${company.logoPath}"\n`;
    });
    
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', `attachment; filename=companies_export_${Date.now()}.csv`);
    res.send(csv);
    
    console.log('✅ Companies exported');
  } catch (error) {
    console.error('❌ Error exporting companies:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to export companies',
      message: error.message
    });
  }
});

// Export leave hierarchy
router.get('/export/leave-hierarchy', async (req, res) => {
  try {
    console.log('📥 Exporting leave hierarchy to CSV...');
    
    const positions = await Position.find()
      .populate('departmentId', 'name')
      .lean();
    
    const hierarchies = await LeaveHierarchy.find()
      .populate('positionId approver1Id approver2Id', 'title')
      .lean();
    
    // Create CSV
    let csv = 'Position ID,Position Title,Department,Approver 1,Approver 2\n';
    
    positions.forEach(pos => {
      const hierarchy = hierarchies.find(h => h.positionId && h.positionId._id.toString() === pos._id.toString());
      csv += `${pos._id},"${pos.title}","${pos.departmentId?.name || 'N/A'}","${hierarchy?.approver1Id?.title || ''}","${hierarchy?.approver2Id?.title || ''}"\n`;
    });
    
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', `attachment; filename=hierarchy_export_${Date.now()}.csv`);
    res.send(csv);
    
    console.log('✅ Hierarchy exported');
  } catch (error) {
    console.error('❌ Error exporting hierarchy:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to export hierarchy',
      message: error.message
    });
  }
});

// ============================================================================
// CSV IMPORT ROUTES (Simplified - No file parser, just JSON)
// ============================================================================

// Import departments
router.post('/import/departments', async (req, res) => {
  try {
    console.log('📤 Importing departments...');
    
    const { departments } = req.body;
    
    if (!departments || !Array.isArray(departments)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid data format. Expected array of departments.'
      });
    }
    
    let imported = 0;
    let failed = 0;
    const errors = [];
    
    for (const dept of departments) {
      try {
        if (!dept.name || dept.name.trim() === '') {
          failed++;
          errors.push(`Empty department name`);
          continue;
        }
        
        // Check for duplicate
        const existing = await Department.findOne({ name: dept.name.trim() });
        if (existing) {
          failed++;
          errors.push(`Duplicate: ${dept.name}`);
          continue;
        }
        
        await Department.create({ name: dept.name.trim() });
        imported++;
      } catch (error) {
        failed++;
        errors.push(`${dept.name}: ${error.message}`);
      }
    }
    
    console.log(`✅ Import complete: ${imported} imported, ${failed} failed`);
    
    res.json({
      success: true,
      message: `Import complete: ${imported} imported, ${failed} failed`,
      imported,
      failed,
      errors: errors.length > 0 ? errors : undefined
    });
  } catch (error) {
    console.error('❌ Error importing departments:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to import departments',
      message: error.message
    });
  }
});

// ============================================================================
// HEALTH CHECK
// ============================================================================

router.get('/health', (req, res) => {
  res.json({
    success: true,
    message: 'HRM Master Settings API is healthy',
    timestamp: new Date().toISOString()
  });
});

module.exports = router;