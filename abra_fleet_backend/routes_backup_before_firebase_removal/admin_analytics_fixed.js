// routes/admin_analytics.js - FIXED VERSION
const express = require('express');
const router = express.Router();

// Get company analytics using existing data structure - FIXED to match actual trip data structure
router.get('/company-analytics', async (req, res) => {
  try {
    const { filter = 'today', company = 'all' } = req.query;
    const db = req.db;
    
    console.log('[Admin Analytics] Company analytics request:', { filter, company });
    
    // Calculate date range based on filter
    const now = new Date();
    let startDate, endDate = now;
    
    switch (filter) {
      case 'today':
        startDate = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        break;
      case 'week':
        startDate = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
        break;
      case 'month':
        startDate = new Date(now.getFullYear(), now.getMonth(), 1);
        break;
      default:
        startDate = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    }

    console.log('[Admin Analytics] Date range:', { startDate, endDate });

    // FIXED: Enhanced pipeline to match actual data structure
    // Trips use customerId (not customer.email) and various date fields
    const pipeline = [
      {
        $match: {
          role: 'customer',
          ...(company !== 'all' && { companyName: company })
        }
      },
      {
        $group: {
          _id: '$companyName',
          totalEmployees: { $sum: 1 },
          employees: {
            $push: {
              employeeId: '$employeeId',
              name: '$name',
              email: '$email',
              department: '$department',
              customerId: { $toString: '$_id' } // Convert ObjectId to string for trip lookup
            }
          }
        }
      },
      {
        $lookup: {
          from: 'trips',
          let: { 
            employeeIds: '$employees.customerId' // Get all employee _ids as strings
          },
          pipeline: [
            {
              $match: {
                $expr: { 
                  $in: ['$customerId', '$$employeeIds'] // Match trips by customerId
                },
                // FIXED: Use multiple date fields with OR condition
                $or: [
                  { createdAt: { $gte: startDate, $lte: endDate } },
                  { tripDate: { $gte: startDate, $lte: endDate } },
                  { completedAt: { $gte: startDate, $lte: endDate } }
                ]
              }
            }
          ],
          as: 'allTrips'
        }
      },
      {
        $addFields: {
          completedTrips: {
            $size: {
              $filter: {
                input: '$allTrips',
                cond: { $eq: ['$$this.status', 'completed'] }
              }
            }
          },
          cancelledTrips: {
            $size: {
              $filter: {
                input: '$allTrips',
                cond: { $eq: ['$$this.status', 'cancelled'] }
              }
            }
          },
          ongoingTrips: {
            $size: {
              $filter: {
                input: '$allTrips',
                cond: { $in: ['$$this.status', ['scheduled', 'in_progress', 'ongoing']] }
              }
            }
          },
          revenue: {
            $sum: {
              $map: {
                input: {
                  $filter: {
                    input: '$allTrips',
                    cond: { $eq: ['$$this.status', 'completed'] }
                  }
                },
                as: 'trip',
                in: { $ifNull: ['$$trip.fare', 0] }
              }
            }
          },
          // FIXED: Employee-wise trip breakdown using customerId
          employeeTrips: {
            $map: {
              input: '$employees',
              as: 'employee',
              in: {
                employeeId: '$$employee.employeeId',
                name: '$$employee.name',
                email: '$$employee.email',
                department: '$$employee.department',
                completedTrips: {
                  $size: {
                    $filter: {
                      input: '$allTrips',
                      cond: {
                        $and: [
                          { $eq: ['$$this.customerId', '$$employee.customerId'] },
                          { $eq: ['$$this.status', 'completed'] }
                        ]
                      }
                    }
                  }
                },
                cancelledTrips: {
                  $size: {
                    $filter: {
                      input: '$allTrips',
                      cond: {
                        $and: [
                          { $eq: ['$$this.customerId', '$$employee.customerId'] },
                          { $eq: ['$$this.status', 'cancelled'] }
                        ]
                      }
                    }
                  }
                },
                totalTrips: {
                  $size: {
                    $filter: {
                      input: '$allTrips',
                      cond: { $eq: ['$$this.customerId', '$$employee.customerId'] }
                    }
                  }
                },
                revenue: {
                  $sum: {
                    $map: {
                      input: {
                        $filter: {
                          input: '$allTrips',
                          cond: {
                            $and: [
                              { $eq: ['$$this.customerId', '$$employee.customerId'] },
                              { $eq: ['$$this.status', 'completed'] }
                            ]
                          }
                        }
                      },
                      as: 'trip',
                      in: { $ifNull: ['$$trip.fare', 0] }
                    }
                  }
                }
              }
            }
          }
        }
      },
      {
        $sort: { revenue: -1, completedTrips: -1, totalEmployees: -1 }
      },
      {
        $limit: 10
      }
    ];

    const companies = await db.collection('users').aggregate(pipeline).toArray();
    
    console.log('[Admin Analytics] Found companies:', companies.length);
    
    // Format the response with detailed employee information
    const mostActive = companies.map(company => ({
      name: company._id || 'Unknown Company',
      totalEmployees: company.totalEmployees || 0,
      completedTrips: company.completedTrips || 0,
      cancelledTrips: company.cancelledTrips || 0,
      ongoingTrips: company.ongoingTrips || 0,
      revenue: company.revenue || 0,
      averageTripsPerEmployee: company.totalEmployees > 0 
        ? Math.round((company.completedTrips || 0) / company.totalEmployees * 100) / 100 
        : 0,
      averageRevenuePerEmployee: company.totalEmployees > 0 
        ? Math.round((company.revenue || 0) / company.totalEmployees * 100) / 100 
        : 0,
      employeeBreakdown: (company.employeeTrips || [])
        .filter(emp => emp.totalTrips > 0) // Only show employees with trips
        .sort((a, b) => (b.completedTrips || 0) - (a.completedTrips || 0)) // Sort by completed trips
        .slice(0, 5) // Top 5 most active employees
    }));

    // Calculate overall analytics
    const analytics = {
      totalCompanies: companies.length,
      totalRevenue: companies.reduce((sum, c) => sum + (c.revenue || 0), 0),
      totalTrips: companies.reduce((sum, c) => sum + (c.completedTrips || 0) + (c.cancelledTrips || 0), 0),
      totalEmployees: companies.reduce((sum, c) => sum + (c.totalEmployees || 0), 0),
      averageRevenuePerCompany: companies.length > 0 
        ? companies.reduce((sum, c) => sum + (c.revenue || 0), 0) / companies.length 
        : 0,
      averageEmployeesPerCompany: companies.length > 0 
        ? companies.reduce((sum, c) => sum + (c.totalEmployees || 0), 0) / companies.length 
        : 0,
      averageTripsPerCompany: companies.length > 0 
        ? companies.reduce((sum, c) => sum + (c.completedTrips || 0), 0) / companies.length 
        : 0
    };

    console.log('[Admin Analytics] Analytics calculated:', analytics);

    res.json({
      success: true,
      analytics,
      mostActive,
      filter,
      dateRange: { startDate, endDate }
    });

  } catch (error) {
    console.error('[Admin Analytics] Error fetching company analytics:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch company analytics',
      error: error.message
    });
  }
});

