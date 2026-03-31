const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');

// Admin Customer Management APIs
// Base route: /api/admin/customers

// GET /api/admin/customers - Get all customers with optional filters
router.get('/', async (req, res) => {
  try {
    const { status, page = 1, limit = 20, search, domain } = req.query;
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    // Build filter
    let filter = {};
    if (status) filter.status = status;
    
    // If domain filter is provided (for client role), filter by email domain
    if (domain) {
      const searchDomain = domain.startsWith('@') ? domain : `@${domain}`;
      filter.email = { $regex: `${searchDomain.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, $options: 'i' };
      console.log('🔍 Filtering customers by domain:', searchDomain);
    }
    
    if (search) {
      filter.$or = [
        { customerId: { $regex: search, $options: 'i' } },
        { 'contactInfo.phone': { $regex: search, $options: 'i' } },
        { 'contactInfo.email': { $regex: search, $options: 'i' } },
        { 'name.firstName': { $regex: search, $options: 'i' } },
        { 'name.lastName': { $regex: search, $options: 'i' } },
        { 'company.name': { $regex: search, $options: 'i' } },
        { email: { $regex: search, $options: 'i' } },
        { name: { $regex: search, $options: 'i' } }
      ];
    }
    
    const customers = await req.db.collection('customers')
      .find(filter)
      .skip(skip)
      .limit(parseInt(limit))
      .sort({ createdAt: -1 })
      .toArray();
    
    const totalCount = await req.db.collection('customers').countDocuments(filter);
    
    // Get customer stats
    const stats = {
      total: await req.db.collection('customers').countDocuments({}),
      active: await req.db.collection('customers').countDocuments({ status: 'active' }),
      inactive: await req.db.collection('customers').countDocuments({ status: 'inactive' })
    };
    
    // 🔧 NORMALIZE CUSTOMER DATA - Handle both flat and nested formats
    const normalizedCustomers = customers.map(customer => {
      // Helper function to safely extract string values
      const safeString = (value, defaultValue = '') => {
        if (!value) return defaultValue;
        if (typeof value === 'string') return value;
        if (typeof value === 'object') {
          return value.name || value.value || defaultValue;
        }
        return String(value);
      };

      return {
        _id: customer._id,
        id: customer._id.toString(),
        customerId: customer.customerId || customer._id.toString(),
        
        // Handle both flat (name: "John Doe") and nested (name: {firstName, lastName})
        name: typeof customer.name === 'string' 
          ? customer.name 
          : customer.name?.firstName && customer.name?.lastName
            ? `${customer.name.firstName} ${customer.name.lastName}`.trim()
            : customer.name?.firstName || customer.name?.lastName || '',
        
        // Handle both flat (email: "john@example.com") and nested (contactInfo: {email})
        email: typeof customer.email === 'string'
          ? customer.email
          : customer.contactInfo?.email || '',
        
        // Handle both flat (phone: "1234567890") and nested (contactInfo: {phone})
        phone: typeof customer.phone === 'string'
          ? customer.phone
          : customer.contactInfo?.phone || '',
        
        // Handle company name from multiple possible locations
        companyName: customer.companyName 
          || customer.company?.name 
          || customer.name?.companyName 
          || '',
        
        department: customer.department || '',
        branch: customer.branch || '',
        employeeId: customer.employeeId || customer.customerId || '',
        status: customer.status || 'active',
        role: customer.role || 'customer',
        firebaseUid: customer.firebaseUid || null,
        clientId: customer.clientId || null,
        createdAt: customer.createdAt,
        updatedAt: customer.updatedAt,
        lastLogin: customer.lastLogin || null,
        createdBy: customer.createdBy || null,
        registrationMethod: customer.registrationMethod || null,
        assignmentType: customer.assignmentType || null
      };
    });
    
    res.json({
      success: true,
      data: normalizedCustomers,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: totalCount,
        pages: Math.ceil(totalCount / parseInt(limit))
      },
      stats
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Failed to fetch customers',
      error: error.message
    });
  }
});

// POST /api/admin/customers - Create a new customer
router.post('/', async (req, res) => {
  const session = req.db.client.startSession();
  
  try {
    const {
      customerId,
      name,
      email,
      phone,
      companyName,
      department,
      branch,
      employeeId,
      password,
      contactInfo,
      company,
      billingAddress,
      shippingAddress,
      status = 'active',
      notes
    } = req.body;
    
    // Support both flat and nested formats
    // Validate required fields - accept either flat format (name, email) or nested format (name.firstName, contactInfo.email)
    const hasFlatFormat = name && typeof name === 'string' && email;
    const hasNestedFormat = name && typeof name === 'object' && contactInfo;
    
    if (!hasFlatFormat && !hasNestedFormat) {
      return res.status(400).json({
        success: false,
        message: 'Missing required fields: name and email (or contactInfo) are required'
      });
    }
    
    await session.withTransaction(async () => {
      // Generate customerId if not provided
      const finalCustomerId = customerId || `CUST${Date.now()}`;
      
      // Check if customer with email already exists
      const existingCustomer = await req.db.collection('customers').findOne(
        { email: hasFlatFormat ? email : contactInfo?.email },
        { session }
      );
      
      if (existingCustomer) {
        throw new Error('Customer with this email already exists');
      }
      
      const now = new Date();
      
      // Support both flat and nested formats
      const customerData = hasFlatFormat ? {
        // Flat format (from CustomerService)
        customerId: finalCustomerId,
        name: name,
        email: email,
        phone: phone || '',
        companyName: companyName || '',
        department: department || '',
        branch: branch || '',
        employeeId: employeeId || finalCustomerId,
        status,
        role: 'customer',
        createdAt: now,
        updatedAt: now
      } : {
        // Nested format (legacy)
        customerId: finalCustomerId,
        name: {
          firstName: name.firstName || '',
          lastName: name.lastName || '',
          companyName: name.companyName
        },
        contactInfo: {
          email: contactInfo.email || '',
          phone: contactInfo.phone || '',
          alternatePhone: contactInfo.alternatePhone
        },
        company: company ? {
          name: company.name,
          taxId: company.taxId,
          registrationNumber: company.registrationNumber
        } : null,
        billingAddress: billingAddress ? {
          street: billingAddress.street,
          city: billingAddress.city,
          state: billingAddress.state,
          postalCode: billingAddress.postalCode,
          country: billingAddress.country
        } : null,
        shippingAddress: shippingAddress ? {
          street: shippingAddress.street,
          city: shippingAddress.city,
          state: shippingAddress.state,
          postalCode: shippingAddress.postalCode,
          country: shippingAddress.country,
          isSameAsBilling: shippingAddress.isSameAsBilling
        } : null,
        status,
        notes: notes || [],
        createdAt: now,
        updatedAt: now
      };
      
      const result = await req.db.collection('customers').insertOne(customerData, { session });
      
      if (!result.insertedId) {
        throw new Error('Failed to create customer');
      }
      
      res.status(201).json({
        success: true,
        message: 'Customer created successfully',
        data: {
          ...customerData,
          _id: result.insertedId,
          id: result.insertedId.toString()
        }
      });
    });
  } catch (error) {
    console.error('❌ Error creating customer:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to create customer'
    });
  } finally {
    await session.endSession();
  }
});


// GET /api/admin/customers/:id - Get customer by ID
router.get('/:id', async (req, res) => {
  try {
    // Build query to find customer
    let query = { customerId: req.params.id };
    
    // If the ID looks like a MongoDB ObjectId, also try to find by _id
    if (/^[0-9a-fA-F]{24}$/.test(req.params.id)) {
      query = {
        $or: [
          { customerId: req.params.id },
          { _id: new ObjectId(req.params.id) }
        ]
      };
    }
    
    const customer = await req.db.collection('customers').findOne(query);
    
    if (!customer) {
      return res.status(404).json({
        success: false,
        message: 'Customer not found'
      });
    }
    
    // 🔧 NORMALIZE CUSTOMER DATA
    const normalizedCustomer = {
      _id: customer._id,
      id: customer._id.toString(),
      customerId: customer.customerId || customer._id.toString(),
      
      name: typeof customer.name === 'string' 
        ? customer.name 
        : customer.name?.firstName && customer.name?.lastName
          ? `${customer.name.firstName} ${customer.name.lastName}`.trim()
          : customer.name?.firstName || customer.name?.lastName || '',
      
      email: typeof customer.email === 'string'
        ? customer.email
        : customer.contactInfo?.email || '',
      
      phone: typeof customer.phone === 'string'
        ? customer.phone
        : customer.contactInfo?.phone || '',
      
      companyName: customer.companyName 
        || customer.company?.name 
        || customer.name?.companyName 
        || '',
      
      department: customer.department || '',
      branch: customer.branch || '',
      employeeId: customer.employeeId || customer.customerId || '',
      status: customer.status || 'active',
      role: customer.role || 'customer',
      firebaseUid: customer.firebaseUid || null,
      clientId: customer.clientId || null,
      createdAt: customer.createdAt,
      updatedAt: customer.updatedAt,
      lastLogin: customer.lastLogin || null,
      createdBy: customer.createdBy || null,
      registrationMethod: customer.registrationMethod || null,
      assignmentType: customer.assignmentType || null
    };
    
    // Get customer's recent orders
    const recentOrders = await req.db.collection('orders')
      .find({ 'customer.customerId': normalizedCustomer.customerId })
      .sort({ createdAt: -1 })
      .limit(5)
      .toArray();
    
    // Get order statistics
    const orderStats = {
      total: await req.db.collection('orders').countDocuments({ 'customer.customerId': normalizedCustomer.customerId }),
      completed: await req.db.collection('orders').countDocuments({ 
        'customer.customerId': normalizedCustomer.customerId,
        status: 'completed' 
      }),
      inProgress: await req.db.collection('orders').countDocuments({ 
        'customer.customerId': normalizedCustomer.customerId,
        status: 'in_progress' 
      }),
      cancelled: await req.db.collection('orders').countDocuments({ 
        'customer.customerId': normalizedCustomer.customerId,
        status: 'cancelled' 
      })
    };
    
    res.json({
      success: true,
      data: {
        ...normalizedCustomer,
        stats: orderStats,
        recentOrders
      }
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Failed to fetch customer details',
      error: error.message
    });
  }
});

// PUT /api/admin/customers/:id - Update customer details
router.put('/:id', async (req, res) => {
  try {
    // Build query to find customer
    let query = { customerId: req.params.id };
    
    // If the ID looks like a MongoDB ObjectId, also try to find by _id
    if (/^[0-9a-fA-F]{24}$/.test(req.params.id)) {
      query = {
        $or: [
          { customerId: req.params.id },
          { _id: new ObjectId(req.params.id) }
        ]
      };
    }
    
    // Prepare update operations
    const updateOperations = {
      $set: {
        updatedAt: new Date()
      }
    };
    
    // Handle name updates
    if (req.body.name) {
      Object.keys(req.body.name).forEach(key => {
        updateOperations.$set[`name.${key}`] = req.body.name[key];
      });
    }
    
    // Handle contact info updates
    if (req.body.contactInfo) {
      Object.keys(req.body.contactInfo).forEach(key => {
        updateOperations.$set[`contactInfo.${key}`] = req.body.contactInfo[key];
      });
    }
    
    // Handle company updates
    if (req.body.company) {
      if (req.body.company === null) {
        updateOperations.$set.company = null;
      } else {
        if (!updateOperations.$set.company) {
          updateOperations.$set.company = {};
        }
        Object.keys(req.body.company).forEach(key => {
          updateOperations.$set[`company.${key}`] = req.body.company[key];
        });
      }
    }
    
    // Handle address updates
    if (req.body.billingAddress) {
      if (req.body.billingAddress === null) {
        updateOperations.$set.billingAddress = null;
      } else {
        if (!updateOperations.$set.billingAddress) {
          updateOperations.$set.billingAddress = {};
        }
        Object.keys(req.body.billingAddress).forEach(key => {
          updateOperations.$set[`billingAddress.${key}`] = req.body.billingAddress[key];
        });
      }
    }
    
    if (req.body.shippingAddress) {
      if (req.body.shippingAddress === null) {
        updateOperations.$set.shippingAddress = null;
      } else {
        if (!updateOperations.$set.shippingAddress) {
          updateOperations.$set.shippingAddress = {};
        }
        Object.keys(req.body.shippingAddress).forEach(key => {
          updateOperations.$set[`shippingAddress.${key}`] = req.body.shippingAddress[key];
        });
      }
    }
    
    // Handle direct field updates
    const directFields = ['status'];
    directFields.forEach(field => {
      if (req.body[field] !== undefined) {
        updateOperations.$set[field] = req.body[field];
      }
    });
    
    // Handle notes (append to existing notes)
    if (req.body.note) {
      updateOperations.$push = {
        notes: {
          content: req.body.note,
          createdAt: new Date(),
          createdBy: req.user?.userId || 'system'
        }
      };
    }
    
    // Perform the update
    const result = await req.db.collection('customers').updateOne(
      query,
      updateOperations
    );
    
    if (result.matchedCount === 0) {
      return res.status(404).json({
        success: false,
        message: 'Customer not found'
      });
    }
    
    // Get updated customer data
    const updatedCustomer = await req.db.collection('customers').findOne(query);
    
    res.json({
      success: true,
      message: 'Customer updated successfully',
      data: updatedCustomer
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Failed to update customer',
      error: error.message
    });
  }
});

// DELETE /api/admin/customers/:id - Delete a customer
router.delete('/:id', async (req, res) => {
  const session = req.db.client.startSession();
  
  try {
    await session.withTransaction(async () => {
      // Build query to find customer
      let query = { customerId: req.params.id };
      
      // If the ID looks like a MongoDB ObjectId, also try to find by _id
      if (/^[0-9a-fA-F]{24}$/.test(req.params.id)) {
        query = {
          $or: [
            { customerId: req.params.id },
            { _id: new ObjectId(req.params.id) }
          ]
        };
      }
      
      // Check if customer has any active orders
      const activeOrders = await req.db.collection('orders').findOne(
        { 
          'customer.customerId': req.params.id,
          status: { $in: ['pending', 'in_progress', 'shipped'] }
        },
        { session }
      );
      
      if (activeOrders) {
        throw new Error('Cannot delete customer with active or pending orders');
      }
      
      // Soft delete the customer
      const result = await req.db.collection('customers').updateOne(
        query,
        { 
          $set: { 
            status: 'deleted',
            deletedAt: new Date(),
            deletedBy: req.user?.userId || 'system'
          } 
        },
        { session }
      );
      
      if (result.matchedCount === 0) {
        throw new Error('Customer not found');
      }
      
      res.json({
        success: true,
        message: 'Customer deleted successfully'
      });
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Failed to delete customer',
      error: error.message
    });
  } finally {
    await session.endSession();
  }
});

// GET /api/admin/customers/:id/orders - Get customer's orders
router.get('/:id/orders', async (req, res) => {
  try {
    const { page = 1, limit = 10, status, startDate, endDate } = req.query;
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    // Find the customer to get the customerId
    let query = { customerId: req.params.id };
    
    // If the ID looks like a MongoDB ObjectId, also try to find by _id
    if (/^[0-9a-fA-F]{24}$/.test(req.params.id)) {
      query = {
        $or: [
          { customerId: req.params.id },
          { _id: new ObjectId(req.params.id) }
        ]
      };
    }
    
    const customer = await req.db.collection('customers').findOne(query);
    
    if (!customer) {
      return res.status(404).json({
        success: false,
        message: 'Customer not found'
      });
    }
    
    // Build orders query
    const ordersQuery = { 'customer.customerId': customer.customerId };
    
    if (status) {
      ordersQuery.status = status;
    }
    
    if (startDate || endDate) {
      ordersQuery.createdAt = {};
      if (startDate) ordersQuery.createdAt.$gte = new Date(startDate);
      if (endDate) ordersQuery.createdAt.$lte = new Date(endDate);
    }
    
    // Get orders with pagination
    const orders = await req.db.collection('orders')
      .find(ordersQuery)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .toArray();
    
    const totalOrders = await req.db.collection('orders').countDocuments(ordersQuery);
    
    // Get order statistics
    const stats = {
      total: totalOrders,
      completed: await req.db.collection('orders').countDocuments({ 
        ...ordersQuery, 
        status: 'completed' 
      }),
      inProgress: await req.db.collection('orders').countDocuments({ 
        ...ordersQuery, 
        status: 'in_progress' 
      }),
      cancelled: await req.db.collection('orders').countDocuments({ 
        ...ordersQuery, 
        status: 'cancelled' 
      })
    };
    
    res.json({
      success: true,
      data: orders,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: totalOrders,
        pages: Math.ceil(totalOrders / parseInt(limit))
      },
      stats
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Failed to fetch customer orders',
      error: error.message
    });
  }
});

/**
 * @swagger
 * /api/admin/customers/{id}/trips:
 *   get:
 *     summary: Get trips for a specific customer
 *     tags: [Customers]
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         schema:
 *           type: string
 *         description: Customer ID or customerId
 *       - in: query
 *         name: status
 *         schema:
 *           type: string
 *           enum: [scheduled, in_progress, completed, cancelled]
 *         description: Filter trips by status
 *       - in: query
 *         name: startDate
 *         schema:
 *           type: string
 *           format: date
 *         description: Filter trips after this date (ISO format)
 *       - in: query
 *         name: endDate
 *         schema:
 *           type: string
 *           format: date
 *         description: Filter trips before this date (ISO format)
 *       - in: query
 *         name: page
 *         schema:
 *           type: integer
 *           default: 1
 *         description: Page number for pagination
 *       - in: query
 *         name: limit
 *         schema:
 *           type: integer
 *           default: 10
 *           maximum: 100
 *         description: Number of items per page
 *     responses:
 *       200:
 *         description: List of customer trips
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success:
 *                   type: boolean
 *                 data:
 *                   type: array
 *                   items:
 *                     $ref: '#/components/schemas/Trip'
 *                 pagination:
 *                   $ref: '#/components/schemas/Pagination'
 *                 stats:
 *                   type: object
 *                   properties:
 *                     total:
 *                       type: integer
 *                     completed:
 *                       type: integer
 *                     inProgress:
 *                       type: integer
 *                     cancelled:
 *                       type: integer
 *       404:
 *         $ref: '#/components/responses/NotFound'
 *       500:
 *         $ref: '#/components/responses/ServerError'
 */
router.get('/:id/trips', async (req, res) => {
  const session = client.startSession();
  try {
    const { id } = req.params;
    const { 
      status, 
      startDate, 
      endDate, 
      page = 1, 
      limit = 10 
    } = req.query;

    const pageNum = parseInt(page, 10) || 1;
    const limitNum = Math.min(parseInt(limit, 10) || 10, 100);
    const skip = (pageNum - 1) * limitNum;

    // Build query
    const query = {
      $or: [
        { _id: id },
        { customerId: id }
      ]
    };

    // Find customer
    const customer = await req.db.collection('customers').findOne(query, { session });
    if (!customer) {
      return res.status(404).json({ 
        success: false, 
        message: 'Customer not found' 
      });
    }

    // Build trips query
    const tripsQuery = { 'customer.customerId': customer.customerId };
    
    // Apply status filter
    if (status) {
      tripsQuery.status = status;
    }

    // Apply date range filter
    if (startDate || endDate) {
      tripsQuery.startTime = {};
      if (startDate) {
        tripsQuery.startTime.$gte = new Date(startDate);
      }
      if (endDate) {
        tripsQuery.startTime.$lte = new Date(endDate);
      }
    }

    // Get total count for pagination
    const total = await req.db.collection('trips').countDocuments(tripsQuery);
    
    // Get paginated trips
    const trips = await req.db.collection('trips')
      .find(tripsQuery)
      .sort({ startTime: -1 })
      .skip(skip)
      .limit(limitNum)
      .toArray();

    // Calculate trip statistics
    const stats = {
      total: await req.db.collection('trips').countDocuments({ 'customer.customerId': customer.customerId }),
      completed: await req.db.collection('trips').countDocuments({ 
        'customer.customerId': customer.customerId, 
        status: 'completed' 
      }),
      inProgress: await req.db.collection('trips').countDocuments({ 
        'customer.customerId': customer.customerId, 
        status: 'in_progress' 
      }),
      cancelled: await req.db.collection('trips').countDocuments({ 
        'customer.customerId': customer.customerId, 
        status: 'cancelled' 
      })
    };

    res.json({
      success: true,
      data: trips,
      pagination: {
        page: pageNum,
        limit: limitNum,
        total,
        pages: Math.ceil(total / limitNum)
      },
      stats
    });
  } catch (error) {
    console.error('Error getting customer trips:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to get customer trips',
      error: error.message 
    });
  } finally {
    await session.endSession();
  }
});

module.exports = router;
