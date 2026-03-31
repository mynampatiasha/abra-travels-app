// routes/employeeManagement.js
// ============================================================================
// EMPLOYEE MANAGEMENT ROUTES - For Admin Panel Users ONLY - JWT ONLY
// ============================================================================
const express = require('express');
const router = express.Router();
const EmployeeAdmin = require('../models/EmployeeAdmin');
const { verifyJWT, requireRole } = require('./jwt_router');

/**
 * Generate a Firebase-compatible UID (28 characters)
 * Format: alphanumeric string similar to Firebase UIDs
 */
function generateFirebaseUid() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let uid = '';
  for (let i = 0; i < 28; i++) {
    uid += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return uid;
}

// ============================================
// CREATE EMPLOYEE WITH PERMISSIONS
// ============================================
router.post('/employees', verifyJWT, requireRole(['super_admin', 'admin']), async (req, res) => {
  console.log('\n📝 CREATE EMPLOYEE WITH PERMISSIONS');
  console.log('─'.repeat(80));
  
  try {
    const {
      name_parson,
      name,
      email,
      phone,
      pwd,
      role,
      permissions
    } = req.body;

    console.log('   Creating employee:', email);
    console.log('   Role:', role);

    // Validation
    if (!name_parson || !name || !email || !pwd) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields',
        message: 'name_parson, name, email, and pwd are required'
      });
    }

    // Check if employee already exists
    const existingEmployee = await EmployeeAdmin.findOne({ email: email.toLowerCase() });
    if (existingEmployee) {
      return res.status(400).json({
        success: false,
        error: 'Employee already exists',
        message: 'An employee with this email already exists'
      });
    }

    // Generate Firebase UID (no longer using Firebase Auth)
    console.log('   Step 1: Generating Firebase UID...');
    const firebaseUid = generateFirebaseUid();
    console.log('   ✅ Firebase UID generated:', firebaseUid);

    // Step 2: Save employee to MongoDB
    console.log('   Step 2: Saving to MongoDB...');
    const newEmployee = new EmployeeAdmin({
      name_parson,
      name,
      email: email.toLowerCase(),
      phone: phone || '',
      pwd, // Will be hashed by pre-save hook
      role: role || 'employee',
      permissions: permissions || new Map(),
      firebaseUid: firebaseUid,
      isActive: true,
      createdBy: req.user.mongoId
    });

    await newEmployee.save();
    console.log('   ✅ Employee saved to MongoDB');

    // Remove password from response
    const employeeResponse = newEmployee.toObject();
    delete employeeResponse.pwd;

    console.log('✅ EMPLOYEE CREATED SUCCESSFULLY');
    console.log('─'.repeat(80) + '\n');

    res.status(201).json({
      success: true,
      message: 'Employee created successfully',
      data: {
        user: employeeResponse, // Keep 'user' key for Flutter compatibility
        firebaseUid: firebaseUid
      }
    });

  } catch (error) {
    console.error('❌ CREATE EMPLOYEE FAILED');
    console.error('   Error:', error.message);
    console.error('─'.repeat(80) + '\n');

    res.status(500).json({
      success: false,
      error: 'Failed to create employee',
      message: error.message,
      details: process.env.NODE_ENV === 'development' ? error.stack : undefined
    });
  }
});

// ============================================
// GET ALL EMPLOYEES (WITH PAGINATION)
// ============================================
router.get('/employees', verifyJWT, requireRole(['super_admin', 'admin']), async (req, res) => {
  console.log('\n📋 GET ALL EMPLOYEES');
  console.log('─'.repeat(80));
  
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;
    const skip = (page - 1) * limit;
    const search = req.query.search || '';
    const roleFilter = req.query.role || '';

    console.log('   Page:', page);
    console.log('   Limit:', limit);
    console.log('   Search:', search);
    console.log('   Role filter:', roleFilter);

    // Build query - ONLY admin panel roles
    const adminRoles = ['super_admin', 'admin', 'employee', 'hr_manager', 'fleet_manager', 'finance', 'operations'];
    
    const query = {
      role: { $in: adminRoles }
    };
    
    if (search) {
      query.$and = [
        { role: { $in: adminRoles } },
        {
          $or: [
            { name_parson: { $regex: search, $options: 'i' } },
            { name: { $regex: search, $options: 'i' } },
            { email: { $regex: search, $options: 'i' } }
          ]
        }
      ];
    }
    
    if (roleFilter && adminRoles.includes(roleFilter)) {
      query.role = roleFilter;
    }

    // Get employees
    const employees = await EmployeeAdmin.find(query)
      .select('-pwd')
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .populate('createdBy', 'name_parson email');

    // Transform employees to include id field for frontend compatibility
    const transformedEmployees = employees.map(emp => {
      const empObj = emp.toObject();
      empObj.id = empObj._id.toString(); // Add id field for frontend
      return empObj;
    });

    const total = await EmployeeAdmin.countDocuments(query);

    console.log('   Found:', transformedEmployees.length, 'employees');
    console.log('   Total employees:', total);
    console.log('✅ EMPLOYEES RETRIEVED');
    console.log('─'.repeat(80) + '\n');

    res.json({
      success: true,
      data: transformedEmployees,
      pagination: {
        page,
        limit,
        total,
        pages: Math.ceil(total / limit)
      }
    });

  } catch (error) {
    console.error('❌ GET EMPLOYEES FAILED');
    console.error('   Error:', error.message);
    console.error('─'.repeat(80) + '\n');

    res.status(500).json({
      success: false,
      error: 'Failed to retrieve employees',
      message: error.message
    });
  }
});

