// routes/client_router.js - Client management routes
const express = require('express');
const router = express.Router();


// Middleware to attach database
router.use((req, res, next) => {
  if (!req.db) {
    return res.status(500).json({ msg: 'Database connection not available' });
  }
  next();
});

// @route   POST /api/clients/sync-customer-counts
// @desc    Sync customer counts for all clients based on actual customer assignments
// @access  Private (Admin)
router.post('/sync-customer-counts', async (req, res) => {
  try {
    console.log('🔄 Syncing customer counts for all clients...');
    
    // Get all clients from Firebase Realtime Database
    const clientsRef = admin.database().ref('clients');
    const clientsSnapshot = await clientsRef.once('value');
    
    if (!clientsSnapshot.exists()) {
      return res.json({
        success: true,
        message: 'No clients found',
        updated: 0
      });
    }
    
    const clients = clientsSnapshot.val();
    const updates = {};
    let totalUpdated = 0;
    
    // Get all customers from both databases
    const firestoreCustomers = await admin.firestore().collection('users')
      .where('role', '==', 'customer')
      .get();
    
    const mongoCustomers = await req.db.collection('users')
      .find({ role: 'customer' })
      .toArray();
    
    // Combine customers from both databases (deduplicate by email)
    const allCustomersMap = new Map();
    
    firestoreCustomers.forEach(doc => {
      const data = doc.data();
      if (data.email) {
        allCustomersMap.set(data.email.toLowerCase(), {
          email: data.email,
          companyName: data.companyName || data.organizationName || '',
          clientId: data.clientId || null, // Check for explicit client assignment
          source: 'firestore'
        });
      }
    });
    
    mongoCustomers.forEach(customer => {
      if (customer.email && !allCustomersMap.has(customer.email.toLowerCase())) {
        allCustomersMap.set(customer.email.toLowerCase(), {
          email: customer.email,
          companyName: customer.companyName || customer.organizationName || '',
          clientId: customer.clientId || null, // Check for explicit client assignment
          source: 'mongodb'
        });
      }
    });
    
    console.log(`📊 Total unique customers found: ${allCustomersMap.size}`);
    console.log(`   - From Firestore: ${firestoreCustomers.size}`);
    console.log(`   - From MongoDB: ${mongoCustomers.length}`);
    
    // Debug: Show sample customers
    const sampleCustomers = Array.from(allCustomersMap.values()).slice(0, 3);
    console.log('📋 Sample customers:');
    sampleCustomers.forEach((customer, index) => {
      console.log(`   ${index + 1}. ${customer.email} (${customer.source})`);
      console.log(`      Company: ${customer.companyName || 'N/A'}`);
      console.log(`      Client ID: ${customer.clientId || 'Not assigned'}`);
    });
    
    // For each client, count customers assigned to them
    for (const [clientId, clientData] of Object.entries(clients)) {
      const clientEmail = clientData.email || '';
      const clientName = clientData.name || '';
      
      // Extract domain from client email (e.g., @infosys.com)
      const clientDomain = clientEmail.includes('@') ? clientEmail.split('@')[1] : '';
      
      let customerCount = 0;
      let explicitAssignments = 0;
      let domainMatches = 0;
      let companyMatches = 0;
      
      // Count customers in multiple ways:
      // 1. Explicitly assigned to this client (preferred method)
      // 2. Fallback to domain matching for backward compatibility
      // 3. Company name matching as additional fallback
      for (const customer of allCustomersMap.values()) {
        let counted = false;
        
        // Method 1: Check explicit client assignment (highest priority)
        if (customer.clientId === clientId) {
          customerCount++;
          explicitAssignments++;
          counted = true;
          continue;
        }
        
        // Method 2: Fallback to domain matching
        if (!counted && clientDomain && customer.email.includes('@')) {
          const customerDomain = customer.email.split('@')[1];
          if (customerDomain && customerDomain.toLowerCase() === clientDomain.toLowerCase()) {
            customerCount++;
            domainMatches++;
            counted = true;
          }
        }
        
        // Method 3: Company name matching (only if not already counted)
        if (!counted && customer.companyName && clientName) {
          const customerCompany = customer.companyName.toLowerCase();
          const clientNameLower = clientName.toLowerCase();
          
          if (customerCompany.includes(clientNameLower) || clientNameLower.includes(customerCompany)) {
            customerCount++;
            companyMatches++;
            counted = true;
          }
        }
      }
      
      console.log(`   Client: ${clientName} (${clientEmail})`);
      console.log(`   Domain: @${clientDomain}`);
      console.log(`   Total Customers: ${customerCount}`);
      console.log(`     - Explicit assignments: ${explicitAssignments}`);
      console.log(`     - Domain matches: ${domainMatches}`);
      console.log(`     - Company matches: ${companyMatches}`);
      
      // Update the client's totalCustomers field
      updates[`${clientId}/totalCustomers`] = customerCount;
      totalUpdated++;
    }
    
    // Apply all updates at once
    if (Object.keys(updates).length > 0) {
      await clientsRef.update(updates);
      console.log(`✅ Updated ${totalUpdated} clients with correct customer counts`);
    }
    
    res.json({
      success: true,
      message: `Successfully synced customer counts for ${totalUpdated} clients`,
      updated: totalUpdated,
      totalCustomers: allCustomersMap.size
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

// @route   GET /api/clients/:clientId/customers
// @desc    Get all customers for a specific client with separate categorization
// @access  Private (Client/Admin)
router.get('/:clientId/customers', async (req, res) => {
  try {
    const { clientId } = req.params;
    
    // Get client info from Firebase Realtime Database
    const clientRef = admin.database().ref(`clients/${clientId}`);
    const clientSnapshot = await clientRef.once('value');
    
    if (!clientSnapshot.exists()) {
      return res.status(404).json({
        success: false,
        message: 'Client not found'
      });
    }
    
    const clientData = clientSnapshot.val();
    const clientEmail = clientData.email || '';
    const clientName = clientData.name || '';
    
    // Extract domain from client email (e.g., @infosys.com)
    const clientDomain = clientEmail.includes('@') ? clientEmail.split('@')[1] : '';
    
    // Get ALL customers from both databases (same as "All Customers" screen)
    const firestoreCustomers = await admin.firestore().collection('users')
      .where('role', '==', 'customer')
      .get();
    
    const mongoCustomers = await req.db.collection('users')
      .find({ role: 'customer' })
      .toArray();
    
    // Combine all customers (same logic as admin dashboard)
    const allCustomersMap = new Map();
    
    // Process Firestore customers
    firestoreCustomers.forEach(doc => {
      const data = doc.data();
      if (data.email) {
        allCustomersMap.set(data.email.toLowerCase(), {
          email: data.email,
          name: data.name || 'Unknown',
          companyName: data.companyName || data.organizationName || '',
          phoneNumber: data.phoneNumber || '',
          clientId: data.clientId || null,
          source: 'firestore'
        });
      }
    });
    
    // Process MongoDB customers
    mongoCustomers.forEach(customer => {
      if (customer.email && !allCustomersMap.has(customer.email.toLowerCase())) {
        allCustomersMap.set(customer.email.toLowerCase(), {
          email: customer.email,
          name: customer.name || 'Unknown',
          companyName: customer.companyName || customer.organizationName || '',
          phoneNumber: customer.phoneNumber || '',
          clientId: customer.clientId || null,
          source: 'mongodb'
        });
      }
    });
    
    // Now categorize customers for this client
    const explicitlyAssigned = [];
    const domainMatched = [];
    const companyMatched = [];
    const allClientCustomers = [];
    
    for (const customer of allCustomersMap.values()) {
      let addedToCategory = false;
      
      // Category 1: Explicitly assigned to this client
      if (customer.clientId === clientId) {
        explicitlyAssigned.push(customer);
        allClientCustomers.push({...customer, assignmentType: 'explicit'});
        addedToCategory = true;
      }
      
      // Category 2: Domain matching (only if not explicitly assigned)
      if (!addedToCategory && clientDomain && customer.email.includes('@')) {
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
      // All customers for this client (total count)
      customers: allClientCustomers,
      totalCount: allClientCustomers.length,
      
      // Separate categories for detailed view
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

// @route   POST /api/clients
// @desc    Create a new client
// @access  Private (Admin)
router.post('/', async (req, res) => {
  console.log('\n🏢 ========== CLIENT CREATION STARTED ==========');
  console.log('📥 Request body:', JSON.stringify(req.body, null, 2));
  
  try {
    const {
      email,
      name,
      phoneNumber,
      organizationName,
      companyName,
      password,
      status = 'active'
    } = req.body;
    
    console.log('✅ Request data extracted successfully');
    console.log('   - Email:', email);
    console.log('   - Name:', name);
    console.log('   - Organization:', organizationName || companyName);
    
    // Validate required fields
    if (!email || !name) {
      console.error('❌ Validation failed - Missing required fields');
      return res.status(400).json({
        success: false,
        message: 'Email and name are required'
      });
    }
    
    console.log('✅ All required fields validated');
    
    // Check if client already exists in admin_users
    console.log('🔍 Checking for existing client...');
    const existingClient = await req.db.collection('admin_users').findOne({
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
    
    // 🔥 CREATE FIREBASE AUTH USER
    console.log('\n🔐 ========== FIREBASE USER CREATION ==========');
    console.log('🔐 Creating Firebase Auth user for:', email);
    
    let firebaseUid = null;
    try {
      // Generate a temporary password if not provided
      const tempPassword = password || Math.random().toString(36).slice(-12) + 'Aa1!';
      
      // Create Firebase Auth user
      const firebaseUser = await admin.auth().createUser({
        email: email,
        emailVerified: false,
        password: tempPassword,
        displayName: name,
        disabled: false
      });
      
      firebaseUid = firebaseUser.uid;
      console.log('✅ Firebase user created successfully');
      console.log('   - Firebase UID:', firebaseUid);
      console.log('   - Email:', firebaseUser.email);
      console.log('   - Display Name:', firebaseUser.displayName);
      
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
    
    // 💾 CREATE CLIENT RECORD IN admin_users
    console.log('\n💾 ========== MONGODB CLIENT CREATION ==========');
    const newClient = {
      firebaseUid: firebaseUid,
      email: email.toLowerCase(),
      name: name,
      role: 'client', // 👈 CRITICAL!
      phoneNumber: phoneNumber || '',
      organizationName: organizationName || companyName || '',
      companyName: companyName || organizationName || '',
      status: status,
      modules: [],
      permissions: {},
      createdAt: new Date(),
      updatedAt: new Date(),
      lastActive: new Date()
    };
    
    console.log('💾 Inserting client into admin_users collection...');
    const result = await req.db.collection('admin_users').insertOne(newClient);
    console.log('✅ Client inserted successfully');
    console.log('   - MongoDB _id:', result.insertedId);
    console.log('   - Firebase UID:', firebaseUid);
    console.log('   - Role: client');
    
    // Also store in Firebase Realtime Database (for compatibility with existing client system)
    console.log('\n💾 ========== FIREBASE REALTIME DB SYNC ==========');
    try {
      const clientRef = admin.database().ref('clients').push();
      await clientRef.set({
        email: email,
        name: name,
        organizationName: organizationName || companyName || '',
        companyName: companyName || organizationName || '',
        phoneNumber: phoneNumber || '',
        totalCustomers: 0,
        createdAt: new Date().toISOString()
      });
      console.log('✅ Client also synced to Firebase Realtime Database');
    } catch (realtimeDbError) {
      console.error('⚠️  Failed to sync to Realtime DB:', realtimeDbError.message);
      // Don't fail the request
    }
    
    console.log('✅ Client creation completed successfully');
    console.log('========== CLIENT CREATION COMPLETE ==========\n');
    
    res.status(201).json({
      success: true,
      message: 'Client created successfully',
      data: { ...newClient, _id: result.insertedId }
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


module.exports = router;
