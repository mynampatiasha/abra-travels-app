// routes/admin-customers-unified.js - UNIFIED CUSTOMER API (MongoDB + Firestore Sync)
const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');


/**
 * GET /api/admin/customers - Get all customers from MongoDB (unified source)
 * Supports filtering, pagination, and search
 */
router.get('/', async (req, res) => {
  try {
    console.log('\n📋 FETCHING ALL CUSTOMERS (UNIFIED)');
    console.log('─'.repeat(80));
    
    const {
      page = 1,
      limit = 50,
      status,
      search,
      organization,
      department,
      fullDetails = false
    } = req.query;

    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    // Build filter
    const filter = {};
    
    // ✅ ALWAYS exclude deleted customers unless explicitly requested
    if (status && status.toLowerCase() === 'deleted') {
      filter.status = 'deleted';
    } else {
      // Exclude deleted customers by default
      filter.status = { $ne: 'deleted' };
      
      // If specific status requested, override the filter
      if (status && status !== 'All') {
        filter.status = status.toLowerCase();
      }
    }
    
    if (organization && organization !== 'All Organizations') {
      filter.$or = [
        { companyName: { $regex: organization, $options: 'i' } },
        { organizationName: { $regex: organization, $options: 'i' } }
      ];
    }
    
    if (department && department !== 'All Departments') {
      filter.department = { $regex: department, $options: 'i' };
    }
    
    if (search) {
      filter.$or = [
        { name: { $regex: search, $options: 'i' } },
        { email: { $regex: search, $options: 'i' } },
        { employeeId: { $regex: search, $options: 'i' } },
        { phone: { $regex: search, $options: 'i' } }
      ];
    }

    console.log('🔍 Filter:', JSON.stringify(filter, null, 2));

    // Get customers from MongoDB (primary source)
    const customers = await req.db.collection('customers')
      .find(filter)
      .skip(skip)
      .limit(parseInt(limit))
      .sort({ createdAt: -1 })
      .toArray();

    const totalCount = await req.db.collection('customers').countDocuments(filter);

    console.log(`✅ Found ${customers.length} customers (${totalCount} total)`);

    // Format response similar to drivers API
    const formattedCustomers = customers.map(customer => ({
      id: customer._id.toString(),
      customerId: customer.customerId || customer._id.toString(),
      name: customer.name,
      email: customer.email,
      phone: customer.phone || '',
      companyName: customer.companyName || customer.organizationName || '',
      department: customer.department || '',
      branch: customer.branch || '',
      employeeId: customer.employeeId || '',
      status: customer.status || 'active',
      role: 'customer',
      firebaseUid: customer.firebaseUid || null,
      createdAt: customer.createdAt,
      updatedAt: customer.updatedAt,
      lastLogin: customer.lastLogin
    }));

    res.json({
      success: true,
      data: formattedCustomers,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: totalCount,
        pages: Math.ceil(totalCount / parseInt(limit))
      },
      summary: {
        total: totalCount,
        active: await req.db.collection('customers').countDocuments({ status: 'active' }),
        inactive: await req.db.collection('customers').countDocuments({ status: 'inactive' }),
        pending: await req.db.collection('customers').countDocuments({ status: 'pending' }),
        deleted: await req.db.collection('customers').countDocuments({ status: 'deleted' })
      }
    });

  } catch (error) {
    console.error('❌ Error fetching customers:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch customers',
      message: error.message
    });
  }
});

/**
 * POST /api/admin/customers - Create new customer (MongoDB + Firebase sync)
 */
