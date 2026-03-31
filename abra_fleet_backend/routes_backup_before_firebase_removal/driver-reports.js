// ============================================================================
// FILE: routes/driver_reports_routes.js
// UPDATED: Uses Email ID for identification (No manual Driver ID required)
// ============================================================================

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const PDFDocument = require('pdfkit');

/**
 * HELPER: Build robust query based on Email
 * This ensures we find data even if trips are mixed (some have email, some have ID)
 */
async function buildDriverQuery(db, email) {
  // 1. Default query criteria: Look for email directly on the trip
  const queryCriteria = [
    { driverEmail: email },
    { 'personalInfo.email': email } // In case trip stores nested object
  ];

  // 2. Try to find the driver profile to get their ID (for legacy data support)
  // This connects the Email from the Token to the DriverID in the database
  try {
    const driver = await db.collection('drivers').findOne({
      $or: [
        { email: email },
        { 'personalInfo.email': email }
      ]
    });

    if (driver && driver.driverId) {
      // If we found a profile, also look for trips with this specific Driver ID
      queryCriteria.push({ driverId: driver.driverId });
    }
  } catch (e) {
    console.log('⚠️ Error looking up driver profile for query construction:', e.message);
  }

  // Return the OR query: Matches Email OR DriverID
  return { $or: queryCriteria };
}

/**
 * GET /api/driver/reports/performance-summary
 * Returns performance metrics based on the logged-in user's EMAIL
 */
router.get('/performance-summary', async (req, res) => {
  try {
    const jwtUser = req.user;
    const db = req.db;

    // 1. Validation
    if (!jwtUser || !jwtUser.email) {
      return res.status(401).json({ status: 'error', message: 'Unauthorized: No email found in token' });
    }

    const driverEmail = jwtUser.email;
    console.log(`📊 [PERFORMANCE] Fetching stats for: ${driverEmail}`);

    // 2. Build Smart Query
    const driverQuery = await buildDriverQuery(db, driverEmail);

    // 3. Get all trips
    const allTrips = await db.collection('trips')
      .find(driverQuery)
      .toArray();

    console.log(`   Found ${allTrips.length} trips total.`);

    const completedTrips = allTrips.filter(t => t.status === 'completed');

    if (allTrips.length === 0) {
      return res.json({
        status: 'success',
        data: {
          totalTrips: 0,
          avgRating: 0,
          onTimePercentage: 0,
          totalKm: 0
        }
      });
    }

    // 4. Calculate metrics
    const totalTrips = allTrips.length;
    
    // Average rating
    const tripsWithRating = completedTrips.filter(t => t.rating && t.rating > 0);
    const avgRating = tripsWithRating.length > 0
      ? (tripsWithRating.reduce((sum, t) => sum + t.rating, 0) / tripsWithRating.length)
      : 0;

    // On-time percentage
    const onTimeTrips = completedTrips.filter(t => {
      if (!t.scheduledEndTime || !t.actualEndTime) return false;
      const scheduled = new Date(t.scheduledEndTime);
      const actual = new Date(t.actualEndTime);
      // Consider on-time if completed within 15 minutes of schedule
      return (actual - scheduled) <= 15 * 60 * 1000; 
    });
    
    const onTimePercentage = completedTrips.length > 0 
      ? Math.round((onTimeTrips.length / completedTrips.length) * 100)
      : 0;

    // Total kilometers (Safety check for null/undefined distances)
    const totalKm = Math.round(completedTrips.reduce((sum, t) => sum + (Number(t.distance) || 0), 0));

    res.json({
      status: 'success',
      data: {
        totalTrips,
        avgRating: parseFloat(avgRating.toFixed(1)),
        onTimePercentage,
        totalKm
      }
    });

  } catch (error) {
    console.error('❌ Error fetching performance summary:', error);
    res.status(500).json({ status: 'error', message: error.message });
  }
});

/**
 * GET /api/driver/reports/daily-analytics
 * Returns daily analytics for today based on EMAIL
 */
