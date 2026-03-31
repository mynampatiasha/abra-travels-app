const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const crypto = require('crypto');

/**
 * Generate a unique Firebase UID for employee
 * Format: emp_[timestamp]_[random]
 */
function generateFirebaseUID(employeeName, email) {
  const timestamp = Date.now().toString(36);
  const randomPart = crypto.randomBytes(4).toString('hex');
  const namePart = employeeName.toLowerCase().replace(/[^a-z0-9]/g, '').substring(0, 8);
  return `emp_${namePart}_${timestamp}_${randomPart}`;
}

/**
 * @route   GET /api/hrm/employees
 * @desc    Get all employees with filtering and pagination
 * @access  Private (HR Manager, Super Admin)
 */
router.get('/', async (req, res) => {
  console.log('\n📋 GET ALL EMPLOYEES');
  console.log('─'.repeat(80));
  
  try {
    const { 
      page = 1, 
      limit = 10, 
      search = '', 
      department = '', 
      status = '',
      companyDomain = '',
      companyName = ''
    } = req.query;
    
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    // Build filter query
    const filter = {};
    
    if (search) {
      filter.$or = [
        { name: { $regex: search, $options: 'i' } },
        { email: { $regex: search, $options: 'i' } },
        { phone: { $regex: search, $options: 'i' } },
        { companyName: { $regex: search, $options: 'i' } }
      ];
    }
    
    if (department) {
      filter.department = department;
    }
    
    if (status) {
      filter.status = status;
    }
    
    // Filter by company domain (extract from email)
    if (companyDomain) {
      filter.email = { $regex: `@${companyDomain.replace('.', '\\.')}$`, $options: 'i' };
      console.log('   🏢 Filtering by company domain:', companyDomain);
    }
    
    // Filter by company name
    if (companyName) {
      filter.companyName = { $regex: companyName, $options: 'i' };
      console.log('   🏢 Filtering by company name:', companyName);
    }
    
    console.log('   Filter:', JSON.stringify(filter));
    console.log('   Page:', page, 'Limit:', limit);
    
    // Get employees with pagination
    const employees = await req.db.collection('hr_employees')
      .find(filter)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .toArray();
    
    // Get total count for pagination
    const total = await req.db.collection('hr_employees').countDocuments(filter);
    
    console.log('   ✅ Found', employees.length, 'employees');
    console.log('   Total:', total);
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      data: employees,
      pagination: {
        currentPage: parseInt(page),
        totalPages: Math.ceil(total / parseInt(limit)),
        totalItems: total,
        itemsPerPage: parseInt(limit)
      }
    });
    
  } catch (error) {
    console.error('❌ Error fetching employees:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to fetch employees',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/hrm/employees/:id
 * @desc    Get employee by ID
 * @access  Private
 */
router.get('/:id', async (req, res) => {
  console.log('\n🔍 GET EMPLOYEE BY ID');
  console.log('─'.repeat(80));
  
  try {
    const { id } = req.params;
    
    if (!ObjectId.isValid(id)) {
      console.log('   ❌ Invalid employee ID');
      return res.status(400).json({
        success: false,
        error: 'Invalid employee ID'
      });
    }
    
    console.log('   Employee ID:', id);
    
    const employee = await req.db.collection('hr_employees').findOne({
      _id: new ObjectId(id)
    });
    
    if (!employee) {
      console.log('   ❌ Employee not found');
      console.log('─'.repeat(80) + '\n');
      
      return res.status(404).json({
        success: false,
        error: 'Employee not found'
      });
    }
    
    console.log('   ✅ Employee found:', employee.name);
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      data: employee
    });
    
  } catch (error) {
    console.error('❌ Error fetching employee:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to fetch employee',
      message: error.message
    });
  }
});

/**
 * @route   POST /api/hrm/employees
 * @desc    Create new employee
 * @access  Private (HR Manager, Super Admin)
 */
