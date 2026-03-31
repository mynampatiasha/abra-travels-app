// routes/admin_recent_activities.js
const express = require('express');
const router = express.Router();
const { MongoClient } = require('mongodb');


// MongoDB connection
const mongoUrl = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';
let db;

MongoClient.connect(mongoUrl)
  .then(client => {
    console.log('✅ Connected to MongoDB for Recent Activities');
    db = client.db('abra_fleet');
  })
  .catch(error => console.error('❌ MongoDB connection error:', error));

// GET /api/admin/recent-activities - Get recent activities for dashboard
router.get('/recent-activities', async (req, res) => {
  try {
    console.log('📊 Fetching recent activities for admin dashboard...');

    if (!db) {
      return res.status(500).json({
        success: false,
        message: 'Database connection not available'
      });
    }

    const activities = [];
    const now = new Date();
    const last24Hours = new Date(now.getTime() - 24 * 60 * 60 * 1000);

    // 1. Recent Customer Registrations
    try {
      const recentCustomers = await db.collection('users')
        .find({
          role: 'customer',
          createdAt: { $gte: last24Hours }
        })
        .sort({ createdAt: -1 })
        .limit(5)
        .toArray();

      recentCustomers.forEach(customer => {
        activities.push({
          id: `customer_${customer._id}`,
          type: 'customer_registration',
          title: 'New customer registered',
          subtitle: `${customer.name || customer.email} joined the platform`,
          timestamp: customer.createdAt,
          icon: 'person_add',
          color: 'green',
          priority: 'medium'
        });
      });
    } catch (error) {
      console.error('Error fetching recent customers:', error);
    }

    // 2. Recent Vehicle Additions
    try {
      const recentVehicles = await db.collection('vehicles')
        .find({
          createdAt: { $gte: last24Hours }
        })
        .sort({ createdAt: -1 })
        .limit(5)
        .toArray();

      recentVehicles.forEach(vehicle => {
        activities.push({
          id: `vehicle_${vehicle._id}`,
          type: 'vehicle_addition',
          title: 'Vehicle added to fleet',
          subtitle: `${vehicle.vehicleNumber} (${vehicle.vehicleType || 'Vehicle'}) added successfully`,
          timestamp: vehicle.createdAt,
          icon: 'directions_car',
          color: 'blue',
          priority: 'medium'
        });
      });
    } catch (error) {
      console.error('Error fetching recent vehicles:', error);
    }

    // 3. Recent Driver Additions
    try {
      const recentDrivers = await db.collection('drivers')
        .find({
          createdAt: { $gte: last24Hours }
        })
        .sort({ createdAt: -1 })
        .limit(5)
        .toArray();

      recentDrivers.forEach(driver => {
        activities.push({
          id: `driver_${driver._id}`,
          type: 'driver_addition',
          title: 'New driver added',
          subtitle: `${driver.name} joined as driver`,
          timestamp: driver.createdAt,
          icon: 'person_add',
          color: 'purple',
          priority: 'medium'
        });
      });
    } catch (error) {
      console.error('Error fetching recent drivers:', error);
    }

    // 4. Recent Trip Completions
    try {
      const recentTrips = await db.collection('trips')
        .find({
          status: 'completed',
          completedAt: { $gte: last24Hours }
        })
        .sort({ completedAt: -1 })
        .limit(10)
        .toArray();

      recentTrips.forEach(trip => {
        activities.push({
          id: `trip_${trip._id}`,
          type: 'trip_completion',
          title: 'Trip completed',
          subtitle: `${trip.pickupLocation?.address || 'Pickup'} to ${trip.dropLocation?.address || 'Drop'}`,
          timestamp: trip.completedAt,
          icon: 'check_circle',
          color: 'green',
          priority: 'low'
        });
      });
    } catch (error) {
      console.error('Error fetching recent trips:', error);
    }

    // 5. Recent Roster Assignments
    try {
      const recentRosters = await db.collection('rosters')
        .find({
          status: 'assigned',
          assignedAt: { $gte: last24Hours }
        })
        .sort({ assignedAt: -1 })
        .limit(5)
        .toArray();

      recentRosters.forEach(roster => {
        activities.push({
          id: `roster_${roster._id}`,
          type: 'roster_assignment',
          title: 'Roster assigned',
          subtitle: `${roster.organizationName || 'Organization'} roster assigned to driver`,
          timestamp: roster.assignedAt,
          icon: 'assignment',
          color: 'orange',
          priority: 'medium'
        });
      });
    } catch (error) {
      console.error('Error fetching recent rosters:', error);
    }

    // 6. Recent Maintenance Activities
    try {
      const recentMaintenance = await db.collection('maintenance_logs')
        .find({
          createdAt: { $gte: last24Hours }
        })
        .sort({ createdAt: -1 })
        .limit(3)
        .toArray();

      recentMaintenance.forEach(maintenance => {
        activities.push({
          id: `maintenance_${maintenance._id}`,
          type: 'maintenance_scheduled',
          title: 'Maintenance scheduled',
          subtitle: `${maintenance.vehicleNumber} - ${maintenance.maintenanceType || 'Service'}`,
          timestamp: maintenance.createdAt,
          icon: 'build',
          color: 'red',
          priority: 'high'
        });
      });
    } catch (error) {
      console.error('Error fetching recent maintenance:', error);
    }

    // 7. Recent Client Additions
    try {
      const recentClients = await db.collection('clients')
        .find({
          createdAt: { $gte: last24Hours }
        })
        .sort({ createdAt: -1 })
        .limit(3)
        .toArray();

      recentClients.forEach(client => {
        activities.push({
          id: `client_${client._id}`,
          type: 'client_addition',
          title: 'New client organization',
          subtitle: `${client.organizationName} registered as client`,
          timestamp: client.createdAt,
          icon: 'business',
          color: 'indigo',
          priority: 'medium'
        });
      });
    } catch (error) {
      console.error('Error fetching recent clients:', error);
    }

    // Sort all activities by timestamp (most recent first)
    activities.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));

    // Limit to top 15 activities
    const limitedActivities = activities.slice(0, 15);

    // Add relative time formatting
    const formatRelativeTime = (timestamp) => {
      const now = new Date();
      const activityTime = new Date(timestamp);
      const diffMs = now - activityTime;
      const diffMins = Math.floor(diffMs / (1000 * 60));
      const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
      const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

      if (diffMins < 1) return 'Just now';
      if (diffMins < 60) return `${diffMins} min${diffMins > 1 ? 's' : ''} ago`;
      if (diffHours < 24) return `${diffHours} hour${diffHours > 1 ? 's' : ''} ago`;
      if (diffDays < 7) return `${diffDays} day${diffDays > 1 ? 's' : ''} ago`;
      return activityTime.toLocaleDateString();
    };

    // Add formatted time to each activity
    limitedActivities.forEach(activity => {
      activity.timeAgo = formatRelativeTime(activity.timestamp);
    });

    console.log(`✅ Found ${limitedActivities.length} recent activities`);

    res.json({
      success: true,
      activities: limitedActivities,
      totalCount: activities.length,
      last24HoursCount: limitedActivities.length
    });

  } catch (error) {
    console.error('❌ Error fetching recent activities:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch recent activities',
      error: error.message
    });
  }
});

module.exports = router;