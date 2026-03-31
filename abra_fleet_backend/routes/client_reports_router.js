// routes/client_reports_router.js
// CLIENT COMPREHENSIVE REPORTS - Domain-Filtered
// Uses exact same DB connection pattern as one_signal_router.js

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const mongoose = require('mongoose');

const { verifyToken } = require('../middleware/auth');



// ── HELPERS ───────────────────────────────────────────────────────────────────
function getDomain(req) {
  const email = (req.user?.email || '').toLowerCase();
  if (!email.includes('@')) return null;
  return email.split('@')[1];
}

function domainRegex(domain) {
  const escaped = domain.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return { $regex: '@' + escaped + '$', $options: 'i' };
}

router.get('/comprehensive', verifyToken, async (req, res) => {
  try {
    // ✅ Use existing mongoose connection from index.js
const db = mongoose.connection.db;

if (!db) {
  console.error('❌ Database connection not available');
  return res.status(503).json({
    success: false,
    message: 'Database connection not ready. Please retry.'
  });
}
    console.log('\n' + '='.repeat(80));
    console.log('📊 CLIENT COMPREHENSIVE REPORTS - DOMAIN FILTERED');
    console.log('='.repeat(80));

    // ── 1. Extract domain ─────────────────────────────────────────────────
    const domain = getDomain(req);
    if (!domain) {
      return res.status(400).json({
        success: false,
        message: 'Cannot determine client domain from token'
      });
    }
    console.log(`🏢 Client Domain: ${domain}`);

    // ── 2. Query params ───────────────────────────────────────────────────
    const { startDate, endDate, reportTypes } = req.query;

    let selectedTypes = [];
    if (reportTypes) {
      selectedTypes = reportTypes.split(',').map(t => t.trim().toLowerCase());
    }

    console.log(`📅 Date: ${startDate || 'all'} → ${endDate || 'all'}`);
    console.log(`📋 Types: ${selectedTypes.length ? selectedTypes.join(', ') : 'all'}`);

    // ── 3. Reusable domain filter for trip stops ──────────────────────────
    // Matches any trip that has at least one stop with a @domain customer
    const domainStopMatch = {
      stops: {
        $elemMatch: {
          'customer.email': domainRegex(domain)
        }
      }
    };

    // ── 4. Date filter for trip scheduledDate (string "YYYY-MM-DD") ───────
    let tripDateFilter = {};
    if (startDate && endDate) {
      tripDateFilter = { scheduledDate: { $gte: startDate, $lte: endDate } };
    }

    const tripFilter = { ...domainStopMatch, ...tripDateFilter };

    // ── 5. Date filter for ISO-date fields (createdAt / submittedAt) ──────
    let isoDateFilter = {};
    if (startDate && endDate) {
      isoDateFilter = {
        $gte: new Date(startDate),
        $lte: new Date(endDate + 'T23:59:59.999Z')
      };
    }

    const responseData = {};

    // ========================================================================
    // SECTION 1: TRIP STATISTICS
    // ========================================================================
    const wantsTrips = selectedTypes.length === 0 || selectedTypes.includes('trips');
    if (wantsTrips) {
      console.log('\n📊 [1/7] Trips...');

      const allTrips = await db.collection('roster-assigned-trips')
        .find(tripFilter).toArray();

      const total      = allTrips.length;
      const scheduled  = allTrips.filter(t => t.status === 'assigned').length;
      const ongoing    = allTrips.filter(t =>
        ['started', 'in_progress', 'ongoing'].includes((t.status || '').toLowerCase())
      ).length;
      const completed  = allTrips.filter(t =>
        ['completed', 'done', 'finished'].includes((t.status || '').toLowerCase())
      ).length;
      const cancelled  = allTrips.filter(t => {
        const s = (t.status || '').toLowerCase();
        const tripCancelled = s === 'cancelled' || s === 'canceled';
        const stopCancelled = (t.stops || []).some(st =>
          ['cancelled', 'canceled'].includes((st.status || '').toLowerCase())
        );
        return tripCancelled || stopCancelled;
      }).length;

      const completedTrips = allTrips.filter(t =>
        ['completed', 'done', 'finished'].includes((t.status || '').toLowerCase())
      );

      // Grouping stats
      const uniqueGroupIds  = new Set(allTrips.map(t => t.tripGroupId).filter(Boolean));
      const uniqueVehicles  = new Set(allTrips.map(t => t.vehicleId?.toString()).filter(Boolean));
      const uniqueDrivers   = new Set(allTrips.map(t => t.driverId?.toString()).filter(Boolean));

      let totalCustomersInGroups = 0;
      let groupsWithCustomers = 0;
      allTrips.forEach(trip => {
        const pickups = (trip.stops || []).filter(s =>
          s.type === 'pickup' &&
          s.customer?.email?.toLowerCase().endsWith(`@${domain}`)
        );
        if (pickups.length > 0) {
          totalCustomersInGroups += pickups.length;
          groupsWithCustomers++;
        }
      });

      // Trips by date (completed)
      const byDateMap = new Map();
      completedTrips.forEach(t => {
        if (t.scheduledDate) {
          byDateMap.set(t.scheduledDate, (byDateMap.get(t.scheduledDate) || 0) + 1);
        }
      });
      const tripsByDate = Array.from(byDateMap.entries())
        .map(([date, count]) => ({ date, count }))
        .sort((a, b) => a.date.localeCompare(b.date));

      // Trips by vehicle (top 10)
      const byVehicleMap = new Map();
      completedTrips.forEach(t => {
        const id = t.vehicleId?.toString();
        if (!id) return;
        if (!byVehicleMap.has(id)) {
          byVehicleMap.set(id, { vehicleId: id, vehicleNumber: t.vehicleNumber || 'Unknown', count: 0 });
        }
        byVehicleMap.get(id).count++;
      });
      const tripsByVehicle = Array.from(byVehicleMap.values())
        .sort((a, b) => b.count - a.count).slice(0, 10);

      // Trips by driver (top 10)
      const byDriverMap = new Map();
      completedTrips.forEach(t => {
        const id = t.driverId?.toString();
        if (!id) return;
        if (!byDriverMap.has(id)) {
          byDriverMap.set(id, { driverId: id, driverName: t.driverName || 'Unknown', count: 0 });
        }
        byDriverMap.get(id).count++;
      });
      const tripsByDriver = Array.from(byDriverMap.values())
        .sort((a, b) => b.count - a.count).slice(0, 10);

      responseData.tripStats = { total, scheduled, ongoing, completed, cancelled };
      responseData.groupingStats = {
        totalGroups: uniqueGroupIds.size,
        avgCustomersPerGroup: groupsWithCustomers > 0
          ? parseFloat((totalCustomersInGroups / groupsWithCustomers).toFixed(2))
          : 0,
        totalVehicles: uniqueVehicles.size,
        totalDrivers: uniqueDrivers.size
      };
      responseData.tripsByDate    = tripsByDate;
      responseData.tripsByVehicle = tripsByVehicle;
      responseData.tripsByDriver  = tripsByDriver;

      console.log(`   ✅ Total: ${total}, Completed: ${completed}`);
    }

    // ========================================================================
    // SECTION 2: SOS ANALYTICS  (SOS raised by @domain customers)
    // ========================================================================
    const wantsSOS = selectedTypes.length === 0 || selectedTypes.includes('sos');
    if (wantsSOS) {
      console.log('\n📊 [2/7] SOS...');

      // Build SOS query scoped to domain customers
      const sosQuery = { 'customer.email': domainRegex(domain) };
      if (startDate && endDate) sosQuery.createdAt = isoDateFilter;

      const allSOS = await db.collection('sos_events').find(sosQuery).toArray();

      const totalSOS   = allSOS.length;
      const activeSOS  = allSOS.filter(s =>
        ['ACTIVE', 'Pending', 'In Progress'].includes(s.status)
      ).length;
      const resolvedSOS = allSOS.filter(s => s.status === 'Resolved').length;

      // Response time
      let totalMs = 0, fastest = Infinity, slowest = 0, validCount = 0;
      allSOS.filter(s => s.status === 'Resolved' && s.resolvedAt && s.createdAt)
        .forEach(s => {
          const mins = Math.round((new Date(s.resolvedAt) - new Date(s.createdAt)) / 60000);
          if (mins < 0) return;
          totalMs += mins; validCount++;
          if (mins < fastest) fastest = mins;
          if (mins > slowest) slowest = mins;
        });

      const avgResponseTime = validCount > 0 ? Math.round(totalMs / validCount) : 0;

      const fmtMins = (m) => {
        if (!m || m === Infinity) return '0 min';
        if (m < 60) return `${m} min`;
        const h = Math.floor(m / 60), mm = m % 60;
        return mm > 0 ? `${h}h ${mm}m` : `${h}h`;
      };

      // SOS by status
      const statusMap = new Map();
      allSOS.forEach(s => {
        const st = s.status || 'Unknown';
        statusMap.set(st, (statusMap.get(st) || 0) + 1);
      });
      const sosByStatus = Array.from(statusMap.entries())
        .map(([status, count]) => ({ status, count }))
        .sort((a, b) => b.count - a.count);

      // SOS by month
      const monthMap = new Map();
      allSOS.forEach(s => {
        const month = new Date(s.createdAt).toISOString().substring(0, 7);
        if (!monthMap.has(month)) monthMap.set(month, { month, active: 0, resolved: 0 });
        if (s.status === 'Resolved') monthMap.get(month).resolved++;
        else monthMap.get(month).active++;
      });
      const sosByMonth = Array.from(monthMap.values())
        .sort((a, b) => a.month.localeCompare(b.month));

      // SOS by date
      const dateMap = new Map();
      allSOS.forEach(s => {
        const d = new Date(s.createdAt).toISOString().split('T')[0];
        dateMap.set(d, (dateMap.get(d) || 0) + 1);
      });
      const sosByDate = Array.from(dateMap.entries())
        .map(([date, count]) => ({ date, count }))
        .sort((a, b) => a.date.localeCompare(b.date));

      responseData.sosStats = {
        total: totalSOS,
        active: activeSOS,
        resolved: resolvedSOS,
        avgResponseTime,
        avgResponseFormatted: fmtMins(avgResponseTime),
        fastestResponse: fastest === Infinity ? 0 : fastest,
        fastestResponseFormatted: fmtMins(fastest === Infinity ? 0 : fastest),
        slowestResponse: slowest,
        slowestResponseFormatted: fmtMins(slowest)
      };
      responseData.sosByDate   = sosByDate;
      responseData.sosByStatus = sosByStatus;
      responseData.sosByMonth  = sosByMonth;

      console.log(`   ✅ Total: ${totalSOS}, Active: ${activeSOS}, Resolved: ${resolvedSOS}`);
    }

    // ========================================================================
    // SECTION 3: DRIVER FEEDBACK  (feedback given BY @domain customers)
    // ========================================================================
    const wantsFeedback = selectedTypes.length === 0 || selectedTypes.includes('feedback');
    if (wantsFeedback) {
      console.log('\n📊 [3/7] Feedback...');

      // Feedback where the customer email ends with @domain
      const fbQuery = {
        feedbackType: 'driver_trip_feedback',
        'customerEmail': domainRegex(domain)
      };
      if (startDate && endDate) fbQuery.submittedAt = isoDateFilter;

      const allFeedback = await db.collection('driver_feedback')
        .find(fbQuery).toArray();

      const totalFeedback = allFeedback.length;
      const totalRating   = allFeedback.reduce((s, f) => s + (f.rating || 0), 0);
      const avgRating     = totalFeedback > 0 ? totalRating / totalFeedback : 0;

      const fiveStars     = allFeedback.filter(f => f.rating === 5).length;
      const fourStars     = allFeedback.filter(f => f.rating === 4).length;
      const positive      = totalFeedback > 0
        ? Math.round(((fiveStars + fourStars) / totalFeedback) * 100)
        : 0;

      // Rating distribution
      const ratingDistribution = [5, 4, 3, 2, 1].map(r => ({
        rating: r,
        count: allFeedback.filter(f => f.rating === r).length
      }));

      // ── Per-driver aggregation (only drivers serving this domain) ─────
      const driverMap = new Map();
      allFeedback.forEach(fb => {
        const id = fb.driverId?.toString();
        if (!id) return;
        if (!driverMap.has(id)) {
          driverMap.set(id, {
            driverId: id,
            driverName: fb.driverName || 'Unknown',
            phoneNumber: fb.driverPhone || '',
            ratings: [],
            fiveStarCount: 0
          });
        }
        const d = driverMap.get(id);
        d.ratings.push(fb.rating || 0);
        if (fb.rating === 5) d.fiveStarCount++;
        if (!d.phoneNumber && fb.driverPhone) d.phoneNumber = fb.driverPhone;
      });

      const driverList = Array.from(driverMap.values()).map(d => ({
        driverId: d.driverId,
        driverName: d.driverName,
        phoneNumber: d.phoneNumber,
        avgRating: parseFloat((d.ratings.reduce((a, b) => a + b, 0) / d.ratings.length).toFixed(2)),
        totalReviews: d.ratings.length,
        fiveStarCount: d.fiveStarCount
      }));

      const topDrivers = [...driverList]
        .sort((a, b) => b.avgRating - a.avgRating || b.fiveStarCount - a.fiveStarCount)
        .slice(0, 10);

      const bottomDrivers = driverList
        .filter(d => d.totalReviews >= 3)
        .sort((a, b) => a.avgRating - b.avgRating)
        .slice(0, 5);

      // Satisfaction (rideAgain) from same domain customers
      const rideAgainStats = [
        { response: 'yes', count: allFeedback.filter(f => f.rideAgain === 'yes').length },
        { response: 'no',  count: allFeedback.filter(f => f.rideAgain === 'no').length },
        { response: 'not_specified', count: allFeedback.filter(f =>
            !f.rideAgain || f.rideAgain === 'not_specified').length }
      ].filter(s => s.count > 0);

      const wouldRideAgain    = rideAgainStats.find(r => r.response === 'yes')?.count || 0;
      const wouldNotRideAgain = rideAgainStats.find(r => r.response === 'no')?.count  || 0;

      responseData.feedbackStats = {
        total: totalFeedback,
        avgRating: parseFloat(avgRating.toFixed(2)),
        fiveStars,
        positive
      };
      responseData.topDrivers         = topDrivers;
      responseData.bottomDrivers      = bottomDrivers;
      responseData.ratingDistribution = ratingDistribution;

      // Satisfaction section uses the same feedback data
      responseData.customerStats = {
        totalFeedback,
        avgRating: parseFloat(avgRating.toFixed(2)),
        wouldRideAgain,
        wouldNotRideAgain
      };
      responseData.rideAgainStats = rideAgainStats;

      console.log(`   ✅ Total: ${totalFeedback}, Avg Rating: ${avgRating.toFixed(2)}`);
    }

    // ========================================================================
    // SECTION 4: DOCUMENT STATUS
    // (vehicles/drivers that served this domain in the given date range)
    // ========================================================================
    // ========================================================================
    // SECTION 4: DOCUMENT STATUS
    // (vehicles/drivers that served this domain in the given date range)
    // ========================================================================
    const wantsDocs = selectedTypes.length === 0 || selectedTypes.includes('documents');
    if (wantsDocs) {
      console.log('\n📊 [4/7] Documents...');

      // Step 1: find all trips for this domain → collect vehicleIds & driverIds
      const domainTrips = await db.collection('roster-assigned-trips')
        .find(domainStopMatch, { projection: { vehicleId: 1, driverId: 1 } })
        .toArray();

      const domainVehicleIds = [...new Set(
        domainTrips.map(t => t.vehicleId?.toString()).filter(Boolean)
      )];
      const domainDriverIds = [...new Set(
        domainTrips.map(t => t.driverId?.toString()).filter(Boolean)
      )];

      const now              = new Date();
      const allExpiringDocs  = [];
      let totalExpired = 0, totalExpiringSoon = 0, totalValid = 0;
      let driverExpired = 0, driverExpiringSoon = 0;
      let vehicleExpired = 0, vehicleExpiringSoon = 0;

      // ── Driver documents ────────────────────────────────────────────────
      const driverObjectIds = domainDriverIds
        .filter(id => ObjectId.isValid(id))
        .map(id => new ObjectId(id));

      if (driverObjectIds.length > 0) {
        const drivers = await db.collection('drivers')
          .find({ _id: { $in: driverObjectIds } }).toArray();

        for (const driver of drivers) {
          const driverName = driver.personalInfo?.name || driver.name || 'Unknown';

          // License
          if (driver.license?.expiryDate) {
            const expiry     = new Date(driver.license.expiryDate);
            const daysLeft   = Math.ceil((expiry - now) / 86400000);
            const isExpired  = daysLeft <= 0;
            const isSoon     = !isExpired && daysLeft <= 30;

            if (isExpired || isSoon) {
              if (isExpired) { totalExpired++; driverExpired++; }
              else           { totalExpiringSoon++; driverExpiringSoon++; }

              allExpiringDocs.push({
                type: 'driver', name: driverName,
                documentType: 'Driver License',
                licenseNumber: driver.license.licenseNumber || 'N/A',
                expiryDate: expiry.toISOString(),
                daysLeft, status: isExpired ? 'expired' : 'expiring_soon'
              });
            }
          }

          // Other documents array - ✅ FIXED: Ensure documents is an array
          const driverDocs = Array.isArray(driver.documents) ? driver.documents : [];
          for (const doc of driverDocs) {
            if (!doc || !doc.expiryDate || doc.status !== 'active') continue;
            const expiry   = new Date(doc.expiryDate);
            const daysLeft = Math.ceil((expiry - now) / 86400000);
            const isExpired = daysLeft <= 0;
            const isSoon    = !isExpired && daysLeft <= 30;

            if (isExpired || isSoon) {
              if (isExpired) { totalExpired++; driverExpired++; }
              else           { totalExpiringSoon++; driverExpiringSoon++; }

              allExpiringDocs.push({
                type: 'driver', name: driverName,
                documentType: doc.documentType || 'Document',
                licenseNumber: doc.documentNumber || 'N/A',
                expiryDate: expiry.toISOString(),
                daysLeft, status: isExpired ? 'expired' : 'expiring_soon'
              });
            }
          }
        }
      }

      // ── Vehicle documents ────────────────────────────────────────────────
      const vehicleObjectIds = domainVehicleIds
        .filter(id => ObjectId.isValid(id))
        .map(id => new ObjectId(id));

      if (vehicleObjectIds.length > 0) {
        const vehicles = await db.collection('vehicles')
          .find({ _id: { $in: vehicleObjectIds } }).toArray();

        const docTypes = [
          { field: 'insurance', label: 'Insurance' },
          { field: 'rc',        label: 'RC' },
          { field: 'fc',        label: 'FC' },
          { field: 'permit',    label: 'Permit' }
        ];

        for (const vehicle of vehicles) {
          const vName = vehicle.registrationNumber || vehicle.vehicleNumber || 'Unknown';

          for (const dt of docTypes) {
            const doc = vehicle[dt.field];
            if (!doc?.expiryDate) continue;
            const expiry   = new Date(doc.expiryDate);
            const daysLeft = Math.ceil((expiry - now) / 86400000);
            const isExpired = daysLeft <= 0;
            const isSoon    = !isExpired && daysLeft <= 30;

            if (isExpired || isSoon) {
              if (isExpired) { totalExpired++; vehicleExpired++; }
              else           { totalExpiringSoon++; vehicleExpiringSoon++; }

              allExpiringDocs.push({
                type: 'vehicle', name: vName,
                documentType: dt.label,
                vehicleNumber: vName,
                expiryDate: expiry.toISOString(),
                daysLeft, status: isExpired ? 'expired' : 'expiring_soon'
              });
            }
          }
        }
      }

      allExpiringDocs.sort((a, b) => a.daysLeft - b.daysLeft);

      responseData.documentStats = {
        total:    { expired: totalExpired,   expiringSoon: totalExpiringSoon,   valid: totalValid },
        drivers:  { expired: driverExpired,  expiringSoon: driverExpiringSoon,  valid: 0 },
        vehicles: { expired: vehicleExpired, expiringSoon: vehicleExpiringSoon, valid: 0 }
      };
      responseData.expiringDocs = allExpiringDocs.slice(0, 50);

      console.log(`   ✅ Expired: ${totalExpired}, Expiring Soon: ${totalExpiringSoon}`);
    }

    // ========================================================================
    // SECTION 5: VEHICLES  (only vehicles that served this domain)
    // ========================================================================
    const wantsVehicles = selectedTypes.length === 0 || selectedTypes.includes('vehicles');
    if (wantsVehicles) {
      console.log('\n📊 [5/7] Vehicles...');

      const domainTrips = await db.collection('roster-assigned-trips')
        .find(domainStopMatch, { projection: { vehicleId: 1 } }).toArray();

      const vehicleIds = [...new Set(
        domainTrips.map(t => t.vehicleId?.toString()).filter(Boolean)
      )];

      const vehicleObjectIds = vehicleIds
        .filter(id => ObjectId.isValid(id))
        .map(id => new ObjectId(id));

      const vehicles = vehicleObjectIds.length > 0
        ? await db.collection('vehicles')
            .find({ _id: { $in: vehicleObjectIds } }).toArray()
        : [];

      const totalVehicles       = vehicles.length;
      const activeVehicles      = vehicles.filter(v => v.status === 'active').length;
      const maintenanceVehicles = vehicles.filter(v => v.status === 'maintenance').length;
      const inactiveVehicles    = vehicles.filter(v => v.status === 'inactive').length;

      // Vehicles by type
      const typeMap = new Map();
      vehicles.forEach(v => {
        const t = v.vehicleType || 'Unknown';
        typeMap.set(t, (typeMap.get(t) || 0) + 1);
      });
      const vehiclesByType = Array.from(typeMap.entries())
        .map(([type, count]) => ({ type, count }))
        .sort((a, b) => b.count - a.count);

      // Vehicles by seating capacity
      const capMap = new Map();
      vehicles.forEach(v => {
        const cap = v.seatingCapacity || 0;
        const range = cap <= 4 ? '1-4' : cap <= 7 ? '5-7' : cap <= 12 ? '8-12' : '13+';
        capMap.set(range, (capMap.get(range) || 0) + 1);
      });
      const vehiclesByCapacity = Array.from(capMap.entries())
        .map(([capacity, count]) => ({ capacity, count }))
        .sort((a, b) => {
          const order = { '1-4': 1, '5-7': 2, '8-12': 3, '13+': 4 };
          return order[a.capacity] - order[b.capacity];
        });

      responseData.vehicleStats    = { total: totalVehicles, active: activeVehicles, maintenance: maintenanceVehicles, inactive: inactiveVehicles };
      responseData.vehiclesByType     = vehiclesByType;
      responseData.vehiclesByCapacity = vehiclesByCapacity;

      console.log(`   ✅ Total: ${totalVehicles}, Active: ${activeVehicles}`);
    }

    // ========================================================================
    // SECTION 6: DRIVERS  (only drivers who served this domain)
    // ========================================================================
    const wantsDrivers = selectedTypes.length === 0 || selectedTypes.includes('drivers');
    if (wantsDrivers) {
      console.log('\n📊 [6/7] Drivers...');

      const domainTrips = await db.collection('roster-assigned-trips')
        .find(domainStopMatch, { projection: { driverId: 1 } }).toArray();

      const driverIds = [...new Set(
        domainTrips.map(t => t.driverId?.toString()).filter(Boolean)
      )];

      const driverObjectIds = driverIds
        .filter(id => ObjectId.isValid(id))
        .map(id => new ObjectId(id));

      const drivers = driverObjectIds.length > 0
        ? await db.collection('drivers')
            .find({ _id: { $in: driverObjectIds } }).toArray()
        : [];

      const totalDrivers    = drivers.length;
      const activeDrivers   = drivers.filter(d => d.status === 'active').length;
      const onLeaveDrivers  = drivers.filter(d =>
        d.status === 'on_leave' || d.status === 'onLeave'
      ).length;
      const inactiveDrivers = drivers.filter(d => d.status === 'inactive').length;

      responseData.driverStats = {
        total: totalDrivers,
        active: activeDrivers,
        onLeave: onLeaveDrivers,
        inactive: inactiveDrivers
      };

      console.log(`   ✅ Total: ${totalDrivers}, Active: ${activeDrivers}`);
    }

    // ========================================================================
    // SECTION 7: CUSTOMERS  (@domain customers only)
    // ========================================================================
    const wantsCustomers = selectedTypes.length === 0 || selectedTypes.includes('customers');
    if (wantsCustomers) {
      console.log('\n📊 [7/7] Customers...');

      const customers = await db.collection('customers')
        .find({ email: domainRegex(domain) }).toArray();

      const totalCustomers    = customers.length;
      const activeCustomers   = customers.filter(c => c.status === 'active').length;
      const inactiveCustomers = customers.filter(c => c.status === 'inactive').length;
      const pendingCustomers  = customers.filter(c => c.status === 'pending').length;

      // Customers by org/department (within the same company)
      const orgMap = new Map();
      customers.forEach(c => {
        const org = c.department || c.team || c.jobTitle || 'General';
        orgMap.set(org, (orgMap.get(org) || 0) + 1);
      });
      const customersByOrganization = Array.from(orgMap.entries())
        .map(([organization, count]) => ({ organization, count }))
        .sort((a, b) => b.count - a.count)
        .slice(0, 10);

      responseData.customerStatsData = {
        total: totalCustomers,
        active: activeCustomers,
        inactive: inactiveCustomers,
        pending: pendingCustomers
      };
      responseData.customersByOrganization = customersByOrganization;

      console.log(`   ✅ Total: ${totalCustomers}, Active: ${activeCustomers}`);
    }

    // ========================================================================
    // METADATA & RESPONSE
    // ========================================================================
    responseData.domain          = domain;
    responseData.dateRange       = { start: startDate || 'All Time', end: endDate || 'All Time' };
    responseData.selectedReportTypes = selectedTypes.length > 0 ? selectedTypes : ['all'];

    console.log('\n' + '='.repeat(80));
    console.log('✅ CLIENT REPORTS COMPLETE');
    console.log('='.repeat(80) + '\n');

    res.json({
      success: true,
      message: 'Client reports retrieved successfully',
      data: responseData
    });

  } catch (error) {
    console.error('\n❌ Client Reports Error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch client reports',
      error: error.message
    });
  }
});


module.exports = router;