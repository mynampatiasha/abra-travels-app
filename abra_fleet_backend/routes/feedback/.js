const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');

// Submit trip feedback
router.post('/submit', verifyToken, async (req, res) => {
  try {
    const db = req.db;
    const {
      tripId,
      rating,
      quickTags = [],
      comment = '',
      feedbackType = 'post_trip'
    } = req.body;

    // Validate rating
    if (!rating || rating < 1 || rating > 5) {
      return res.status(400).json({ error: 'Rating must be between 1 and 5' });
    }

    // Get trip details
    const trip = await db.collection('rosters').findOne({ _id: new ObjectId(tripId) });
    if (!trip) {
      return res.status(404).json({ error: 'Trip not found' });
    }

    // Check if feedback already exists
    const existingFeedback = await db.collection('feedback').findOne({
      tripId: new ObjectId(tripId),
      customerId: new ObjectId(req.user.userId)
    });

    if (existingFeedback) {
      return res.status(400).json({ error: 'Feedback already submitted for this trip' });
    }

    // Create feedback document
    const feedback = {
      tripId: new ObjectId(tripId),
      tripType: trip.tripType || 'pickup',
      customerId: new ObjectId(req.user.userId),
      driverId: trip.driverId ? new ObjectId(trip.driverId) : null,
      vehicleId: trip.vehicleId ? new ObjectId(trip.vehicleId) : null,
      routeId: trip.routeId ? new ObjectId(trip.routeId) : null,
      organizationId: new ObjectId(trip.organizationId),
      rating: parseInt(rating),
      quickTags,
      comment: comment.trim(),
      feedbackType,
      tripDate: trip.date,
      tripDelay: trip.actualPickupTime && trip.scheduledPickupTime 
        ? Math.round((new Date(trip.actualPickupTime) - new Date(trip.scheduledPickupTime)) / 60000)
        : 0,
      wasLate: trip.status === 'delayed',
      promptedAt: new Date(),
      submittedAt: new Date(),
      status: 'submitted',
      reviewedBy: null,
      actionTaken: null
    };

    const result = await db.collection('feedback').insertOne(feedback);

    // Update aggregated stats asynchronously
    updateDriverStats(db, trip.driverId, trip.organizationId);
    updateVehicleStats(db, trip.vehicleId, trip.organizationId);

    // Auto-escalate if rating is low
    if (rating <= 2) {
      await escalateFeedback(db, result.insertedId, feedback);
    }

    res.json({
      success: true,
      feedbackId: result.insertedId,
      message: 'Thank you for your feedback!'
    });
  } catch (error) {
    console.error('Error submitting feedback:', error);
    res.status(500).json({ error: 'Failed to submit feedback' });
  }
});

// Get feedback eligibility for a trip
router.get('/eligibility/:tripId', verifyToken, async (req, res) => {
  try {
    const db = req.db;
    const { tripId } = req.params;

    const trip = await db.collection('rosters').findOne({ _id: new ObjectId(tripId) });
    if (!trip) {
      return res.status(404).json({ error: 'Trip not found' });
    }

    // Check if already submitted
    const existingFeedback = await db.collection('feedback').findOne({
      tripId: new ObjectId(tripId),
      customerId: new ObjectId(req.user.userId)
    });

    if (existingFeedback) {
      return res.json({ eligible: false, reason: 'already_submitted' });
    }

    // Check if trip is completed
    if (trip.status !== 'completed') {
      return res.json({ eligible: false, reason: 'trip_not_completed' });
    }

    // Check if user rated recently (within 2 hours)
    const recentFeedback = await db.collection('feedback').findOne({
      customerId: new ObjectId(req.user.userId),
      submittedAt: { $gte: new Date(Date.now() - 2 * 60 * 60 * 1000) }
    });

    if (recentFeedback) {
      return res.json({ eligible: false, reason: 'rated_recently' });
    }

    // Smart sampling logic
    const shouldPrompt = await shouldRequestFeedback(db, trip, req.user.userId);

    res.json({
      eligible: shouldPrompt.eligible,
      reason: shouldPrompt.reason,
      feedbackType: shouldPrompt.feedbackType,
      tripDetails: {
        tripId: trip._id,
        driverName: trip.driverName,
        vehicleNumber: trip.vehicleNumber,
        date: trip.date
      }
    });
  } catch (error) {
    console.error('Error checking feedback eligibility:', error);
    res.status(500).json({ error: 'Failed to check eligibility' });
  }
});

// Get customer's feedback history
router.get('/my-feedback', verifyToken, async (req, res) => {
  try {
    const db = req.db;
    const { limit = 20, skip = 0 } = req.query;

    const feedback = await db.collection('feedback')
      .find({ customerId: new ObjectId(req.user.userId) })
      .sort({ submittedAt: -1 })
      .limit(parseInt(limit))
      .skip(parseInt(skip))
      .toArray();

    const total = await db.collection('feedback')
      .countDocuments({ customerId: new ObjectId(req.user.userId) });

    res.json({ feedback, total });
  } catch (error) {
    console.error('Error fetching feedback:', error);
    res.status(500).json({ error: 'Failed to fetch feedback' });
  }
});

