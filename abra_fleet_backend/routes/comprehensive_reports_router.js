// routes/comprehensive_reports_router.js
// 📊 COMPREHENSIVE Reports API - COMPLETE VERSION WITH ALL SECTIONS
// ============================================================================
// ✅ INCLUDES:
// ✅ 1. Trips, SOS, Feedback, Documents, Satisfaction, Tickets (EXISTING)
// ✅ 2. Drivers, Vehicles, Customers, Clients (NEW)
// ============================================================================

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');

// ============================================================================
// @route   GET /api/reports/comprehensive
// @desc    Get analytics data with multi-select filters
// @access  Private (Admin/Manager)
// ============================================================================
router.get('/comprehensive', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📊 COMPREHENSIVE REPORTS - COMPLETE VERSION');
    console.log('='.repeat(80));
    
    // ========================================================================
    // EXTRACT FILTER PARAMETERS
    // ========================================================================
    const { startDate, endDate, reportTypes } = req.query;
    
    let dateQuery = {};
    
    if (startDate && endDate) {
      dateQuery = {
        scheduledDate: {
          $gte: startDate,
          $lte: endDate
        }
      };
      console.log(`📅 Filtering by date range: ${startDate} to ${endDate}`);
    } else {
      console.log(`📅 Fetching ALL data (no date filter)`);
    }
    
    // Parse selected report types
    let selectedTypes = [];
    if (reportTypes) {
      selectedTypes = reportTypes.split(',').map(t => t.trim().toLowerCase());
      console.log(`📋 Selected Report Types: ${selectedTypes.join(', ').toUpperCase()}`);
    } else {
      console.log(`📋 No specific report types selected`);
    }
    
    // Initialize response data
    let responseData = {};
    
    // ========================================================================
    // SECTION 1: TRIP STATISTICS
    // ========================================================================
    if (selectedTypes.length === 0 || selectedTypes.includes('trips')) {
      console.log('\n📊 [1/10] Analyzing TRIPS...');
      
      const allTrips = await req.db.collection('roster-assigned-trips').find(dateQuery).toArray();
      const completedTrips = allTrips.filter(t => t.status === 'completed');
      
      const totalTrips = allTrips.length;
      const scheduledTrips = allTrips.filter(t => t.status === 'assigned').length;
      const ongoingTrips = allTrips.filter(t => ['started', 'in_progress', 'ongoing'].includes(t.status?.toLowerCase())).length;
      const completedCount = completedTrips.length;
      const cancelledTrips = allTrips.filter(t => t.status === 'cancelled').length;
      
      console.log(`   ✅ Total: ${totalTrips}, Completed: ${completedCount}`);
      
      // Trip grouping stats
      const uniqueGroupIds = new Set(allTrips.map(t => t.tripGroupId).filter(Boolean));
      let totalCustomersInGroups = 0;
      let groupsWithCustomers = 0;
      
      for (const trip of allTrips) {
        if (trip.stops && Array.isArray(trip.stops)) {
          const pickupStops = trip.stops.filter(s => s.type === 'pickup');
          if (pickupStops.length > 0) {
            totalCustomersInGroups += pickupStops.length;
            groupsWithCustomers++;
          }
        }
      }
      
      const avgCustomersPerGroup = groupsWithCustomers > 0 ? totalCustomersInGroups / groupsWithCustomers : 0;
      const uniqueVehicles = new Set(allTrips.map(t => t.vehicleId?.toString()).filter(Boolean));
      const uniqueDrivers = new Set(allTrips.map(t => t.driverId?.toString()).filter(Boolean));
      
      // Trips by vehicle
      const tripsByVehicleMap = new Map();
      for (const trip of completedTrips) {
        const vehicleId = trip.vehicleId?.toString();
        if (!vehicleId) continue;
        
        if (!tripsByVehicleMap.has(vehicleId)) {
          tripsByVehicleMap.set(vehicleId, {
            vehicleId,
            vehicleNumber: trip.vehicleNumber || 'Unknown',
            count: 0
          });
        }
        tripsByVehicleMap.get(vehicleId).count++;
      }
      
      const tripsByVehicle = Array.from(tripsByVehicleMap.values())
        .sort((a, b) => b.count - a.count)
        .slice(0, 10);
      
      // Trips by driver
      const tripsByDriverMap = new Map();
      for (const trip of completedTrips) {
        const driverId = trip.driverId?.toString();
        if (!driverId) continue;
        
        if (!tripsByDriverMap.has(driverId)) {
          tripsByDriverMap.set(driverId, {
            driverId,
            driverName: trip.driverName || 'Unknown',
            count: 0
          });
        }
        tripsByDriverMap.get(driverId).count++;
      }
      
      const tripsByDriver = Array.from(tripsByDriverMap.values())
        .sort((a, b) => b.count - a.count)
        .slice(0, 10);
      
      // Trips by date
      const tripsByDateMap = new Map();
      for (const trip of completedTrips) {
        const date = trip.scheduledDate;
        if (!tripsByDateMap.has(date)) {
          tripsByDateMap.set(date, 0);
        }
        tripsByDateMap.set(date, tripsByDateMap.get(date) + 1);
      }
      
      const tripsByDate = Array.from(tripsByDateMap.entries())
        .map(([date, count]) => ({ date, count }))
        .sort((a, b) => a.date.localeCompare(b.date));
      
      responseData.tripStats = {
        total: totalTrips,
        scheduled: scheduledTrips,
        ongoing: ongoingTrips,
        completed: completedCount,
        cancelled: cancelledTrips
      };
      
      responseData.groupingStats = {
        totalGroups: uniqueGroupIds.size,
        avgCustomersPerGroup: parseFloat(avgCustomersPerGroup.toFixed(2)),
        totalVehicles: uniqueVehicles.size,
        totalDrivers: uniqueDrivers.size
      };
      
      responseData.tripsByDate = tripsByDate;
      responseData.tripsByVehicle = tripsByVehicle;
      responseData.tripsByDriver = tripsByDriver;
    }
    
    // ========================================================================
    // SECTION 2: SOS ANALYTICS
    // ========================================================================
    if (selectedTypes.length === 0 || selectedTypes.includes('sos')) {
      console.log('\n📊 [2/10] Analyzing SOS...');
      
      let sosQuery = {};
      if (startDate && endDate) {
        sosQuery.createdAt = {
          $gte: new Date(startDate),
          $lte: new Date(endDate)
        };
      }
      
      const allSOS = await req.db.collection('sos_events').find(sosQuery).toArray();
      
      const totalSOS = allSOS.length;
      const activeSOS = allSOS.filter(s => ['ACTIVE', 'Pending', 'In Progress'].includes(s.status)).length;
      const resolvedSOS = allSOS.filter(s => s.status === 'Resolved').length;
      
      // Calculate response time
      const resolvedSOSEvents = allSOS.filter(s => s.status === 'Resolved' && s.resolvedAt && s.createdAt);
      
      let totalResponseMinutes = 0;
      let fastestResponse = Infinity;
      let slowestResponse = 0;
      let validResponseCount = 0;
      
      for (const sos of resolvedSOSEvents) {
        try {
          const created = new Date(sos.createdAt);
          const resolved = new Date(sos.resolvedAt);
          
          if (isNaN(created.getTime()) || isNaN(resolved.getTime())) continue;
          
          const responseMinutes = Math.round((resolved - created) / 60000);
          if (responseMinutes < 0) continue;
          
          totalResponseMinutes += responseMinutes;
          validResponseCount++;
          
          if (responseMinutes < fastestResponse) fastestResponse = responseMinutes;
          if (responseMinutes > slowestResponse) slowestResponse = responseMinutes;
          
        } catch (err) {
          console.log(`   ⚠️  Error processing SOS ${sos._id}: ${err.message}`);
        }
      }
      
      const avgResponseTime = validResponseCount > 0 
        ? Math.round(totalResponseMinutes / validResponseCount) 
        : 0;
      
      // Format minutes function
      const formatMinutes = (minutes) => {
        if (minutes === 0) return '0 min';
        if (minutes < 60) return `${minutes} min`;
        
        const hours = Math.floor(minutes / 60);
        const mins = minutes % 60;
        
        if (hours < 24) {
          return mins > 0 ? `${hours}h ${mins}m` : `${hours}h`;
        }
        
        const days = Math.floor(hours / 24);
        const remainingHours = hours % 24;
        
        if (remainingHours > 0) {
          return `${days}d ${remainingHours}h`;
        }
        return `${days}d`;
      };
      
      // SOS by status
      const sosByStatusMap = new Map();
      for (const sos of allSOS) {
        const status = sos.status || 'Unknown';
        sosByStatusMap.set(status, (sosByStatusMap.get(status) || 0) + 1);
      }
      
      const sosByStatus = Array.from(sosByStatusMap.entries())
        .map(([status, count]) => ({ status, count }))
        .sort((a, b) => b.count - a.count);
      
      // SOS by month
      const sosByMonthMap = new Map();
      for (const sos of allSOS) {
        const month = new Date(sos.createdAt).toISOString().substring(0, 7);
        const status = sos.status === 'Resolved' ? 'resolved' : 'active';
        
        if (!sosByMonthMap.has(month)) {
          sosByMonthMap.set(month, { month, active: 0, resolved: 0 });
        }
        
        if (status === 'resolved') {
          sosByMonthMap.get(month).resolved++;
        } else {
          sosByMonthMap.get(month).active++;
        }
      }
      
      const sosByMonth = Array.from(sosByMonthMap.values())
        .sort((a, b) => a.month.localeCompare(b.month));
      
      // SOS by date
      const sosByDateMap = new Map();
      for (const sos of allSOS) {
        const date = new Date(sos.createdAt).toISOString().split('T')[0];
        sosByDateMap.set(date, (sosByDateMap.get(date) || 0) + 1);
      }
      
      const sosByDate = Array.from(sosByDateMap.entries())
        .map(([date, count]) => ({ date, count }))
        .sort((a, b) => a.date.localeCompare(b.date));
      
      responseData.sosStats = {
        total: totalSOS,
        active: activeSOS,
        resolved: resolvedSOS,
        avgResponseTime: avgResponseTime,
        avgResponseFormatted: formatMinutes(avgResponseTime),
        fastestResponse: fastestResponse === Infinity ? 0 : fastestResponse,
        fastestResponseFormatted: formatMinutes(fastestResponse === Infinity ? 0 : fastestResponse),
        slowestResponse: slowestResponse,
        slowestResponseFormatted: formatMinutes(slowestResponse)
      };
      
      responseData.sosByDate = sosByDate;
      responseData.sosByStatus = sosByStatus;
      responseData.sosByMonth = sosByMonth;
      
      console.log(`   ✅ Total: ${totalSOS}, Active: ${activeSOS}, Resolved: ${resolvedSOS}`);
    }
    
    // ========================================================================
    // SECTION 3: DRIVER FEEDBACK
    // ========================================================================
    if (selectedTypes.length === 0 || selectedTypes.includes('feedback')) {
      console.log('\n📊 [3/10] Analyzing FEEDBACK...');
      
      let feedbackQuery = { feedbackType: 'driver_trip_feedback' };
      if (startDate && endDate) {
        feedbackQuery.submittedAt = {
          $gte: new Date(startDate),
          $lte: new Date(endDate)
        };
      }
      
      const allFeedback = await req.db.collection('driver_feedback')
        .find(feedbackQuery)
        .toArray();
      
      const totalFeedback = allFeedback.length;
      const totalRating = allFeedback.reduce((sum, f) => sum + (f.rating || 0), 0);
      const avgRating = totalFeedback > 0 ? totalRating / totalFeedback : 0;
      
      const fiveStars = allFeedback.filter(f => f.rating === 5).length;
      const fourStars = allFeedback.filter(f => f.rating === 4).length;
      const positiveFeedback = fiveStars + fourStars;
      const positivePercentage = totalFeedback > 0 ? Math.round((positiveFeedback / totalFeedback) * 100) : 0;
      
      // Top drivers
      const driverFeedbackMap = new Map();
      for (const feedback of allFeedback) {
        const driverId = feedback.driverId?.toString();
        if (!driverId) continue;
        
        if (!driverFeedbackMap.has(driverId)) {
          driverFeedbackMap.set(driverId, {
            driverId,
            driverName: feedback.driverName || 'Unknown',
            phoneNumber: feedback.driverPhone || '',
            ratings: [],
            fiveStarCount: 0
          });
        }
        
        const driver = driverFeedbackMap.get(driverId);
        driver.ratings.push(feedback.rating || 0);
        if (feedback.rating === 5) driver.fiveStarCount++;
        
        if (!driver.phoneNumber && feedback.driverPhone) {
          driver.phoneNumber = feedback.driverPhone;
        }
      }
      
      const topDrivers = Array.from(driverFeedbackMap.values())
        .filter(d => d.ratings.length >= 1)
        .map(d => ({
          driverId: d.driverId,
          driverName: d.driverName,
          phoneNumber: d.phoneNumber,
          avgRating: parseFloat((d.ratings.reduce((a, b) => a + b, 0) / d.ratings.length).toFixed(2)),
          totalReviews: d.ratings.length,
          fiveStarCount: d.fiveStarCount
        }))
        .sort((a, b) => {
          if (b.avgRating !== a.avgRating) return b.avgRating - a.avgRating;
          return b.fiveStarCount - a.fiveStarCount;
        })
        .slice(0, 10);
      
      // Fetch missing phone numbers
      for (const driver of topDrivers) {
        if (!driver.phoneNumber && driver.driverId) {
          try {
            const driverDoc = await req.db.collection('drivers').findOne({ 
              _id: new ObjectId(driver.driverId) 
            });
            if (driverDoc) {
              driver.phoneNumber = driverDoc.phoneNumber || 
                                  driverDoc.phone || 
                                  driverDoc.personalInfo?.phone || 
                                  driverDoc.contactNumber || 
                                  '';
            }
          } catch (err) {
            console.log(`   ⚠️  Could not fetch phone for driver ${driver.driverId}`);
          }
        }
      }
      
      // Bottom drivers
      const bottomDrivers = Array.from(driverFeedbackMap.values())
        .filter(d => d.ratings.length >= 3)
        .map(d => ({
          driverId: d.driverId,
          driverName: d.driverName,
          avgRating: parseFloat((d.ratings.reduce((a, b) => a + b, 0) / d.ratings.length).toFixed(2)),
          totalReviews: d.ratings.length
        }))
        .sort((a, b) => a.avgRating - b.avgRating)
        .slice(0, 5);
      
      // Rating distribution
      const ratingDistribution = [
        { rating: 5, count: allFeedback.filter(f => f.rating === 5).length },
        { rating: 4, count: allFeedback.filter(f => f.rating === 4).length },
        { rating: 3, count: allFeedback.filter(f => f.rating === 3).length },
        { rating: 2, count: allFeedback.filter(f => f.rating === 2).length },
        { rating: 1, count: allFeedback.filter(f => f.rating === 1).length },
      ];
      
      responseData.feedbackStats = {
        total: totalFeedback,
        avgRating: parseFloat(avgRating.toFixed(2)),
        fiveStars: fiveStars,
        positive: positivePercentage
      };
      
      responseData.topDrivers = topDrivers;
      responseData.bottomDrivers = bottomDrivers;
      responseData.ratingDistribution = ratingDistribution;
      
      console.log(`   ✅ Total: ${totalFeedback}, Avg Rating: ${avgRating.toFixed(2)}`);
    }
    
    // ========================================================================
    // SECTION 4: DOCUMENT EXPIRY
    // ========================================================================
    if (selectedTypes.length === 0 || selectedTypes.includes('documents')) {
      console.log('\n📊 [4/10] Analyzing DOCUMENTS...');
      
      const now = new Date();
      const thirtyDaysFromNow = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
      
      const allExpiringDocs = [];
      let totalExpiredCount = 0;
      let totalExpiringSoonCount = 0;
      let driverExpiredCount = 0;
      let driverExpiringSoonCount = 0;
      let vehicleExpiredCount = 0;
      let vehicleExpiringSoonCount = 0;
      
      // Check driver licenses
      const driversWithLicenses = await req.db.collection('drivers').find({
        status: 'active',
        'license.expiryDate': { $exists: true }
      }).toArray();
      
      for (const driver of driversWithLicenses) {
        if (!driver.license || !driver.license.expiryDate) continue;
        
        const expiryDate = new Date(driver.license.expiryDate);
        const daysUntilExpiry = Math.ceil((expiryDate - now) / (1000 * 60 * 60 * 24));
        
        if (daysUntilExpiry > 30) continue;
        
        const isExpired = daysUntilExpiry <= 0;
        
        if (isExpired) {
          totalExpiredCount++;
          driverExpiredCount++;
        } else {
          totalExpiringSoonCount++;
          driverExpiringSoonCount++;
        }
        
        const driverName = driver.personalInfo?.name || driver.name || driver.driverId || 'Unknown';
        
        allExpiringDocs.push({
          type: 'driver',
          name: driverName,
          userId: driver._id?.toString(),
          userEmail: driver.personalInfo?.email || driver.email || '',
          documentType: 'Driver License',
          licenseNumber: driver.license.licenseNumber || 'N/A',
          expiryDate: expiryDate.toISOString(),
          daysLeft: daysUntilExpiry,
          status: isExpired ? 'expired' : 'expiring_soon'
        });
      }
      
      // Check driver documents array
      const driversWithDocs = await req.db.collection('drivers').find({
        status: 'active',
        'documents': { $exists: true, $ne: [] }
      }).toArray();
      
      for (const driver of driversWithDocs) {
        if (!driver.documents || !Array.isArray(driver.documents)) continue;
        
        for (const doc of driver.documents) {
          if (!doc.expiryDate || doc.status !== 'active') continue;
          
          const expiryDate = new Date(doc.expiryDate);
          const daysUntilExpiry = Math.ceil((expiryDate - now) / (1000 * 60 * 60 * 24));
          
          if (daysUntilExpiry > 30) continue;
          
          const isExpired = daysUntilExpiry <= 0;
          
          if (isExpired) {
            totalExpiredCount++;
            driverExpiredCount++;
          } else {
            totalExpiringSoonCount++;
            driverExpiringSoonCount++;
          }
          
          const driverName = driver.personalInfo?.name || driver.name || driver.driverId || 'Unknown';
          
          allExpiringDocs.push({
            type: 'driver',
            name: driverName,
            userId: driver._id?.toString(),
            userEmail: driver.personalInfo?.email || driver.email || '',
            documentType: doc.documentType || 'Document',
            licenseNumber: doc.documentNumber || driver.driverId || 'N/A',
            expiryDate: expiryDate.toISOString(),
            daysLeft: daysUntilExpiry,
            status: isExpired ? 'expired' : 'expiring_soon'
          });
        }
      }
      
      // Check vehicle documents
      const documentTypes = [
        { field: 'insurance', label: 'Insurance' },
        { field: 'rc', label: 'RC' },
        { field: 'fc', label: 'FC' },
        { field: 'permit', label: 'Permit' }
      ];
      
      const vehicles = await req.db.collection('vehicles').find({
        status: 'active'
      }).toArray();
      
      for (const vehicle of vehicles) {
        for (const docType of documentTypes) {
          const doc = vehicle[docType.field];
          if (!doc || !doc.expiryDate) continue;
          
          const expiryDate = new Date(doc.expiryDate);
          const daysUntilExpiry = Math.ceil((expiryDate - now) / (1000 * 60 * 60 * 24));
          
          if (daysUntilExpiry > 30) continue;
          
          const isExpired = daysUntilExpiry <= 0;
          
          if (isExpired) {
            totalExpiredCount++;
            vehicleExpiredCount++;
          } else {
            totalExpiringSoonCount++;
            vehicleExpiringSoonCount++;
          }
          
          allExpiringDocs.push({
            type: 'vehicle',
            name: vehicle.registrationNumber || vehicle.vehicleNumber || 'Unknown',
            userId: vehicle._id?.toString(),
            userEmail: '',
            documentType: docType.label,
            licenseNumber: vehicle.registrationNumber || 'N/A',
            vehicleNumber: vehicle.registrationNumber,
            expiryDate: expiryDate.toISOString(),
            daysLeft: daysUntilExpiry,
            status: isExpired ? 'expired' : 'expiring_soon'
          });
        }
      }
      
      allExpiringDocs.sort((a, b) => a.daysLeft - b.daysLeft);
      
      const totalVehicles = vehicles.length;
      const totalDrivers = driversWithLicenses.length;
      const vehicleValidCount = Math.max(0, (totalVehicles * 4) - vehicleExpiredCount - vehicleExpiringSoonCount);
      const driverValidCount = Math.max(0, (totalDrivers * 2) - driverExpiredCount - driverExpiringSoonCount);
      const totalValidCount = vehicleValidCount + driverValidCount;
      
      responseData.documentStats = {
        total: {
          expired: totalExpiredCount,
          expiringSoon: totalExpiringSoonCount,
          valid: totalValidCount
        },
        vehicles: {
          expired: vehicleExpiredCount,
          expiringSoon: vehicleExpiringSoonCount,
          valid: vehicleValidCount
        },
        drivers: {
          expired: driverExpiredCount,
          expiringSoon: driverExpiringSoonCount,
          valid: driverValidCount
        }
      };
      
      responseData.expiringDocs = allExpiringDocs.slice(0, 50);
      
      console.log(`   ✅ Expired: ${totalExpiredCount}, Expiring Soon: ${totalExpiringSoonCount}`);
    }
    
    // ========================================================================
    // SECTION 5: CUSTOMER SATISFACTION
    // ========================================================================
    if (selectedTypes.length === 0 || selectedTypes.includes('satisfaction')) {
      console.log('\n📊 [5/10] Analyzing CUSTOMER SATISFACTION...');
      
      let feedbackQuery = { feedbackType: 'driver_trip_feedback' };
      if (startDate && endDate) {
        feedbackQuery.submittedAt = {
          $gte: new Date(startDate),
          $lte: new Date(endDate)
        };
      }
      
      const allFeedback = await req.db.collection('driver_feedback')
        .find(feedbackQuery)
        .toArray();
      
      const totalFeedback = allFeedback.length;
      const totalRating = allFeedback.reduce((sum, f) => sum + (f.rating || 0), 0);
      const avgRating = totalFeedback > 0 ? totalRating / totalFeedback : 0;
      
      const rideAgainStats = [
        { response: 'yes', count: allFeedback.filter(f => f.rideAgain === 'yes').length },
        { response: 'no', count: allFeedback.filter(f => f.rideAgain === 'no').length },
        { response: 'not_specified', count: allFeedback.filter(f => !f.rideAgain || f.rideAgain === 'not_specified').length },
      ].filter(s => s.count > 0);
      
      const wouldRideAgain = rideAgainStats.find(r => r.response === 'yes')?.count || 0;
      const wouldNotRideAgain = rideAgainStats.find(r => r.response === 'no')?.count || 0;
      
      responseData.customerStats = {
        totalFeedback: totalFeedback,
        avgRating: parseFloat(avgRating.toFixed(2)),
        wouldRideAgain: wouldRideAgain,
        wouldNotRideAgain: wouldNotRideAgain
      };
      
      responseData.rideAgainStats = rideAgainStats;
      
      console.log(`   ✅ Total: ${totalFeedback}, Avg Rating: ${avgRating.toFixed(2)}`);
    }
    
    // ========================================================================
    // SECTION 6: SUPPORT TICKETS
    // ========================================================================
    // ========================================================================
// SECTION 6: SUPPORT TICKETS
// ========================================================================
if (selectedTypes.length === 0 || selectedTypes.includes('tickets')) {
  console.log('\n📊 [6/10] Analyzing SUPPORT TICKETS...');
  
  let ticketQuery = {};
  if (startDate && endDate) {
    ticketQuery.createdAt = {
      $gte: new Date(startDate),
      $lte: new Date(endDate)
    };
  }
  
  const allTickets = await req.db.collection('tickets').find(ticketQuery).toArray();
  
  const totalTickets = allTickets.length;
  const openTickets = allTickets.filter(t => t.status === 'Open').length;
  const inProgressTickets = allTickets.filter(t => t.status === 'In Progress').length;
  const closedTickets = allTickets.filter(t => t.status === 'closed').length;
  
  const closedTicketsList = allTickets.filter(t => t.status === 'closed' && t.closedAt);
  let totalResolutionTime = 0;
  for (const ticket of closedTicketsList) {
    const resolutionHours = (new Date(ticket.closedAt) - new Date(ticket.createdAt)) / (60 * 60 * 1000);
    totalResolutionTime += resolutionHours;
  }
  
  const avgResolutionTime = closedTicketsList.length > 0 
    ? Math.round(totalResolutionTime / closedTicketsList.length) 
    : 0;
  
  // Tickets by category
  const ticketsByCategoryMap = new Map();
  for (const ticket of allTickets) {
    const category = ticket.category || 'Uncategorized';
    ticketsByCategoryMap.set(category, (ticketsByCategoryMap.get(category) || 0) + 1);
  }
  
  const ticketsByCategory = Array.from(ticketsByCategoryMap.entries())
    .map(([category, count]) => ({ category, count }))
    .sort((a, b) => b.count - a.count);
  
  // ✅ NEW: Tickets by priority
  const ticketsByPriorityMap = new Map();
  for (const ticket of allTickets) {
    const priority = ticket.priority || 'Medium';
    ticketsByPriorityMap.set(priority, (ticketsByPriorityMap.get(priority) || 0) + 1);
  }
  
  const ticketsByPriority = Array.from(ticketsByPriorityMap.entries())
    .map(([priority, count]) => ({ priority, count }))
    .sort((a, b) => {
      const order = { 'High': 1, 'Medium': 2, 'Low': 3 };
      return (order[a.priority] || 4) - (order[b.priority] || 4);
    });
  
  responseData.ticketStats = {
    total: totalTickets,
    open: openTickets,
    inProgress: inProgressTickets, // ✅ CORRECT KEY
    closed: closedTickets,
    avgResolutionTime: avgResolutionTime
  };
  
  responseData.ticketsByCategory = ticketsByCategory;
  responseData.ticketsByPriority = ticketsByPriority; // ✅ NEW
  
  console.log(`   ✅ Total: ${totalTickets}, Open: ${openTickets}, In Progress: ${inProgressTickets}, Closed: ${closedTickets}`);
}
    
    // ========================================================================
    // ✅ SECTION 7: DRIVERS (NEW)
    // ========================================================================
    if (selectedTypes.length === 0 || selectedTypes.includes('drivers')) {
      console.log('\n📊 [7/10] Analyzing DRIVERS...');
      
      const allDrivers = await req.db.collection('drivers').find({}).toArray();
      
      const totalDrivers = allDrivers.length;
      const activeDrivers = allDrivers.filter(d => d.status === 'active').length;
      const onLeaveDrivers = allDrivers.filter(d => d.status === 'on_leave' || d.status === 'onLeave').length;
      const inactiveDrivers = allDrivers.filter(d => d.status === 'inactive').length;
      
      responseData.driverStats = {
        total: totalDrivers,
        active: activeDrivers,
        onLeave: onLeaveDrivers,
        inactive: inactiveDrivers
      };
      
      console.log(`   ✅ Total: ${totalDrivers}, Active: ${activeDrivers}, On Leave: ${onLeaveDrivers}`);
    }
    
    // ========================================================================
    // ✅ SECTION 8: VEHICLES (NEW)
    // ========================================================================
    if (selectedTypes.length === 0 || selectedTypes.includes('vehicles')) {
      console.log('\n📊 [8/10] Analyzing VEHICLES...');
      
      const allVehicles = await req.db.collection('vehicles').find({}).toArray();
      
      const totalVehicles = allVehicles.length;
      const activeVehicles = allVehicles.filter(v => v.status === 'active').length;
      const maintenanceVehicles = allVehicles.filter(v => v.status === 'maintenance').length;
      const inactiveVehicles = allVehicles.filter(v => v.status === 'inactive').length;
      
      // Vehicles by type
      const vehiclesByTypeMap = new Map();
      for (const vehicle of allVehicles) {
        const type = vehicle.vehicleType || 'Unknown';
        vehiclesByTypeMap.set(type, (vehiclesByTypeMap.get(type) || 0) + 1);
      }
      
      const vehiclesByType = Array.from(vehiclesByTypeMap.entries())
        .map(([type, count]) => ({ type, count }))
        .sort((a, b) => b.count - a.count);
      
      // Vehicles by seating capacity
      const vehiclesByCapacityMap = new Map();
      for (const vehicle of allVehicles) {
        const capacity = vehicle.seatingCapacity || 0;
        const capacityRange = capacity <= 4 ? '1-4' : 
                             capacity <= 7 ? '5-7' : 
                             capacity <= 12 ? '8-12' : 
                             '13+';
        vehiclesByCapacityMap.set(capacityRange, (vehiclesByCapacityMap.get(capacityRange) || 0) + 1);
      }
      
      const vehiclesByCapacity = Array.from(vehiclesByCapacityMap.entries())
        .map(([capacity, count]) => ({ capacity, count }))
        .sort((a, b) => {
          const order = { '1-4': 1, '5-7': 2, '8-12': 3, '13+': 4 };
          return order[a.capacity] - order[b.capacity];
        });
      
      responseData.vehicleStats = {
        total: totalVehicles,
        active: activeVehicles,
        maintenance: maintenanceVehicles,
        inactive: inactiveVehicles
      };
      
      responseData.vehiclesByType = vehiclesByType;
      responseData.vehiclesByCapacity = vehiclesByCapacity;
      
      console.log(`   ✅ Total: ${totalVehicles}, Active: ${activeVehicles}, Maintenance: ${maintenanceVehicles}`);
    }
    
    // ========================================================================
    // ✅ SECTION 9: CUSTOMERS (NEW)
    // ========================================================================
    if (selectedTypes.length === 0 || selectedTypes.includes('customers')) {
      console.log('\n📊 [9/10] Analyzing CUSTOMERS...');
      
      const allCustomers = await req.db.collection('customers').find({}).toArray();
      
      const totalCustomers = allCustomers.length;
      const activeCustomers = allCustomers.filter(c => c.status === 'active').length;
      const inactiveCustomers = allCustomers.filter(c => c.status === 'inactive').length;
      const pendingCustomers = allCustomers.filter(c => c.status === 'pending').length;
      
      // Customers by organization
      const customersByOrgMap = new Map();
      for (const customer of allCustomers) {
        const org = customer.companyName || customer.organizationName || 'Unknown';
        customersByOrgMap.set(org, (customersByOrgMap.get(org) || 0) + 1);
      }
      
      const customersByOrganization = Array.from(customersByOrgMap.entries())
        .map(([organization, count]) => ({ organization, count }))
        .sort((a, b) => b.count - a.count)
        .slice(0, 10);
      
      responseData.customerStats = {
        total: totalCustomers,
        active: activeCustomers,
        inactive: inactiveCustomers,
        pending: pendingCustomers
      };
      
      responseData.customersByOrganization = customersByOrganization;
      
      console.log(`   ✅ Total: ${totalCustomers}, Active: ${activeCustomers}`);
    }
    
    // ========================================================================
    // ✅ SECTION 10: CLIENTS (NEW)
    // ========================================================================
    if (selectedTypes.length === 0 || selectedTypes.includes('clients')) {
      console.log('\n📊 [10/10] Analyzing CLIENTS...');
      
      const allClients = await req.db.collection('clients').find({}).toArray();
      
      const totalClients = allClients.length;
      const activeClients = allClients.filter(c => c.status === 'active').length;
      const inactiveClients = allClients.filter(c => c.status === 'inactive').length;
      const pendingClients = allClients.filter(c => c.status === 'pending').length;
      
      // Top clients by customer count
      const clientsWithCustomerCount = [];
      
      for (const client of allClients) {
        // Get email domain from client email
        const clientEmail = client.email || '';
        const domain = clientEmail.includes('@') ? '@' + clientEmail.split('@')[1] : null;
        
        if (!domain) continue;
        
        // Count customers with matching domain
        const customerCount = await req.db.collection('customers').countDocuments({
          email: { $regex: domain + '$', $options: 'i' }
        });
        
        clientsWithCustomerCount.push({
          clientId: client._id?.toString(),
          name: client.name || client.companyName || 'Unknown',
          customerCount: customerCount
        });
      }
      
      const topClientsByCustomers = clientsWithCustomerCount
        .sort((a, b) => b.customerCount - a.customerCount)
        .slice(0, 10);
      
      responseData.clientStats = {
        total: totalClients,
        active: activeClients,
        inactive: inactiveClients,
        pending: pendingClients
      };
      
      responseData.topClientsByCustomers = topClientsByCustomers;
      
      console.log(`   ✅ Total: ${totalClients}, Active: ${activeClients}`);
    }
    
    // ========================================================================
    // ADD METADATA
    // ========================================================================
    responseData.dateRange = {
      start: startDate || 'All Time',
      end: endDate || 'All Time'
    };
    
    responseData.selectedReportTypes = selectedTypes.length > 0 ? selectedTypes : ['all'];
    
    // ========================================================================
    // RESPONSE
    // ========================================================================
    console.log('\n' + '='.repeat(80));
    console.log('✅ COMPREHENSIVE REPORTS COMPLETED - ALL 10 SECTIONS');
    console.log(`📋 Report Types: ${responseData.selectedReportTypes.join(', ').toUpperCase()}`);
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Comprehensive reports retrieved successfully',
      data: responseData
    });
    
  } catch (error) {
    console.error('\n❌ Error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch reports',
      error: error.message
    });
  }
});

module.exports = router;