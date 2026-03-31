// routes/hrm_payroll.js

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');

/**
 * GET /api/hrm/payroll
 * Fetch all payroll entries with employee details
 */
router.get('/', async (req, res) => {
  console.log('\n📥 GET /api/hrm/payroll - Fetch all payroll entries');
  console.log('─'.repeat(80));
  
  try {
    const payrollCollection = req.db.collection('hr_payroll');
    const employeesCollection = req.db.collection('hr_employees');
    
    // Fetch all payroll entries
    const payrollEntries = await payrollCollection.find({}).sort({ createdAt: -1 }).toArray();
    console.log(`✅ Found ${payrollEntries.length} payroll entries`);
    
    // Enrich with employee details
    const enrichedPayroll = await Promise.all(
      payrollEntries.map(async (payroll) => {
        let employeeName = 'Unknown';
        
        try {
          // Find employee by ID
          const employee = await employeesCollection.findOne({
            _id: ObjectId.isValid(payroll.employee_id) ? new ObjectId(payroll.employee_id) : payroll.employee_id
          });
          
          if (employee) {
            employeeName = employee.name;
          }
        } catch (err) {
          console.warn(`⚠️  Could not find employee for payroll ${payroll._id}:`, err.message);
        }
        
        return {
          ...payroll,
          employee_name: employeeName
        };
      })
    );
    
    console.log('✅ Payroll entries fetched and enriched successfully');
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Payroll entries fetched successfully',
      data: enrichedPayroll,
      count: enrichedPayroll.length
    });
    
  } catch (error) {
    console.error('❌ Error fetching payroll entries:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to fetch payroll entries',
      message: error.message
    });
  }
});

/**
 * POST /api/hrm/payroll
 * Create a new payroll entry
 */
router.post('/', async (req, res) => {
  console.log('\n📥 POST /api/hrm/payroll - Create new payroll entry');
  console.log('─'.repeat(80));
  console.log('Body:', JSON.stringify(req.body, null, 2));
  
  try {
    const { employee_id, amount, pay_date, comment } = req.body;
    
    // Validation
    if (!employee_id) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Employee ID is required'
      });
    }
    
    if (amount === undefined || amount === null) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Amount is required'
      });
    }
    
    const parsedAmount = parseFloat(amount);
    if (isNaN(parsedAmount) || parsedAmount <= 0) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Amount must be a positive number'
      });
    }
    
    if (!pay_date) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Pay date is required'
      });
    }
    
    // Validate date
    const payDate = new Date(pay_date);
    if (isNaN(payDate.getTime())) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Invalid date format'
      });
    }
    
    // Verify employee exists
    const employeesCollection = req.db.collection('hr_employees');
    const employee = await employeesCollection.findOne({
      _id: ObjectId.isValid(employee_id) ? new ObjectId(employee_id) : employee_id
    });
    
    if (!employee) {
      return res.status(404).json({
        success: false,
        error: 'Not found',
        message: 'Employee not found'
      });
    }
    
    console.log('✅ Employee found:', employee.name);
    
    // Create payroll entry
    const payrollCollection = req.db.collection('hr_payroll');
    
    const newPayroll = {
      employee_id: employee_id,
      amount: parsedAmount,
      pay_date: payDate.toISOString(),
      comment: comment ? comment.trim() : '',
      createdAt: new Date(),
      updatedAt: new Date(),
      createdBy: req.user?.email || 'admin'
    };
    
    const result = await payrollCollection.insertOne(newPayroll);
    console.log('✅ Payroll entry created with ID:', result.insertedId);
    
    // Fetch the created payroll with employee name
    const createdPayroll = await payrollCollection.findOne({ _id: result.insertedId });
    const enrichedPayroll = {
      ...createdPayroll,
      employee_name: employee.name
    };
    
    console.log('✅ Payroll entry created successfully');
    console.log('─'.repeat(80) + '\n');
    
    res.status(201).json({
      success: true,
      message: 'Payroll entry created successfully',
      data: enrichedPayroll
    });
    
  } catch (error) {
    console.error('❌ Error creating payroll entry:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to create payroll entry',
      message: error.message
    });
  }
});

/**
 * PUT /api/hrm/payroll/:id
 * Update an existing payroll entry
 */
