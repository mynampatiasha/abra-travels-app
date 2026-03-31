// routes/client-customers.js
// ============================================================================
// CLIENT CUSTOMER MANAGEMENT APIs
// ============================================================================
// Base route: /api/client/customers
// Allows clients to view ONLY their organization's employees (by email domain)
// ============================================================================

const express = require('express');
const router = express.Router();

// GET /api/client/customers - Get customers by domain (CLIENT ROLE ONLY)
router.get('/', async (req, res) => {
  try {
    const { domain, status, page = 1, limit = 10000, search } = req.query;
    
    console.log('\n🔍 CLIENT CUSTOMER REQUEST');
    console.log('─'.repeat(80));
    console.log('Domain filter:', domain);
    console.log('Status filter:', status);
    console.log('Search query:', search);
    
    // ✅ CRITICAL: Require domain parameter for client requests
    if (!domain) {
      return res.status(400).json({
        success: false,
        message: 'Domain parameter is required for client requests'
      });
    }
    
    // Build filter
    const filter = {};
    
    // ✅ FILTER BY EMAIL DOMAIN (e.g., @infosys.com)
    const searchDomain = domain.startsWith('@') ? domain : `@${domain}`;
    filter.email = { 
      $regex: `${searchDomain.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 
      $options: 'i' 
    };
    
    console.log('📧 Email regex filter:', filter.email);
    
    // Optional: Status filter
    if (status && status !== 'All') {
      filter.status = status;
    }
    
    // Optional: Search filter (name, email, employeeId)
    if (search) {
      filter.$and = [
        { email: filter.email }, // Keep domain filter
        {
          $or: [
            { name: { $regex: search, $options: 'i' } },
            { email: { $regex: search, $options: 'i' } },
            { employeeId: { $regex: search, $options: 'i' } },
            { 'name.firstName': { $regex: search, $options: 'i' } },
            { 'name.lastName': { $regex: search, $options: 'i' } }
          ]
        }
      ];
    }
    
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    // Fetch customers from database
    const customers = await req.db.collection('customers')
      .find(filter)
      .skip(skip)
      .limit(parseInt(limit))
      .sort({ createdAt: -1 })
      .toArray();
    
    const totalCount = await req.db.collection('customers').countDocuments(filter);
    
    console.log(`✅ Found ${customers.length} customers for domain ${searchDomain}`);
    console.log('─'.repeat(80));
    
    // 🔧 NORMALIZE CUSTOMER DATA (handle both flat and nested formats)
    const normalizedCustomers = customers.map(customer => {
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
        
        companyName: customer.companyName 
          || customer.company?.name 
          || customer.name?.companyName 
          || '',
        
        department: customer.department || '',
        branch: customer.branch || '',
        employeeId: customer.employeeId || customer.customerId || '',
        status: customer.status || 'active',
        role: customer.role || 'customer',
        createdAt: customer.createdAt,
        updatedAt: customer.updatedAt,
        lastLogin: customer.lastLogin || null,
      };
    });
    
    // Calculate statistics for this domain
    const stats = {
      total: totalCount,
      active: await req.db.collection('customers').countDocuments({ 
        ...filter, 
        status: 'active' 
      }),
      inactive: await req.db.collection('customers').countDocuments({ 
        ...filter, 
        status: 'inactive' 
      })
    };
    
    res.json({
      success: true,
      data: normalizedCustomers,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: totalCount,
        pages: Math.ceil(totalCount / parseInt(limit))
      },
      summary: stats
    });
    
  } catch (error) {
    console.error('❌ Error fetching client customers:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch customers',
      error: error.message
    });
  }
});

// GET /api/client/customers/count - Count customers by domain
router.get('/count', async (req, res) => {
  try {
    const { domain } = req.query;
    
    if (!domain) {
      return res.status(400).json({
        success: false,
        message: 'Domain parameter is required'
      });
    }
    
    const searchDomain = domain.startsWith('@') ? domain : `@${domain}`;
    const count = await req.db.collection('customers').countDocuments({
      email: { 
        $regex: `${searchDomain.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 
        $options: 'i' 
      }
    });
    
    console.log(`✅ Count for domain ${searchDomain}: ${count}`);
    
    res.json({
      success: true,
      domain: searchDomain,
      count: count
    });
    
  } catch (error) {
    console.error('❌ Error counting customers:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to count customers',
      error: error.message
    });
  }
});

module.exports = router;