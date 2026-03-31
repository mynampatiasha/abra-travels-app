const express = require('express');
const router = express.Router();
const { body, validationResult, query, param } = require('express-validator');

// @route   GET /api/client/dashboard/analytics
// @desc    Get comprehensive client analytics dashboard
// @access  Private (Admin/Client Manager)
router.get('/dashboard/analytics', [
  query('clientId').optional().notEmpty().withMessage('Client ID required'),
  query('timeframe').optional().isIn(['7d', '30d', '90d', '1y']).withMessage('Invalid timeframe'),
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: errors.array().map(err => err.msg)
      });
    }

    const { clientId, timeframe = '30d' } = req.query;
    
    // Calculate date range
    const endDate = new Date();
    const startDate = new Date();
    
    switch (timeframe) {
      case '7d':
        startDate.setDate(endDate.getDate() - 7);
        break;
      case '30d':
        startDate.setDate(endDate.getDate() - 30);
        break;
      case '90d':
        startDate.setDate(endDate.getDate() - 90);
        break;
      case '1y':
        startDate.setFullYear(endDate.getFullYear() - 1);
        break;
      default:
        startDate.setDate(endDate.getDate() - 30);
    }

    // Build match criteria
    let matchCriteria = {
      createdAt: { $gte: startDate, $lte: endDate }
    };
    
    if (clientId) {
      matchCriteria.clientId = clientId;
    }

    // Get trip analytics
    const tripAnalytics = await req.db.collection('trips').aggregate([
      { $match: matchCriteria },
      {
        $group: {
          _id: '$clientId',
          totalTrips: { $sum: 1 },
          completedTrips: {
            $sum: { $cond: [{ $eq: ['$status', 'completed'] }, 1, 0] }
          },
          cancelledTrips: {
            $sum: { $cond: [{ $eq: ['$status', 'cancelled'] }, 1, 0] }
          },
          totalRevenue: { $sum: '$fare' },
          totalDistance: { $sum: '$distance' },
          averageRating: { $avg: '$customerRating' },
          uniqueCustomers: { $addToSet: '$customerId' }
        }
      },
      {
        $addFields: {
          uniqueCustomerCount: { $size: '$uniqueCustomers' },
          completionRate: {
            $cond: {
              if: { $gt: ['$totalTrips', 0] },
              then: { $multiply: [{ $divide: ['$completedTrips', '$totalTrips'] }, 100] },
              else: 0
            }
          },
          cancellationRate: {
            $cond: {
              if: { $gt: ['$totalTrips', 0] },
              then: { $multiply: [{ $divide: ['$cancelledTrips', '$totalTrips'] }, 100] },
              else: 0
            }
          }
        }
      }
    ]).toArray();

    // Get vehicle utilization for client
    const vehicleUtilization = await req.db.collection('vehicles').aggregate([
      {
        $lookup: {
          from: 'trips',
          let: { vehicleId: '$vehicleId' },
          pipeline: [
            {
              $match: {
                $expr: { $eq: ['$vehicleId', '$$vehicleId'] },
                ...matchCriteria
              }
            }
          ],
          as: 'trips'
        }
      },
      {
        $addFields: {
          tripCount: { $size: '$trips' },
          utilizationRate: {
            $cond: {
              if: { $gt: [{ $size: '$trips' }, 0] },
              then: { $multiply: [{ $divide: [{ $size: '$trips' }, 30] }, 100] }, // Assuming 30 days max utilization
              else: 0
            }
          }
        }
      },
      {
        $group: {
          _id: null,
          totalVehicles: { $sum: 1 },
          activeVehicles: {
            $sum: { $cond: [{ $gt: ['$tripCount', 0] }, 1, 0] }
          },
          averageUtilization: { $avg: '$utilizationRate' },
          totalTripsServed: { $sum: '$tripCount' }
        }
      }
    ]).toArray();

    // Get customer satisfaction metrics
    const satisfactionMetrics = await req.db.collection('feedback').aggregate([
      {
        $match: {
          ...matchCriteria,
          ...(clientId && { clientId })
        }
      },
      {
        $group: {
          _id: '$type',
          averageRating: { $avg: '$rating' },
          totalFeedback: { $sum: 1 },
          positiveRatings: {
            $sum: { $cond: [{ $gte: ['$rating', 4] }, 1, 0] }
          },
          negativeRatings: {
            $sum: { $cond: [{ $lte: ['$rating', 2] }, 1, 0] }
          }
        }
      }
    ]).toArray();

    // Get monthly trend data
    const monthlyTrends = await req.db.collection('trips').aggregate([
      { $match: matchCriteria },
      {
        $group: {
          _id: {
            year: { $year: '$createdAt' },
            month: { $month: '$createdAt' }
          },
          trips: { $sum: 1 },
          revenue: { $sum: '$fare' },
          distance: { $sum: '$distance' }
        }
      },
      { $sort: { '_id.year': 1, '_id.month': 1 } }
    ]).toArray();

    // Get top performing routes
    const topRoutes = await req.db.collection('trips').aggregate([
      { $match: matchCriteria },
      {
        $group: {
          _id: {
            pickup: '$pickupLocation',
            drop: '$dropLocation'
          },
          tripCount: { $sum: 1 },
          totalRevenue: { $sum: '$fare' },
          averageRating: { $avg: '$customerRating' }
        }
      },
      { $sort: { tripCount: -1 } },
      { $limit: 10 }
    ]).toArray();

    // Compile response
    const analytics = tripAnalytics[0] || {};
    const vehicleStats = vehicleUtilization[0] || {};
    
    res.json({
      success: true,
      data: {
        timeframe,
        period: { startDate, endDate },
        overview: {
          totalTrips: analytics.totalTrips || 0,
          completedTrips: analytics.completedTrips || 0,
          cancelledTrips: analytics.cancelledTrips || 0,
          totalRevenue: analytics.totalRevenue || 0,
          totalDistance: analytics.totalDistance || 0,
          uniqueCustomers: analytics.uniqueCustomerCount || 0,
          completionRate: parseFloat((analytics.completionRate || 0).toFixed(2)),
          cancellationRate: parseFloat((analytics.cancellationRate || 0).toFixed(2)),
          averageRating: analytics.averageRating ? parseFloat(analytics.averageRating.toFixed(2)) : null
        },
        fleet: {
          totalVehicles: vehicleStats.totalVehicles || 0,
          activeVehicles: vehicleStats.activeVehicles || 0,
          averageUtilization: vehicleStats.averageUtilization ? parseFloat(vehicleStats.averageUtilization.toFixed(2)) : 0,
          totalTripsServed: vehicleStats.totalTripsServed || 0
        },
        satisfaction: satisfactionMetrics.reduce((acc, metric) => {
          acc[metric._id] = {
            averageRating: parseFloat((metric.averageRating || 0).toFixed(2)),
            totalFeedback: metric.totalFeedback,
            satisfactionRate: metric.totalFeedback > 0 
              ? parseFloat(((metric.positiveRatings / metric.totalFeedback) * 100).toFixed(2))
              : 0
          };
          return acc;
        }, {}),
        trends: {
          monthly: monthlyTrends.map(trend => ({
            period: `${trend._id.year}-${String(trend._id.month).padStart(2, '0')}`,
            trips: trend.trips,
            revenue: trend.revenue,
            distance: trend.distance
          }))
        },
        topRoutes: topRoutes.map(route => ({
          route: `${route._id.pickup} → ${route._id.drop}`,
          tripCount: route.tripCount,
          revenue: route.totalRevenue,
          averageRating: route.averageRating ? parseFloat(route.averageRating.toFixed(2)) : null
        }))
      }
    });

  } catch (error) {
    console.error('Client analytics error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while fetching client analytics',
      error: error.message
    });
  }
});