router.put('/:id', async (req, res) => {
  console.log('\n📥 PUT /api/hrm/payroll/:id - Update payroll entry');
  console.log('─'.repeat(80));
  console.log('Payroll ID:', req.params.id);
  console.log('Body:', JSON.stringify(req.body, null, 2));
  
  try {
    const { id } = req.params;
    const { employee_id, amount, pay_date, comment } = req.body;
    
    // Validate ID
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Invalid payroll entry ID'
      });
    }
    
    // Validation
    if (!employee_id) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Employee ID is required'
      });
    }
    
    if (amount === undefined || amount === null) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Amount is required'
      });
    }
    
    const parsedAmount = parseFloat(amount);
    if (isNaN(parsedAmount) || parsedAmount <= 0) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Amount must be a positive number'
      });
    }
    
    if (!pay_date) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Pay date is required'
      });
    }
    
    // Validate date
    const payDate = new Date(pay_date);
    if (isNaN(payDate.getTime())) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Invalid date format'
      });
    }
    
    // Verify employee exists
    const employeesCollection = req.db.collection('hr_employees');
    const employee = await employeesCollection.findOne({
      _id: ObjectId.isValid(employee_id) ? new ObjectId(employee_id) : employee_id
    });
    
    if (!employee) {
      return res.status(404).json({
        success: false,
        error: 'Not found',
        message: 'Employee not found'
      });
    }
    
    console.log('✅ Employee found:', employee.name);
    
    // Update payroll entry
    const payrollCollection = req.db.collection('hr_payroll');
    
    const updateData = {
      employee_id: employee_id,
      amount: parsedAmount,
      pay_date: payDate.toISOString(),
      comment: comment ? comment.trim() : '',
      updatedAt: new Date(),
      updatedBy: req.user?.email || 'admin'
    };
    
    const result = await payrollCollection.updateOne(
      { _id: new ObjectId(id) },
      { $set: updateData }
    );
    
    if (result.matchedCount === 0) {
      return res.status(404).json({
        success: false,
        error: 'Not found',
        message: 'Payroll entry not found'
      });
    }
    
    console.log('✅ Payroll entry updated successfully');
    
    // Fetch updated payroll with employee name
    const updatedPayroll = await payrollCollection.findOne({ _id: new ObjectId(id) });
    const enrichedPayroll = {
      ...updatedPayroll,
      employee_name: employee.name
    };
    
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Payroll entry updated successfully',
      data: enrichedPayroll
    });
    
  } catch (error) {
    console.error('❌ Error updating payroll entry:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to update payroll entry',
      message: error.message
    });
  }
});

/**
 * DELETE /api/hrm/payroll/:id
 * Delete a payroll entry
 */
router.delete('/:id', async (req, res) => {
  console.log('\n📥 DELETE /api/hrm/payroll/:id - Delete payroll entry');
  console.log('─'.repeat(80));
  console.log('Payroll ID:', req.params.id);
  
  try {
    const { id } = req.params;
    
    // Validate ID
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Invalid payroll entry ID'
      });
    }
    
    const payrollCollection = req.db.collection('hr_payroll');
    
    // Check if payroll exists
    const payroll = await payrollCollection.findOne({ _id: new ObjectId(id) });
    
    if (!payroll) {
      return res.status(404).json({
        success: false,
        error: 'Not found',
        message: 'Payroll entry not found'
      });
    }
    
    // Delete payroll entry
    const result = await payrollCollection.deleteOne({ _id: new ObjectId(id) });
    
    console.log('✅ Payroll entry deleted successfully');
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Payroll entry deleted successfully',
      deletedCount: result.deletedCount
    });
    
  } catch (error) {
    console.error('❌ Error deleting payroll entry:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to delete payroll entry',
      message: error.message
    });
  }
});

/**
 * GET /api/hrm/payroll/:id
 * Get a single payroll entry by ID
 */
router.get('/:id', async (req, res) => {
  console.log('\n📥 GET /api/hrm/payroll/:id - Get single payroll entry');
  console.log('─'.repeat(80));
  console.log('Payroll ID:', req.params.id);
  
  try {
    const { id } = req.params;
    
    // Validate ID
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Invalid payroll entry ID'
      });
    }
    
    const payrollCollection = req.db.collection('hr_payroll');
    const employeesCollection = req.db.collection('hr_employees');
    
    // Fetch payroll entry
    const payroll = await payrollCollection.findOne({ _id: new ObjectId(id) });
    
    if (!payroll) {
      return res.status(404).json({
        success: false,
        error: 'Not found',
        message: 'Payroll entry not found'
      });
    }
    
    // Enrich with employee details
    let employeeName = 'Unknown';
    try {
      const employee = await employeesCollection.findOne({
        _id: ObjectId.isValid(payroll.employee_id) ? new ObjectId(payroll.employee_id) : payroll.employee_id
      });
      
      if (employee) {
        employeeName = employee.name;
      }
    } catch (err) {
      console.warn('⚠️  Could not find employee:', err.message);
    }
    
    const enrichedPayroll = {
      ...payroll,
      employee_name: employeeName
    };
    
    console.log('✅ Payroll entry fetched successfully');
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Payroll entry fetched successfully',
      data: enrichedPayroll
    });
    
  } catch (error) {
    console.error('❌ Error fetching payroll entry:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to fetch payroll entry',
      message: error.message
    });
  }
});

