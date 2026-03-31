// routes/admin-clients-unified.js - UNIFIED CLIENT API (MongoDB + Firestore Sync)
const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');


// Middleware to attach database
router.use((req, res, next) => {
  if (!req.db) {
    return res.status(500).json({ msg: 'Database connection not available' });
  }
  next();
});

/**
 * GET /api/admin/clients/unified - Get all clients from MongoDB (unified source)
 * Supports filtering, pagination, and search
 */
router.get('/', async (req, res) => {
  try {
    console.log('\n🏢 FETCHING ALL CLIENTS (UNIFIED)');
    console.log('─'.repeat(80));
    
    const {
      page = 1,
      limit = 50,
      status,
      search,
      organization,
      fullDetails = false
    } = req.query;

    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    // Build filter
    const filter = {};
    
    if (status && status !== 'All') {
      filter.status = status.toLowerCase();
    }
    
    if (organization && organization !== 'All Organizations') {
      filter.$or = [
        { companyName: { $regex: organization, $options: 'i' } },
        { organizationName: { $regex: organization, $options: 'i' } }
      ];
    }
    
    if (search) {
      filter.$or = [
        { name: { $regex: search, $options: 'i' } },
        { email: { $regex: search, $options: 'i' } },
        { clientId: { $regex: search, $options: 'i' } },
        { phone: { $regex: search, $options: 'i' } }
      ];
    }

    console.log('🔍 Filter:', JSON.stringify(filter, null, 2));

    // Get clients from MongoDB (primary source)
    const clients = await req.db.collection('clients')
      .find(filter)
      .skip(skip)
      .limit(parseInt(limit))
      .sort({ createdAt: -1 })
      .toArray();

    const totalCount = await req.db.collection('clients').countDocuments(filter);

    console.log(`✅ Found ${clients.length} clients (${totalCount} total)`);

    // Format response
    const formattedClients = clients.map(client => ({
      id: client._id.toString(),
      clientId: client.clientId || client._id.toString(),
      name: client.name,
      email: client.email,
      phone: client.phone || '',
      companyName: client.companyName || client.organizationName || '',
      organizationName: client.organizationName || client.companyName || '',
      status: client.status || 'active',
      role: 'client',
      firebaseUid: client.firebaseUid || null,
      totalCustomers: client.totalCustomers || 0,
      createdAt: client.createdAt,
      updatedAt: client.updatedAt,
      lastLogin: client.lastLogin
    }));

    res.json({
      success: true,
      data: formattedClients,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: totalCount,
        pages: Math.ceil(totalCount / parseInt(limit))
      },
      summary: {
        total: totalCount,
        active: await req.db.collection('clients').countDocuments({ status: 'active' }),
        inactive: await req.db.collection('clients').countDocuments({ status: 'inactive' }),
        pending: await req.db.collection('clients').countDocuments({ status: 'pending' })
      }
    });

  } catch (error) {
    console.error('❌ Error fetching clients:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch clients',
      message: error.message
    });
  }
});

/**
 * POST /api/admin/clients/unified - Create new client (MongoDB + Firebase sync)
 */
