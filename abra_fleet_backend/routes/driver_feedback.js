// routes/driver_feedback.js
// ============================================================================
// DRIVER FEEDBACK MANAGEMENT - Complete Feedback System
// ============================================================================
// Features:
// ✅ Uses NEW 'driver_feedback' collection (clean separation)
// ✅ Get feedback for specific driver
// ✅ Get recent feedback across all drivers
// ✅ Get overall feedback statistics
// ✅ Get feedback by rating
// ✅ Reply to customer feedback (admin) WITH FCM NOTIFICATIONS
// ✅ Export feedback reports
// ============================================================================

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');
const notificationService = require('../services/fcm_service'); // ✅ FCM SERVICE

// ============================================================================
// @route   GET /api/admin/drivers/:driverId/feedback
// @desc    Get all feedback for a specific driver
// @access  Private (Admin only)
// ============================================================================
router.get('/drivers/:driverId/feedback', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '⭐'.repeat(40));
    console.log('FETCHING DRIVER FEEDBACK');
    console.log('⭐'.repeat(40));
    
    const { driverId } = req.params;
    const { limit = 50, skip = 0, sortBy = 'submittedAt', order = 'desc' } = req.query;
    
    console.log(`🔍 Driver ID: ${driverId}`);
    console.log(`📄 Limit: ${limit}, Skip: ${skip}`);
    console.log(`🔄 Sort: ${sortBy} ${order}`);
    
    // Validate ObjectId
    if (!ObjectId.isValid(driverId)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid driver ID format'
      });
    }
    
    // ========================================================================
    // STEP 1: Find driver in drivers collection
    // ========================================================================
    const driver = await req.db.collection('drivers').findOne({
      _id: new ObjectId(driverId)
    });
    
    if (!driver) {
      console.log('❌ Driver not found');
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }
    
    console.log(`✅ Driver found: ${driver.personalInfo?.name || driver.name || 'Unknown'}`);
    
    // ========================================================================
    // STEP 2: ✅ Get feedback from driver_feedback collection
    // ========================================================================
    const sortOrder = order === 'desc' ? -1 : 1;
    
    const feedbackList = await req.db.collection('driver_feedback')
      .find({ driverId: new ObjectId(driverId) })
      .sort({ [sortBy]: sortOrder })
      .skip(parseInt(skip))
      .limit(parseInt(limit))
      .toArray();
    
    const totalCount = await req.db.collection('driver_feedback')
      .countDocuments({ driverId: new ObjectId(driverId) });
    
    console.log(`✅ Found ${feedbackList.length} feedback entries (total: ${totalCount})`);
    
    // ========================================================================
    // STEP 3: Get feedback stats from driver document
    // ========================================================================
    const stats = driver.feedbackStats || {
      totalFeedback: 0,
      averageRating: 0,
      rating5Stars: 0,
      rating4Stars: 0,
      rating3Stars: 0,
      rating2Stars: 0,
      rating1Stars: 0,
      totalRatingPoints: 0
    };
    
    console.log(`\n📊 FEEDBACK SUMMARY:`);
    console.log(`   Total Feedback: ${stats.totalFeedback}`);
    console.log(`   Average Rating: ${stats.averageRating}/5.0`);
    console.log(`   5 Stars: ${stats.rating5Stars}`);
    console.log(`   4 Stars: ${stats.rating4Stars}`);
    console.log(`   3 Stars: ${stats.rating3Stars}`);
    console.log(`   2 Stars: ${stats.rating2Stars}`);
    console.log(`   1 Star: ${stats.rating1Stars}`);
    console.log('⭐'.repeat(40) + '\n');
    
    res.json({
      success: true,
      message: 'Feedback retrieved successfully',
      data: {
        driver: {
          id: driver._id.toString(),
          driverId: driver.driverId,
          name: driver.personalInfo?.name || driver.name || 'Unknown',
          email: driver.personalInfo?.email || driver.email || '',
          phone: driver.personalInfo?.phone || driver.phone || ''
        },
        feedbackList: feedbackList,
        stats: stats,
        pagination: {
          total: totalCount,
          limit: parseInt(limit),
          skip: parseInt(skip),
          hasMore: (parseInt(skip) + parseInt(limit)) < totalCount
        }
      }
    });
    
  } catch (error) {
    console.error('❌ Error fetching driver feedback:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch driver feedback',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/admin/feedback/recent
// @desc    Get recent feedback across all drivers
// @access  Private (Admin only)
// ============================================================================
router.get('/feedback/recent', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '📋'.repeat(40));
    console.log('FETCHING RECENT DRIVER TRIP FEEDBACK');
    console.log('📋'.repeat(40));
    
    const { limit = 20, rating, driverId } = req.query;
    
    console.log(`📄 Limit: ${limit}`);
    if (rating) console.log(`⭐ Filter by rating: ${rating}`);
    if (driverId) console.log(`👤 Filter by driver: ${driverId}`);
    
    // ✅ BUILD QUERY - Query driver_feedback collection
    const query = {
      feedbackType: 'driver_trip_feedback'  // ✅ Only trip feedback
    };
    
    if (rating) {
      query.rating = parseInt(rating);
    }
    
    if (driverId && ObjectId.isValid(driverId)) {
      query.driverId = new ObjectId(driverId);
    }
    
    console.log('📋 Query:', JSON.stringify(query, null, 2));
    
    // ✅ Fetch from driver_feedback collection
    const recentFeedback = await req.db.collection('driver_feedback')
      .find(query)
      .sort({ submittedAt: -1 })
      .limit(parseInt(limit))
      .toArray();
    
    console.log(`✅ Found ${recentFeedback.length} driver trip feedback entries`);
    
    // Enrich with missing data if needed
    const enrichedFeedback = await Promise.all(
      recentFeedback.map(async (feedback) => {
        // If customer name is missing or is an object, fetch from database
        if (!feedback.customerName || typeof feedback.customerName === 'object') {
          const customer = await req.db.collection('customers').findOne({
            _id: feedback.customerId
          });
          
          if (customer) {
            feedback.customerName = customer.name || 'Unknown';
            feedback.customerEmail = customer.email || feedback.customerEmail;
            feedback.customerPhone = customer.phone || null;
          }
        }
        
        // If driver name is missing, fetch from database
        if (!feedback.driverName) {
          const driver = await req.db.collection('drivers').findOne({
            _id: feedback.driverId
          });
          
          if (driver) {
            feedback.driverName = driver.personalInfo?.name || driver.name || 'Unknown';
            feedback.driverEmail = driver.personalInfo?.email || driver.email || '';
          }
        }
        
        return feedback;
      })
    );
    
    console.log('📋'.repeat(40) + '\n');
    
    res.json({
      success: true,
      message: 'Driver trip feedback retrieved successfully',
      data: enrichedFeedback,
      count: enrichedFeedback.length
    });
    
  } catch (error) {
    console.error('❌ Error fetching recent feedback:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch recent feedback',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/admin/feedback/stats
// @desc    Get overall feedback statistics across all drivers
// @access  Private (Admin only)
// ============================================================================
router.get('/feedback/stats', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '📊'.repeat(40));
    console.log('FETCHING DRIVER TRIP FEEDBACK STATISTICS');
    console.log('📊'.repeat(40));
    
    // ✅ Aggregate statistics from driver_feedback collection
    const stats = await req.db.collection('driver_feedback').aggregate([
      {
        $match: {
          feedbackType: 'driver_trip_feedback'
        }
      },
      {
        $group: {
          _id: null,
          totalFeedback: { $sum: 1 },
          averageRating: { $avg: '$rating' },
          totalRatingPoints: { $sum: '$rating' },
          rating5Stars: { $sum: { $cond: [{ $eq: ['$rating', 5] }, 1, 0] } },
          rating4Stars: { $sum: { $cond: [{ $eq: ['$rating', 4] }, 1, 0] } },
          rating3Stars: { $sum: { $cond: [{ $eq: ['$rating', 3] }, 1, 0] } },
          rating2Stars: { $sum: { $cond: [{ $eq: ['$rating', 2] }, 1, 0] } },
          rating1Stars: { $sum: { $cond: [{ $eq: ['$rating', 1] }, 1, 0] } }
        }
      }
    ]).toArray();
    
    const result = stats[0] || {
      totalFeedback: 0,
      averageRating: 0,
      totalRatingPoints: 0,
      rating5Stars: 0,
      rating4Stars: 0,
      rating3Stars: 0,
      rating2Stars: 0,
      rating1Stars: 0
    };
    
    // Round average rating to 2 decimal places
    result.averageRating = Math.round((result.averageRating || 0) * 100) / 100;
    
    // Get top rated drivers (drivers with averageRating >= 4.5)
    const topDrivers = await req.db.collection('drivers').find({
      'feedbackStats.averageRating': { $gte: 4.5 },
      'feedbackStats.totalFeedback': { $gte: 5 }
    })
    .sort({ 'feedbackStats.averageRating': -1 })
    .limit(10)
    .project({
      driverId: 1,
      'personalInfo.name': 1,
      name: 1,
      'feedbackStats.averageRating': 1,
      'feedbackStats.totalFeedback': 1
    })
    .toArray();
    
    // Get low rated drivers (drivers with averageRating < 3.0)
    const lowRatedDrivers = await req.db.collection('drivers').find({
      'feedbackStats.averageRating': { $lt: 3.0 },
      'feedbackStats.totalFeedback': { $gte: 3 }
    })
    .sort({ 'feedbackStats.averageRating': 1 })
    .limit(10)
    .project({
      driverId: 1,
      'personalInfo.name': 1,
      name: 1,
      'feedbackStats.averageRating': 1,
      'feedbackStats.totalFeedback': 1
    })
    .toArray();
    
    console.log(`\n📊 DRIVER TRIP FEEDBACK STATISTICS:`);
    console.log(`   Total Feedback: ${result.totalFeedback}`);
    console.log(`   Average Rating: ${result.averageRating}/5.0`);
    console.log(`   5 Stars: ${result.rating5Stars}`);
    console.log(`   4 Stars: ${result.rating4Stars}`);
    console.log(`   3 Stars: ${result.rating3Stars}`);
    console.log(`   2 Stars: ${result.rating2Stars}`);
    console.log(`   1 Star: ${result.rating1Stars}`);
    console.log(`   Top Drivers: ${topDrivers.length}`);
    console.log(`   Low Rated Drivers: ${lowRatedDrivers.length}`);
    console.log('📊'.repeat(40) + '\n');
    
    res.json({
      success: true,
      message: 'Driver trip feedback statistics retrieved successfully',
      data: {
        overall: result,
        topDrivers: topDrivers.map(d => ({
          id: d._id.toString(),
          driverId: d.driverId,
          name: d.personalInfo?.name || d.name || 'Unknown',
          averageRating: d.feedbackStats?.averageRating || 0,
          totalFeedback: d.feedbackStats?.totalFeedback || 0
        })),
        lowRatedDrivers: lowRatedDrivers.map(d => ({
          id: d._id.toString(),
          driverId: d.driverId,
          name: d.personalInfo?.name || d.name || 'Unknown',
          averageRating: d.feedbackStats?.averageRating || 0,
          totalFeedback: d.feedbackStats?.totalFeedback || 0
        }))
      }
    });
    
  } catch (error) {
    console.error('❌ Error fetching feedback statistics:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch statistics',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/admin/feedback/by-rating/:rating
// @desc    Get all feedback with specific rating
// @access  Private (Admin only)
// ============================================================================
router.get('/feedback/by-rating/:rating', verifyToken, async (req, res) => {
  try {
    const { rating } = req.params;
    const { limit = 50, skip = 0 } = req.query;
    
    const ratingNum = parseInt(rating);
    
    if (ratingNum < 1 || ratingNum > 5) {
      return res.status(400).json({
        success: false,
        message: 'Rating must be between 1 and 5'
      });
    }
    
    console.log(`\n⭐ Fetching ${ratingNum}-star feedback...`);
    
    // ✅ Query driver_feedback collection
    const feedback = await req.db.collection('driver_feedback')
      .find({ 
        rating: ratingNum,
        feedbackType: 'driver_trip_feedback'
      })
      .sort({ submittedAt: -1 })
      .skip(parseInt(skip))
      .limit(parseInt(limit))
      .toArray();
    
    const total = await req.db.collection('driver_feedback')
      .countDocuments({ 
        rating: ratingNum,
        feedbackType: 'driver_trip_feedback'
      });
    
    console.log(`✅ Found ${feedback.length} out of ${total} total ${ratingNum}-star reviews\n`);
    
    res.json({
      success: true,
      message: `Retrieved ${ratingNum}-star feedback`,
      data: feedback,
      pagination: {
        total: total,
        limit: parseInt(limit),
        skip: parseInt(skip),
        hasMore: (parseInt(skip) + parseInt(limit)) < total
      }
    });
    
  } catch (error) {
    console.error('❌ Error fetching feedback by rating:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch feedback',
      error: error.message
    });
  }
});


// ============================================================================
// DIAGNOSTIC ROUTE - Check feedback details
// ============================================================================
router.get('/feedback/:feedbackId/check', verifyToken, async (req, res) => {
  try {
    const { feedbackId } = req.params;
    
    console.log(`\n🔍 CHECKING FEEDBACK: ${feedbackId}`);
    
    // Check driver_feedback collection
    const inDriverFeedback = await req.db.collection('driver_feedback').findOne({
      _id: new ObjectId(feedbackId)
    });
    
    // Check customer_feedback collection
    const inCustomerFeedback = await req.db.collection('customer_feedback').findOne({
      _id: new ObjectId(feedbackId)
    });
    
    console.log(`   In driver_feedback: ${inDriverFeedback ? 'YES' : 'NO'}`);
    console.log(`   In customer_feedback: ${inCustomerFeedback ? 'YES' : 'NO'}`);
    
    if (inDriverFeedback) {
      console.log(`   Customer: ${inDriverFeedback.customerName}`);
      console.log(`   Driver: ${inDriverFeedback.driverName}`);
      console.log(`   Has admin reply: ${inDriverFeedback.hasAdminReply || false}`);
    }
    
    if (inCustomerFeedback) {
      console.log(`   Customer: ${inCustomerFeedback.customerName}`);
      console.log(`   Driver: ${inCustomerFeedback.driverName}`);
      console.log(`   Has admin reply: ${inCustomerFeedback.hasAdminReply || false}`);
    }
    
    res.json({
      success: true,
      feedbackId: feedbackId,
      found: {
        driver_feedback: !!inDriverFeedback,
        customer_feedback: !!inCustomerFeedback
      },
      data: {
        driver_feedback: inDriverFeedback,
        customer_feedback: inCustomerFeedback
      }
    });
    
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// ============================================================================
// @route   POST /api/admin/feedback/:feedbackId/reply
// @desc    Admin reply to customer feedback - FIXED VERSION
// @access  Private (Admin only)
// ============================================================================
router.post('/feedback/:feedbackId/reply', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '💬'.repeat(40));
    console.log('ADMIN REPLYING TO FEEDBACK');
    console.log('💬'.repeat(40));
    
    const { feedbackId } = req.params;
    const { reply } = req.body;
    
    if (!reply || reply.trim().length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Reply message is required'
      });
    }
    
    if (!ObjectId.isValid(feedbackId)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid feedback ID'
      });
    }
    
    console.log(`📋 Feedback ID: ${feedbackId}`);
    console.log(`💬 Reply: ${reply.substring(0, 50)}...`);
    
    // Get admin details
    const adminId = req.user.userId || req.user.id;
    const adminName = req.user.name || 'Admin';
    
    // ✅ STEP 1: Check which collection has the feedback
    console.log('🔍 Searching in driver_feedback collection...');
    let feedback = await req.db.collection('driver_feedback').findOne({
      _id: new ObjectId(feedbackId)
    });
    
    let collectionUsed = 'driver_feedback';
    
    if (!feedback) {
      console.log('❌ NOT FOUND in driver_feedback collection');
      console.log('🔍 Searching in customer_feedback collection...');
      
      feedback = await req.db.collection('customer_feedback').findOne({
        _id: new ObjectId(feedbackId)
      });
      
      collectionUsed = 'customer_feedback';
      
      if (!feedback) {
        console.log('❌ NOT FOUND in customer_feedback collection');
        return res.status(404).json({
          success: false,
          message: 'Feedback not found in database'
        });
      }
      
      console.log('✅ FOUND in customer_feedback collection');
    } else {
      console.log('✅ FOUND in driver_feedback collection');
    }
    
    console.log(`   Customer: ${feedback.customerName}`);
    console.log(`   Driver: ${feedback.driverName}`);
    console.log(`   Rating: ${feedback.rating}/5`);
    
    // ✅ STEP 2: Prepare the admin reply object
    const adminReplyData = {
      message: reply.trim(),
      repliedBy: adminName,
      repliedById: adminId,
      repliedAt: new Date()
    };
    
    // ✅ STEP 3: Update the document using updateOne (more reliable)
    console.log(`💾 Updating in ${collectionUsed} collection...`);
    
    const updateResult = await req.db.collection(collectionUsed).updateOne(
      { _id: new ObjectId(feedbackId) },
      {
        $set: {
          adminReply: adminReplyData,
          hasAdminReply: true,
          updatedAt: new Date()
        }
      }
    );
    
    console.log(`   Matched: ${updateResult.matchedCount}`);
    console.log(`   Modified: ${updateResult.modifiedCount}`);
    
    if (updateResult.matchedCount === 0) {
      console.log('❌ ERROR: Document not found during update');
      return res.status(404).json({
        success: false,
        message: 'Feedback not found'
      });
    }
    
    if (updateResult.modifiedCount === 0) {
      console.log('⚠️  WARNING: Document matched but not modified (might already have same reply)');
    } else {
      console.log('✅ Document updated successfully');
    }
    
    // ✅ STEP 4: Fetch the updated document to verify
    const updatedFeedback = await req.db.collection(collectionUsed).findOne({
      _id: new ObjectId(feedbackId)
    });
    
    if (!updatedFeedback) {
      console.log('❌ CRITICAL: Document disappeared after update!');
      return res.status(500).json({
        success: false,
        message: 'Failed to retrieve updated feedback'
      });
    }
    
    console.log('✅ Verified: Document retrieved after update');
    console.log(`   Has admin reply: ${updatedFeedback.hasAdminReply}`);
    
    // ✅ STEP 5: Update in driver's embedded feedback array (optional)
    try {
      const driverUpdateResult = await req.db.collection('drivers').updateOne(
        { 
          _id: updatedFeedback.driverId,
          'customerFeedback.feedbackId': updatedFeedback._id
        },
        {
          $set: {
            'customerFeedback.$.adminReply': adminReplyData
          }
        }
      );
      
      if (driverUpdateResult.modifiedCount > 0) {
        console.log(`✅ Reply synced to driver's profile`);
      } else {
        console.log(`ℹ️  Driver profile not updated (feedback may not be embedded)`);
      }
    } catch (driverUpdateError) {
      console.log(`⚠️  Driver profile update failed: ${driverUpdateError.message}`);
      // Don't fail the whole operation
    }
    
    // ========================================================================
    // ⭐ SEND FCM NOTIFICATION TO CUSTOMER
    // ========================================================================
    console.log('\n📲 SENDING FCM NOTIFICATION TO CUSTOMER');
    console.log('='.repeat(60));
    
    let customerNotified = false;
    
    try {
      const customer = await req.db.collection('customers').findOne({
        _id: updatedFeedback.customerId
      });
      
      if (!customer) {
        console.log('⚠️  Customer not found');
      } else {
        console.log(`✅ Customer found: ${customer.name || customer.email}`);
        
        // Get all customer devices
        const devices = await req.db.collection('user_devices').find({
          $or: [
            { userEmail: customer.email },
            { userId: customer._id.toString() }
          ],
          isActive: true
        }).toArray();
        
        console.log(`📱 Found ${devices.length} device(s) for customer`);
        
        let fcmSuccessCount = 0;
        const fcmErrors = [];
        
        // Send FCM to all devices
        for (const device of devices) {
          try {
            await notificationService.send({
              deviceToken: device.deviceToken,
              deviceType: device.deviceType || 'android',
              title: '💬 Admin Replied to Your Feedback',
              body: reply.trim().substring(0, 100),
              data: {
                type: 'feedback_reply',
                feedbackId: feedbackId,
                tripId: updatedFeedback.tripId?.toString() || '',
                driverName: updatedFeedback.driverName || '',
                adminReply: reply.trim(),
                action: 'open_feedback_details'
              },
              priority: 'high'
            });
            
            fcmSuccessCount++;
            console.log(`✅ FCM sent to ${device.deviceType}`);
          } catch (fcmError) {
            console.log(`⚠️  FCM failed for ${device.deviceType}: ${fcmError.message}`);
            fcmErrors.push({
              deviceType: device.deviceType,
              error: fcmError.message
            });
          }
        }
        
        // Save to database notification
        await req.db.collection('notifications').insertOne({
          userId: customer._id,
          userEmail: customer.email,
          userRole: 'customer',
          type: 'feedback_reply',
          title: '💬 Admin Replied to Your Feedback',
          body: `We've responded to your feedback about ${updatedFeedback.driverName}`,
          message: `Admin Reply: ${reply.trim()}`,
          data: {
            feedbackId: feedbackId,
            tripId: updatedFeedback.tripId?.toString() || '',
            driverName: updatedFeedback.driverName,
            adminReply: reply.trim()
          },
          priority: 'high',
          category: 'feedback',
          isRead: false,
          createdAt: new Date(),
          updatedAt: new Date(),
          expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
          deliveryStatus: {
            fcm: fcmSuccessCount > 0 ? 'success' : 'no_devices',
            database: 'success'
          },
          fcmResponse: {
            success: fcmSuccessCount,
            failed: devices.length - fcmSuccessCount,
            errors: fcmErrors
          },
          channels: fcmSuccessCount > 0 ? ['fcm', 'database'] : ['database']
        });
        
        customerNotified = true;
        console.log(`✅ Database notification saved`);
        console.log(`📊 FCM sent to ${fcmSuccessCount}/${devices.length} device(s)`);
      }
    } catch (notifError) {
      console.log(`⚠️  Notification failed: ${notifError.message}`);
      // Don't fail the reply if notification fails
    }
    
    console.log('='.repeat(60));
    console.log('💬'.repeat(40) + '\n');
    
    // ✅ STEP 6: Return success response
    res.json({
      success: true,
      message: customerNotified 
        ? 'Reply added successfully and customer notified'
        : 'Reply added successfully',
      data: {
        feedbackId: feedbackId,
        adminReply: adminReplyData,
        customerNotified: customerNotified,
        collectionUsed: collectionUsed,
        updateResult: {
          matched: updateResult.matchedCount,
          modified: updateResult.modifiedCount
        }
      }
    });
    
  } catch (error) {
    console.error('❌ Error adding reply:', error);
    console.error('Stack trace:', error.stack);
    res.status(500).json({
      success: false,
      message: 'Failed to add reply',
      error: error.message
    });
  }
});