/**
 * GET /api/hrm/payroll/employee/:employeeId
 * Get all payroll entries for a specific employee
 */
router.get('/employee/:employeeId', async (req, res) => {
  console.log('\n📥 GET /api/hrm/payroll/employee/:employeeId - Get employee payroll history');
  console.log('─'.repeat(80));
  console.log('Employee ID:', req.params.employeeId);
  
  try {
    const { employeeId } = req.params;
    
    const payrollCollection = req.db.collection('hr_payroll');
    const employeesCollection = req.db.collection('hr_employees');
    
    // Verify employee exists
    const employee = await employeesCollection.findOne({
      _id: ObjectId.isValid(employeeId) ? new ObjectId(employeeId) : employeeId
    });
    
    if (!employee) {
      return res.status(404).json({
        success: false,
        error: 'Not found',
        message: 'Employee not found'
      });
    }
    
    // Fetch payroll entries for this employee
    const payrollEntries = await payrollCollection
      .find({ employee_id: employeeId })
      .sort({ pay_date: -1 })
      .toArray();
    
    console.log(`✅ Found ${payrollEntries.length} payroll entries for ${employee.name}`);
    
    // Enrich with employee name
    const enrichedPayroll = payrollEntries.map(payroll => ({
      ...payroll,
      employee_name: employee.name
    }));
    
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Employee payroll history fetched successfully',
      data: enrichedPayroll,
      employee: {
        id: employee._id,
        name: employee.name,
        email: employee.email
      },
      count: enrichedPayroll.length
    });
    
  } catch (error) {
    console.error('❌ Error fetching employee payroll history:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to fetch employee payroll history',
      message: error.message
    });
  }
});

/**
 * GET /api/hrm/payroll/stats/summary
 * Get payroll statistics summary
 */
router.get('/stats/summary', async (req, res) => {
  console.log('\n📥 GET /api/hrm/payroll/stats/summary - Get payroll statistics');
  console.log('─'.repeat(80));
  
  try {
    const payrollCollection = req.db.collection('hr_payroll');
    
    // Get total payroll amount
    const totalResult = await payrollCollection.aggregate([
      {
        $group: {
          _id: null,
          totalAmount: { $sum: '$amount' },
          count: { $sum: 1 },
          avgAmount: { $avg: '$amount' }
        }
      }
    ]).toArray();
    
    const stats = totalResult.length > 0 ? totalResult[0] : {
      totalAmount: 0,
      count: 0,
      avgAmount: 0
    };
    
    // Get monthly breakdown (last 6 months)
    const sixMonthsAgo = new Date();
    sixMonthsAgo.setMonth(sixMonthsAgo.getMonth() - 6);
    
    const monthlyBreakdown = await payrollCollection.aggregate([
      {
        $match: {
          pay_date: { $gte: sixMonthsAgo.toISOString() }
        }
      },
      {
        $group: {
          _id: {
            year: { $year: { $toDate: '$pay_date' } },
            month: { $month: { $toDate: '$pay_date' } }
          },
          totalAmount: { $sum: '$amount' },
          count: { $sum: 1 }
        }
      },
      {
        $sort: { '_id.year': 1, '_id.month': 1 }
      }
    ]).toArray();
    
    console.log('✅ Payroll statistics calculated successfully');
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Payroll statistics fetched successfully',
      data: {
        summary: {
          totalAmount: stats.totalAmount,
          totalEntries: stats.count,
          averageAmount: stats.avgAmount
        },
        monthlyBreakdown: monthlyBreakdown
      }
    });
    
  } catch (error) {
    console.error('❌ Error fetching payroll statistics:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to fetch payroll statistics',
      message: error.message
    });
  }
});

module.exports = router;