router.post('/', async (req, res) => {
  try {
    console.log('\n➕ CREATING NEW CLIENT (UNIFIED)');
    console.log('─'.repeat(80));
    
    const {
      name,
      email,
      phone,
      companyName,
      organizationName,
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

    // Check if client already exists
    const existingClient = await req.db.collection('clients').findOne({
      email: email.toLowerCase()
    });

    if (existingClient) {
      return res.status(409).json({
        success: false,
        error: 'Client already exists',
        message: 'A client with this email already exists'
      });
    }

    let firebaseUid = null;

    // 🔥 CREATE FIREBASE AUTH USER
    console.log('🔐 Creating Firebase Auth user for:', email);
    try {
      // Generate a temporary password if not provided
      const tempPassword = password || Math.random().toString(36).slice(-12) + 'Aa1!';
      
      // Create Firebase Auth user
      const firebaseUser = await admin.auth().createUser({
        email: email.toLowerCase(),
        emailVerified: false,
        password: tempPassword,
        displayName: name,
        disabled: false
      });
      
      firebaseUid = firebaseUser.uid;
      console.log('✅ Firebase user created successfully');
      console.log('   - Firebase UID:', firebaseUid);
      
      // Set custom claims for client role
      await admin.auth().setCustomUserClaims(firebaseUid, {
        role: 'client'
      });
      console.log('✅ Custom claims set: role=client');
      
    } catch (firebaseError) {
      console.error('❌ Firebase user creation failed:', firebaseError.message);
      
      // If Firebase user already exists, try to get the existing user
      if (firebaseError.code === 'auth/email-already-exists') {
        console.log('⚠️  Firebase user already exists, fetching existing user...');
        try {
          const existingFirebaseUser = await admin.auth().getUserByEmail(email);
          firebaseUid = existingFirebaseUser.uid;
          console.log('✅ Using existing Firebase UID:', firebaseUid);
        } catch (fetchError) {
          console.error('❌ Failed to fetch existing Firebase user:', fetchError.message);
          return res.status(500).json({
            success: false,
            message: 'Email already registered in Firebase but cannot retrieve user details'
          });
        }
      } else {
        return res.status(500).json({
          success: false,
          message: `Failed to create Firebase user: ${firebaseError.message}`
        });
      }
    }

    // 💾 CREATE CLIENT RECORD IN CLIENTS COLLECTION
    console.log('💾 Creating client in clients collection...');
    const newClient = {
      clientId: `CLIENT${Date.now()}`,
      name: name.trim(),
      email: email.toLowerCase().trim(),
      phone: phone?.trim() || '',
      companyName: companyName?.trim() || organizationName?.trim() || '',
      organizationName: organizationName?.trim() || companyName?.trim() || '',
      status: status.toLowerCase(),
      role: 'client',
      firebaseUid,
      totalCustomers: 0,
      createdAt: new Date(),
      updatedAt: new Date(),
      createdBy: req.user?.uid || 'system'
    };

    const result = await req.db.collection('clients').insertOne(newClient);
    console.log('✅ Client created in MongoDB:', result.insertedId);

    // Update Firebase custom claims with clientId
    if (firebaseUid) {
      await admin.auth().setCustomUserClaims(firebaseUid, {
        role: 'client',
        clientId: result.insertedId.toString()
      });
    }

    // 🔄 SYNC TO FIRESTORE FOR COMPATIBILITY
    if (firebaseUid) {
      try {
        await admin.firestore().collection('users').doc(firebaseUid).set({
          name,
          email: email.toLowerCase(),
          phone: phone || '',
          companyName: companyName || organizationName || '',
          organizationName: organizationName || companyName || '',
          role: 'client',
          status: status.toLowerCase(),
          clientId: result.insertedId.toString(),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        console.log('✅ Client synced to Firestore');
      } catch (firestoreError) {
        console.warn('⚠️ Firestore sync failed:', firestoreError.message);
      }
    }

    // Also store in Firebase Realtime Database (for compatibility with existing client system)
    try {
      const clientRef = admin.database().ref('clients').push();
      await clientRef.set({
        email: email.toLowerCase(),
        name: name,
        organizationName: organizationName || companyName || '',
        companyName: companyName || organizationName || '',
        phoneNumber: phone || '',
        totalCustomers: 0,
        createdAt: new Date().toISOString()
      });
      console.log('✅ Client also synced to Firebase Realtime Database');
    } catch (realtimeDbError) {
      console.error('⚠️  Failed to sync to Realtime DB:', realtimeDbError.message);
      // Don't fail the request
    }

    console.log('✅ Client creation completed successfully');

    res.status(201).json({
      success: true,
      message: 'Client created successfully',
      data: {
        id: result.insertedId.toString(),
        clientId: newClient.clientId,
        firebaseUid,
        ...newClient
      }
    });

  } catch (error) {
    console.error('❌ Error creating client:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to create client',
      message: error.message
    });
  }
});

/**
 * GET /api/admin/clients/unified/:id - Get client by ID
 */
router.get('/:id', async (req, res) => {
  try {
    const clientId = req.params.id;
    
    let query = { clientId };
    
    // If ID looks like MongoDB ObjectId, also search by _id
    if (/^[0-9a-fA-F]{24}$/.test(clientId)) {
      query = {
        $or: [
          { clientId },
          { _id: new ObjectId(clientId) }
        ]
      };
    }

    const client = await req.db.collection('clients').findOne(query);

    if (!client) {
      return res.status(404).json({
        success: false,
        error: 'Client not found'
      });
    }

    res.json({
      success: true,
      data: {
        id: client._id.toString(),
        clientId: client.clientId,
        ...client
      }
    });

  } catch (error) {
    console.error('❌ Error fetching client:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch client',
      message: error.message
    });
  }
});

/**
 * PUT /api/admin/clients/unified/:id - Update client
 */
router.put('/:id', async (req, res) => {
  try {
    const clientId = req.params.id;
    const updateData = { ...req.body };
    
    // Remove fields that shouldn't be updated directly
    delete updateData._id;
    delete updateData.createdAt;
    delete updateData.createdBy;
    
    updateData.updatedAt = new Date();

    let query = { clientId };
    if (/^[0-9a-fA-F]{24}$/.test(clientId)) {
      query = {
        $or: [
          { clientId },
          { _id: new ObjectId(clientId) }
        ]
      };
    }

    const result = await req.db.collection('clients').updateOne(
      query,
      { $set: updateData }
    );

    if (result.matchedCount === 0) {
      return res.status(404).json({
        success: false,
        error: 'Client not found'
      });
    }

    // Get updated client
    const updatedClient = await req.db.collection('clients').findOne(query);

    // Sync to Firestore if firebaseUid exists
    if (updatedClient.firebaseUid) {
      try {
        await admin.firestore().collection('users').doc(updatedClient.firebaseUid).update({
          ...updateData,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        console.log('✅ Client synced to Firestore');
      } catch (firestoreError) {
        console.warn('⚠️ Firestore sync failed:', firestoreError.message);
      }
    }

    res.json({
      success: true,
      message: 'Client updated successfully',
      data: updatedClient
    });

  } catch (error) {
    console.error('❌ Error updating client:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to update client',
      message: error.message
    });
  }
});

/**
 * DELETE /api/admin/clients/unified/:id - Delete client (soft delete)
 */
router.delete('/:id', async (req, res) => {
  try {
    const clientId = req.params.id;

    let query = { clientId };
    if (/^[0-9a-fA-F]{24}$/.test(clientId)) {
      query = {
        $or: [
          { clientId },
          { _id: new ObjectId(clientId) }
        ]
      };
    }

    // Soft delete by updating status
    const result = await req.db.collection('clients').updateOne(
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
        error: 'Client not found'
      });
    }

    res.json({
      success: true,
      message: 'Client deleted successfully'
    });

  } catch (error) {
    console.error('❌ Error deleting client:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete client',
      message: error.message
    });
  }
});

