// ============================================================================
// FILE: backend/routes/attendance_router.js
// COMPLETE ATTENDANCE SYSTEM - ALL BACKEND LOGIC IN ONE FILE
// ============================================================================

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');

module.exports = (db) => {
  const attendanceCollection = db.collection('driver_attendance');
  const usersCollection = db.collection('users');
  const tripsCollection = db.collection('trips');

  // =========================================================================
  // 1. AUTO-MARK ATTENDANCE (Called when driver starts trip)
  // =========================================================================
  router.post('/auto-mark', async (req, res) => {
    try {
      const { driverId, tripId, location, vehicleId } = req.body;
      
      if (!driverId || !tripId) {
        return res.status(400).json({
          success: false,
          message: 'Driver ID and Trip ID are required',
        });
      }

      const today = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
      const now = new Date();

      // Check if already marked today
      const existing = await attendanceCollection.findOne({
        driverId,
        date: today,
      });

      if (existing) {
        return res.json({
          success: true,
          message: 'Attendance already marked for today',
          attendance: existing,
          alreadyMarked: true,
        });
      }

      // Get driver info
      const driver = await usersCollection.findOne({ 
        _id: ObjectId.isValid(driverId) ? new ObjectId(driverId) : driverId 
      });

      if (!driver) {
        return res.status(404).json({
          success: false,
          message: 'Driver not found',
        });
      }

      // Calculate if late (assuming 7:00 AM shift start)
      const shiftStartHour = 7;
      const currentHour = now.getHours();
      const currentMinute = now.getMinutes();
      const minutesSinceShiftStart = (currentHour - shiftStartHour) * 60 + currentMinute;
      const isLate = minutesSinceShiftStart > 0;
      const lateByMinutes = isLate ? minutesSinceShiftStart : 0;

      // Create attendance record
      const attendance = {
        driverId,
        driverName: driver.name || 'Unknown',
        driverEmail: driver.email || '',
        date: today,
        
        // Clock times
        clockInTime: now.toISOString(),
        clockOutTime: null,
        
        // Trip tracking
        firstTripId: tripId,
        lastTripId: null,
        totalTrips: 0,
        completedTrips: 0,
        
        // Location
        clockInLocation: location || null,
        clockOutLocation: null,
        
        // Shift info
        scheduledShiftStart: '07:00',
        scheduledShiftEnd: '18:00',
        
        // Calculated fields
        totalHours: 0,
        totalDistance: 0,
        customersTransported: 0,
        
        // Status
        status: 'present',
        isAutoMarked: true,
        isLate,
        lateByMinutes,
        
        // Vehicle
        vehicleId: vehicleId || null,
        vehicleNumber: null,
        
        // Timestamps
        createdAt: now.toISOString(),
        updatedAt: now.toISOString(),
      };

      const result = await attendanceCollection.insertOne(attendance);
      attendance._id = result.insertedId;

      console.log(`✅ Attendance marked for driver ${driverName} at ${now.toLocaleTimeString()}`);

      res.json({
        success: true,
        message: isLate 
          ? `Attendance marked - Late by ${lateByMinutes} minutes`
          : 'Attendance marked successfully',
        attendance,
        isLate,
        lateByMinutes,
      });

    } catch (error) {
      console.error('❌ Error auto-marking attendance:', error);
      res.status(500).json({
        success: false,
        message: error.message,
      });
    }
  });

  // =========================================================================
  // 2. COMPLETE ATTENDANCE (Called when driver ends trip)
  // =========================================================================
  router.post('/complete', async (req, res) => {
    try {
      const { driverId, tripId, location } = req.body;
      const today = new Date().toISOString().split('T')[0];
      const now = new Date();

      const attendance = await attendanceCollection.findOne({
        driverId,
        date: today,
      });

      if (!attendance) {
        return res.status(404).json({
          success: false,
          message: 'No attendance record found for today',
        });
      }

      // Calculate total hours
      const clockInTime = new Date(attendance.clockInTime);
      const totalMilliseconds = now - clockInTime;
      const totalHours = totalMilliseconds / (1000 * 60 * 60);

      // Get trip statistics for today
      const todayTrips = await tripsCollection.find({
        driverId,
        scheduledDate: today,
      }).toArray();

      const completedTrips = todayTrips.filter(t => t.status === 'completed').length;
      const totalDistance = todayTrips.reduce((sum, t) => sum + (t.distance || 0), 0);
      const customersTransported = todayTrips.reduce((sum, t) => sum + (t.customer ? 1 : 0), 0);

      // Update attendance
      await attendanceCollection.updateOne(
        { _id: attendance._id },
        {
          $set: {
            clockOutTime: now.toISOString(),
            lastTripId: tripId,
            clockOutLocation: location || null,
            totalHours: parseFloat(totalHours.toFixed(2)),
            totalTrips: todayTrips.length,
            completedTrips,
            totalDistance: parseFloat(totalDistance.toFixed(2)),
            customersTransported,
            updatedAt: now.toISOString(),
          },
        }
      );

      console.log(`✅ Attendance completed for driver at ${now.toLocaleTimeString()}`);
      console.log(`   Total hours: ${totalHours.toFixed(2)}h, Trips: ${completedTrips}/${todayTrips.length}`);

      res.json({
        success: true,
        message: 'Attendance completed successfully',
        totalHours: parseFloat(totalHours.toFixed(2)),
        totalTrips: todayTrips.length,
        completedTrips,
      });

    } catch (error) {
      console.error('❌ Error completing attendance:', error);
      res.status(500).json({
        success: false,
        message: error.message,
      });
    }
  });

  // =========================================================================
  // 3. GET TODAY'S ATTENDANCE
  // =========================================================================
  router.get('/driver/:driverId/today', async (req, res) => {
    try {
      const { driverId } = req.params;
      const today = new Date().toISOString().split('T')[0];

      const attendance = await attendanceCollection.findOne({
        driverId,
        date: today,
      });

      res.json({
        success: true,
        attendance: attendance || null,
      });

    } catch (error) {
      console.error('❌ Error getting today attendance:', error);
      res.status(500).json({
        success: false,
        message: error.message,
      });
    }
  });

  // =========================================================================
  // 4. GET MONTHLY STATISTICS
  // =========================================================================
  router.get('/driver/:driverId/stats', async (req, res) => {
    try {
      const { driverId } = req.params;
      const { year, month } = req.query;
      
      const targetYear = parseInt(year) || new Date().getFullYear();
      const targetMonth = parseInt(month) || new Date().getMonth() + 1;

      const startDate = `${targetYear}-${targetMonth.toString().padStart(2, '0')}-01`;
      const lastDay = new Date(targetYear, targetMonth, 0).getDate();
      const endDate = `${targetYear}-${targetMonth.toString().padStart(2, '0')}-${lastDay}`;

      const records = await attendanceCollection
        .find({
          driverId,
          date: { $gte: startDate, $lte: endDate },
        })
        .toArray();

      const stats = {
        workingDays: records.length,
        presentDays: records.filter(r => r.status === 'present').length,
        absentDays: records.filter(r => r.status === 'absent').length,
        lateDays: records.filter(r => r.isLate === true).length,
        leaveDays: records.filter(r => r.status === 'on-leave').length,
        totalHours: records.reduce((sum, r) => sum + (r.totalHours || 0), 0),
        avgHoursPerDay: 0,
        totalTrips: records.reduce((sum, r) => sum + (r.totalTrips || 0), 0),
        totalDistance: records.reduce((sum, r) => sum + (r.totalDistance || 0), 0),
        totalCustomers: records.reduce((sum, r) => sum + (r.customersTransported || 0), 0),
        presentPercentage: 0,
      };

      if (stats.workingDays > 0) {
        stats.avgHoursPerDay = parseFloat((stats.totalHours / stats.workingDays).toFixed(2));
        stats.presentPercentage = parseFloat(((stats.presentDays / stats.workingDays) * 100).toFixed(1));
      }

      res.json({
        success: true,
        stats,
      });

    } catch (error) {
      console.error('❌ Error getting monthly stats:', error);
      res.status(500).json({
        success: false,
        message: error.message,
      });
    }
  });

  // =========================================================================
  // 5. GET ATTENDANCE HISTORY
  // =========================================================================
  router.get('/driver/:driverId/history', async (req, res) => {
    try {
      const { driverId } = req.params;
      const { limit = 10, startDate, endDate } = req.query;

      const query = { driverId };
      
      if (startDate || endDate) {
        query.date = {};
        if (startDate) query.date.$gte = startDate;
        if (endDate) query.date.$lte = endDate;
      }

      const attendance = await attendanceCollection
        .find(query)
        .sort({ date: -1 })
        .limit(parseInt(limit))
        .toArray();

      res.json({
        success: true,
        attendance,
        count: attendance.length,
      });

    } catch (error) {
      console.error('❌ Error getting attendance history:', error);
      res.status(500).json({
        success: false,
        message: error.message,
      });
    }
  });

  // =========================================================================
  // 6. GET MONTHLY CALENDAR
  // =========================================================================
  router.get('/driver/:driverId/calendar', async (req, res) => {
    try {
      const { driverId } = req.params;
      const { year, month } = req.query;

      const targetYear = parseInt(year) || new Date().getFullYear();
      const targetMonth = parseInt(month) || new Date().getMonth() + 1;

      const startDate = `${targetYear}-${targetMonth.toString().padStart(2, '0')}-01`;
      const lastDay = new Date(targetYear, targetMonth, 0).getDate();
      const endDate = `${targetYear}-${targetMonth.toString().padStart(2, '0')}-${lastDay}`;

      const records = await attendanceCollection
        .find({
          driverId,
          date: { $gte: startDate, $lte: endDate },
        })
        .toArray();

      // Convert to calendar object
      const calendar = {};
      records.forEach(record => {
        calendar[record.date] = record;
      });

      res.json({
        success: true,
        calendar,
        month: targetMonth,
        year: targetYear,
      });

    } catch (error) {
      console.error('❌ Error getting calendar:', error);
      res.status(500).json({
        success: false,
        message: error.message,
      });
    }
  });

  // =========================================================================
  // 7. ADMIN: GET ALL DRIVERS ATTENDANCE FOR TODAY
  // =========================================================================
  router.get('/admin/today', async (req, res) => {
    try {
      const today = new Date().toISOString().split('T')[0];

      const attendance = await attendanceCollection
        .find({ date: today })
        .sort({ driverName: 1 })
        .toArray();

      const summary = {
        total: attendance.length,
        present: attendance.filter(a => a.status === 'present').length,
        absent: attendance.filter(a => a.status === 'absent').length,
        late: attendance.filter(a => a.isLate === true).length,
      };

      res.json({
        success: true,
        date: today,
        summary,
        attendance,
      });

    } catch (error) {
      console.error('❌ Error getting admin attendance:', error);
      res.status(500).json({
        success: false,
        message: error.message,
      });
    }
  });

  return router;
};

// ============================================================================
// HOW TO USE IN server.js:
// ============================================================================
// const attendanceRouter = require('./routes/attendance_router');
// app.use('/api/attendance', verifyToken, attendanceRouter(db));
// ============================================================================