// ============================================================================
// @route   GET /api/admin/feedback/export
// @desc    Export feedback data as CSV
// @access  Private (Admin only)
// ============================================================================
router.get('/feedback/export', verifyToken, async (req, res) => {
  try {
    console.log('\n📥 EXPORTING DRIVER TRIP FEEDBACK DATA...');
    
    const { startDate, endDate, driverId, rating } = req.query;
    
    // ✅ BUILD QUERY - Query driver_feedback collection
    const query = {
      feedbackType: 'driver_trip_feedback'
    };
    
    if (startDate || endDate) {
      query.submittedAt = {};
      if (startDate) query.submittedAt.$gte = new Date(startDate);
      if (endDate) query.submittedAt.$lte = new Date(endDate);
    }
    
    if (driverId && ObjectId.isValid(driverId)) {
      query.driverId = new ObjectId(driverId);
    }
    
    if (rating) {
      query.rating = parseInt(rating);
    }
    
    const feedback = await req.db.collection('driver_feedback')
      .find(query)
      .sort({ submittedAt: -1 })
      .toArray();
    
    console.log(`✅ Exporting ${feedback.length} driver trip feedback entries`);
    
    // Generate CSV
    const csvHeader = 'Date,Trip Number,Customer Name,Customer Email,Customer Phone,Driver Name,Driver Email,Driver Phone,Vehicle Number,Rating,Feedback,Ride Again,Trip ID\n';
    
    const csvRows = feedback.map(f => {
      const date = new Date(f.submittedAt).toISOString().split('T')[0];
      const escapeCsv = (str) => `"${(str || '').replace(/"/g, '""')}"`;
      
      return [
        date,
        escapeCsv(f.tripNumber || ''),
        escapeCsv(f.customerName || ''),
        escapeCsv(f.customerEmail || ''),
        escapeCsv(f.customerPhone || ''),
        escapeCsv(f.driverName || ''),
        escapeCsv(f.driverEmail || ''),
        escapeCsv(f.driverPhone || ''),
        escapeCsv(f.vehicleNumber || ''),
        f.rating,
        escapeCsv(f.feedback || ''),
        f.rideAgain || 'not_specified',
        f.tripId?.toString() || ''
      ].join(',');
    });
    
    const csv = csvHeader + csvRows.join('\n');
    
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', `attachment; filename=driver-trip-feedback-${Date.now()}.csv`);
    res.send(csv);
    
    console.log('✅ CSV export sent\n');
    
  } catch (error) {
    console.error('❌ Error exporting feedback:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to export feedback',
      error: error.message
    });
  }
});

module.exports = router;