/**
 * GET /api/admin/clients/unified/:clientId/customers - Get all customers for a specific client
 */
router.get('/:clientId/customers', async (req, res) => {
  try {
    const { clientId } = req.params;
    
    // Get client info from MongoDB
    const client = await req.db.collection('clients').findOne({
      $or: [
        { clientId },
        { _id: /^[0-9a-fA-F]{24}$/.test(clientId) ? new ObjectId(clientId) : null }
      ].filter(Boolean)
    });
    
    if (!client) {
      return res.status(404).json({
        success: false,
        message: 'Client not found'
      });
    }
    
    const clientEmail = client.email || '';
    const clientName = client.name || '';
    
    // Extract domain from client email (e.g., @infosys.com)
    const clientDomain = clientEmail.includes('@') ? clientEmail.split('@')[1] : '';
    
    // Get customers from MongoDB customers collection
    const customers = await req.db.collection('customers')
      .find({ status: { $ne: 'deleted' } })
      .toArray();
    
    // Categorize customers for this client
    const explicitlyAssigned = [];
    const domainMatched = [];
    const companyMatched = [];
    const allClientCustomers = [];
    
    for (const customer of customers) {
      let addedToCategory = false;
      
      // Category 1: Explicitly assigned to this client
      if (customer.clientId === clientId || customer.clientId === client._id.toString()) {
        explicitlyAssigned.push(customer);
        allClientCustomers.push({...customer, assignmentType: 'explicit'});
        addedToCategory = true;
      }
      
      // Category 2: Domain matching (only if not explicitly assigned)
      if (!addedToCategory && clientDomain && customer.email && customer.email.includes('@')) {
        const customerDomain = customer.email.split('@')[1];
        if (customerDomain && customerDomain.toLowerCase() === clientDomain.toLowerCase()) {
          domainMatched.push(customer);
          allClientCustomers.push({...customer, assignmentType: 'domain'});
          addedToCategory = true;
        }
      }
      
      // Category 3: Company name matching (only if not in other categories)
      if (!addedToCategory && customer.companyName && clientName) {
        if (customer.companyName.toLowerCase().includes(clientName.toLowerCase()) ||
            clientName.toLowerCase().includes(customer.companyName.toLowerCase())) {
          companyMatched.push(customer);
          allClientCustomers.push({...customer, assignmentType: 'company'});
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

module.exports = router;