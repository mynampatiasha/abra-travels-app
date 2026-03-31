// routes/driver_demo_data.js
// Special demo data endpoints for drivertest@gmail.com

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');

// Demo data for drivertest@gmail.com
const DEMO_DRIVER_EMAIL = 'drivertest@gmail.com';

// Check if request is for demo driver
function isDemoDriver(email) {
  return email && email.toLowerCase() === DEMO_DRIVER_EMAIL;
}

// GET /api/driver/demo/active-trip - Get demo active trip
router.get('/active-trip', async (req, res) => {
  try {
    const userEmail = req.user?.email || req.query.email;
    
    if (!isDemoDriver(userEmail)) {
      return res.status(404).json({
        success: false,
        message: 'Demo data only available for demo driver'
      });
    }

    const demoActiveTrip = {
      trip: {
        id: 'demo_trip_001',
        tripNumber: 'TR240001',
        from: 'Koramangala, Bangalore',
        to: 'Manyata Tech Park, Bangalore',
        distance: 18.5,
        customers: 1,
        status: 'in_progress',
        startTime: new Date(Date.now() - 30 * 60 * 1000).toISOString(), // 30 minutes ago
        estimatedEndTime: new Date(Date.now() + 60 * 60 * 1000).toISOString(), // 1 hour from now
        currentLocation: {
          latitude: 12.9716,
          longitude: 77.5946,
          address: 'MG Road, Bangalore'
        }
      },
      customer: {
        id: 'demo_customer_001',
        name: 'Priya Sharma',
        phone: '+91 9123456789',
        email: 'customer123@abrafleet.com',
        pickupAddress: 'Koramangala, Bangalore',
        dropAddress: 'Manyata Tech Park, Bangalore'
      },
      vehicle: {
        id: 'demo_vehicle_001',
        registrationNumber: 'KA01AB1234',
        model: 'Maruti Eeco',
        type: 'Van',
        capacity: 4,
        fuelType: 'Petrol'
      }
    };

    res.json({
      success: true,
      data: demoActiveTrip
    });

  } catch (error) {
    console.error('Error fetching demo active trip:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch demo active trip',
      error: error.message
    });
  }
});

// GET /api/driver/demo/dashboard-stats - Get demo dashboard stats
router.get('/dashboard-stats', async (req, res) => {
  try {
    const userEmail = req.user?.email || req.query.email;
    
    if (!isDemoDriver(userEmail)) {
      return res.status(404).json({
        success: false,
        message: 'Demo data only available for demo driver'
      });
    }

    const demoStats = {
      totalTrips: 15,
      totalDistance: 287.5,
      averageRating: '4.8',
      onTimePercentage: '94%',
      completedTrips: 14,
      cancelledTrips: 1,
      totalEarnings: 4250,
      monthlyTrips: 15,
      weeklyTrips: 4
    };

    res.json({
      success: true,
      data: demoStats
    });

  } catch (error) {
    console.error('Error fetching demo dashboard stats:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch demo dashboard stats',
      error: error.message
    });
  }
});

// GET /api/driver/demo/vehicle-check - Get demo vehicle check data
router.get('/vehicle-check', async (req, res) => {
  try {
    const userEmail = req.user?.email || req.query.email;
    
    if (!isDemoDriver(userEmail)) {
      return res.status(404).json({
        success: false,
        message: 'Demo data only available for demo driver'
      });
    }

    const demoVehicleCheck = {
      vehicle: {
        registrationNumber: 'KA01AB1234',
        model: 'Maruti Eeco',
        type: 'Van',
        fuelLevel: 75,
        mileage: 45230,
        lastServiceDate: '2024-11-15',
        nextServiceDue: '2025-02-15'
      },
      checks: {
        engine: { status: 'good', lastChecked: '2024-12-20' },
        brakes: { status: 'good', lastChecked: '2024-12-20' },
        tires: { status: 'fair', lastChecked: '2024-12-20', notes: 'Front tires need replacement soon' },
        lights: { status: 'good', lastChecked: '2024-12-20' },
        battery: { status: 'good', lastChecked: '2024-12-20' }
      },
      documents: {
        insurance: { status: 'valid', expiryDate: '2025-06-15' },
        fitness: { status: 'valid', expiryDate: '2025-03-20' },
        pollution: { status: 'valid', expiryDate: '2024-12-30' },
        permit: { status: 'valid', expiryDate: '2025-08-10' }
      },
      overallStatus: 'good'
    };

    res.json({
      success: true,
      data: demoVehicleCheck
    });

  } catch (error) {
    console.error('Error fetching demo vehicle check:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch demo vehicle check',
      error: error.message
    });
  }
});