// ============================================
// GET EMPLOYEE BY ID
// ============================================
router.get('/employees/:id', verifyJWT, requireRole(['super_admin', 'admin']), async (req, res) => {
  console.log('\n👤 GET EMPLOYEE BY ID');
  console.log('─'.repeat(80));
  
  try {
    const employeeId = req.params.id;
    console.log('   Employee ID:', employeeId);

    const employee = await EmployeeAdmin.findById(employeeId)
      .select('-pwd')
      .populate('createdBy', 'name_parson email');

    if (!employee) {
      console.log('   ❌ Employee not found');
      return res.status(404).json({
        success: false,
        error: 'Employee not found',
        message: 'No employee found with this ID'
      });
    }

    // Transform employee to include id field for frontend compatibility
    const empObj = employee.toObject();
    empObj.id = empObj._id.toString();

    console.log('   ✅ Employee found:', employee.email);
    console.log('─'.repeat(80) + '\n');

    res.json({
      success: true,
      data: { user: empObj } // Keep 'user' key for Flutter compatibility
    });

  } catch (error) {
    console.error('❌ GET EMPLOYEE FAILED');
    console.error('   Error:', error.message);
    console.error('─'.repeat(80) + '\n');

    res.status(500).json({
      success: false,
      error: 'Failed to retrieve employee',
      message: error.message
    });
  }
});

// ============================================
// UPDATE EMPLOYEE DETAILS
// ============================================
router.put('/employees/:id', verifyJWT, requireRole(['super_admin', 'admin']), async (req, res) => {
  console.log('\n✏️  UPDATE EMPLOYEE DETAILS');
  console.log('─'.repeat(80));
  
  try {
    const employeeId = req.params.id;
    const {
      name_parson,
      name,
      phone,
      role,
      isActive,
      pwd // Optional password update
    } = req.body;

    console.log('   Employee ID:', employeeId);
    console.log('   Updating fields:', Object.keys(req.body));

    const employee = await EmployeeAdmin.findById(employeeId);
    
    if (!employee) {
      return res.status(404).json({
        success: false,
        error: 'Employee not found',
        message: 'No employee found with this ID'
      });
    }

    // Update fields (only if provided)
    if (name_parson) employee.name_parson = name_parson;
    if (name) employee.name = name;
    if (phone !== undefined) employee.phone = phone;
    if (role) employee.role = role;
    if (isActive !== undefined) employee.isActive = isActive;
    if (pwd) employee.pwd = pwd; // Will be hashed by pre-save hook

    // Use validateBeforeSave: false to skip required field validation for partial updates
    await employee.save({ validateBeforeSave: false });

    // Note: Firebase custom claims no longer used (JWT-only system)
    console.log('   ✅ Employee updated (JWT-only, no Firebase claims)');

    const updatedEmployee = employee.toObject();
    delete updatedEmployee.pwd;

    console.log('✅ EMPLOYEE UPDATED');
    console.log('─'.repeat(80) + '\n');

    res.json({
      success: true,
      message: 'Employee updated successfully',
      data: { user: updatedEmployee }
    });

  } catch (error) {
    console.error('❌ UPDATE EMPLOYEE FAILED');
    console.error('   Error:', error.message);
    console.error('─'.repeat(80) + '\n');

    res.status(500).json({
      success: false,
      error: 'Failed to update employee',
      message: error.message
    });
  }
});

