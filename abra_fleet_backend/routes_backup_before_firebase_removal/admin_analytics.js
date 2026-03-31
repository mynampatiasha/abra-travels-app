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
              customerId: '$firebaseUid' // Use firebaseUid for trip lookup
            }
          }
        }
      },
      {
        $lookup: {
          from: 'trips',
          let: { 
            employeeFirebaseUids: '$employees.customerId' // Get all employee firebaseUids
          },
          pipeline: [
            {
              $match: {
                $expr: { 
                  $in: ['$customerId', '$$employeeFirebaseUids'] // Match trips by customerId = firebaseUid
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

// Get detailed trip information by type
router.get('/trips/:type', async (req, res) => {
  try {
    const { type } = req.params;
    const db = req.db;
    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    console.log(`[Admin Analytics] Fetching ${type} trips...`);

    let matchCondition = {};
    
    switch (type) {
      case 'active':
        matchCondition = { status: { $in: ['scheduled', 'in_progress', 'ongoing'] } };
        break;
      case 'completed-today':
        matchCondition = { 
          status: 'completed',
          $or: [
            { completedAt: { $gte: todayStart } },
            { updatedAt: { $gte: todayStart } }
          ]
        };
        break;
      case 'cancelled-today':
        matchCondition = { 
          status: 'cancelled',
          $or: [
            { cancelledAt: { $gte: todayStart } },
            { updatedAt: { $gte: todayStart } }
          ]
        };
        break;
      default:
        return res.status(400).json({
          success: false,
          message: 'Invalid trip type. Use: active, completed-today, or cancelled-today'
        });
    }

    const pipeline = [
      { $match: matchCondition },
      {
        $lookup: {
          from: 'users',
          localField: 'customerId',
          foreignField: 'firebaseUid',
          as: 'customer'
        }
      },
      {
        $lookup: {
          from: 'drivers',
          localField: 'driverId',
          foreignField: 'firebaseUid',
          as: 'driver'
        }
      },
      {
        $lookup: {
          from: 'vehicles',
          localField: 'vehicleId',
          foreignField: '_id',
          as: 'vehicle'
        }
      },
      {
        $addFields: {
          customerName: { $arrayElemAt: ['$customer.name', 0] },
          driverName: { $arrayElemAt: ['$driver.name', 0] },
          vehicleNumber: { $arrayElemAt: ['$vehicle.vehicleNumber', 0] }
        }
      },
      {
        $project: {
          tripId: '$_id',
          customerId: 1,
          customerName: 1,
          driverId: 1,
          driverName: 1,
          vehicleId: 1,
          vehicleNumber: 1,
          pickupLocation: 1,
          dropLocation: 1,
          fare: 1,
          status: 1,
          createdAt: 1,
          updatedAt: 1,
          completedAt: 1,
          cancelledAt: 1
        }
      },
      { $sort: { createdAt: -1 } },
      { $limit: 50 }
    ];

    const trips = await db.collection('trips').aggregate(pipeline).toArray();

    console.log(`[Admin Analytics] Found ${trips.length} ${type} trips`);

    res.json({
      success: true,
      trips,
      type,
      count: trips.length
    });

  } catch (error) {
    console.error(`[Admin Analytics] Error fetching ${req.params.type} trips:`, error);
    res.status(500).json({
      success: false,
      message: `Failed to fetch ${req.params.type} trips`,
      error: error.message
    });
  }
});

// Get driver ratings overview
router.get('/ratings/overview', async (req, res) => {
  try {
    const db = req.db;

    console.log('[Admin Analytics] Fetching ratings overview...');

    // Get all ratings with driver information
    const pipeline = [
      {
        $lookup: {
          from: 'drivers',
          localField: 'driverId',
          foreignField: 'firebaseUid',
          as: 'driver'
        }
      },
      {
        $addFields: {
          driverName: { $arrayElemAt: ['$driver.name', 0] }
        }
      },
      {
        $group: {
          _id: '$driverId',
          driverName: { $first: '$driverName' },
          ratings: { $push: '$rating' },
          averageRating: { $avg: '$rating' },
          totalRatings: { $sum: 1 }
        }
      },
      { $sort: { averageRating: -1, totalRatings: -1 } }
    ];

    const driverRatings = await db.collection('ratings').aggregate(pipeline).toArray();

    // Calculate overall statistics
    const allRatings = await db.collection('ratings').find({}).toArray();
    const totalRatings = allRatings.length;
    const averageRating = totalRatings > 0 
      ? allRatings.reduce((sum, r) => sum + r.rating, 0) / totalRatings 
      : 0;

    // Calculate rating distribution
    const distribution = {};
    for (let i = 1; i <= 5; i++) {
      distribution[i] = allRatings.filter(r => Math.floor(r.rating) === i).length;
    }

    // Get top 10 drivers
    const topDrivers = driverRatings
      .filter(d => d.totalRatings >= 3) // Only drivers with at least 3 ratings
      .slice(0, 10);

    const ratingsData = {
      averageRating,
      totalRatings,
      distribution,
      topDrivers,
      totalDriversRated: driverRatings.length
    };

    console.log('[Admin Analytics] Ratings overview calculated:', {
      averageRating,
      totalRatings,
      topDriversCount: topDrivers.length
    });

    res.json({
      success: true,
      ratingsData
    });

  } catch (error) {
    console.error('[Admin Analytics] Error fetching ratings overview:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch ratings overview',
      error: error.message
    });
  }
});

// Get average driver rating
router.get('/ratings/average', async (req, res) => {
  try {
    const db = req.db;

    console.log('[Admin Analytics] Fetching average driver rating...');

    const result = await db.collection('ratings').aggregate([
      {
        $group: {
          _id: null,
          averageRating: { $avg: '$rating' },
          totalRatings: { $sum: 1 }
        }
      }
    ]).toArray();

    const averageRating = result.length > 0 ? result[0].averageRating : 0;
    const totalRatings = result.length > 0 ? result[0].totalRatings : 0;

    console.log('[Admin Analytics] Average rating calculated:', { averageRating, totalRatings });

    res.json({
      success: true,
      averageRating,
      totalRatings
    });

  } catch (error) {
    console.error('[Admin Analytics] Error fetching average rating:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch average rating',
      error: error.message
    });
  }
});

// Get revenue details by type
router.get('/revenue/details', async (req, res) => {
  try {
    const { type = 'today' } = req.query;
    const db = req.db;
    const now = new Date();

    console.log(`[Admin Analytics] Fetching ${type} revenue details...`);

    // Calculate date range
    let startDate, endDate = now;
    
    switch (type) {
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

    const pipeline = [
      {
        $match: {
          status: 'completed',
          $or: [
            { completedAt: { $gte: startDate, $lte: endDate } },
            { updatedAt: { $gte: startDate, $lte: endDate } }
          ]
        }
      },
      {
        $lookup: {
          from: 'users',
          localField: 'customerId',
          foreignField: 'firebaseUid',
          as: 'customer'
        }
      },
      {
        $addFields: {
          companyName: { $arrayElemAt: ['$customer.companyName', 0] }
        }
      },
      {
        $group: {
          _id: '$companyName',
          totalRevenue: { $sum: { $ifNull: ['$fare', 0] } },
          totalTrips: { $sum: 1 },
          trips: {
            $push: {
              tripId: '$_id',
              fare: '$fare',
              completedAt: '$completedAt'
            }
          }
        }
      },
      { $sort: { totalRevenue: -1 } }
    ];

    const revenueBreakdown = await db.collection('trips').aggregate(pipeline).toArray();

    // Calculate totals
    const totalRevenue = revenueBreakdown.reduce((sum, item) => sum + item.totalRevenue, 0);
    const totalTrips = revenueBreakdown.reduce((sum, item) => sum + item.totalTrips, 0);

    // Format breakdown for response
    const breakdown = revenueBreakdown.map(item => ({
      source: item._id || 'Unknown Company',
      amount: item.totalRevenue,
      trips: item.totalTrips
    }));

    const revenueData = {
      totalRevenue,
      totalTrips,
      breakdown,
      type,
      dateRange: { startDate, endDate }
    };

    console.log(`[Admin Analytics] ${type} revenue details:`, {
      totalRevenue,
      totalTrips,
      breakdownCount: breakdown.length
    });

    res.json({
      success: true,
      revenueData
    });

  } catch (error) {
    console.error(`[Admin Analytics] Error fetching ${req.query.type} revenue details:`, error);
    res.status(500).json({
      success: false,
      message: `Failed to fetch ${req.query.type} revenue details`,
      error: error.message
    });
  }
});

// GET /api/admin/analytics/company-employee-stats
router.get('/company-employee-stats', async (req, res) => {
  try {
    const db = req.db;
    console.log('[Admin Analytics] Fetching company employee stats...');

    // Get unique companies from users collection (customers with companyName/organizationName)
    const usersData = await db.collection('users').find({ role: 'customer' }).toArray();
    
    if (!usersData || usersData.length === 0) {
      return res.json({
        success: true,
        companies: [],
        message: 'No customer data found'
      });
    }

    // Also get companies from customers collection
    const customersData = await db.collection('customers').find({}).toArray();
    
    // Fetch trip data for additional metrics
    const tripsData = await db.collection('trips').find({}).toArray();

    // Extract unique companies from both collections
    const companiesMap = new Map();
    
    // From users collection (customers)
    usersData.forEach(user => {
      const companyName = user.companyName || user.organizationName;
      if (companyName && companyName.trim()) {
        if (!companiesMap.has(companyName)) {
          companiesMap.set(companyName, {
            name: companyName,
            employees: [],
            source: 'users'
          });
        }
        companiesMap.get(companyName).employees.push(user);
      }
    });
    
    // From customers collection
    customersData.forEach(customer => {
      const companyName = customer.company?.name || customer.name?.companyName;
      if (companyName && companyName.trim()) {
        if (!companiesMap.has(companyName)) {
          companiesMap.set(companyName, {
            name: companyName,
            employees: [],
            source: 'customers'
          });
        }
        // Add customer as employee if not already added
        const existing = companiesMap.get(companyName).employees.find(e => 
          e.email === customer.contactInfo?.email || e._id === customer._id
        );
        if (!existing) {
          companiesMap.get(companyName).employees.push({
            _id: customer._id,
            name: customer.name?.firstName + ' ' + customer.name?.lastName,
            email: customer.contactInfo?.email,
            firebaseUid: customer.customerId,
            status: customer.status || 'active'
          });
        }
      }
    });

    // Process company data
    const companies = [];
    
    for (const [companyName, companyData] of companiesMap) {
      const companyEmployees = companyData.employees;
      
      // Count trips for this company
      const companyTrips = tripsData.filter(trip => {
        // Match by customer's company
        const tripCustomer = usersData.find(c => 
          c.firebaseUid === trip.customerId || 
          c._id?.toString() === trip.customerId
        );
        return tripCustomer && (
          tripCustomer.companyName === companyName || 
          tripCustomer.organizationName === companyName
        );
      });

      const activeTrips = companyTrips.filter(trip => 
        trip.status === 'in_progress' || trip.status === 'ongoing' || trip.status === 'scheduled'
      ).length;
      
      const completedTrips = companyTrips.filter(trip => trip.status === 'completed').length;

      // Calculate total revenue
      const totalRevenue = companyTrips
        .filter(trip => trip.status === 'completed' && trip.fare)
        .reduce((sum, trip) => sum + (parseFloat(trip.fare) || 0), 0);

      companies.push({
        id: companyName.toLowerCase().replace(/\s+/g, '_'),
        name: companyName,
        totalEmployees: companyEmployees.length,
        activeEmployees: companyEmployees.filter(e => e.status === 'active' || !e.status).length,
        activeTrips: activeTrips,
        completedTrips: completedTrips,
        totalRevenue: totalRevenue,
        contactPerson: null,
        phone: null,
        email: null,
        status: 'active'
      });
    }

    // Sort by total employees in descending order
    companies.sort((a, b) => b.totalEmployees - a.totalEmployees);

    console.log(`[Admin Analytics] Found ${companies.length} companies with employee data`);

    return res.json({
      success: true,
      companies: companies,
      totalCompanies: companies.length,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ Error fetching company employee stats:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to fetch company employee statistics',
      error: error.message
    });
  }
});

module.exports = router;