// @route   POST /api/client/contract/create
// @desc    Create a new client contract
// @access  Private (Admin)
router.post('/contract/create', [
  body('clientName').notEmpty().withMessage('Client name is required'),
  body('contactPerson').notEmpty().withMessage('Contact person is required'),
  body('email').isEmail().withMessage('Valid email is required'),
  body('phone').notEmpty().withMessage('Phone number is required'),
  body('contractType').isIn(['monthly', 'yearly', 'per_trip', 'custom']).withMessage('Invalid contract type'),
  body('startDate').isISO8601().withMessage('Valid start date is required'),
  body('endDate').isISO8601().withMessage('Valid end date is required'),
  body('rateStructure').isObject().withMessage('Rate structure is required'),
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: errors.array().map(err => err.msg)
      });
    }

    const {
      clientName,
      contactPerson,
      email,
      phone,
      address,
      contractType,
      startDate,
      endDate,
      rateStructure,
      vehicleAllocation,
      serviceLevel,
      paymentTerms,
      specialRequirements
    } = req.body;

    // Generate client ID
    const clientId = `CL${Date.now().toString().slice(-6)}`;

    // Create contract document
    const contractData = {
      clientId,
      clientName,
      contactPerson,
      email,
      phone,
      address: address || '',
      contractType,
      startDate: new Date(startDate),
      endDate: new Date(endDate),
      rateStructure: {
        baseRate: rateStructure.baseRate || 0,
        perKmRate: rateStructure.perKmRate || 0,
        perHourRate: rateStructure.perHourRate || 0,
        minimumCharge: rateStructure.minimumCharge || 0,
        currency: rateStructure.currency || 'INR'
      },
      vehicleAllocation: vehicleAllocation || {
        dedicatedVehicles: [],
        sharedPool: true,
        priorityLevel: 'standard'
      },
      serviceLevel: serviceLevel || {
        responseTime: '15 minutes',
        availability: '24/7',
        supportLevel: 'standard'
      },
      paymentTerms: paymentTerms || {
        billingCycle: 'monthly',
        paymentDue: 30,
        currency: 'INR'
      },
      specialRequirements: specialRequirements || [],
      status: 'active',
      createdBy: { email: req.user?.uid || 'system',
        email: req.user?.email || 'system',
        name: req.user?.name || req.user?.email || 'System'
       },
      createdAt: new Date(),
      updatedAt: new Date()
    };

    // Insert contract
    const result = await req.db.collection('client_contracts').insertOne(contractData);

    if (!result.insertedId) {
      throw new Error('Failed to create contract');
    }

    // Create client profile
    const clientProfile = {
      clientId,
      name: clientName,
      contactPerson,
      email,
      phone,
      address,
      contractId: result.insertedId,
      status: 'active',
      totalTrips: 0,
      totalRevenue: 0,
      lastActivity: new Date(),
      createdAt: new Date(),
      updatedAt: new Date()
    };

    await req.db.collection('clients').insertOne(clientProfile);

    res.status(201).json({
      success: true,
      message: 'Client contract created successfully',
      data: {
        contractId: result.insertedId,
        clientId,
        ...contractData
      }
    });

  } catch (error) {
    console.error('Create contract error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while creating contract',
      error: error.message
    });
  }
});