router.post('/', async (req, res) => {
  console.log('\n➕ CREATE NEW EMPLOYEE');
  console.log('─'.repeat(80));
  
  try {
    const {
      name,
      email,
      phone,
      department,
      designation,
      hireDate,
      salary,
      status,
      address,
      emergencyContact,
      bloodGroup,
      dateOfBirth,
      gender,
      companyName
    } = req.body;
    
    // Validate required fields
    if (!name || !email || !phone || !department || !hireDate) {
      console.log('   ❌ Missing required fields');
      return res.status(400).json({
        success: false,
        error: 'Missing required fields',
        required: ['name', 'email', 'phone', 'department', 'hireDate']
      });
    }
    
    // Check if email already exists
    const existingEmployee = await req.db.collection('hr_employees').findOne({ 
      email: email.toLowerCase() 
    });
    
    if (existingEmployee) {
      console.log('   ❌ Email already exists');
      return res.status(400).json({
        success: false,
        error: 'Email already exists'
      });
    }
    
    console.log('   Name:', name);
    console.log('   Email:', email);
    console.log('   Department:', department);
    
    // Extract company domain from email
    const emailDomain = email.toLowerCase().split('@')[1];
    console.log('   🏢 Company Domain:', emailDomain);
    
    // Generate Firebase UID automatically
    const firebaseUid = generateFirebaseUID(name, email);
    console.log('   🔥 Generated Firebase UID:', firebaseUid);
    
    // Create employee document
    const newEmployee = {
      name,
      email: email.toLowerCase(),
      phone,
      department,
      designation: designation || '',
      hireDate: new Date(hireDate),
      salary: salary || 0,
      status: status || 'active',
      address: address || '',
      emergencyContact: emergencyContact || '',
      bloodGroup: bloodGroup || '',
      dateOfBirth: dateOfBirth ? new Date(dateOfBirth) : null,
      gender: gender || '',
      companyName: companyName || '',
      companyDomain: emailDomain,
      firebaseUid: firebaseUid,
      fcmToken: null, // Will be set when employee logs in on mobile
      createdAt: new Date(),
      updatedAt: new Date(),
      createdBy: req.user.uid
    };
    
    const result = await req.db.collection('hr_employees').insertOne(newEmployee);
    
    console.log('   ✅ Employee created successfully');
    console.log('   Employee ID:', result.insertedId);
    console.log('─'.repeat(80) + '\n');
    
    res.status(201).json({
      success: true,
      message: 'Employee created successfully',
      data: {
        _id: result.insertedId,
        ...newEmployee
      }
    });
    
  } catch (error) {
    console.error('❌ Error creating employee:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to create employee',
      message: error.message
    });
  }
});

/**
 * @route   PUT /api/hrm/employees/:id
 * @desc    Update employee
 * @access  Private (HR Manager, Super Admin)
 */
router.put('/:id', async (req, res) => {
  console.log('\n✏️ UPDATE EMPLOYEE');
  console.log('─'.repeat(80));
  
  try {
    const { id } = req.params;
    
    if (!ObjectId.isValid(id)) {
      console.log('   ❌ Invalid employee ID');
      return res.status(400).json({
        success: false,
        error: 'Invalid employee ID'
      });
    }
    
    console.log('   Employee ID:', id);
    
    const {
      name,
      email,
      phone,
      department,
      designation,
      hireDate,
      salary,
      status,
      address,
      emergencyContact,
      bloodGroup,
      dateOfBirth,
      gender
    } = req.body;
    
    // Build update object
    const updateData = {
      updatedAt: new Date(),
      updatedBy: req.user.uid
    };
    
    if (name) updateData.name = name;
    if (email) updateData.email = email.toLowerCase();
    if (phone) updateData.phone = phone;
    if (department) updateData.department = department;
    if (designation !== undefined) updateData.designation = designation;
    if (hireDate) updateData.hireDate = new Date(hireDate);
    if (salary !== undefined) updateData.salary = salary;
    if (status) updateData.status = status;
    if (address !== undefined) updateData.address = address;
    if (emergencyContact !== undefined) updateData.emergencyContact = emergencyContact;
    if (bloodGroup !== undefined) updateData.bloodGroup = bloodGroup;
    if (dateOfBirth) updateData.dateOfBirth = new Date(dateOfBirth);
    if (gender !== undefined) updateData.gender = gender;
    
    console.log('   Updating fields:', Object.keys(updateData).join(', '));
    
    const result = await req.db.collection('hr_employees').updateOne(
      { _id: new ObjectId(id) },
      { $set: updateData }
    );
    
    if (result.matchedCount === 0) {
      console.log('   ❌ Employee not found');
      console.log('─'.repeat(80) + '\n');
      
      return res.status(404).json({
        success: false,
        error: 'Employee not found'
      });
    }
    
    console.log('   ✅ Employee updated successfully');
    console.log('─'.repeat(80) + '\n');
    
    // Fetch updated employee
    const updatedEmployee = await req.db.collection('hr_employees').findOne({
      _id: new ObjectId(id)
    });
    
    res.json({
      success: true,
      message: 'Employee updated successfully',
      data: updatedEmployee
    });
    
  } catch (error) {
    console.error('❌ Error updating employee:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to update employee',
      message: error.message
    });
  }
});