// Get manpower statistics using existing collections
router.get('/manpower-stats', async (req, res) => {
  try {
    const db = req.db;
    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    console.log('[Admin Analytics] Fetching manpower stats...');

    // Get counts from existing collections using the correct structure
    const [
      totalCustomers,
      totalDrivers,
      totalVehicles,
      totalClients,
      pendingRosters,
      ongoingRosters,
      activeTrips,
      completedTripsToday,
      cancelledTripsToday
    ] = await Promise.all([
      // Count customers from users collection
      db.collection('users').countDocuments({ role: 'customer' }),
      
      // Count active drivers
      db.collection('drivers').countDocuments({ status: { $ne: 'inactive' } }),
      
      // Count active vehicles
      db.collection('vehicles').countDocuments({ status: { $ne: 'inactive' } }),
      
      // Count distinct companies from users collection
      db.collection('users').distinct('companyName', { role: 'customer' }).then(orgs => orgs.filter(org => org && org.trim()).length),
      
      // Count pending rosters
      db.collection('rosters').countDocuments({ status: 'pending_assignment' }),
      
      // Count ongoing rosters
      db.collection('rosters').countDocuments({ status: { $in: ['approved', 'in_progress'] } }),
      
      // Count active trips
      db.collection('trips').countDocuments({ status: { $in: ['scheduled', 'in_progress', 'ongoing'] } }),
      
      // Count completed trips today
      db.collection('trips').countDocuments({ 
        status: 'completed',
        $or: [
          { completedAt: { $gte: todayStart } },
          { updatedAt: { $gte: todayStart } }
        ]
      }),
      
      // Count cancelled trips today
      db.collection('trips').countDocuments({ 
        status: 'cancelled',
        $or: [
          { cancelledAt: { $gte: todayStart } },
          { updatedAt: { $gte: todayStart } }
        ]
      })
    ]);

    const stats = {
      totalCustomers,
      totalDrivers,
      totalVehicles,
      totalClients,
      pendingRosters,
      ongoingRosters,
      activeTrips,
      completedTripsToday,
      cancelledTripsToday
    };

    console.log('[Admin Analytics] Manpower stats:', stats);

    res.json({
      success: true,
      stats
    });

  } catch (error) {
    console.error('[Admin Analytics] Error fetching manpower stats:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch manpower statistics',
      error: error.message
    });
  }
});

