// routes/admin-clients-unified-test.js
// COMPLETE CLIENT MANAGEMENT ROUTES - MongoDB ONLY (NO FIREBASE)
const express = require('express');
const router = express.Router();
const bcrypt = require('bcrypt');
const { ObjectId } = require('mongodb');

// Middleware to ensure database connection
router.use((req, res, next) => {
  if (!req.db) {
    return res.status(500).json({
      success: false,
      message: 'Database connection not available'
    });
  }
  next();
});

// ==================== GET ALL CLIENTS ====================
// @route   GET /api/admin/clients/unified
// @desc    Fetch all clients with pagination, filtering, and search
// @access  Private (Admin)
router.get('/', async (req, res) => {
  try {
    console.log('📥 GET /api/admin/clients/unified - Fetching all clients');
    
    // Extract query parameters
    const {
      page = 1,
      limit = 50,
      status,
      search,
      organization,
      sortBy = 'createdAt',
      sortOrder = 'desc'
    } = req.query;

    const pageNum = parseInt(page);
    const limitNum = parseInt(limit);
    const skip = (pageNum - 1) * limitNum;

    // Build query filter
    const filter = {};

    // Status filter
    if (status && status !== 'all') {
      filter.status = status;
    }

    // Organization filter
    if (organization) {
      filter.$or = [
        { organizationName: { $regex: organization, $options: 'i' } },
        { companyName: { $regex: organization, $options: 'i' } }
      ];
    }

    // Search filter (name, email, phone, or clientId)
    if (search) {
      filter.$or = [
        { name: { $regex: search, $options: 'i' } },
        { email: { $regex: search, $options: 'i' } },
        { phone: { $regex: search, $options: 'i' } },
        { contactPerson: { $regex: search, $options: 'i' } },
        { organizationName: { $regex: search, $options: 'i' } },
        { companyName: { $regex: search, $options: 'i' } }
      ];
    }

    console.log('🔍 Query filter:', JSON.stringify(filter));

    // Count total documents matching filter
    const totalCount = await req.db.collection('clients').countDocuments(filter);

    // Build sort object
    const sort = {};
    sort[sortBy] = sortOrder === 'asc' ? 1 : -1;

    // Fetch clients with pagination
    const clients = await req.db.collection('clients')
      .find(filter)
      .sort(sort)
      .skip(skip)
      .limit(limitNum)
      .toArray();

    // Calculate summary statistics
    const activeCount = await req.db.collection('clients')
      .countDocuments({ status: 'active' });
    const inactiveCount = await req.db.collection('clients')
      .countDocuments({ status: 'inactive' });
    const suspendedCount = await req.db.collection('clients')
      .countDocuments({ status: 'suspended' });

    console.log(`✅ Found ${clients.length} clients (Page ${pageNum}/${Math.ceil(totalCount / limitNum)})`);

    res.json({
      success: true,
      data: clients,
      pagination: {
        currentPage: pageNum,
        totalPages: Math.ceil(totalCount / limitNum),
        totalCount: totalCount,
        limit: limitNum,
        hasNextPage: pageNum < Math.ceil(totalCount / limitNum),
        hasPrevPage: pageNum > 1
      },
      summary: {
        total: totalCount,
        active: activeCount,
        inactive: inactiveCount,
        suspended: suspendedCount
      }
    });

  } catch (error) {
    console.error('❌ Error fetching clients:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch clients',
      error: error.message
    });
  }
});

// ==================== GET SINGLE CLIENT ====================
// @route   GET /api/admin/clients/unified/:id
// @desc    Get a single client by ID
// @access  Private (Admin/Client)
router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log(`📥 GET /api/admin/clients/unified/${id} - Fetching client`);

    // Try to find by _id or custom clientId
    let client;
    if (ObjectId.isValid(id)) {
      client = await req.db.collection('clients').findOne({ _id: new ObjectId(id) });
    }
    
    if (!client) {
      client = await req.db.collection('clients').findOne({ clientId: id });
    }

    if (!client) {
      console.log(`⚠️ Client not found: ${id}`);
      return res.status(404).json({
        success: false,
        message: 'Client not found'
      });
    }

    console.log(`✅ Client found: ${client.name}`);

    res.json({
      success: true,
      data: client
    });

  } catch (error) {
    console.error('❌ Error fetching client:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch client',
      error: error.message
    });
  }
});

