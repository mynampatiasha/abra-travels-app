const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');

// GET /api/driver/dashboard/stats - Get driver's daily stats
router.get('/stats', async (req, res) => {
  try {
    const driverId = req.user.email;
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);

    // Get today's trips
    const trips = await req.db.collection('trips').find({
      driverId: driverId,
      startTime: {
        $gte: today,
        $lt: tomorrow
      }
    }).toArray();

    // Calculate stats
    const totalTrips = trips.length;
    const totalDistance = trips.reduce((sum, trip) => sum + (trip.distance || 0), 0);
    
    // Calculate on-time percentage (trips that arrived within 15 mins of estimated time)
    const completedTrips = trips.filter(trip => trip.status === 'completed');
    const onTimeTrips = completedTrips.filter(trip => {
      if (!trip.estimatedEndTime || !trip.actualEndTime) return false;
      const estimated = new Date(trip.estimatedEndTime);
      const actual = new Date(trip.actualEndTime);
      const diffMinutes = Math.abs(actual - estimated) / (1000 * 60);
      return diffMinutes <= 15;
    });
    const onTimePercentage = completedTrips.length > 0 
      ? Math.round((onTimeTrips.length / completedTrips.length) * 100) 
      : 100;

    // Get driver's average rating from completed trips
    const tripsWithRatings = completedTrips.filter(trip => trip.rating && trip.rating > 0);
    const averageRating = tripsWithRatings.length > 0
      ? (tripsWithRatings.reduce((sum, trip) => sum + trip.rating, 0) / tripsWithRatings.length).toFixed(1)
      : '5.0';

    res.json({
      status: 'success',
      data: {
        totalTrips: totalTrips,
        totalDistance: Math.round(totalDistance * 10) / 10, // Round to 1 decimal
        averageRating: averageRating,
        onTimePercentage: `${onTimePercentage}%`
      }
    });

  } catch (error) {
    console.error('Error fetching driver stats:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to fetch driver stats',
      error: error.message
    });
  }
});

// GET /api/driver/dashboard/vehicle-check - Get current vehicle status
router.get('/vehicle-check', async (req, res) => {
  try {
    const driverId = req.user.email;

    // Find the current active roster assignment for the driver
    const now = new Date();
    const roster = await req.db.collection('rosters').findOne({
      driverId: driverId,
      startTime: { $lte: now },
      endTime: { $gte: now },
      status: 'active'
    });

    if (!roster || !roster.vehicleId) {
      return res.json({
        status: 'success',
        data: {
          vehicleAssigned: false,
          checks: []
        }
      });
    }

    // Get the vehicle details
    const vehicle = await req.db.collection('vehicles').findOne({
      _id: new ObjectId(roster.vehicleId)
    });

    if (!vehicle) {
      return res.json({
        status: 'success',
        data: {
          vehicleAssigned: false,
          checks: []
        }
      });
    }

    // Get latest vehicle check/report for this vehicle
    const latestCheck = await req.db.collection('vehicle_checks').findOne(
      { vehicleId: roster.vehicleId },
      { sort: { checkDate: -1 } }
    );

    // Default check items
    const defaultChecks = [
      {
        label: 'Fuel Level',
        status: 'Full',
        isOk: true,
        lastChecked: null
      },
      {
        label: 'Engine Oil',
        status: 'Normal',
        isOk: true,
        lastChecked: null
      },
      {
        label: 'Tire Pressure',
        status: 'Normal',
        isOk: true,
        lastChecked: null
      },
      {
        label: 'Brake System',
        status: 'Normal',
        isOk: true,
        lastChecked: null
      }
    ];

    // If we have a recent check, use that data
    let checks = defaultChecks;
    if (latestCheck) {
      checks = latestCheck.checks || defaultChecks;
    }

    res.json({
      status: 'success',
      data: {
        vehicleAssigned: true,
        vehicleId: roster.vehicleId,
        vehicleNumber: vehicle.registrationNumber,
        vehicleModel: vehicle.model,
        checks: checks,
        lastCheckDate: latestCheck?.checkDate || null
      }
    });

  } catch (error) {
    console.error('Error fetching vehicle check:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to fetch vehicle check',
      error: error.message
    });
  }
});

// POST /api/driver/dashboard/vehicle-check - Submit vehicle check
router.post('/vehicle-check', async (req, res) => {
  try {
    const driverId = req.user.email;
    const { vehicleId, checks } = req.body;

    if (!vehicleId || !checks || !Array.isArray(checks)) {
      return res.status(400).json({
        status: 'error',
        message: 'Vehicle ID and checks array are required'
      });
    }

    // Verify the driver is assigned to this vehicle
    const now = new Date();
    const roster = await req.db.collection('rosters').findOne({
      driverId: driverId,
      vehicleId: vehicleId,
      startTime: { $lte: now },
      endTime: { $gte: now },
      status: 'active'
    });

    if (!roster) {
      return res.status(403).json({
        status: 'error',
        message: 'You are not assigned to this vehicle'
      });
    }

    // Save the vehicle check
    const checkDocument = {
      vehicleId: vehicleId,
      driverId: driverId,
      checkDate: new Date(),
      checks: checks,
      createdAt: new Date()
    };

    await req.db.collection('vehicle_checks').insertOne(checkDocument);

    // If any check is not OK, create an alert
    const issuesFound = checks.filter(check => !check.isOk);
    if (issuesFound.length > 0) {
      const alertDocument = {
        vehicleId: vehicleId,
        driverId: driverId,
        type: 'vehicle_check_issue',
        severity: 'warning',
        message: `Vehicle check found ${issuesFound.length} issue(s)`,
        issues: issuesFound.map(issue => ({
          label: issue.label,
          status: issue.status
        })),
        createdAt: new Date(),
        resolved: false
      };
      await req.db.collection('alerts').insertOne(alertDocument);
    }

    res.json({
      status: 'success',
      message: 'Vehicle check submitted successfully',
      data: {
        checkId: checkDocument._id,
        issuesFound: issuesFound.length
      }
    });

  } catch (error) {
    console.error('Error submitting vehicle check:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to submit vehicle check',
      error: error.message
    });
  }
});

module.exports = router;