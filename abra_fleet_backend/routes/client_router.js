// routes/client_router.js
const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const { ObjectId } = require('mongodb');
const { verifyJWT } = require('../middleware/auth');
const emailService = require('../services/email_service');

// ─────────────────────────────────────────────────────────────────────────────
// MULTER CONFIG
// ─────────────────────────────────────────────────────────────────────────────
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(__dirname, '../uploads/client_documents');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1e9);
    cb(null, uniqueSuffix + path.extname(file.originalname));
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 20 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const allowed = ['.pdf', '.jpg', '.jpeg', '.png', '.doc', '.docx', '.xls', '.xlsx'];
    const ext = path.extname(file.originalname).toLowerCase();
    if (allowed.includes(ext)) cb(null, true);
    else cb(new Error(`File type ${ext} not allowed`));
  },
});

// ─────────────────────────────────────────────────────────────────────────────
// DB MIDDLEWARE
// ─────────────────────────────────────────────────────────────────────────────
router.use((req, res, next) => {
  if (!req.db) {
    return res.status(500).json({ success: false, message: 'Database connection not available' });
  }
  next();
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/clients/profile
// ✅ FIXED: Dual lookup - checks both clients and users collections
// ─────────────────────────────────────────────────────────────────────────────
router.get('/profile', verifyJWT, async (req, res) => {
  try {
    console.log('📱 GET /api/clients/profile - Fetching client profile');
    console.log('🔑 User from JWT:', req.user);

    const userEmail = req.user?.email;
    const userId = req.user?.userId;
    
    if (!userEmail) {
      console.error('❌ No email found in JWT token');
      return res.status(401).json({ success: false, message: 'User not authenticated' });
    }

    console.log('🔍 Looking for client with email:', userEmail);

    // ✅ STEP 1: Try to find in clients collection by email
    let client = await req.db.collection('clients').findOne({ 
      email: userEmail.toLowerCase() 
    });

    // ✅ STEP 2: If not found, check users collection for linked clientId
    if (!client && userId) {
      console.log('   Client not found by email, checking users collection...');
      
      const user = await req.db.collection('users').findOne({ 
        _id: new ObjectId(userId),
        role: 'client'
      });

      if (user && user.clientId) {
        console.log('   Found linked clientId:', user.clientId);
        
        // Try to get client by linked ID
        try {
          const clientObjId = new ObjectId(user.clientId);
          client = await req.db.collection('clients').findOne({ _id: clientObjId });
        } catch (e) {
          console.log('   Invalid clientId format:', user.clientId);
        }
      }
    }

    // ✅ STEP 3: If still not found, return 404
    if (!client) {
      console.error('❌ Client not found in database for email:', userEmail);
      return res.status(404).json({ 
        success: false, 
        message: 'Client profile not found. Please contact administrator.' 
      });
    }

    console.log('✅ Client found:', client._id);

    const { _id, firebaseUid, password, ...clientData } = client;
    res.json({ success: true, data: { id: _id.toString(), ...clientData } });
  } catch (error) {
    console.error('❌ Error fetching client profile:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch client profile', error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/clients
// ─────────────────────────────────────────────────────────────────────────────
router.get('/', async (req, res) => {
  try {
    const {
      page = 1, limit = 100, status, search,
      country, state, city, area, department, startDate, endDate
    } = req.query;

    const query = { role: 'client' };

    if (status && status !== 'all') query.status = status;
    if (country)    query['location.country']    = { $regex: country,    $options: 'i' };
    if (state)      query['location.state']      = { $regex: state,      $options: 'i' };
    if (city)       query['location.city']       = { $regex: city,       $options: 'i' };
    if (area)       query['location.area']       = { $regex: area,       $options: 'i' };
    if (department) query.department             = { $regex: department, $options: 'i' };

    if (startDate || endDate) {
      query.createdAt = {};
      if (startDate) query.createdAt.$gte = new Date(startDate);
      if (endDate)   query.createdAt.$lte = new Date(new Date(endDate).setHours(23, 59, 59, 999));
    }

    if (search) {
      query.$or = [
        { name:        { $regex: search, $options: 'i' } },
        { email:       { $regex: search, $options: 'i' } },
        { phone:       { $regex: search, $options: 'i' } },
        { phoneNumber: { $regex: search, $options: 'i' } },
      ];
    }

    const pageNum  = parseInt(page);
    const limitNum = parseInt(limit);

    const clients = await req.db.collection('clients')
      .find(query)
      .sort({ createdAt: -1 })
      .skip((pageNum - 1) * limitNum)
      .limit(limitNum)
      .toArray();

    const total = await req.db.collection('clients').countDocuments(query);

    const transformedClients = clients.map(client => ({
      id:               client._id.toString(),
      email:            client.email              || '',
      name:             client.name               || '',
      phone:            client.phone              || client.phoneNumber || '',
      phoneNumber:      client.phoneNumber        || client.phone       || '',
      contactPerson:    client.contactPerson      || client.name        || '',
      address:          client.address            || '',
      branch:           client.branch             || '',
      department:       client.department         || '',
      gstNumber:        client.gstNumber          || null,
      panNumber:        client.panNumber          || null,
      organizationName: client.organizationName   || client.companyName || '',
      companyName:      client.companyName        || client.organizationName || '',
      status:           client.status             || 'active',
      totalCustomers:   client.totalCustomers     || 0,
      location:         client.location           || { country: '', state: '', city: '', area: '' },
      documents:        client.documents          || [],
      createdAt:        client.createdAt          || new Date(),
      updatedAt:        client.updatedAt          || new Date(),
      isActive:         client.status             === 'active',
    }));

    res.json({
      success: true,
      data: transformedClients,
      pagination: {
        page:  pageNum,
        limit: limitNum,
        total,
        pages: Math.ceil(total / limitNum)
      },
      summary: {
        total,
        active:    await req.db.collection('clients').countDocuments({ ...query, status: 'active' }),
        inactive:  await req.db.collection('clients').countDocuments({ ...query, status: 'inactive' }),
        suspended: await req.db.collection('clients').countDocuments({ ...query, status: 'suspended' }),
      }
    });
  } catch (error) {
    console.error('Error fetching clients:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch clients', error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/clients/:id
// ─────────────────────────────────────────────────────────────────────────────
router.get('/:id', async (req, res) => {
  try {
    let clientId;
    try { clientId = new ObjectId(req.params.id); } catch {
      return res.status(400).json({ success: false, message: 'Invalid client ID format' });
    }

    const client = await req.db.collection('clients').findOne({ _id: clientId });
    if (!client) {
      return res.status(404).json({ success: false, message: 'Client not found' });
    }

    const { _id, firebaseUid, password, ...clientData } = client;
    res.json({ success: true, data: { id: _id.toString(), ...clientData } });
  } catch (error) {
    console.error('Error fetching client:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch client', error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/clients/:clientId/customers
// ─────────────────────────────────────────────────────────────────────────────
router.get('/:clientId/customers', async (req, res) => {
  try {
    let clientObjId;
    try { clientObjId = new ObjectId(req.params.clientId); } catch {
      return res.status(400).json({ success: false, message: 'Invalid client ID' });
    }

    const clientData = await req.db.collection('clients').findOne({ _id: clientObjId });
    if (!clientData) {
      return res.status(404).json({ success: false, message: 'Client not found' });
    }

    const clientEmail  = clientData.email || '';
    const clientName   = clientData.name  || '';
    const clientDomain = clientEmail.includes('@') ? clientEmail.split('@')[1] : '';

    const allCustomers = await req.db.collection('customers').find({}).toArray();

    const explicitlyAssigned = [];
    const domainMatched      = [];
    const companyMatched     = [];
    const allClientCustomers = [];

    for (const customer of allCustomers) {
      const custEmail   = (customer.email || '').toLowerCase();
      const custCompany = (customer.companyName || customer.organizationName || '').toLowerCase();
      let added = false;

      if (customer.clientId === req.params.clientId) {
        explicitlyAssigned.push(customer);
        allClientCustomers.push({ ...customer, assignmentType: 'explicit' });
        added = true;
      }

      if (!added && clientDomain && custEmail.includes('@')) {
        if (custEmail.split('@')[1]?.toLowerCase() === clientDomain.toLowerCase()) {
          domainMatched.push(customer);
          allClientCustomers.push({ ...customer, assignmentType: 'domain' });
          added = true;
        }
      }

      if (!added && custCompany && clientName) {
        const lowerName = clientName.toLowerCase();
        if (custCompany.includes(lowerName) || lowerName.includes(custCompany)) {
          companyMatched.push(customer);
          allClientCustomers.push({ ...customer, assignmentType: 'company' });
        }
      }
    }

    res.json({
      success:    true,
      customers:  allClientCustomers,
      totalCount: allClientCustomers.length,
      categories: {
        explicitlyAssigned: { customers: explicitlyAssigned, count: explicitlyAssigned.length },
        domainMatched:      { customers: domainMatched,      count: domainMatched.length, domain: clientDomain },
        companyMatched:     { customers: companyMatched,     count: companyMatched.length },
      },
      clientInfo: { name: clientName, email: clientEmail, domain: clientDomain },
    });
  } catch (error) {
    console.error('Error fetching client customers:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch customers', error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/clients/sync-customer-counts
// ─────────────────────────────────────────────────────────────────────────────
router.post('/sync-customer-counts', async (req, res) => {
  try {
    console.log('🔄 Syncing customer counts for all clients...');

    const clients   = await req.db.collection('clients').find({ role: 'client' }).toArray();
    const customers = await req.db.collection('customers').find({}).toArray();

    let totalUpdated = 0;

    for (const client of clients) {
      const clientDomain = client.email?.includes('@') ? client.email.split('@')[1].toLowerCase() : '';
      const clientName   = (client.name || '').toLowerCase();
      let count = 0;

      for (const customer of customers) {
        const custEmail   = (customer.email || '').toLowerCase();
        const custCompany = (customer.companyName || '').toLowerCase();

        if (customer.clientId === client._id.toString()) { count++; continue; }

        if (clientDomain && custEmail.includes('@')) {
          if (custEmail.split('@')[1]?.toLowerCase() === clientDomain) { count++; continue; }
        }

        if (clientName && custCompany) {
          if (custCompany.includes(clientName) || clientName.includes(custCompany)) { count++; }
        }
      }

      await req.db.collection('clients').updateOne(
        { _id: client._id },
        { $set: { totalCustomers: count, updatedAt: new Date() } }
      );
      totalUpdated++;
    }

    console.log(`✅ Synced ${totalUpdated} clients`);
    res.json({ success: true, message: `Synced ${totalUpdated} clients`, updated: totalUpdated });
  } catch (error) {
    console.error('Error syncing customer counts:', error);
    res.status(500).json({ success: false, message: 'Failed to sync', error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/clients  — CREATE CLIENT
// ─────────────────────────────────────────────────────────────────────────────
router.post('/', upload.array('documents', 20), async (req, res) => {
  console.log('\n========== CLIENT CREATION STARTED ==========');

  try {
    const {
      email, name, phoneNumber, phone,
      organizationName, companyName, address, contactPerson,
      gstNumber, panNumber, password,
      status = 'active',
      branch, department, country, state, city, area,
      documentMetadata,
    } = req.body;

    if (!email || !name) {
      return res.status(400).json({ success: false, message: 'Email and name are required' });
    }

    const existing = await req.db.collection('clients').findOne({ email: email.toLowerCase() });
    if (existing) {
      return res.status(409).json({ success: false, message: 'Client with this email already exists' });
    }

    let metaList = [];
    if (documentMetadata) { try { metaList = JSON.parse(documentMetadata); } catch { metaList = []; } }

    const documents = (req.files || []).map((file, idx) => ({
      id:           new ObjectId().toString(),
      documentName: metaList[idx]?.documentName || file.originalname,
      documentType: metaList[idx]?.documentType || 'other',
      expiryDate:   metaList[idx]?.expiryDate   || null,
      fileName:     file.filename,
      originalName: file.originalname,
      filePath:     file.path,
      fileSize:     file.size,
      mimeType:     file.mimetype,
      uploadedAt:   new Date(),
    }));

    const newClient = {
      email:            email.toLowerCase(),
      name:             name.trim(),
      role:             'client',
      phone:            phoneNumber || phone || '',
      phoneNumber:      phoneNumber || phone || '',
      organizationName: organizationName || companyName || name,
      companyName:      companyName || organizationName || name,
      address:          address       || '',
      contactPerson:    contactPerson || name,
      branch:           branch        || '',
      department:       department    || '',
      gstNumber:        gstNumber     || null,
      panNumber:        panNumber     || null,
      status,
      modules:          [],
      permissions:      {},
      totalCustomers:   0,
      location: {
        country: country || '',
        state:   state   || '',
        city:    city    || '',
        area:    area    || '',
      },
      documents,
      createdAt:  new Date(),
      updatedAt:  new Date(),
      lastActive: new Date(),
    };

    const result = await req.db.collection('clients').insertOne(newClient);
    console.log('✅ Client created:', result.insertedId);

    // ============================================================================
    // SEND WELCOME EMAIL WITH PASSWORD SETUP LINK
    // ============================================================================
    if (newClient.email) {
      try {
        console.log('\n📧 Sending welcome email to client...');
        
        // Generate password reset token
        const resetToken = crypto.randomBytes(32).toString('hex');
        const resetTokenExpiry = new Date(Date.now() + 3600000); // 1 hour
        
        // Store reset token in client record
        await req.db.collection('clients').updateOne(
          { _id: result.insertedId },
          {
            $set: {
              passwordResetToken: resetToken,
              passwordResetExpires: resetTokenExpiry
            }
          }
        );
        
        // Create password setup link
        const resetLink = `${process.env.FRONTEND_URL}/reset-password?token=${resetToken}&email=${encodeURIComponent(newClient.email)}`;
        
        // Send welcome email with password setup link
        await emailService.sendCustomerApprovalEmail({
          email: newClient.email,
          name: newClient.name || newClient.contactPerson || 'Client',
          companyName: newClient.organizationName || newClient.companyName,
          passwordResetLink: resetLink
        });
        
        console.log('   ✅ Welcome email sent to:', newClient.email);
      } catch (emailError) {
        console.error('   ⚠️ Failed to send welcome email:', emailError.message);
        // Don't fail the client creation if email fails
      }
    }

    res.status(201).json({
      success: true,
      message: 'Client created successfully',
      data: { id: result.insertedId.toString(), ...newClient },
    });
  } catch (error) {
    console.error('CLIENT CREATION FAILED:', error.message);
    res.status(500).json({ success: false, message: 'Failed to create client', error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// PUT /api/clients/:id/status  — STATUS ONLY UPDATE
// ─────────────────────────────────────────────────────────────────────────────
router.put('/:id/status', async (req, res) => {
  try {
    const { status } = req.body;

    if (!['active', 'inactive', 'suspended'].includes(status)) {
      return res.status(400).json({ success: false, message: 'Invalid status value' });
    }

    let clientId;
    try { clientId = new ObjectId(req.params.id); } catch {
      return res.status(400).json({ success: false, message: 'Invalid client ID format' });
    }

    const result = await req.db.collection('clients').updateOne(
      { _id: clientId },
      { $set: { status, updatedAt: new Date() } }
    );

    if (result.matchedCount === 0) {
      return res.status(404).json({ success: false, message: 'Client not found' });
    }

    res.json({ success: true, message: `Client status updated to ${status}` });
  } catch (error) {
    console.error('Error updating client status:', error);
    res.status(500).json({ success: false, message: 'Failed to update status', error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// PUT /api/clients/:id  — UPDATE CLIENT
// ─────────────────────────────────────────────────────────────────────────────
router.put('/:id', upload.array('documents', 20), async (req, res) => {
  console.log('\n========== CLIENT UPDATE STARTED ==========');

  try {
    let clientId;
    try { clientId = new ObjectId(req.params.id); } catch {
      return res.status(400).json({ success: false, message: 'Invalid client ID format' });
    }

    const {
      email, name, phoneNumber, phone, address, contactPerson,
      gstNumber, panNumber, organizationName, companyName,
      branch, department, country, state, city, area,
      status, documentMetadata,
    } = req.body;

    if (!email || !name) {
      return res.status(400).json({ success: false, message: 'Email and name are required' });
    }

    const existingClient = await req.db.collection('clients').findOne({ _id: clientId });
    if (!existingClient) {
      return res.status(404).json({ success: false, message: 'Client not found' });
    }

    let metaList = [];
    if (documentMetadata) { try { metaList = JSON.parse(documentMetadata); } catch { metaList = []; } }

    const newDocs = (req.files || []).map((file, idx) => ({
      id:           new ObjectId().toString(),
      documentName: metaList[idx]?.documentName || file.originalname,
      documentType: metaList[idx]?.documentType || 'other',
      expiryDate:   metaList[idx]?.expiryDate   || null,
      fileName:     file.filename,
      originalName: file.originalname,
      filePath:     file.path,
      fileSize:     file.size,
      mimeType:     file.mimetype,
      uploadedAt:   new Date(),
    }));

    const mergedDocuments = [...(existingClient.documents || []), ...newDocs];

    const updateData = {
      email:            email.toLowerCase(),
      name:             name.trim(),
      phone:            phoneNumber || phone || existingClient.phone || '',
      phoneNumber:      phoneNumber || phone || existingClient.phoneNumber || '',
      address:          address       || existingClient.address       || '',
      contactPerson:    contactPerson || existingClient.contactPerson || name,
      branch:           branch        || existingClient.branch        || '',
      department:       department    || existingClient.department    || '',
      gstNumber:        gstNumber     || existingClient.gstNumber     || null,
      panNumber:        panNumber     || existingClient.panNumber     || null,
      organizationName: organizationName || companyName || existingClient.organizationName || '',
      companyName:      companyName || organizationName || existingClient.companyName || '',
      location: {
        country: country ?? existingClient.location?.country ?? '',
        state:   state   ?? existingClient.location?.state   ?? '',
        city:    city    ?? existingClient.location?.city    ?? '',
        area:    area    ?? existingClient.location?.area    ?? '',
      },
      documents: mergedDocuments,
      ...(status && { status }),
      updatedAt: new Date(),
    };

    await req.db.collection('clients').updateOne({ _id: clientId }, { $set: updateData });
    console.log('✅ Client updated successfully');

    res.json({
      success: true,
      message: 'Client updated successfully',
      data: { id: clientId.toString(), ...existingClient, ...updateData },
    });
  } catch (error) {
    console.error('Error updating client:', error);
    res.status(500).json({ success: false, message: 'Failed to update client', error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// DELETE /api/clients/:id/documents/:docId
// ─────────────────────────────────────────────────────────────────────────────
router.delete('/:id/documents/:docId', async (req, res) => {
  try {
    let clientId;
    try { clientId = new ObjectId(req.params.id); } catch {
      return res.status(400).json({ success: false, message: 'Invalid client ID' });
    }

    const client = await req.db.collection('clients').findOne({ _id: clientId });
    if (!client) return res.status(404).json({ success: false, message: 'Client not found' });

    const docToDelete = (client.documents || []).find(d => d.id === req.params.docId);
    if (docToDelete?.filePath && fs.existsSync(docToDelete.filePath)) {
      try { fs.unlinkSync(docToDelete.filePath); } catch {}
    }

    await req.db.collection('clients').updateOne(
      { _id: clientId },
      { $pull: { documents: { id: req.params.docId } }, $set: { updatedAt: new Date() } }
    );

    res.json({ success: true, message: 'Document deleted successfully' });
  } catch (error) {
    console.error('Error deleting document:', error);
    res.status(500).json({ success: false, message: 'Failed to delete document', error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/clients/:id/documents/:docId/download
// ─────────────────────────────────────────────────────────────────────────────
router.get('/:id/documents/:docId/download', async (req, res) => {
  try {
    let clientId;
    try { clientId = new ObjectId(req.params.id); } catch {
      return res.status(400).json({ success: false, message: 'Invalid client ID' });
    }

    const client = await req.db.collection('clients').findOne({ _id: clientId });
    if (!client) return res.status(404).json({ success: false, message: 'Client not found' });

    const doc = (client.documents || []).find(d => d.id === req.params.docId);
    if (!doc)                         return res.status(404).json({ success: false, message: 'Document not found' });
    if (!fs.existsSync(doc.filePath)) return res.status(404).json({ success: false, message: 'File not found on disk' });

    res.download(doc.filePath, doc.originalName);
  } catch (error) {
    console.error('Error downloading document:', error);
    res.status(500).json({ success: false, message: 'Failed to download document', error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// DELETE /api/clients/:id
// ─────────────────────────────────────────────────────────────────────────────
router.delete('/:id', async (req, res) => {
  console.log('\n========== CLIENT DELETION STARTED ==========');

  try {
    let clientId;
    try { clientId = new ObjectId(req.params.id); } catch {
      return res.status(400).json({ success: false, message: 'Invalid client ID format' });
    }

    const existingClient = await req.db.collection('clients').findOne({ _id: clientId });
    if (!existingClient) {
      return res.status(404).json({ success: false, message: 'Client not found' });
    }

    for (const doc of existingClient.documents || []) {
      if (doc.filePath && fs.existsSync(doc.filePath)) {
        try { fs.unlinkSync(doc.filePath); } catch {}
      }
    }

    await req.db.collection('clients').deleteOne({ _id: clientId });
    console.log('✅ Client deleted:', existingClient.email);

    res.json({ success: true, message: 'Client deleted successfully' });
  } catch (error) {
    console.error('Error deleting client:', error);
    res.status(500).json({ success: false, message: 'Failed to delete client', error: error.message });
  }
});

module.exports = router;