/**
 * @route   DELETE /api/hrm/employees/:id
 * @desc    Delete employee
 * @access  Private (HR Manager, Super Admin)
 */
router.delete('/:id', async (req, res) => {
  console.log('\n🗑️ DELETE EMPLOYEE');
  console.log('─'.repeat(80));
  
  try {
    const { id } = req.params;
    
    if (!ObjectId.isValid(id)) {
      console.log('   ❌ Invalid employee ID');
      return res.status(400).json({
        success: false,
        error: 'Invalid employee ID'
      });
    }
    
    console.log('   Employee ID:', id);
    
    // Get employee details before deletion
    const employee = await req.db.collection('hr_employees').findOne({
      _id: new ObjectId(id)
    });
    
    if (!employee) {
      console.log('   ❌ Employee not found');
      console.log('─'.repeat(80) + '\n');
      
      return res.status(404).json({
        success: false,
        error: 'Employee not found'
      });
    }
    
    console.log('   Deleting employee:', employee.name);
    
    // Delete employee
    const result = await req.db.collection('hr_employees').deleteOne({
      _id: new ObjectId(id)
    });
    
    console.log('   ✅ Employee deleted successfully');
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Employee deleted successfully',
      data: {
        id,
        name: employee.name
      }
    });
    
  } catch (error) {
    console.error('❌ Error deleting employee:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to delete employee',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/hrm/employees/by-company/:domain
 * @desc    Get employees by company domain
 * @access  Private
 */
router.get('/by-company/:domain', async (req, res) => {
  console.log('\n🏢 GET EMPLOYEES BY COMPANY DOMAIN');
  console.log('─'.repeat(80));
  
  try {
    const { domain } = req.params;
    const { 
      page = 1, 
      limit = 50, 
      search = '', 
      department = '', 
      status = 'active' 
    } = req.query;
    
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    console.log('   Company Domain:', domain);
    console.log('   Page:', page, 'Limit:', limit);
    
    // Build filter query
    const filter = {
      email: { $regex: `@${domain.replace('.', '\\.')}$`, $options: 'i' }
    };
    
    if (search) {
      filter.$and = [
        { email: { $regex: `@${domain.replace('.', '\\.')}$`, $options: 'i' } },
        {
          $or: [
            { name: { $regex: search, $options: 'i' } },
            { email: { $regex: search, $options: 'i' } },
            { phone: { $regex: search, $options: 'i' } },
            { department: { $regex: search, $options: 'i' } }
          ]
        }
      ];
      delete filter.email; // Remove the simple email filter since we're using $and
    }
    
    if (department) {
      filter.department = department;
    }
    
    if (status) {
      filter.status = status;
    }
    
    console.log('   Filter:', JSON.stringify(filter));
    
    // Get employees with pagination
    const employees = await req.db.collection('hr_employees')
      .find(filter)
      .sort({ name: 1 })
      .skip(skip)
      .limit(parseInt(limit))
      .toArray();
    
    // Get total count for pagination
    const total = await req.db.collection('hr_employees').countDocuments(filter);
    
    // Get company statistics
    const companyStats = await req.db.collection('hr_employees').aggregate([
      {
        $match: {
          email: { $regex: `@${domain.replace('.', '\\.')}$`, $options: 'i' }
        }
      },
      {
        $group: {
          _id: null,
          totalEmployees: { $sum: 1 },
          activeEmployees: {
            $sum: { $cond: [{ $eq: ['$status', 'active'] }, 1, 0] }
          },
          departments: { $addToSet: '$department' },
          avgSalary: { $avg: '$salary' }
        }
      }
    ]).toArray();
    
    const stats = companyStats[0] || {
      totalEmployees: 0,
      activeEmployees: 0,
      departments: [],
      avgSalary: 0
    };
    
    console.log('   ✅ Found', employees.length, 'employees for domain', domain);
    console.log('   Total employees for domain:', stats.totalEmployees);
    console.log('   Active employees:', stats.activeEmployees);
    console.log('   Departments:', stats.departments.length);
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      data: employees,
      pagination: {
        currentPage: parseInt(page),
        totalPages: Math.ceil(total / parseInt(limit)),
        totalItems: total,
        itemsPerPage: parseInt(limit)
      },
      companyStats: {
        domain: domain,
        totalEmployees: stats.totalEmployees,
        activeEmployees: stats.activeEmployees,
        departments: stats.departments,
        avgSalary: Math.round(stats.avgSalary || 0)
      }
    });
    
  } catch (error) {
    console.error('❌ Error fetching employees by domain:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to fetch employees by domain',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/hrm/employees/companies/domains
 * @desc    Get all unique company domains
 * @access  Private
 */
router.get('/companies/domains', async (req, res) => {
  console.log('\n🏢 GET ALL COMPANY DOMAINS');
  console.log('─'.repeat(80));
  
  try {
    // Get all unique company domains from employee emails
    const domains = await req.db.collection('hr_employees').aggregate([
      {
        $project: {
          domain: {
            $arrayElemAt: [
              { $split: ['$email', '@'] },
              1
            ]
          },
          companyName: '$companyName',
          status: '$status'
        }
      },
      {
        $group: {
          _id: '$domain',
          companyName: { $first: '$companyName' },
          totalEmployees: { $sum: 1 },
          activeEmployees: {
            $sum: { $cond: [{ $eq: ['$status', 'active'] }, 1, 0] }
          }
        }
      },
      {
        $sort: { totalEmployees: -1 }
      }
    ]).toArray();
    
    console.log('   ✅ Found', domains.length, 'unique company domains');
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      data: domains.map(d => ({
        domain: d._id,
        companyName: d.companyName || d._id.split('.')[0].toUpperCase(),
        totalEmployees: d.totalEmployees,
        activeEmployees: d.activeEmployees
      }))
    });
    
  } catch (error) {
    console.error('❌ Error fetching company domains:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to fetch company domains',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/hrm/employees/stats/overview
 * @desc    Get employee statistics
 * @access  Private
 */
router.get('/stats/overview', async (req, res) => {
  console.log('\n📊 GET EMPLOYEE STATISTICS');
  console.log('─'.repeat(80));
  
  try {
    const totalEmployees = await req.db.collection('hr_employees').countDocuments();
    
    const activeEmployees = await req.db.collection('hr_employees').countDocuments({
      status: 'active'
    });
    
    const inactiveEmployees = await req.db.collection('hr_employees').countDocuments({
      status: 'inactive'
    });
    
    // Get department-wise count
    const departmentStats = await req.db.collection('hr_employees').aggregate([
      {
        $group: {
          _id: '$department',
          count: { $sum: 1 }
        }
      },
      {
        $sort: { count: -1 }
      }
    ]).toArray();
    
    console.log('   Total Employees:', totalEmployees);
    console.log('   Active:', activeEmployees);
    console.log('   Inactive:', inactiveEmployees);
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      data: {
        totalEmployees,
        activeEmployees,
        inactiveEmployees,
        departmentStats
      }
    });
    
  } catch (error) {
    console.error('❌ Error fetching employee statistics:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to fetch employee statistics',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/hrm/employees/export/excel
 * @desc    Export employees to Excel
 * @access  Private
 */
router.get('/export/excel', async (req, res) => {
  console.log('\n📥 EXPORT EMPLOYEES TO EXCEL');
  console.log('─'.repeat(80));
  
  try {
    const { department = '', status = '' } = req.query;
    
    // Build filter
    const filter = {};
    if (department) filter.department = department;
    if (status) filter.status = status;
    
    const employees = await req.db.collection('hr_employees')
      .find(filter)
      .sort({ name: 1 })
      .toArray();
    
    console.log('   ✅ Exporting', employees.length, 'employees');
    console.log('─'.repeat(80) + '\n');
    
    // Format data for export
    const exportData = employees.map(emp => ({
      ID: emp._id.toString(),
      Name: emp.name,
      Email: emp.email,
      Phone: emp.phone,
      Department: emp.department,
      Designation: emp.designation || '',
      'Hire Date': emp.hireDate ? new Date(emp.hireDate).toLocaleDateString() : '',
      Salary: emp.salary || 0,
      Status: emp.status,
      Address: emp.address || '',
      'Emergency Contact': emp.emergencyContact || '',
      'Blood Group': emp.bloodGroup || '',
      'Date of Birth': emp.dateOfBirth ? new Date(emp.dateOfBirth).toLocaleDateString() : '',
      Gender: emp.gender || ''
    }));
    
    res.json({
      success: true,
      data: exportData,
      filename: `employees_${new Date().toISOString().split('T')[0]}.xlsx`
    });
    
  } catch (error) {
    console.error('❌ Error exporting employees:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to export employees',
      message: error.message
    });
  }
});

module.exports = router;