router.get('/daily-analytics', async (req, res) => {
  try {
    const jwtUser = req.user;
    const db = req.db;
    // Optional date param, default to today
    const targetDate = req.query.date ? new Date(req.query.date) : new Date();

    if (!jwtUser || !jwtUser.email) {
      return res.status(401).json({ status: 'error', message: 'Unauthorized' });
    }

    const driverEmail = jwtUser.email;
    console.log(`📊 [DAILY] Fetching for: ${driverEmail} on ${targetDate.toISOString().split('T')[0]}`);

    // Date Range (Start to End of specific day)
    const startOfDay = new Date(targetDate);
    startOfDay.setHours(0, 0, 0, 0);
    
    const endOfDay = new Date(targetDate);
    endOfDay.setHours(23, 59, 59, 999);

    // Build Query
    const driverQuery = await buildDriverQuery(db, driverEmail);
    
    // Combine Driver Query with Date Query
    const query = {
      $and: [
        driverQuery,
        {
          $or: [
            { startTime: { $gte: startOfDay, $lte: endOfDay } },
            { endTime: { $gte: startOfDay, $lte: endOfDay } },
            // Also include scheduled trips if they haven't started yet
            { scheduledTime: { $gte: startOfDay, $lte: endOfDay } }
          ]
        }
      ]
    };

    const todayTrips = await db.collection('trips').find(query).toArray();

    // Calculate working hours
    let totalWorkingMinutes = 0;
    todayTrips.forEach(trip => {
      if (trip.startTime && trip.endTime) {
        const start = new Date(trip.startTime);
        const end = new Date(trip.endTime);
        const minutes = (end - start) / (1000 * 60);
        totalWorkingMinutes += minutes;
      }
    });

    const hours = Math.floor(totalWorkingMinutes / 60);
    const minutes = Math.floor(totalWorkingMinutes % 60);
    const workingHours = `${hours}h ${minutes}min`;

    // Fuel & Distance
    const completedTrips = todayTrips.filter(t => t.status === 'completed');
    const totalDistance = completedTrips.reduce((sum, t) => sum + (Number(t.distance) || 0), 0);
    const totalFuel = completedTrips.reduce((sum, t) => sum + (Number(t.fuelConsumed) || 0), 0);
    
    const fuelEfficiency = totalFuel > 0 
      ? (totalDistance / totalFuel).toFixed(1)
      : 'N/A';

    res.json({
      status: 'success',
      data: {
        workingHours,
        fuelEfficiency: totalFuel > 0 ? `${fuelEfficiency} km/L` : 'N/A',
        tripsToday: todayTrips.length,
        distanceToday: totalDistance.toFixed(1)
      }
    });

  } catch (error) {
    console.error('❌ Error fetching daily analytics:', error);
    res.status(500).json({ status: 'error', message: error.message });
  }
});

/**
 * GET /api/driver/reports/trips
 * Returns filtered trip list based on EMAIL
 */
router.get('/trips', async (req, res) => {
  try {
    const jwtUser = req.user;
    const db = req.db;
    const { startDate, endDate } = req.query;

    if (!jwtUser || !jwtUser.email) {
      return res.status(401).json({ status: 'error', message: 'Unauthorized' });
    }

    const driverEmail = jwtUser.email;
    
    // 1. Base Query (User Email)
    const driverQuery = await buildDriverQuery(db, driverEmail);
    
    // We need to use $and to combine the driver query with the date filter
    const queryParts = [driverQuery];

    // 2. Add Date Filter
    if (startDate) {
      const start = new Date(startDate);
      start.setHours(0, 0, 0, 0);
      
      const end = endDate ? new Date(endDate) : new Date();
      end.setHours(23, 59, 59, 999);
      
      queryParts.push({ startTime: { $gte: start, $lte: end } });
    }

    // 3. Execute
    const finalQuery = queryParts.length > 1 ? { $and: queryParts } : queryParts[0];

    const trips = await db.collection('trips')
      .find(finalQuery)
      .sort({ startTime: -1 })
      .toArray();

    // 4. Summary Calculation
    const completedTrips = trips.filter(t => t.status === 'completed');
    const totalDistance = completedTrips.reduce((sum, t) => sum + (Number(t.distance) || 0), 0);
    const totalDuration = completedTrips.reduce((sum, t) => {
      if (t.startTime && t.endTime) {
        return sum + (new Date(t.endTime) - new Date(t.startTime));
      }
      return sum;
    }, 0);

    res.json({
      status: 'success',
      data: {
        trips: trips.map(trip => ({
          id: trip._id,
          tripNumber: trip.tripNumber || 'N/A',
          startTime: trip.startTime,
          endTime: trip.endTime,
          status: trip.status || 'unknown',
          distance: Number(trip.distance) || 0,
          rating: trip.rating || null,
          customerName: trip.customerName || 'N/A',
          pickupLocation: trip.pickupLocation,
          dropoffLocation: trip.dropoffLocation
        })),
        summary: {
          totalTrips: trips.length,
          completedTrips: completedTrips.length,
          totalDistance: totalDistance.toFixed(1),
          totalDurationHours: (totalDuration / (1000 * 60 * 60)).toFixed(1)
        }
      }
    });

  } catch (error) {
    console.error('❌ Error fetching trips:', error);
    res.status(500).json({ status: 'error', message: error.message });
  }
});