// @route   GET /api/client/billing/generate
// @desc    Generate billing report for client
// @access  Private (Admin/Client Manager)
router.get('/billing/generate', [
  query('clientId').notEmpty().withMessage('Client ID is required'),
  query('billingPeriod').notEmpty().withMessage('Billing period is required'),
  query('startDate').isISO8601().withMessage('Valid start date is required'),
  query('endDate').isISO8601().withMessage('Valid end date is required'),
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: errors.array().map(err => err.msg)
      });
    }

    const { clientId, billingPeriod, startDate, endDate } = req.query;
    const periodStart = new Date(startDate);
    const periodEnd = new Date(endDate);

    // Get client contract details
    const client = await req.db.collection('clients').findOne({ clientId });
    if (!client) {
      return res.status(404).json({
        success: false,
        message: 'Client not found'
      });
    }

    const contract = await req.db.collection('client_contracts').findOne({
      clientId: clientId,
      status: 'active'
    });

    if (!contract) {
      return res.status(404).json({
        success: false,
        message: 'Active contract not found for client'
      });
    }

    // Get all trips for the billing period
    const trips = await req.db.collection('trips').find({
      clientId: clientId,
      status: 'completed',
      completedAt: { $gte: periodStart, $lte: periodEnd }
    }).toArray();

    // Calculate billing details
    let totalAmount = 0;
    let totalDistance = 0;
    let totalDuration = 0;
    const tripDetails = [];

    for (const trip of trips) {
      const distance = trip.distance || 0;
      const duration = trip.duration || 0; // in minutes
      const durationHours = duration / 60;

      // Calculate trip cost based on rate structure
      let tripCost = 0;
      const rates = contract.rateStructure;

      switch (contract.contractType) {
        case 'per_trip':
          tripCost = rates.baseRate || 0;
          break;
        case 'monthly':
          // For monthly contracts, trips might be included or charged separately
          tripCost = (rates.perKmRate || 0) * distance + (rates.perHourRate || 0) * durationHours;
          break;
        default:
          tripCost = rates.baseRate + (rates.perKmRate || 0) * distance + (rates.perHourRate || 0) * durationHours;
      }

      // Apply minimum charge if applicable
      if (rates.minimumCharge && tripCost < rates.minimumCharge) {
        tripCost = rates.minimumCharge;
      }

      totalAmount += tripCost;
      totalDistance += distance;
      totalDuration += duration;

      tripDetails.push({
        tripId: trip.tripId,
        date: trip.completedAt,
        pickup: trip.pickupLocation,
        drop: trip.dropLocation,
        distance: distance,
        duration: duration,
        vehicleType: trip.vehicleInfo?.type || 'N/A',
        cost: tripCost
      });
    }

    // Apply any contract-level discounts or surcharges
    const discountPercentage = contract.discount?.percentage || 0;
    const discountAmount = (totalAmount * discountPercentage) / 100;
    const netAmount = totalAmount - discountAmount;

    // Calculate taxes
    const taxRate = contract.taxRate || 18; // Default GST rate
    const taxAmount = (netAmount * taxRate) / 100;
    const finalAmount = netAmount + taxAmount;

    // Generate invoice number
    const invoiceNumber = `INV-${clientId}-${Date.now().toString().slice(-6)}`;

    // Create billing document
    const billingData = {
      invoiceNumber,
      clientId,
      clientName: client.name,
      billingPeriod,
      periodStart,
      periodEnd,
      contract: {
        contractId: contract._id,
        contractType: contract.contractType,
        rateStructure: contract.rateStructure
      },
      summary: {
        totalTrips: trips.length,
        totalDistance: parseFloat(totalDistance.toFixed(2)),
        totalDuration: Math.round(totalDuration),
        grossAmount: parseFloat(totalAmount.toFixed(2)),
        discountPercentage,
        discountAmount: parseFloat(discountAmount.toFixed(2)),
        netAmount: parseFloat(netAmount.toFixed(2)),
        taxRate,
        taxAmount: parseFloat(taxAmount.toFixed(2)),
        finalAmount: parseFloat(finalAmount.toFixed(2)),
        currency: contract.rateStructure.currency || 'INR'
      },
      tripDetails,
      status: 'generated',
      generatedAt: new Date(),
      generatedBy: { email: req.user?.uid || 'system',
        email: req.user?.email || 'system'
       }
    };

    // Save billing record
    const result = await req.db.collection('client_billing').insertOne(billingData);

    res.json({
      success: true,
      message: 'Billing report generated successfully',
      data: {
        billingId: result.insertedId,
        ...billingData
      }
    });

  } catch (error) {
    console.error('Generate billing error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while generating billing report',
      error: error.message
    });
  }
});

