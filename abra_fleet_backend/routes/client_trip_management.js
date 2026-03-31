// routes/client_trip_management.js
// ✅ AUTO-FILTERS ALL ENDPOINTS BY USER EMAIL DOMAIN

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');

// Extract domain from email (e.g., "user@company.com" → "company.com")
function extractDomain(email) {
  if (!email || typeof email !== 'string' || !email.includes('@')) return null;
  return email.split('@')[1].toLowerCase().trim();
}

// Build MongoDB filter to match trips with ANY stop from this domain
function buildDomainFilter(domain) {
  if (!domain) throw new Error('Invalid domain');
  const escapedDomain = domain.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return {
    'stops': {
      $elemMatch: {
        'customer.email': { 
          $regex: `@${escapedDomain}$`, 
          $options: 'i' 
        }
      }
    }
  };
}

// ✅ GET /api/client/trips/dashboard
router.get('/dashboard', async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📊 CLIENT TRIP DASHBOARD - FETCHING SUMMARY');
    console.log('='.repeat(80));
    
    const domain = extractDomain(req.user.email);
    console.log('🏢 Client Domain:', domain);
    console.log('👤 User Email:', req.user.email);
    
    if (!domain) {
      console.log('❌ Invalid email - no domain found');
      return res.status(400).json({ 
        success: false, 
        message: 'Invalid email - cannot determine company domain' 
      });
    }
    
    const { fromDate, toDate } = req.query;
    const filter = buildDomainFilter(domain);
    
    // Add date range
    if (fromDate || toDate) {
      filter.scheduledDate = {};
      if (fromDate) filter.scheduledDate.$gte = fromDate;
      if (toDate) filter.scheduledDate.$lte = toDate;
    }
    
    console.log('🔍 Query filter:', JSON.stringify(filter, null, 2));
    
    // Fetch ALL trips for this domain
    const allTrips = await req.db.collection('roster-assigned-trips')
      .find(filter)
      .toArray();
    
    console.log(`📦 Found ${allTrips.length} trip(s) for domain: ${domain}`);
    
    // Count by status
    const summary = {
      ongoing: allTrips.filter(t => 
        t.status === 'started' || t.status === 'in_progress'
      ).length,
      scheduled: allTrips.filter(t => t.status === 'assigned').length,
      completed: allTrips.filter(t => 
        t.status === 'completed' || t.status === 'done' || t.status === 'finished'
      ).length,
      cancelled: allTrips.filter(t => {
        const status = (t.status || '').toLowerCase();
        const hasCancelledStops = t.stops?.some(s => 
          (s.status || '').toLowerCase() === 'cancelled'
        );
        return status === 'cancelled' || hasCancelledStops;
      }).length,
      total: allTrips.length,
      delayed: 0,
      totalVehicles: new Set(allTrips.map(t => t.vehicleId).filter(Boolean).map(String)).size,
      totalDrivers: new Set(allTrips.map(t => t.driverId).filter(Boolean).map(String)).size,
      totalCustomers: new Set(
        allTrips.flatMap(t => 
          (t.stops || [])
            .filter(s => 
              s.type === 'pickup' && 
              s.customer?.email && 
              extractDomain(s.customer.email) === domain
            )
            .map(s => s.customer.email)
        )
      ).size,
      domain: domain
    };
    
    console.log('📊 DASHBOARD SUMMARY:');
    console.log(`   🟢 Ongoing: ${summary.ongoing}`);
    console.log(`   🔵 Scheduled: ${summary.scheduled}`);
    console.log(`   ⚫ Completed: ${summary.completed}`);
    console.log(`   🔴 Cancelled: ${summary.cancelled}`);
    console.log(`   📊 Total: ${summary.total}`);
    console.log(`   👥 Customers (${domain}): ${summary.totalCustomers}`);
    console.log('='.repeat(80) + '\n');
    
    res.json({ success: true, message: 'Dashboard summary retrieved', data: summary });
  } catch (error) {
    console.error('❌ Dashboard error:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

// ✅ GET /api/client/trips/list
router.get('/list', async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📋 CLIENT TRIP LIST - FETCHING FILTERED TRIPS');
    console.log('='.repeat(80));
    
    const domain = extractDomain(req.user.email);
    console.log('🏢 Client Domain:', domain);
    console.log('👤 User Email:', req.user.email);
    
    if (!domain) {
      return res.status(400).json({ success: false, message: 'Invalid email' });
    }
    
    const { fromDate, toDate, status, search, page = 1, limit = 20 } = req.query;
    console.log('📊 Status filter:', status || 'all');
    console.log('🔍 Search:', search || 'none');
    console.log('📄 Page:', page, ', Limit:', limit);
    
    const filter = buildDomainFilter(domain);
    
    // Add filters
    if (fromDate || toDate) {
      filter.scheduledDate = {};
      if (fromDate) filter.scheduledDate.$gte = fromDate;
      if (toDate) filter.scheduledDate.$lte = toDate;
    }
    
    if (status && status !== 'all') {
      if (status === 'ongoing') filter.status = { $in: ['started', 'in_progress'] };
      else if (status === 'scheduled') filter.status = 'assigned';
      else if (status === 'cancelled') {
        filter.$or = [
          { status: /cancel/i },
          { 'stops': { $elemMatch: { status: /cancel/i } } }
        ];
      }
      else if (status === 'completed') filter.status = { $in: ['completed', 'done', 'finished'] };
      else filter.status = status;
    }
    
    if (search) {
      filter.$or = [
        { vehicleNumber: { $regex: search, $options: 'i' } },
        { driverName: { $regex: search, $options: 'i' } },
        { tripNumber: { $regex: search, $options: 'i' } }
      ];
    }
    
    console.log('🔍 Query filter:', JSON.stringify(filter, null, 2));
    
    const total = await req.db.collection('roster-assigned-trips').countDocuments(filter);
    const trips = await req.db.collection('roster-assigned-trips')
      .find(filter)
      .sort({ scheduledDate: -1, createdAt: -1 })
      .skip((parseInt(page) - 1) * parseInt(limit))
      .limit(parseInt(limit))
      .toArray();
    
    console.log(`📦 Found ${trips.length} trip(s) for domain: ${domain}`);
    console.log('='.repeat(80) + '\n');
    
    const enhanced = trips.map(t => {
      const totalStops = t.stops?.length || 0;
      const completedStops = t.stops?.filter(s => s.status === 'completed').length || 0;
      
      return {
        _id: t._id,
        tripNumber: t.tripNumber,
        vehicleNumber: t.vehicleNumber || 'Unknown',
        vehicleName: t.vehicleName || '',
        driverName: t.driverName || 'Unknown',
        driverPhone: t.driverPhone || '',
        scheduledDate: t.scheduledDate,
        startTime: t.startTime,
        endTime: t.endTime,
        status: t.status,
        progress: totalStops > 0 ? Math.round((completedStops / totalStops) * 100) : 0,
        totalStops,
        completedStops,
        customerCount: t.stops?.filter(s => 
          s.type === 'pickup' && 
          s.customer?.email && 
          extractDomain(s.customer.email) === domain
        ).length || 0,
        totalDistance: t.totalDistance || 0,
        totalTime: t.totalTime || 0
      };
    });
    
    res.json({
      success: true,
      data: {
        trips: enhanced,
        pagination: {
          page: parseInt(page),
          limit: parseInt(limit),
          total,
          totalPages: Math.ceil(total / parseInt(limit))
        },
        filters: { domain, status: status || 'all' }
      }
    });
  } catch (error) {
    console.error('❌ List error:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

// ✅ GET /api/client/trips/:tripId/details
router.get('/:tripId/details', async (req, res) => {
  try {
    const domain = extractDomain(req.user.email);
    if (!domain) return res.status(400).json({ success: false, message: 'Invalid email' });
    if (!ObjectId.isValid(req.params.tripId)) {
      return res.status(400).json({ success: false, message: 'Invalid trip ID' });
    }
    
    const trip = await req.db.collection('roster-assigned-trips').findOne({
      _id: new ObjectId(req.params.tripId),
      ...buildDomainFilter(domain)
    });
    
    if (!trip) {
      return res.status(404).json({ 
        success: false, 
        message: 'Trip not found or you do not have access'
      });
    }
    
    res.json({ success: true, data: trip });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
});

// ✅ GET /api/client/trips/bulk-report
router.get('/bulk-report', async (req, res) => {
  try {
    const domain = extractDomain(req.user.email);
    if (!domain) return res.status(400).json({ success: false, message: 'Invalid email' });
    
    const filter = buildDomainFilter(domain);
    const trips = await req.db.collection('roster-assigned-trips').find(filter).toArray();
    
    res.json({
      success: true,
      data: {
        trips,
        summary: { total: trips.length },
        domain
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
});

module.exports = router;