router.post('/', async (req, res) => {
  try {
    console.log('\n➕ CREATING NEW CUSTOMER (UNIFIED)');
    console.log('─'.repeat(80));
    
    const {
      name,
      email,
      phone,
      companyName,
      department,
      branch,
      employeeId,
      password,
      status = 'active'
    } = req.body;

    // Validate required fields
    if (!name || !email) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields',
        message: 'Name and email are required'
      });
    }

    // Check if customer already exists
    const existingCustomer = await req.db.collection('customers').findOne({
      $or: [
        { email: email.toLowerCase() },
        ...(employeeId ? [{ employeeId }] : [])
      ]
    });

    if (existingCustomer) {
      return res.status(409).json({
        success: false,
        error: 'Customer already exists',
        message: 'A customer with this email or employee ID already exists'
      });
    }

    let firebaseUid = null;

    // Create Firebase Auth user if password provided
    if (password) {
      try {
        const firebaseUser = await admin.auth().createUser({
          email: email.toLowerCase(),
          password,
          displayName: name,
          emailVerified: false
        });
        firebaseUid = firebaseUser.uid;
        console.log('✅ Firebase user created:', firebaseUid);

        // Set custom claims
        await admin.auth().setCustomUserClaims(firebaseUid, {
          role: 'customer',
          customerId: null // Will be updated after MongoDB creation
        });

      } catch (firebaseError) {
        console.error('❌ Firebase user creation failed:', firebaseError);
        return res.status(400).json({
          success: false,
          error: 'Failed to create Firebase user',
          message: firebaseError.message
        });
      }
    }

    // Create customer in MongoDB
    const newCustomer = {
      customerId: employeeId || `CUST${Date.now()}`,
      name: name.trim(),
      email: email.toLowerCase().trim(),
      phone: phone?.trim() || '',
      companyName: companyName?.trim() || '',
      department: department?.trim() || '',
      branch: branch?.trim() || '',
      employeeId: employeeId?.trim() || '',
      status: status.toLowerCase(),
      role: 'customer',
      firebaseUid,
      createdAt: new Date(),
      updatedAt: new Date(),
      createdBy: req.user?.uid || 'system'
    };

    const result = await req.db.collection('customers').insertOne(newCustomer);
    console.log('✅ Customer created in MongoDB:', result.insertedId);

    // Update Firebase custom claims with customerId
    if (firebaseUid) {
      await admin.auth().setCustomUserClaims(firebaseUid, {
        role: 'customer',
        customerId: result.insertedId.toString()
      });
    }

    // Sync to Firestore for compatibility
    if (firebaseUid) {
      try {
        await admin.firestore().collection('users').doc(firebaseUid).set({
          name,
          email: email.toLowerCase(),
          phone: phone || '',
          companyName: companyName || '',
          department: department || '',
          branch: branch || '',
          employeeId: employeeId || '',
          role: 'customer',
          status: status.toLowerCase(),
          customerId: result.insertedId.toString(),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        console.log('✅ Customer synced to Firestore');
      } catch (firestoreError) {
        console.warn('⚠️ Firestore sync failed:', firestoreError.message);
      }
    }

    res.status(201).json({
      success: true,
      message: 'Customer created successfully',
      data: {
        id: result.insertedId.toString(),
        customerId: newCustomer.customerId,
        firebaseUid,
        ...newCustomer
      }
    });

  } catch (error) {
    console.error('❌ Error creating customer:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to create customer',
      message: error.message
    });
  }
});

/**
 * GET /api/admin/customers/:id - Get customer by ID
 */
router.get('/:id', async (req, res) => {
  try {
    const customerId = req.params.id;
    
    let query = { customerId };
    
    // If ID looks like MongoDB ObjectId, also search by _id
    if (/^[0-9a-fA-F]{24}$/.test(customerId)) {
      query = {
        $or: [
          { customerId },
          { _id: new ObjectId(customerId) }
        ]
      };
    }

    const customer = await req.db.collection('customers').findOne(query);

    if (!customer) {
      return res.status(404).json({
        success: false,
        error: 'Customer not found'
      });
    }

    res.json({
      success: true,
      data: {
        id: customer._id.toString(),
        customerId: customer.customerId,
        ...customer
      }
    });

  } catch (error) {
    console.error('❌ Error fetching customer:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch customer',
      message: error.message
    });
  }
});

/**
 * PUT /api/admin/customers/:id - Update customer
 */
router.put('/:id', async (req, res) => {
  try {
    const customerId = req.params.id;
    const updateData = { ...req.body };
    
    // Remove fields that shouldn't be updated directly
    delete updateData._id;
    delete updateData.createdAt;
    delete updateData.createdBy;
    
    updateData.updatedAt = new Date();

    let query = { customerId };
    if (/^[0-9a-fA-F]{24}$/.test(customerId)) {
      query = {
        $or: [
          { customerId },
          { _id: new ObjectId(customerId) }
        ]
      };
    }

    const result = await req.db.collection('customers').updateOne(
      query,
      { $set: updateData }
    );

    if (result.matchedCount === 0) {
      return res.status(404).json({
        success: false,
        error: 'Customer not found'
      });
    }

    // Get updated customer
    const updatedCustomer = await req.db.collection('customers').findOne(query);

    // Sync to Firestore if firebaseUid exists
    if (updatedCustomer.firebaseUid) {
      try {
        await admin.firestore().collection('users').doc(updatedCustomer.firebaseUid).update({
          ...updateData,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        console.log('✅ Customer synced to Firestore');
      } catch (firestoreError) {
        console.warn('⚠️ Firestore sync failed:', firestoreError.message);
      }
    }

    res.json({
      success: true,
      message: 'Customer updated successfully',
      data: updatedCustomer
    });

  } catch (error) {
    console.error('❌ Error updating customer:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to update customer',
      message: error.message
    });
  }
});

/**
 * DELETE /api/admin/customers/:id - Delete customer (soft delete)
 */
router.delete('/:id', async (req, res) => {
  try {
    const customerId = req.params.id;

    let query = { customerId };
    if (/^[0-9a-fA-F]{24}$/.test(customerId)) {
      query = {
        $or: [
          { customerId },
          { _id: new ObjectId(customerId) }
        ]
      };
    }

    // Soft delete by updating status
    const result = await req.db.collection('customers').updateOne(
      query,
      { 
        $set: { 
          status: 'deleted',
          deletedAt: new Date(),
          deletedBy: req.user?.uid || 'system'
        } 
      }
    );

    if (result.matchedCount === 0) {
      return res.status(404).json({
        success: false,
        error: 'Customer not found'
      });
    }

    res.json({
      success: true,
      message: 'Customer deleted successfully'
    });

  } catch (error) {
    console.error('❌ Error deleting customer:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete customer',
      message: error.message
    });
  }
});

module.exports = router;