// Get revenue statistics using existing trip data
router.get('/revenue-stats', async (req, res) => {
  try {
    const { filter = 'today' } = req.query;
    const db = req.db;
    const now = new Date();

    console.log('[Admin Analytics] Fetching revenue stats for filter:', filter);

    // Calculate date ranges
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const weekStart = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);

    // Get revenue for different periods using fare field
    const [todayRevenue, weekRevenue, monthRevenue] = await Promise.all([
      db.collection('trips').aggregate([
        {
          $match: {
            status: 'completed',
            $or: [
              { completedAt: { $gte: todayStart } },
              { updatedAt: { $gte: todayStart } }
            ]
          }
        },
        {
          $group: {
            _id: null,
            total: { $sum: { $ifNull: ['$fare', 0] } }
          }
        }
      ]).toArray(),
      
      db.collection('trips').aggregate([
        {
          $match: {
            status: 'completed',
            $or: [
              { completedAt: { $gte: weekStart } },
              { updatedAt: { $gte: weekStart } }
            ]
          }
        },
        {
          $group: {
            _id: null,
            total: { $sum: { $ifNull: ['$fare', 0] } }
          }
        }
      ]).toArray(),
      
      db.collection('trips').aggregate([
        {
          $match: {
            status: 'completed',
            $or: [
              { completedAt: { $gte: monthStart } },
              { updatedAt: { $gte: monthStart } }
            ]
          }
        },
        {
          $group: {
            _id: null,
            total: { $sum: { $ifNull: ['$fare', 0] } }
          }
        }
      ]).toArray()
    ]);

    const revenue = {
      todayRevenue: todayRevenue[0]?.total || 0,
      weekRevenue: weekRevenue[0]?.total || 0,
      monthRevenue: monthRevenue[0]?.total || 0
    };

    console.log('[Admin Analytics] Revenue stats:', revenue);

    res.json({
      success: true,
      revenue,
      filter
    });

  } catch (error) {
    console.error('[Admin Analytics] Error fetching revenue stats:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch revenue statistics',
      error: error.message
    });
  }
});

module.exports = router;