// ============================================
// UPDATE EMPLOYEE PERMISSIONS
// ============================================
router.put('/employees/:id/permissions', verifyJWT, requireRole(['super_admin', 'admin']), async (req, res) => {
  console.log('\n🔐 UPDATE EMPLOYEE PERMISSIONS');
  console.log('─'.repeat(80));
  
  try {
    const employeeId = req.params.id;
    const { permissions } = req.body;

    console.log('   Employee ID:', employeeId);
    console.log('   Permissions keys:', permissions ? Object.keys(permissions).length : 0);

    const employee = await EmployeeAdmin.findById(employeeId);
    
    if (!employee) {
      return res.status(404).json({
        success: false,
        error: 'Employee not found',
        message: 'No employee found with this ID'
      });
    }

    // Update permissions
    if (permissions) {
      employee.permissions = new Map(Object.entries(permissions));
    }

    // Use validateBeforeSave: false to skip required field validation
    await employee.save({ validateBeforeSave: false });

    const updatedEmployee = employee.toObject();
    delete updatedEmployee.pwd;

    console.log('✅ PERMISSIONS UPDATED');
    console.log('─'.repeat(80) + '\n');

    res.json({
      success: true,
      message: 'Permissions updated successfully',
      data: { user: updatedEmployee }
    });

  } catch (error) {
    console.error('❌ UPDATE PERMISSIONS FAILED');
    console.error('   Error:', error.message);
    console.error('─'.repeat(80) + '\n');

    res.status(500).json({
      success: false,
      error: 'Failed to update permissions',
      message: error.message
    });
  }
});

// ============================================
// DELETE EMPLOYEE (SOFT DELETE)
// ============================================
router.delete('/employees/:id', verifyJWT, requireRole(['super_admin']), async (req, res) => {
  console.log('\n🗑️  DELETE EMPLOYEE');
  console.log('─'.repeat(80));
  
  try {
    const employeeId = req.params.id;
    console.log('   Employee ID:', employeeId);

    const employee = await EmployeeAdmin.findById(employeeId);
    
    if (!employee) {
      return res.status(404).json({
        success: false,
        error: 'Employee not found',
        message: 'No employee found with this ID'
      });
    }

    // Soft delete - just deactivate
    employee.isActive = false;
    await employee.save();

    // Note: Firebase user management no longer used (JWT-only system)
    console.log('   ✅ Employee deactivated (JWT-only, no Firebase)');

    console.log('✅ EMPLOYEE DELETED (SOFT)');
    console.log('─'.repeat(80) + '\n');

    res.json({
      success: true,
      message: 'Employee deleted successfully'
    });

  } catch (error) {
    console.error('❌ DELETE EMPLOYEE FAILED');
    console.error('   Error:', error.message);
    console.error('─'.repeat(80) + '\n');

    res.status(500).json({
      success: false,
      error: 'Failed to delete employee',
      message: error.message
    });
  }
});

// ============================================
// TOGGLE EMPLOYEE STATUS
// ============================================
router.patch('/employees/:id/toggle-status', verifyJWT, requireRole(['super_admin', 'admin']), async (req, res) => {
  console.log('\n🔄 TOGGLE EMPLOYEE STATUS');
  console.log('─'.repeat(80));
  
  try {
    const employeeId = req.params.id;
    console.log('   Employee ID:', employeeId);

    const employee = await EmployeeAdmin.findById(employeeId);
    
    if (!employee) {
      return res.status(404).json({
        success: false,
        error: 'Employee not found',
        message: 'No employee found with this ID'
      });
    }

    // Toggle status
    employee.isActive = !employee.isActive;
    await employee.save();

    // Note: Firebase user management no longer used (JWT-only system)
    console.log('   ✅ Employee status toggled (JWT-only, no Firebase)');
    console.log('   New status:', employee.isActive ? 'Active' : 'Inactive');
    console.log('✅ STATUS TOGGLED');
    console.log('─'.repeat(80) + '\n');

    res.json({
      success: true,
      message: `Employee ${employee.isActive ? 'activated' : 'deactivated'} successfully`,
      data: {
        isActive: employee.isActive
      }
    });

  } catch (error) {
    console.error('❌ TOGGLE STATUS FAILED');
    console.error('   Error:', error.message);
    console.error('─'.repeat(80) + '\n');

    res.status(500).json({
      success: false,
      error: 'Failed to toggle employee status',
      message: error.message
    });
  }
});

module.exports = router;