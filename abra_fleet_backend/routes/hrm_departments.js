const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');

/**
 * @route   GET /api/hrm/departments
 * @desc    Get all departments
 * @access  Private (HR Manager, Super Admin)
 */
router.get('/', async (req, res) => {
  console.log('\n📋 GET ALL DEPARTMENTS');
  console.log('─'.repeat(80));
  
  try {
    const { 
      page = 1, 
      limit = 100, 
      search = '' 
    } = req.query;
    
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    // Build filter query
    const filter = {};
    
    if (search) {
      filter.name = { $regex: search, $options: 'i' };
    }
    
    console.log('   Filter:', JSON.stringify(filter));
    console.log('   Page:', page, 'Limit:', limit);
    
    // Get departments with pagination
    const departments = await req.db.collection('hr_departments')
      .find(filter)
      .sort({ name: 1 })
      .skip(skip)
      .limit(parseInt(limit))
      .toArray();
    
    // Get total count for pagination
    const total = await req.db.collection('hr_departments').countDocuments(filter);
    
    console.log('   ✅ Found', departments.length, 'departments');
    console.log('   Total:', total);
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      data: departments,
      pagination: {
        currentPage: parseInt(page),
        totalPages: Math.ceil(total / parseInt(limit)),
        totalItems: total,
        itemsPerPage: parseInt(limit)
      }
    });
    
  } catch (error) {
    console.error('❌ Error fetching departments:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to fetch departments',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/hrm/departments/:id
 * @desc    Get department by ID
 * @access  Private
 */
router.get('/:id', async (req, res) => {
  console.log('\n🔍 GET DEPARTMENT BY ID');
  console.log('─'.repeat(80));
  
  try {
    const { id } = req.params;
    
    if (!ObjectId.isValid(id)) {
      console.log('   ❌ Invalid department ID');
      return res.status(400).json({
        success: false,
        error: 'Invalid department ID'
      });
    }
    
    console.log('   Department ID:', id);
    
    const department = await req.db.collection('hr_departments').findOne({
      _id: new ObjectId(id)
    });
    
    if (!department) {
      console.log('   ❌ Department not found');
      console.log('─'.repeat(80) + '\n');
      
      return res.status(404).json({
        success: false,
        error: 'Department not found'
      });
    }
    
    console.log('   ✅ Department found:', department.name);
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      data: department
    });
    
  } catch (error) {
    console.error('❌ Error fetching department:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to fetch department',
      message: error.message
    });
  }
});

/**
 * @route   POST /api/hrm/departments
 * @desc    Create new department
 * @access  Private (HR Manager, Super Admin)
 */
router.post('/', async (req, res) => {
  console.log('\n➕ CREATE NEW DEPARTMENT');
  console.log('─'.repeat(80));
  
  try {
    const { name, description } = req.body;
    
    // Validate required fields
    if (!name) {
      console.log('   ❌ Missing department name');
      return res.status(400).json({
        success: false,
        error: 'Department name is required'
      });
    }
    
    // Check if department already exists
    const existingDepartment = await req.db.collection('hr_departments').findOne({ 
      name: { $regex: new RegExp(`^${name}$`, 'i') }
    });
    
    if (existingDepartment) {
      console.log('   ❌ Department already exists');
      return res.status(400).json({
        success: false,
        error: 'Department already exists'
      });
    }
    
    console.log('   Name:', name);
    console.log('   Description:', description || 'N/A');
    
    // Create department document
    const newDepartment = {
      name: name.trim(),
      description: description || '',
      employeeCount: 0,
      isActive: true,
      createdAt: new Date(),
      updatedAt: new Date(),
      createdBy: req.user.email
    };
    
    const result = await req.db.collection('hr_departments').insertOne(newDepartment);
    
    console.log('   ✅ Department created successfully');
    console.log('   Department ID:', result.insertedId);
    console.log('─'.repeat(80) + '\n');
    
    res.status(201).json({
      success: true,
      message: 'Department created successfully',
      data: {
        _id: result.insertedId,
        ...newDepartment
      }
    });
    
  } catch (error) {
    console.error('❌ Error creating department:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to create department',
      message: error.message
    });
  }
});

/**
 * @route   PUT /api/hrm/departments/:id
 * @desc    Update department
 * @access  Private (HR Manager, Super Admin)
 */
