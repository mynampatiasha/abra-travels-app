// routes/admin_client_analytics.js
// ============================================================================
// ADMIN CLIENT ANALYTICS ROUTER - FINAL CORRECT VERSION
// ============================================================================
// ✅ Counts employees from 'customers' collection (like ClientAdminDashboard)
// ✅ NOT from trip stops - that was the bug!
// ============================================================================

const express = require('express');
const router = express.Router();
const { verifyToken } = require('../middleware/auth');

// ============================================================================
// @route   GET /api/admin/client-analytics/trip-stats
// @desc    Get trip statistics grouped by client domain
// @access  Private (Admin only)
// @query   fromDate, toDate, limit (optional)
// ============================================================================
router.get('/trip-stats', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📊 CLIENT ANALYTICS - TRIP STATISTICS BY DOMAIN');
    console.log('='.repeat(80));
    
    const { fromDate, toDate, limit = 10 } = req.query;
    
    console.log(`👤 Admin: ${req.user.email || req.user.id}`);
    console.log(`📅 From Date: ${fromDate || 'all time'}`);
    console.log(`📅 To Date: ${toDate || 'all time'}`);
    console.log(`📊 Limit: ${limit} clients`);
    
    // ========================================================================
    // STEP 1: Build date filter
    // ========================================================================
    const filter = {};
    
    if (fromDate || toDate) {
      filter.scheduledDate = {};
      
      if (fromDate) {
        filter.scheduledDate.$gte = fromDate;
      }
      
      if (toDate) {
        filter.scheduledDate.$lte = toDate;
      }
    }
    
    console.log('🔍 Date Filter:', JSON.stringify(filter, null, 2));
    
    // ========================================================================
    // STEP 2: Fetch ALL clients first
    // ========================================================================
    const allClients = await req.db.collection('clients')
      .find({})
      .toArray();
    
    console.log(`🏢 Found ${allClients.length} total client(s) in database`);
    
    // Create domain-to-client mapping
    const domainToClientMap = new Map();
    
    for (const client of allClients) {
      if (client.email && client.email.includes('@')) {
        const domain = client.email.split('@')[1].toLowerCase().trim();
        domainToClientMap.set(domain, client);
        
        console.log(`   ✅ Mapped: ${domain} → ${client.companyName || client.name || 'Unnamed'}`);
      }
    }
    
    console.log(`\n📋 Total Domains Mapped: ${domainToClientMap.size}\n`);
    
    // ========================================================================
    // STEP 3: Count EMPLOYEES from 'customers' collection (like Client Dashboard)
    // ========================================================================
    console.log('👥 Counting employees from customers collection...\n');
    
    const domainEmployeeCounts = new Map();
    
    // For each domain, count customers with that domain
    for (const [domain, client] of domainToClientMap.entries()) {
      try {
        // Count customers where email ends with @domain
        const employeeCount = await req.db.collection('customers')
          .countDocuments({
            email: { $regex: `@${domain}$`, $options: 'i' }
          });
        
        domainEmployeeCounts.set(domain, employeeCount);
        
        console.log(`   👥 ${client.companyName || client.name}: ${employeeCount} employees (@${domain})`);
      } catch (err) {
        console.log(`   ⚠️  Error counting employees for ${domain}: ${err.message}`);
        domainEmployeeCounts.set(domain, 0);
      }
    }
    
    console.log('');
    
    // ========================================================================
    // STEP 4: Fetch all trips matching filter
    // ========================================================================
    const allTrips = await req.db.collection('roster-assigned-trips')
      .find(filter)
      .toArray();
    
    console.log(`📦 Found ${allTrips.length} total trip(s)\n`);
    
    // ========================================================================
    // STEP 5: Group trips by client domain
    // ========================================================================
    const clientDataMap = new Map(); // domain -> { client, tripIds: Set }
    
    for (const trip of allTrips) {
      if (!trip.stops || !Array.isArray(trip.stops)) continue;
      
      // Find pickup stops with customer emails
      const pickupStops = trip.stops.filter(s => 
        s.type === 'pickup' && 
        s.customer && 
        s.customer.email
      );
      
      for (const stop of pickupStops) {
        const email = stop.customer.email.toLowerCase().trim();
        
        // Extract domain from email
        if (email.includes('@')) {
          const domain = email.split('@')[1];
          
          // Check if this domain belongs to a registered client
          if (domainToClientMap.has(domain)) {
            // Initialize data structure for this domain if not exists
            if (!clientDataMap.has(domain)) {
              clientDataMap.set(domain, {
                client: domainToClientMap.get(domain),
                tripIds: new Set(), // Prevent duplicate trips
              });
            }
            
            const clientData = clientDataMap.get(domain);
            
            // Add trip ID
            clientData.tripIds.add(trip._id.toString());
          }
        }
      }
    }
    
    console.log(`✅ Processed trips for ${clientDataMap.size} client domain(s) with trips\n`);
    
    // ========================================================================
    // STEP 6: Calculate statistics for each client
    // ========================================================================
    const clientAnalytics = [];
    
    for (const [domain, data] of clientDataMap.entries()) {
      const client = data.client;
      const tripIds = Array.from(data.tripIds);
      
      // Get actual trip objects for this client
      const clientTrips = allTrips.filter(trip => 
        tripIds.includes(trip._id.toString())
      );
      
      const totalTrips = clientTrips.length;
      
      // Count trips by status
      const completed = clientTrips.filter(t => {
        const status = (t.status || '').toLowerCase();
        return status === 'completed' || status === 'done' || status === 'finished';
      }).length;
      
      const ongoing = clientTrips.filter(t => {
        const status = (t.status || '').toLowerCase();
        return status === 'started' || status === 'in_progress' || status === 'ongoing';
      }).length;
      
      const scheduled = clientTrips.filter(t => {
        const status = (t.status || '').toLowerCase();
        return status === 'assigned' || status === 'scheduled' || status === 'pending';
      }).length;
      
      // Count cancelled trips
      const cancelled = clientTrips.filter(t => {
        const status = (t.status || '').toLowerCase();
        const isTripCancelled = status === 'cancelled' || status === 'canceled';
        
        const hasStops = t.stops && Array.isArray(t.stops) && t.stops.length > 0;
        const hasCancelledStops = hasStops && t.stops.some(s => {
          const stopStatus = (s.status || '').toLowerCase();
          return stopStatus === 'cancelled' || stopStatus === 'canceled';
        });
        
        return isTripCancelled || hasCancelledStops;
      }).length;
      
      // ✅ Get employee count from customers collection
      const employeeCount = domainEmployeeCounts.get(domain) || 0;
      
      // Calculate estimated revenue
      const estimatedRevenue = totalTrips * 450.0;
      
      console.log(`📊 ${client.companyName || client.name || domain}`);
      console.log(`   Domain: ${domain}`);
      console.log(`   👥 Employees: ${employeeCount} (from customers collection)`);
      console.log(`   🚗 Total Trips: ${totalTrips} (Completed: ${completed}, Ongoing: ${ongoing}, Scheduled: ${scheduled}, Cancelled: ${cancelled})`);
      console.log(`   💰 Revenue: ₹${estimatedRevenue.toFixed(2)}\n`);
      
      clientAnalytics.push({
        domain: domain,
        companyName: client.companyName || client.name || domain,
        clientId: client._id || null,
        clientEmail: client.email || `unknown@${domain}`,
        
        // ✅ Employee count from customers collection
        customerCount: employeeCount,
        
        // Trip metrics
        totalTrips: totalTrips,
        completedTrips: completed,
        ongoingTrips: ongoing,
        scheduledTrips: scheduled,
        cancelledTrips: cancelled,
        
        // Financial metrics
        estimatedRevenue: estimatedRevenue,
        
        // Additional info
        isActive: client.isActive !== false,
        createdAt: client.createdAt || null
      });
    }
    
    // ========================================================================
    // STEP 7: Add clients with zero trips (but show employee counts)
    // ========================================================================
    for (const [domain, client] of domainToClientMap.entries()) {
      const hasData = clientAnalytics.some(ca => ca.domain === domain);
      
      if (!hasData) {
        // ✅ Get employee count even if no trips
        const employeeCount = domainEmployeeCounts.get(domain) || 0;
        
        console.log(`📊 ${client.companyName || client.name || domain}`);
        console.log(`   Domain: ${domain}`);
        console.log(`   👥 Employees: ${employeeCount} (from customers collection)`);
        console.log(`   ⚠️  No trips found for this client\n`);
        
        clientAnalytics.push({
          domain: domain,
          companyName: client.companyName || client.name || domain,
          clientId: client._id || null,
          clientEmail: client.email || `unknown@${domain}`,
          
          // ✅ Show employee count even with no trips
          customerCount: employeeCount,
          
          // All trip counts are zero
          totalTrips: 0,
          completedTrips: 0,
          ongoingTrips: 0,
          scheduledTrips: 0,
          cancelledTrips: 0,
          estimatedRevenue: 0.0,
          
          isActive: client.isActive !== false,
          createdAt: client.createdAt || null
        });
      }
    }
    
    // ========================================================================
    // STEP 8: Sort by total trips and limit
    // ========================================================================
    clientAnalytics.sort((a, b) => b.totalTrips - a.totalTrips);
    
    const topClients = clientAnalytics.slice(0, parseInt(limit));
    
    console.log('='.repeat(80));
    console.log(`✅ RETURNING ${topClients.length} CLIENT(S)`);
    console.log('='.repeat(80));
    
    // Final summary
    topClients.forEach((client, index) => {
      console.log(`\n${index + 1}. ${client.companyName} (${client.domain})`);
      console.log(`   👥 Employees: ${client.customerCount}`);
      console.log(`   🚗 Trips: ${client.totalTrips} total`);
      console.log(`   └─ ${client.completedTrips} completed, ${client.ongoingTrips} ongoing, ${client.scheduledTrips} scheduled, ${client.cancelledTrips} cancelled`);
    });
    
    console.log('\n' + '='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: `Found ${topClients.length} clients with trip statistics`,
      data: {
        clients: topClients,
        totalClientsAnalyzed: clientAnalytics.length,
        totalTripsAnalyzed: allTrips.length,
        filters: {
          fromDate: fromDate || null,
          toDate: toDate || null,
          limit: parseInt(limit)
        }
      }
    });
    
  } catch (error) {
    console.error('❌ Error fetching client analytics:', error);
    console.error('Stack trace:', error.stack);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch client analytics',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/admin/client-analytics/summary
// @desc    Get overall summary statistics
// @access  Private (Admin only)
// ============================================================================
router.get('/summary', verifyToken, async (req, res) => {
  try {
    console.log('\n📊 CLIENT ANALYTICS - OVERALL SUMMARY');
    
    const { fromDate, toDate } = req.query;
    
    const filter = {};
    if (fromDate || toDate) {
      filter.scheduledDate = {};
      if (fromDate) filter.scheduledDate.$gte = fromDate;
      if (toDate) filter.scheduledDate.$lte = toDate;
    }
    
    const allTrips = await req.db.collection('roster-assigned-trips')
      .find(filter)
      .toArray();
    
    const totalTrips = allTrips.length;
    
    const completed = allTrips.filter(t => {
      const status = (t.status || '').toLowerCase();
      return ['completed', 'done', 'finished'].includes(status);
    }).length;
    
    const ongoing = allTrips.filter(t => {
      const status = (t.status || '').toLowerCase();
      return ['started', 'in_progress', 'ongoing'].includes(status);
    }).length;
    
    const scheduled = allTrips.filter(t => {
      const status = (t.status || '').toLowerCase();
      return ['assigned', 'scheduled', 'pending'].includes(status);
    }).length;
    
    const cancelled = allTrips.filter(t => {
      const status = (t.status || '').toLowerCase();
      const isTripCancelled = status === 'cancelled' || status === 'canceled';
      const hasCancelledStops = t.stops?.some(s => {
        const stopStatus = (s.status || '').toLowerCase();
        return stopStatus === 'cancelled' || stopStatus === 'canceled';
      });
      return isTripCancelled || hasCancelledStops;
    }).length;
    
    // Get unique registered client domains
    const allClients = await req.db.collection('clients').find({}).toArray();
    const registeredDomains = new Set();
    
    allClients.forEach(client => {
      if (client.email && client.email.includes('@')) {
        registeredDomains.add(client.email.split('@')[1].toLowerCase());
      }
    });
    
    // ✅ Count total customers from customers collection
    const totalCustomers = await req.db.collection('customers').countDocuments({});
    
    res.json({
      success: true,
      data: {
        totalTrips,
        completedTrips: completed,
        ongoingTrips: ongoing,
        scheduledTrips: scheduled,
        cancelledTrips: cancelled,
        totalClients: registeredDomains.size,
        totalCustomers: totalCustomers,
        filters: {
          fromDate: fromDate || null,
          toDate: toDate || null
        }
      }
    });
    
  } catch (error) {
    console.error('❌ Error fetching summary:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch summary',
      error: error.message
    });
  }
});

module.exports = router;

// ============================================================================
// ✅ KEY FIX: EMPLOYEE COUNT SOURCE
// ============================================================================
//
// OLD (WRONG):
// - Counted unique emails from trip.stops[].customer.email
// - Problem: Only counts customers who have trips
// - Result: Employee count = 0 for clients with no trips, wrong otherwise
//
// NEW (CORRECT):
// - Counts documents in 'customers' collection by domain
// - Query: db.customers.countDocuments({ email: /@domain$/i })
// - Same method as ClientAdminDashboard uses
// - Result: Shows actual employee count (3, 42, 22, 11) like Client Management
//
// ============================================================================