/**
 * POST /api/driver/reports/generate
 * Generates a report based on EMAIL and saves snapshot
 */
router.post('/generate', async (req, res) => {
  try {
    const jwtUser = req.user;
    const db = req.db;
    const { type, startDate: customStartDate, endDate: customEndDate } = req.body;

    if (!jwtUser || !jwtUser.email) {
      return res.status(401).json({ status: 'error', message: 'Unauthorized' });
    }

    const driverEmail = jwtUser.email;

    if (!['daily', 'weekly', 'monthly', 'custom'].includes(type)) {
      return res.status(400).json({ status: 'error', message: 'Invalid report type' });
    }

    // Determine Dates
    let startDate, endDate;
    const now = new Date();

    switch (type) {
      case 'daily':
        startDate = new Date(now.setHours(0, 0, 0, 0));
        endDate = new Date(now.setHours(23, 59, 59, 999));
        break;
      case 'weekly':
        startDate = new Date();
        const day = startDate.getDay();
        const diff = startDate.getDate() - day + (day === 0 ? -6 : 1);
        startDate.setDate(diff);
        startDate.setHours(0, 0, 0, 0);
        endDate = new Date(startDate);
        endDate.setDate(startDate.getDate() + 6);
        endDate.setHours(23, 59, 59, 999);
        break;
      case 'monthly':
        startDate = new Date(now.getFullYear(), now.getMonth(), 1);
        endDate = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59, 999);
        break;
      case 'custom':
        if (!customStartDate) return res.status(400).json({ status: 'error', message: 'Start date required' });
        startDate = new Date(customStartDate);
        startDate.setHours(0, 0, 0, 0);
        endDate = customEndDate ? new Date(customEndDate) : new Date(customStartDate);
        endDate.setHours(23, 59, 59, 999);
        break;
    }

    // Build Query
    const driverQuery = await buildDriverQuery(db, driverEmail);
    const query = {
      $and: [
        driverQuery,
        { startTime: { $gte: startDate, $lte: endDate } }
      ]
    };

    // Fetch Data
    const trips = await db.collection('trips').find(query).sort({ startTime: 1 }).toArray();
    const completedTrips = trips.filter(t => t.status === 'completed');

    // Calculations
    const totalDistance = completedTrips.reduce((sum, t) => sum + (Number(t.distance) || 0), 0);
    const totalFuel = completedTrips.reduce((sum, t) => sum + (Number(t.fuelConsumed) || 0), 0);
    const tripsWithRating = completedTrips.filter(t => t.rating && t.rating > 0);
    const avgRating = tripsWithRating.length > 0 
      ? (tripsWithRating.reduce((sum, t) => sum + t.rating, 0) / tripsWithRating.length)
      : 0;

    // Calculate working hours
    let totalWorkingMinutes = 0;
    completedTrips.forEach(trip => {
      if (trip.startTime && trip.endTime) {
        const minutes = (new Date(trip.endTime) - new Date(trip.startTime)) / (1000 * 60);
        totalWorkingMinutes += minutes;
      }
    });
    
    // Create Report Object
    const report = {
      driverEmail: driverEmail,
      reportType: type,
      generatedAt: new Date(),
      period: { startDate, endDate },
      summary: {
        totalTrips: trips.length,
        completedTrips: completedTrips.length,
        cancelledTrips: trips.filter(t => t.status === 'cancelled').length,
        totalDistance: parseFloat(totalDistance.toFixed(2)),
        totalFuel: parseFloat(totalFuel.toFixed(2)),
        fuelEfficiency: totalFuel > 0 ? parseFloat((totalDistance / totalFuel).toFixed(2)) : 0,
        avgRating: parseFloat(avgRating.toFixed(2)),
        workingHours: parseFloat((totalWorkingMinutes / 60).toFixed(2))
      },
      trips: trips.map(t => ({
        tripNumber: t.tripNumber || 'N/A',
        date: t.startTime,
        status: t.status,
        distance: t.distance,
        rating: t.rating
      }))
    };

    // Save
    const result = await db.collection('driver_reports').insertOne(report);

    res.json({
      status: 'success',
      message: 'Report generated successfully',
      data: {
        reportId: result.insertedId,
        report
      }
    });

  } catch (error) {
    console.error('❌ Error generating report:', error);
    res.status(500).json({ status: 'error', message: error.message });
  }
});