router.put('/:id', async (req, res) => {
  console.log('\n✏️ UPDATE DEPARTMENT');
  console.log('─'.repeat(80));
  
  try {
    const { id } = req.params;
    
    if (!ObjectId.isValid(id)) {
      console.log('   ❌ Invalid department ID');
      return res.status(400).json({
        success: false,
        error: 'Invalid department ID'
      });
    }
    
    console.log('   Department ID:', id);
    
    const { name, description, isActive } = req.body;
    
    // Build update object
    const updateData = {
      updatedAt: new Date(),
      updatedBy: req.user.email
    };
    
    if (name) {
      // Check if new name already exists (excluding current department)
      const existingDepartment = await req.db.collection('hr_departments').findOne({ 
        name: { $regex: new RegExp(`^${name}$`, 'i') },
        _id: { $ne: new ObjectId(id) }
      });
      
      if (existingDepartment) {
        console.log('   ❌ Department name already exists');
        return res.status(400).json({
          success: false,
          error: 'Department name already exists'
        });
      }
      
      updateData.name = name.trim();
    }
    
    if (description !== undefined) updateData.description = description;
    if (isActive !== undefined) updateData.isActive = isActive;
    
    console.log('   Updating fields:', Object.keys(updateData).join(', '));
    
    const result = await req.db.collection('hr_departments').updateOne(
      { _id: new ObjectId(id) },
      { $set: updateData }
    );
    
    if (result.matchedCount === 0) {
      console.log('   ❌ Department not found');
      console.log('─'.repeat(80) + '\n');
      
      return res.status(404).json({
        success: false,
        error: 'Department not found'
      });
    }
    
    console.log('   ✅ Department updated successfully');
    console.log('─'.repeat(80) + '\n');
    
    // Fetch updated department
    const updatedDepartment = await req.db.collection('hr_departments').findOne({
      _id: new ObjectId(id)
    });
    
    res.json({
      success: true,
      message: 'Department updated successfully',
      data: updatedDepartment
    });
    
  } catch (error) {
    console.error('❌ Error updating department:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to update department',
      message: error.message
    });
  }
});

/**
 * @route   DELETE /api/hrm/departments/:id
 * @desc    Delete department
 * @access  Private (HR Manager, Super Admin)
 */
router.delete('/:id', async (req, res) => {
  console.log('\n🗑️ DELETE DEPARTMENT');
  console.log('─'.repeat(80));
  
  try {
    const { id } = req.params;
    
    if (!ObjectId.isValid(id)) {
      console.log('   ❌ Invalid department ID');
      return res.status(400).json({
        success: false,
        error: 'Invalid department ID'
      });
    }
    
    console.log('   Department ID:', id);
    
    // Check if department has employees
    const employeeCount = await req.db.collection('hr_employees').countDocuments({
      department: id
    });
    
    if (employeeCount > 0) {
      console.log('   ❌ Department has employees, cannot delete');
      console.log('   Employee count:', employeeCount);
      console.log('─'.repeat(80) + '\n');
      
      return res.status(400).json({
        success: false,
        error: 'Cannot delete department with employees',
        message: `This department has ${employeeCount} employee(s). Please reassign them first.`
      });
    }
    
    // Get department details before deletion
    const department = await req.db.collection('hr_departments').findOne({
      _id: new ObjectId(id)
    });
    
    if (!department) {
      console.log('   ❌ Department not found');
      console.log('─'.repeat(80) + '\n');
      
      return res.status(404).json({
        success: false,
        error: 'Department not found'
      });
    }
    
    console.log('   Deleting department:', department.name);
    
    // Delete department
    const result = await req.db.collection('hr_departments').deleteOne({
      _id: new ObjectId(id)
    });
    
    console.log('   ✅ Department deleted successfully');
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Department deleted successfully',
      data: {
        id,
        name: department.name
      }
    });
    
  } catch (error) {
    console.error('❌ Error deleting department:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to delete department',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/hrm/departments/stats/overview
 * @desc    Get department statistics
 * @access  Private
 */
router.get('/stats/overview', async (req, res) => {
  console.log('\n📊 GET DEPARTMENT STATISTICS');
  console.log('─'.repeat(80));
  
  try {
    const totalDepartments = await req.db.collection('hr_departments').countDocuments();
    
    const activeDepartments = await req.db.collection('hr_departments').countDocuments({
      isActive: true
    });
    
    // Get employee count per department
    const departmentEmployeeCounts = await req.db.collection('hr_employees').aggregate([
      {
        $group: {
          _id: '$department',
          count: { $sum: 1 }
        }
      }
    ]).toArray();
    
    console.log('   Total Departments:', totalDepartments);
    console.log('   Active:', activeDepartments);
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      data: {
        totalDepartments,
        activeDepartments,
        inactiveDepartments: totalDepartments - activeDepartments,
        departmentEmployeeCounts
      }
    });
    
  } catch (error) {
    console.error('❌ Error fetching department statistics:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to fetch department statistics',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/hrm/departments/export/csv
 * @desc    Export departments to CSV
 * @access  Private
 */
router.get('/export/csv', async (req, res) => {
  console.log('\n📥 EXPORT DEPARTMENTS TO CSV');
  console.log('─'.repeat(80));
  
  try {
    const departments = await req.db.collection('hr_departments')
      .find({})
      .sort({ name: 1 })
      .toArray();
    
    console.log('   ✅ Exporting', departments.length, 'departments');
    console.log('─'.repeat(80) + '\n');
    
    // Format data for CSV export
    const exportData = departments.map(dept => ({
      'Department ID': dept._id.toString(),
      'Department Name': dept.name,
      'Description': dept.description || '',
      'Employee Count': dept.employeeCount || 0,
      'Status': dept.isActive ? 'Active' : 'Inactive',
      'Created At': new Date(dept.createdAt).toLocaleDateString()
    }));
    
    res.json({
      success: true,
      data: exportData,
      filename: `departments_${new Date().toISOString().split('T')[0]}.csv`
    });
    
  } catch (error) {
    console.error('❌ Error exporting departments:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to export departments',
      message: error.message
    });
  }
});

module.exports = router;