// Get driver feedback stats (for admin/driver)
router.get('/driver/:driverId/stats', verifyToken, async (req, res) => {
  try {
    const db = req.db;
    const { driverId } = req.params;
    const { period = 'month' } = req.query;

    const stats = await db.collection('driver_feedback_stats').findOne({
      driverId: new ObjectId(driverId),
      period: getPeriodKey(period)
    });

    if (!stats) {
      return res.json({
        driverId,
        totalTrips: 0,
        feedbackReceived: 0,
        averageRating: 0,
        ratingBreakdown: { 5: 0, 4: 0, 3: 0, 2: 0, 1: 0 }
      });
    }

    res.json(stats);
  } catch (error) {
    console.error('Error fetching driver stats:', error);
    res.status(500).json({ error: 'Failed to fetch driver stats' });
  }
});

// Get all feedback for admin
router.get('/admin/all', verifyToken, async (req, res) => {
  try {
    const db = req.db;
    const {
      organizationId,
      rating,
      status,
      startDate,
      endDate,
      limit = 50,
      skip = 0
    } = req.query;

    const query = {};
    
    if (organizationId) query.organizationId = new ObjectId(organizationId);
    if (rating) query.rating = parseInt(rating);
    if (status) query.status = status;
    if (startDate || endDate) {
      query.submittedAt = {};
      if (startDate) query.submittedAt.$gte = new Date(startDate);
      if (endDate) query.submittedAt.$lte = new Date(endDate);
    }

    const feedback = await db.collection('feedback')
      .find(query)
      .sort({ submittedAt: -1 })
      .limit(parseInt(limit))
      .skip(parseInt(skip))
      .toArray();

    const total = await db.collection('feedback').countDocuments(query);

    res.json({ feedback, total });
  } catch (error) {
    console.error('Error fetching admin feedback:', error);
    res.status(500).json({ error: 'Failed to fetch feedback' });
  }
});

// Helper: Smart feedback sampling logic
async function shouldRequestFeedback(db, trip, userId) {
  // Always ask for first trip with this driver
  const previousTripsWithDriver = await db.collection('rosters').countDocuments({
    customerId: new ObjectId(userId),
    driverId: trip.driverId,
    status: 'completed',
    _id: { $ne: trip._id }
  });

  if (previousTripsWithDriver === 0) {
    return { eligible: true, reason: 'first_trip_with_driver', feedbackType: 'post_trip' };
  }

  // Always ask if trip was delayed significantly
  if (trip.status === 'delayed' || trip.actualPickupTime) {
    const delay = Math.round((new Date(trip.actualPickupTime) - new Date(trip.scheduledPickupTime)) / 60000);
    if (delay > 10) {
      return { eligible: true, reason: 'significant_delay', feedbackType: 'incident' };
    }
  }

  // Check if it's last trip of the week (Friday evening)
  const tripDate = new Date(trip.date);
  if (tripDate.getDay() === 5 && trip.tripType === 'drop') {
    return { eligible: true, reason: 'weekly_summary', feedbackType: 'weekly_detailed' };
  }

  // Random sampling (20% of regular trips)
  if (Math.random() < 0.20) {
    return { eligible: true, reason: 'random_sampling', feedbackType: 'post_trip' };
  }

  return { eligible: false, reason: 'not_selected' };
}

// Helper: Update driver aggregated stats
async function updateDriverStats(db, driverId, organizationId) {
  if (!driverId) return;

  const period = getPeriodKey('month');
  
  const stats = await db.collection('feedback').aggregate([
    {
      $match: {
        driverId: new ObjectId(driverId),
        submittedAt: { $gte: new Date(new Date().getFullYear(), new Date().getMonth(), 1) }
      }
    },
    {
      $group: {
        _id: null,
        totalFeedback: { $sum: 1 },
        averageRating: { $avg: '$rating' },
        ratings: { $push: '$rating' }
      }
    }
  ]).toArray();

  if (stats.length > 0) {
    const ratingBreakdown = { 5: 0, 4: 0, 3: 0, 2: 0, 1: 0 };
    stats[0].ratings.forEach(r => ratingBreakdown[r]++);

    await db.collection('driver_feedback_stats').updateOne(
      { driverId: new ObjectId(driverId), period },
      {
        $set: {
          organizationId: new ObjectId(organizationId),
          feedbackReceived: stats[0].totalFeedback,
          averageRating: Math.round(stats[0].averageRating * 10) / 10,
          ratingBreakdown,
          lastUpdated: new Date()
        }
      },
      { upsert: true }
    );
  }
}

// Helper: Update vehicle stats
async function updateVehicleStats(db, vehicleId, organizationId) {
  if (!vehicleId) return;
  // Similar to driver stats
}

// Helper: Escalate low ratings
async function escalateFeedback(db, feedbackId, feedback) {
  await db.collection('feedback').updateOne(
    { _id: feedbackId },
    { $set: { status: 'escalated', escalatedAt: new Date() } }
  );

  // Create admin notification
  await db.collection('notifications').insertOne({
    type: 'low_rating_alert',
    title: 'Low Rating Alert',
    message: `Trip received ${feedback.rating} star rating`,
    data: { feedbackId, tripId: feedback.tripId, rating: feedback.rating },
    organizationId: feedback.organizationId,
    createdAt: new Date(),
    read: false
  });
}

// Helper: Get period key
function getPeriodKey(period) {
  const now = new Date();
  if (period === 'month') {
    return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
  }
  return period;
}

module.exports = router;