/**
 * GET /api/driver/reports/history
 * Returns list of previously generated reports based on EMAIL
 */
router.get('/history', async (req, res) => {
  try {
    const jwtUser = req.user;
    const db = req.db;
    const { type, limit = 10 } = req.query;

    if (!jwtUser || !jwtUser.email) {
      return res.status(401).json({ status: 'error', message: 'Unauthorized' });
    }

    const query = { driverEmail: jwtUser.email };
    if (type) query.reportType = type;

    const reports = await db.collection('driver_reports')
      .find(query)
      .sort({ generatedAt: -1 })
      .limit(parseInt(limit))
      .toArray();

    res.json({
      status: 'success',
      data: reports.map(r => ({
        id: r._id,
        type: r.reportType,
        generatedAt: r.generatedAt,
        period: r.period,
        summary: r.summary
      }))
    });

  } catch (error) {
    console.error('❌ Error fetching history:', error);
    res.status(500).json({ status: 'error', message: error.message });
  }
});

/**
 * GET /api/driver/reports/download/:reportId
 * Download PDF
 */
router.get('/download/:reportId', async (req, res) => {
  try {
    const { reportId } = req.params;
    const db = req.db;

    if (!ObjectId.isValid(reportId)) {
      return res.status(400).json({ status: 'error', message: 'Invalid Report ID' });
    }

    const report = await db.collection('driver_reports').findOne({ _id: new ObjectId(reportId) });

    if (!report) {
      return res.status(404).json({ status: 'error', message: 'Report not found' });
    }

    // --- PDF Generation Logic ---
    const doc = new PDFDocument({ margin: 50 });

    const filename = `Report-${report.reportType}-${new Date(report.generatedAt).toISOString().split('T')[0]}.pdf`;
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);

    doc.pipe(res);

    doc.fontSize(20).text(`Driver Report: ${report.reportType.toUpperCase()}`, { align: 'center' });
    doc.moveDown();
    doc.fontSize(12).text(`Generated on: ${new Date(report.generatedAt).toUTCString()}`);
    doc.text(`Driver Email: ${report.driverEmail}`);
    doc.text(`Period: ${new Date(report.period.startDate).toDateString()} to ${new Date(report.period.endDate).toDateString()}`);
    doc.moveDown(2);

    doc.fontSize(16).text('Summary', { underline: true });
    doc.moveDown();
    doc.fontSize(12)
      .text(`Total Trips: ${report.summary.totalTrips}`)
      .text(`Completed Trips: ${report.summary.completedTrips}`)
      .text(`Total Distance: ${report.summary.totalDistance} KM`)
      .text(`Average Rating: ${report.summary.avgRating}`)
      .text(`Working Hours: ${report.summary.workingHours}`);
    
    doc.end();
    
  } catch (error) {
    console.error('Error downloading report:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to download report',
      error: error.message
    });
  }
});

module.exports = router;