// @route   GET /api/client/performance/report
// @desc    Get client performance report
// @access  Private (Admin/Client Manager)
router.get('/performance/report', [
  query('clientId').notEmpty().withMessage('Client ID is required'),
  query('timeframe').optional().isIn(['7d', '30d', '90d', '1y']).withMessage('Invalid timeframe'),
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: errors.array().map(err => err.msg)
      });
    }

    const { clientId, timeframe = '30d' } = req.query;
    
    // Calculate date range
    const endDate = new Date();
    const startDate = new Date();
    
    switch (timeframe) {
      case '7d':
        startDate.setDate(endDate.getDate() - 7);
        break;
      case '30d':
        startDate.setDate(endDate.getDate() - 30);
        break;
      case '90d':
        startDate.setDate(endDate.getDate() - 90);
        break;
      case '1y':
        startDate.setFullYear(endDate.getFullYear() - 1);
        break;
    }

    // Get client details
    const client = await req.db.collection('clients').findOne({ clientId });
    if (!client) {
      return res.status(404).json({
        success: false,
        message: 'Client not found'
      });
    }

    // Performance metrics aggregation
    const performanceMetrics = await req.db.collection('trips').aggregate([
      {
        $match: {
          clientId: clientId,
          createdAt: { $gte: startDate, $lte: endDate }
        }
      },
      {
        $group: {
          _id: null,
          totalTrips: { $sum: 1 },
          completedTrips: {
            $sum: { $cond: [{ $eq: ['$status', 'completed'] }, 1, 0] }
          },
          cancelledTrips: {
            $sum: { $cond: [{ $eq: ['$status', 'cancelled'] }, 1, 0] }
          },
          onTimeTrips: {
            $sum: { $cond: [{ $eq: ['$onTime', true] }, 1, 0] }
          },
          totalRevenue: { $sum: '$fare' },
          totalDistance: { $sum: '$distance' },
          averageRating: { $avg: '$customerRating' },
          averageTripDuration: { $avg: '$duration' }
        }
      }
    ]).toArray();

    const metrics = performanceMetrics[0] || {};

    // Calculate KPIs
    const completionRate = metrics.totalTrips > 0 
      ? ((metrics.completedTrips / metrics.totalTrips) * 100).toFixed(2)
      : 0;
    
    const cancellationRate = metrics.totalTrips > 0 
      ? ((metrics.cancelledTrips / metrics.totalTrips) * 100).toFixed(2)
      : 0;
    
    const onTimePerformance = metrics.completedTrips > 0 
      ? ((metrics.onTimeTrips / metrics.completedTrips) * 100).toFixed(2)
      : 0;

    // Get vehicle utilization
    const vehicleUtilization = await req.db.collection('trips').aggregate([
      {
        $match: {
          clientId: clientId,
          createdAt: { $gte: startDate, $lte: endDate }
        }
      },
      {
        $group: {
          _id: '$vehicleId',
          tripCount: { $sum: 1 },
          totalDistance: { $sum: '$distance' },
          totalRevenue: { $sum: '$fare' }
        }
      },
      { $sort: { tripCount: -1 } },
      { $limit: 10 }
    ]).toArray();

    // Get customer satisfaction trends
    const satisfactionTrends = await req.db.collection('feedback').aggregate([
      {
        $match: {
          clientId: clientId,
          createdAt: { $gte: startDate, $lte: endDate }
        }
      },
      {
        $group: {
          _id: {
            year: { $year: '$createdAt' },
            month: { $month: '$createdAt' },
            week: { $week: '$createdAt' }
          },
          averageRating: { $avg: '$rating' },
          feedbackCount: { $sum: 1 }
        }
      },
      { $sort: { '_id.year': 1, '_id.month': 1, '_id.week': 1 } }
    ]).toArray();

    res.json({
      success: true,
      data: {
        client: {
          clientId: client.clientId,
          name: client.name,
          contactPerson: client.contactPerson
        },
        period: { startDate, endDate, timeframe },
        kpis: {
          totalTrips: metrics.totalTrips || 0,
          completionRate: parseFloat(completionRate),
          cancellationRate: parseFloat(cancellationRate),
          onTimePerformance: parseFloat(onTimePerformance),
          averageRating: metrics.averageRating ? parseFloat(metrics.averageRating.toFixed(2)) : null,
          totalRevenue: metrics.totalRevenue || 0,
          totalDistance: metrics.totalDistance || 0,
          averageTripDuration: metrics.averageTripDuration ? Math.round(metrics.averageTripDuration) : 0
        },
        vehiclePerformance: vehicleUtilization.map(vehicle => ({
          vehicleId: vehicle._id,
          tripCount: vehicle.tripCount,
          totalDistance: vehicle.totalDistance,
          totalRevenue: vehicle.totalRevenue,
          averageRevenuePerTrip: vehicle.tripCount > 0 
            ? parseFloat((vehicle.totalRevenue / vehicle.tripCount).toFixed(2))
            : 0
        })),
        satisfactionTrends: satisfactionTrends.map(trend => ({
          period: `${trend._id.year}-W${trend._id.week}`,
          averageRating: parseFloat(trend.averageRating.toFixed(2)),
          feedbackCount: trend.feedbackCount
        }))
      }
    });

  } catch (error) {
    console.error('Client performance report error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while generating performance report',
      error: error.message
    });
  }
});

module.exports = router;