// ==================== CREATE CLIENT ====================
// @route   POST /api/admin/clients/unified
// @desc    Create a new client (MongoDB ONLY - NO FIREBASE)
// @access  Private (Admin)
router.post('/', async (req, res) => {
  console.log('\n🏢 ========== CLIENT CREATION STARTED (MongoDB ONLY) ==========');
  console.log('📥 Request body:', JSON.stringify(req.body, null, 2));
  
  try {
    const {
      email,
      name,
      password,
      phone,
      phoneNumber,
      address,
      contactPerson,
      branch,
      organizationName,
      companyName,
      gstNumber,
      panNumber,
      status = 'active',
      role = 'client'
    } = req.body;
    
    console.log('✅ Request data extracted successfully');
    console.log('   - Email:', email);
    console.log('   - Name:', name);
    console.log('   - Organization:', organizationName || companyName || name);
    
    // Validate required fields
    if (!email || !name) {
      console.error('❌ Validation failed - Missing required fields');
      return res.status(400).json({
        success: false,
        message: 'Email and name are required'
      });
    }

    if (!password || password.length < 6) {
      console.error('❌ Validation failed - Password must be at least 6 characters');
      return res.status(400).json({
        success: false,
        message: 'Password must be at least 6 characters'
      });
    }
    
    console.log('✅ All required fields validated');
    
    // Check if client already exists
    console.log('🔍 Checking for existing client...');
    const existingClient = await req.db.collection('clients').findOne({
      email: email.toLowerCase()
    });
    
    if (existingClient) {
      console.error('❌ Client already exists:', email);
      return res.status(409).json({
        success: false,
        message: 'Client with this email already exists'
      });
    }
    
    console.log('✅ No duplicate client found');
    
    // Hash password
    console.log('🔐 Hashing password...');
    const hashedPassword = await bcrypt.hash(password, 10);
    console.log('✅ Password hashed successfully');
    
    // Generate unique client ID
    const clientId = `CLIENT_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    
    // Create client document
    console.log('\n💾 ========== MONGODB CLIENT CREATION ==========');
    const newClient = {
      clientId: clientId,
      email: email.toLowerCase(),
      name: name,
      password: hashedPassword,
      role: role,
      phone: phone || phoneNumber || '',
      phoneNumber: phone || phoneNumber || '',
      address: address || '',
      contactPerson: contactPerson || '',
      branch: branch || '',
      organizationName: organizationName || companyName || name,
      companyName: companyName || organizationName || name,
      gstNumber: gstNumber || '',
      panNumber: panNumber || '',
      status: status,
      totalCustomers: 0,
      isActive: status === 'active',
      createdAt: new Date(),
      updatedAt: new Date(),
      lastActive: new Date()
    };
    
    console.log('💾 Inserting client into clients collection...');
    const result = await req.db.collection('clients').insertOne(newClient);
    console.log('✅ Client inserted successfully');
    console.log('   - MongoDB _id:', result.insertedId);
    console.log('   - Client ID:', clientId);
    console.log('   - Role:', role);
    
    console.log('✅ Client creation completed successfully');
    console.log('========== CLIENT CREATION COMPLETE ==========\n');
    
    // Return created client (without password)
    const { password: _, ...clientWithoutPassword } = newClient;
    
    res.status(201).json({
      success: true,
      message: 'Client created successfully',
      data: { 
        ...clientWithoutPassword, 
        _id: result.insertedId,
        id: result.insertedId.toString()
      }
    });
    
  } catch (error) {
    console.error('\n❌ ========== CLIENT CREATION FAILED ==========');
    console.error('Error:', error.message);
    console.error('Stack:', error.stack);
    console.error('========== ERROR END ==========\n');
    
    res.status(500).json({
      success: false,
      message: 'Failed to create client',
      error: error.message
    });
  }
});

// ==================== UPDATE CLIENT ====================
// @route   PUT /api/admin/clients/unified/:id
// @desc    Update client information
// @access  Private (Admin)
router.put('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log(`🔄 PUT /api/admin/clients/unified/${id} - Updating client`);
    console.log('📥 Update data:', JSON.stringify(req.body, null, 2));

    // Prepare update data (exclude sensitive fields)
    const updateData = { ...req.body };
    delete updateData._id;
    delete updateData.email; // Email cannot be changed
    delete updateData.password; // Password updated separately
    delete updateData.clientId;
    delete updateData.createdAt;
    
    updateData.updatedAt = new Date();

    // Find and update client
    let result;
    if (ObjectId.isValid(id)) {
      result = await req.db.collection('clients').findOneAndUpdate(
        { _id: new ObjectId(id) },
        { $set: updateData },
        { returnDocument: 'after' }
      );
    } else {
      result = await req.db.collection('clients').findOneAndUpdate(
        { clientId: id },
        { $set: updateData },
        { returnDocument: 'after' }
      );
    }

    if (!result.value) {
      console.log(`⚠️ Client not found: ${id}`);
      return res.status(404).json({
        success: false,
        message: 'Client not found'
      });
    }

    console.log(`✅ Client updated successfully: ${result.value.name}`);

    // Remove password from response
    const { password, ...clientWithoutPassword } = result.value;

    res.json({
      success: true,
      message: 'Client updated successfully',
      data: clientWithoutPassword
    });

  } catch (error) {
    console.error('❌ Error updating client:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update client',
      error: error.message
    });
  }
});

// ==================== DELETE CLIENT ====================
// @route   DELETE /api/admin/clients/unified/:id
// @desc    Delete a client
// @access  Private (Admin)
router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log(`🗑️ DELETE /api/admin/clients/unified/${id} - Deleting client`);

    // Find and delete client
    let result;
    if (ObjectId.isValid(id)) {
      result = await req.db.collection('clients').findOneAndDelete(
        { _id: new ObjectId(id) }
      );
    } else {
      result = await req.db.collection('clients').findOneAndDelete(
        { clientId: id }
      );
    }

    if (!result.value) {
      console.log(`⚠️ Client not found: ${id}`);
      return res.status(404).json({
        success: false,
        message: 'Client not found'
      });
    }

    console.log(`✅ Client deleted successfully: ${result.value.name}`);

    res.json({
      success: true,
      message: 'Client deleted successfully',
      data: { deletedId: id }
    });

  } catch (error) {
    console.error('❌ Error deleting client:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete client',
      error: error.message
    });
  }
});

// ==================== GET CLIENT CUSTOMERS ====================
// @route   GET /api/admin/clients/unified/:id/customers
// @desc    Get all customers for a specific client
// @access  Private (Admin/Client)
router.get('/:clientId/customers', async (req, res) => {
  try {
    const { clientId } = req.params;
    console.log(`📥 GET /api/admin/clients/unified/${clientId}/customers`);

    // Get client info
    let client;
    if (ObjectId.isValid(clientId)) {
      client = await req.db.collection('clients').findOne({ _id: new ObjectId(clientId) });
    } else {
      client = await req.db.collection('clients').findOne({ clientId: clientId });
    }

    if (!client) {
      return res.status(404).json({
        success: false,
        message: 'Client not found'
      });
    }

    const clientEmail = client.email || '';
    const clientName = client.name || '';
    const clientDomain = clientEmail.includes('@') ? clientEmail.split('@')[1] : '';

    // Get all customers from MongoDB
    const allCustomers = await req.db.collection('users')
      .find({ role: 'customer' })
      .toArray();

    console.log(`📊 Total customers in database: ${allCustomers.length}`);

    // Categorize customers
    const explicitlyAssigned = [];
    const domainMatched = [];
    const companyMatched = [];
    const allClientCustomers = [];

    for (const customer of allCustomers) {
      let addedToCategory = false;

      // Category 1: Explicitly assigned to this client
      const customerClientId = customer.clientId || customer.client_id;
      if (customerClientId === clientId || customerClientId === client._id?.toString()) {
        explicitlyAssigned.push(customer);
        allClientCustomers.push({ ...customer, assignmentType: 'explicit' });
        addedToCategory = true;
      }

      // Category 2: Domain matching
      if (!addedToCategory && clientDomain && customer.email && customer.email.includes('@')) {
        const customerDomain = customer.email.split('@')[1];
        if (customerDomain && customerDomain.toLowerCase() === clientDomain.toLowerCase()) {
          domainMatched.push(customer);
          allClientCustomers.push({ ...customer, assignmentType: 'domain' });
          addedToCategory = true;
        }
      }

      // Category 3: Company name matching
      if (!addedToCategory && customer.companyName && clientName) {
        const customerCompany = customer.companyName.toLowerCase();
        const clientNameLower = clientName.toLowerCase();
        if (customerCompany.includes(clientNameLower) || clientNameLower.includes(customerCompany)) {
          companyMatched.push(customer);
          allClientCustomers.push({ ...customer, assignmentType: 'company' });
        }
      }
    }

    console.log(`📊 Client: ${clientName}`);
    console.log(`   Explicitly assigned: ${explicitlyAssigned.length}`);
    console.log(`   Domain matched (@${clientDomain}): ${domainMatched.length}`);
    console.log(`   Company matched: ${companyMatched.length}`);
    console.log(`   Total: ${allClientCustomers.length}`);

    res.json({
      success: true,
      customers: allClientCustomers,
      totalCount: allClientCustomers.length,
      categories: {
        explicitlyAssigned: {
          customers: explicitlyAssigned,
          count: explicitlyAssigned.length,
          description: 'Customers explicitly assigned to this client'
        },
        domainMatched: {
          customers: domainMatched,
          count: domainMatched.length,
          description: `Employees with @${clientDomain} email domain`,
          domain: clientDomain
        },
        companyMatched: {
          customers: companyMatched,
          count: companyMatched.length,
          description: 'Customers matched by company name'
        }
      },
      clientInfo: {
        name: clientName,
        email: clientEmail,
        domain: clientDomain
      }
    });

  } catch (error) {
    console.error('❌ Error fetching client customers:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch client customers',
      error: error.message
    });
  }
});

// ==================== SYNC CUSTOMER COUNTS ====================
// @route   POST /api/admin/clients/unified/sync-customer-counts
// @desc    Sync customer counts for all clients
// @access  Private (Admin)
router.post('/sync-customer-counts', async (req, res) => {
  try {
    console.log('🔄 Syncing customer counts for all clients...');

    // Get all clients
    const clients = await req.db.collection('clients').find({}).toArray();

    if (clients.length === 0) {
      return res.json({
        success: true,
        message: 'No clients found',
        updated: 0
      });
    }

    // Get all customers
    const allCustomers = await req.db.collection('users')
      .find({ role: 'customer' })
      .toArray();

    console.log(`📊 Total customers found: ${allCustomers.length}`);

    let totalUpdated = 0;

    // For each client, count customers
    for (const client of clients) {
      const clientId = client._id.toString();
      const clientEmail = client.email || '';
      const clientName = client.name || '';
      const clientDomain = clientEmail.includes('@') ? clientEmail.split('@')[1] : '';

      let customerCount = 0;

      for (const customer of allCustomers) {
        // Check explicit assignment
        const customerClientId = customer.clientId || customer.client_id;
        if (customerClientId === clientId || customerClientId === client.clientId) {
          customerCount++;
          continue;
        }

        // Check domain matching
        if (clientDomain && customer.email && customer.email.includes('@')) {
          const customerDomain = customer.email.split('@')[1];
          if (customerDomain && customerDomain.toLowerCase() === clientDomain.toLowerCase()) {
            customerCount++;
            continue;
          }
        }

        // Check company matching
        if (customer.companyName && clientName) {
          const customerCompany = customer.companyName.toLowerCase();
          const clientNameLower = clientName.toLowerCase();
          if (customerCompany.includes(clientNameLower) || clientNameLower.includes(customerCompany)) {
            customerCount++;
          }
        }
      }

      // Update client's totalCustomers field
      await req.db.collection('clients').updateOne(
        { _id: client._id },
        { $set: { totalCustomers: customerCount, updatedAt: new Date() } }
      );

      console.log(`   Client: ${clientName} → ${customerCount} customers`);
      totalUpdated++;
    }

    console.log(`✅ Updated ${totalUpdated} clients with customer counts`);

    res.json({
      success: true,
      message: `Successfully synced customer counts for ${totalUpdated} clients`,
      updated: totalUpdated,
      totalCustomers: allCustomers.length
    });

  } catch (error) {
    console.error('❌ Error syncing customer counts:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to sync customer counts',
      error: error.message
    });
  }
});

// ==================== SEARCH CLIENTS ====================
// @route   GET /api/admin/clients/unified/search
// @desc    Search clients by query
// @access  Private (Admin)
router.get('/search', async (req, res) => {
  try {
    const { q, limit = 20 } = req.query;
    
    if (!q) {
      return res.status(400).json({
        success: false,
        message: 'Search query is required'
      });
    }

    console.log(`🔍 Searching clients: "${q}"`);

    const clients = await req.db.collection('clients')
      .find({
        $or: [
          { name: { $regex: q, $options: 'i' } },
          { email: { $regex: q, $options: 'i' } },
          { phone: { $regex: q, $options: 'i' } },
          { contactPerson: { $regex: q, $options: 'i' } },
          { organizationName: { $regex: q, $options: 'i' } },
          { companyName: { $regex: q, $options: 'i' } }
        ]
      })
      .limit(parseInt(limit))
      .toArray();

    console.log(`✅ Found ${clients.length} matching clients`);

    res.json({
      success: true,
      data: clients,
      count: clients.length
    });

  } catch (error) {
    console.error('❌ Error searching clients:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to search clients',
      error: error.message
    });
  }
});

module.exports = router;