// GET /api/driver/demo/today-route - Get demo today's route
router.get('/today-route', async (req, res) => {
  try {
    const userEmail = req.user?.email || req.query.email;
    
    if (!isDemoDriver(userEmail)) {
      return res.status(404).json({
        success: false,
        message: 'Demo data only available for demo driver'
      });
    }

    const demoTodayRoute = {
      hasRoute: true,
      message: 'Route assigned successfully',
      rosterId: 'demo_roster_001',
      scheduledDate: new Date().toISOString(),
      vehicle: {
        id: 'demo_vehicle_001',
        registrationNumber: 'KA01AB1234',
        model: 'Maruti Eeco',
        make: 'Maruti',
        capacity: 4,
        totalCapacity: 4,
        availableSeats: 1, // Driver + 2 picked up + 1 available
        fuelType: 'Petrol',
        status: 'active'
      },
      routeSummary: {
        totalCustomers: 3,
        completedCustomers: 1,
        pendingCustomers: 2,
        totalDistance: 35.8,
        estimatedDuration: 90,
        routeType: 'mixed',
        availableSeats: 1
      },
      customers: [
        {
          id: 'cust_001',
          customerId: 'customer_001',
          name: 'Amit Patel',
          phone: '+91 9234567890',
          email: 'amit.patel@abrafleet.com',
          tripType: 'pickup',
          tripTypeLabel: 'LOGIN',
          shift: 'morning',
          scheduledTime: '08:30 AM',
          fromLocation: 'Electronic City, Bangalore',
          toLocation: 'Manyata Tech Park, Bangalore',
          fromCoordinates: {
            latitude: 12.8456,
            longitude: 77.6603
          },
          toCoordinates: {
            latitude: 13.0389,
            longitude: 77.6197
          },
          status: 'completed',
          distance: 12.5,
          estimatedDuration: 25
        },
        {
          id: 'cust_002',
          customerId: 'customer_002',
          name: 'Sneha Reddy',
          phone: '+91 9345678901',
          email: 'sneha.reddy@abrafleet.com',
          tripType: 'pickup',
          tripTypeLabel: 'LOGIN',
          shift: 'morning',
          scheduledTime: '09:15 AM',
          fromLocation: 'Whitefield, Bangalore',
          toLocation: 'Manyata Tech Park, Bangalore',
          fromCoordinates: {
            latitude: 12.9698,
            longitude: 77.7500
          },
          toCoordinates: {
            latitude: 13.0389,
            longitude: 77.6197
          },
          status: 'picked_up',
          distance: 15.8,
          estimatedDuration: 30
        },
        {
          id: 'cust_003',
          customerId: 'customer_003',
          name: 'Priya Sharma',
          phone: '+91 9123456789',
          email: 'customer123@abrafleet.com',
          tripType: 'pickup',
          tripTypeLabel: 'LOGIN',
          shift: 'morning',
          scheduledTime: '09:45 AM',
          fromLocation: 'Koramangala, Bangalore',
          toLocation: 'Manyata Tech Park, Bangalore',
          fromCoordinates: {
            latitude: 12.9352,
            longitude: 77.6245
          },
          toCoordinates: {
            latitude: 13.0389,
            longitude: 77.6197
          },
          status: 'in_progress',
          distance: 18.5,
          estimatedDuration: 35
        }
      ],
      routeOptimization: {
        optimized: true,
        optimizedAt: new Date().toISOString(),
        totalDistance: 35.8,
        totalDuration: 90
      }
    };

    res.json({
      success: true,
      data: demoTodayRoute
    });

  } catch (error) {
    console.error('Error fetching demo today route:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch demo today route',
      error: error.message
    });
  }
});

// POST /api/driver/demo/share-location - Demo share location
router.post('/share-location', async (req, res) => {
  try {
    const userEmail = req.user?.email || req.body.email;
    
    if (!isDemoDriver(userEmail)) {
      return res.status(404).json({
        success: false,
        message: 'Demo data only available for demo driver'
      });
    }

    const { tripId, latitude, longitude } = req.body;

    // Simulate successful location sharing
    console.log(`Demo location shared for trip ${tripId}: ${latitude}, ${longitude}`);

    res.json({
      success: true,
      message: 'Location shared successfully',
      data: {
        tripId,
        latitude,
        longitude,
        timestamp: new Date().toISOString(),
        shared: true
      }
    });

  } catch (error) {
    console.error('Error sharing demo location:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to share location',
      error: error.message
    });
  }
});

// POST /api/driver/demo/update-trip-status - Demo update trip status
router.post('/update-trip-status', async (req, res) => {
  try {
    const userEmail = req.user?.email || req.body.email;
    
    if (!isDemoDriver(userEmail)) {
      return res.status(404).json({
        success: false,
        message: 'Demo data only available for demo driver'
      });
    }

    const { tripId, status } = req.body;

    // Simulate successful status update
    console.log(`Demo trip status updated for trip ${tripId}: ${status}`);

    res.json({
      success: true,
      message: `Trip status updated to ${status}`,
      data: {
        tripId,
        status,
        updatedAt: new Date().toISOString()
      }
    });

  } catch (error) {
    console.error('Error updating demo trip status:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update trip status',
      error: error.message
    });
  }
});

// POST /api/driver/demo/end-trip - Demo end trip
router.post('/end-trip', async (req, res) => {
  try {
    const userEmail = req.user?.email || req.body.email;
    
    if (!isDemoDriver(userEmail)) {
      return res.status(404).json({
        success: false,
        message: 'Demo data only available for demo driver'
      });
    }

    const { tripId, endLocation } = req.body;

    // Simulate successful trip end
    console.log(`Demo trip ended for trip ${tripId}:`, endLocation);

    res.json({
      success: true,
      message: 'Trip ended successfully',
      data: {
        tripId,
        endLocation,
        endTime: new Date().toISOString(),
        status: 'completed'
      }
    });

  } catch (error) {
    console.error('Error ending demo trip:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to end trip',
      error: error.message
    });
  }
});

module.exports = router;