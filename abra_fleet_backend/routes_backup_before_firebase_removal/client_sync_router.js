// routes/client_sync_router.js - Missing client sync endpoints
const express = require('express');
const router = express.Router();

// POST /clients/sync-customer-counts - Sync customer counts
router.post('/sync-customer-counts', async (req, res) => {
  try {
    console.log('📊 Syncing customer counts...');
    
    // Get customer counts from database
    const totalCustomers = await req.db.collection('customers').countDocuments();
    const activeCustomers = await req.db.collection('customers')
      .countDocuments({ status: 'active' });
    const pendingApprovals = await req.db.collection('customers')
      .countDocuments({ status: 'pending' });
    
    // Get roster counts
    const totalRosters = await req.db.collection('rosters').countDocuments();
    const activeRosters = await req.db.collection('rosters')
      .countDocuments({ status: 'active' });
    
    const counts = {
      customers: {
        total: totalCustomers,
        active: activeCustomers,
        pending: pendingApprovals
      },
      rosters: {
        total: totalRosters,
        active: activeRosters
      },
      lastUpdated: new Date().toISOString()
    };
    
    console.log('✅ Customer counts synced:', counts);
    
    res.json({
      success: true,
      data: counts,
      message: 'Customer counts synced successfully'
    });
    
  } catch (error) {
    console.error('❌ Error syncing customer counts:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to sync customer counts',
      message: error.message
    });
  }
});

// GET /clients/dashboard-stats - Get dashboard statistics
router.get('/dashboard-stats', async (req, res) => {
  try {
    console.log('📊 Fetching dashboard stats...');
    
    // Get various counts for dashboard
    const stats = {
      customers: await req.db.collection('customers').countDocuments(),
      drivers: await req.db.collection('drivers').countDocuments(),
      vehicles: await req.db.collection('vehicles').countDocuments(),
      activeTrips: await req.db.collection('trips').countDocuments({ status: 'active' }),
      pendingRosters: await req.db.collection('rosters').countDocuments({ status: 'pending' }),
      notifications: await req.db.collection('notifications').countDocuments({ read: false })
    };
    
    console.log('✅ Dashboard stats fetched:', stats);
    
    res.json({
      success: true,
      data: stats
    });
    
  } catch (error) {
    console.error('❌ Error fetching dashboard stats:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch dashboard stats',
      message: error.message
    });
  }
});

module.exports = router;