// // services/admin_live_tracking_service.js
// // ============================================================================
// // ADMIN LIVE TRACKING SERVICE - Business Logic Layer
// // ============================================================================
// // Fetches from ALL 3 collections:
// //   1. roster-assigned-trips  → tripType: pickup/drop (multi-stop roster trips)
// //   2. trips                  → tripType: manual (admin panel manual trips)
// //   3. client_created_trips   → tripType: client_request (client requested trips)
// // ============================================================================

// const { ObjectId } = require('mongodb');
// const notificationService = require('./fcm_service');

// // ============================================================================
// // UTILITY: Haversine distance between two coordinates (km)
// // ============================================================================
// function calculateDistance(lat1, lon1, lat2, lon2) {
//   const R = 6371;
//   const dLat = toRad(lat2 - lat1);
//   const dLon = toRad(lon2 - lon1);
//   const a =
//     Math.sin(dLat / 2) * Math.sin(dLat / 2) +
//     Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
//     Math.sin(dLon / 2) * Math.sin(dLon / 2);
//   const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
//   return R * c;
// }

// function toRad(degrees) {
//   return degrees * (Math.PI / 180);
// }

// // ============================================================================
// // NORMALISER: roster-assigned-trips → shared vehicle shape
// // ============================================================================
// function normaliseRosterTrip(trip) {
//   const now = new Date();
//   let isIdle = false;
//   if (trip.currentLocation && trip.currentLocation.timestamp) {
//     const lastUpdate = new Date(trip.currentLocation.timestamp);
//     const minutesSinceUpdate = (now - lastUpdate) / 1000 / 60;
//     isIdle = minutesSinceUpdate > 10;
//   }

//   const currentStopIndex = trip.currentStopIndex || 0;
//   const currentStop =
//     trip.stops && trip.stops[currentStopIndex]
//       ? trip.stops[currentStopIndex]
//       : null;
//   const completedStops = trip.stops
//     ? trip.stops.filter((s) => s.status === 'completed').length
//     : 0;
//   const totalStops = trip.stops ? trip.stops.length : 0;

//   // Normalise stop coordinates — roster uses coordinates.latitude/longitude nested
//   const normalisedStops = (trip.stops || []).map((stop) => ({
//     ...stop,
//     location: {
//       address: stop.location?.address || '',
//       coordinates: {
//         latitude: stop.location?.coordinates?.latitude || null,
//         longitude: stop.location?.coordinates?.longitude || null,
//       },
//     },
//   }));

//   return {
//     tripId: trip._id.toString(),
//     tripGroupId: trip.tripGroupId || null,
//     tripNumber: trip.tripNumber || 'N/A',
//     source: 'roster',
//     tripType: trip.tripType || 'pickup',

//     vehicleId: trip.vehicleId?.toString() || '',
//     vehicleNumber: trip.vehicleNumber || 'Unknown',
//     vehicleName: trip.vehicleName || trip.vehicleNumber || 'Unknown',

//     driverId: trip.driverId?.toString() || '',
//     driverName: trip.driverName || 'Unknown',
//     driverPhone: trip.driverPhone || '',
//     driverEmail: trip.driverEmail || '',

//     status: trip.status,
//     isIdle: isIdle,
//     scheduledDate: trip.scheduledDate || null,

//     currentLocation: trip.currentLocation || null,
//     locationHistory: (trip.locationHistory || []).slice(-50),

//     stops: normalisedStops,
//     totalStops: totalStops,
//     completedStops: completedStops,
//     currentStopIndex: currentStopIndex,
//     currentStop: currentStop,

//     progress: totalStops > 0 ? (completedStops / totalStops) * 100 : 0,

//     totalDistance: trip.totalDistance || 0,
//     estimatedDuration: trip.estimatedDuration || 0,

//     customerName: null,
//     customerPhone: null,
//     customerEmail: null,

//     lastUpdated: trip.currentLocation?.timestamp || trip.updatedAt,
//   };
// }

// // ============================================================================
// // NORMALISER: trips (manual admin panel trips) → shared vehicle shape
// // pickupLocation + dropLocation converted into a 2-stop array
// // ============================================================================
// function normaliseManualTrip(trip) {
//   const now = new Date();
//   let isIdle = false;
//   if (trip.currentLocation && trip.currentLocation.timestamp) {
//     const lastUpdate = new Date(trip.currentLocation.timestamp);
//     const minutesSinceUpdate = (now - lastUpdate) / 1000 / 60;
//     isIdle = minutesSinceUpdate > 10;
//   }

//   const stops = [];

//   if (trip.pickupLocation) {
//     stops.push({
//       stopId: 'pickup',
//       sequence: 1,
//       type: 'pickup',
//       status:
//         trip.status === 'started' || trip.status === 'in_progress'
//           ? 'arrived'
//           : 'pending',
//       customer: {
//         name: trip.customerName || trip.customer?.name || 'Customer',
//         email: trip.customerEmail || trip.customer?.email || '',
//         phone: trip.customerPhone || trip.customer?.phone || '',
//       },
//       location: {
//         address: trip.pickupLocation.address || '',
//         coordinates: {
//           latitude:
//             trip.pickupLocation.latitude ||
//             trip.pickupLocation.coordinates?.coordinates?.[1] ||
//             null,
//           longitude:
//             trip.pickupLocation.longitude ||
//             trip.pickupLocation.coordinates?.coordinates?.[0] ||
//             null,
//         },
//       },
//       estimatedTime: trip.scheduledPickupTime || null,
//     });
//   }

//   if (trip.dropLocation) {
//     stops.push({
//       stopId: 'drop',
//       sequence: 2,
//       type: 'drop',
//       status: 'pending',
//       customer: {
//         name: trip.customerName || trip.customer?.name || 'Customer',
//         email: trip.customerEmail || trip.customer?.email || '',
//         phone: trip.customerPhone || trip.customer?.phone || '',
//       },
//       location: {
//         address: trip.dropLocation.address || '',
//         coordinates: {
//           latitude:
//             trip.dropLocation.latitude ||
//             trip.dropLocation.coordinates?.coordinates?.[1] ||
//             null,
//           longitude:
//             trip.dropLocation.longitude ||
//             trip.dropLocation.coordinates?.coordinates?.[0] ||
//             null,
//         },
//       },
//       estimatedTime: trip.dropTime || trip.estimatedEndTime || null,
//     });
//   }

//   return {
//     tripId: trip._id.toString(),
//     tripGroupId: null,
//     tripNumber: trip.tripNumber || 'N/A',
//     source: 'manual',
//     tripType: 'manual',

//     vehicleId: trip.vehicleId?.toString() || '',
//     vehicleNumber: trip.vehicleNumber || 'Unknown',
//     vehicleName: trip.vehicleNumber || 'Unknown',

//     driverId: trip.driverId?.toString() || '',
//     driverName: trip.driverName || 'Unknown',
//     driverPhone: trip.driverPhone || '',
//     driverEmail: trip.driverEmail || '',

//     status: trip.status,
//     isIdle: isIdle,
//     scheduledDate: trip.scheduledPickupTime
//       ? new Date(trip.scheduledPickupTime).toISOString().split('T')[0]
//       : null,

//     currentLocation: trip.currentLocation || null,
//     locationHistory: (trip.locationHistory || []).slice(-50),

//     stops: stops,
//     totalStops: stops.length,
//     completedStops: 0,
//     currentStopIndex: 0,
//     currentStop: stops[0] || null,

//     progress: trip.status === 'completed' ? 100 : 50,

//     totalDistance: trip.distance || 0,
//     estimatedDuration: trip.estimatedDuration || 0,

//     customerName: trip.customerName || trip.customer?.name || 'N/A',
//     customerPhone: trip.customerPhone || trip.customer?.phone || '',
//     customerEmail: trip.customerEmail || trip.customer?.email || '',

//     lastUpdated: trip.currentLocation?.timestamp || trip.updatedAt,
//   };
// }

// // ============================================================================
// // NORMALISER: client_created_trips → shared vehicle shape
// // Uses clientName/clientEmail/clientPhone instead of customerName
// // ============================================================================
// function normaliseClientTrip(trip) {
//   const now = new Date();
//   let isIdle = false;
//   if (trip.currentLocation && trip.currentLocation.timestamp) {
//     const lastUpdate = new Date(trip.currentLocation.timestamp);
//     const minutesSinceUpdate = (now - lastUpdate) / 1000 / 60;
//     isIdle = minutesSinceUpdate > 10;
//   }

//   const stops = [];

//   if (trip.pickupLocation) {
//     stops.push({
//       stopId: 'pickup',
//       sequence: 1,
//       type: 'pickup',
//       status:
//         trip.status === 'started' || trip.status === 'in_progress'
//           ? 'arrived'
//           : 'pending',
//       customer: {
//         name: trip.clientName || 'Client',
//         email: trip.clientEmail || '',
//         phone: trip.clientPhone || '',
//       },
//       location: {
//         address: trip.pickupLocation.address || '',
//         coordinates: {
//           latitude:
//             trip.pickupLocation.latitude ||
//             trip.pickupLocation.coordinates?.coordinates?.[1] ||
//             null,
//           longitude:
//             trip.pickupLocation.longitude ||
//             trip.pickupLocation.coordinates?.coordinates?.[0] ||
//             null,
//         },
//       },
//       estimatedTime: trip.scheduledPickupTime || null,
//     });
//   }

//   if (trip.dropLocation) {
//     stops.push({
//       stopId: 'drop',
//       sequence: 2,
//       type: 'drop',
//       status: 'pending',
//       customer: {
//         name: trip.clientName || 'Client',
//         email: trip.clientEmail || '',
//         phone: trip.clientPhone || '',
//       },
//       location: {
//         address: trip.dropLocation.address || '',
//         coordinates: {
//           latitude:
//             trip.dropLocation.latitude ||
//             trip.dropLocation.coordinates?.coordinates?.[1] ||
//             null,
//           longitude:
//             trip.dropLocation.longitude ||
//             trip.dropLocation.coordinates?.coordinates?.[0] ||
//             null,
//         },
//       },
//       estimatedTime: trip.estimatedEndTime || trip.scheduledDropTime || null,
//     });
//   }

//   return {
//     tripId: trip._id.toString(),
//     tripGroupId: null,
//     tripNumber: trip.tripNumber || 'N/A',
//     source: 'client',
//     tripType: 'client_request',

//     vehicleId: trip.vehicleId?.toString() || '',
//     vehicleNumber: trip.vehicleNumber || 'Unknown',
//     vehicleName: trip.vehicleNumber || 'Unknown',

//     driverId: trip.driverId?.toString() || '',
//     driverName: trip.driverName || 'Unknown',
//     driverPhone: trip.driverPhone || '',
//     driverEmail: trip.driverEmail || '',

//     status: trip.status,
//     isIdle: isIdle,
//     scheduledDate: trip.scheduledPickupTime
//       ? new Date(trip.scheduledPickupTime).toISOString().split('T')[0]
//       : null,

//     currentLocation: trip.currentLocation || null,
//     locationHistory: (trip.locationHistory || []).slice(-50),

//     stops: stops,
//     totalStops: stops.length,
//     completedStops: 0,
//     currentStopIndex: 0,
//     currentStop: stops[0] || null,

//     progress: trip.status === 'completed' ? 100 : 50,

//     totalDistance: trip.distance || 0,
//     estimatedDuration: trip.estimatedDuration || 0,

//     // Map client fields to common customer field names
//     customerName: trip.clientName || 'N/A',
//     customerPhone: trip.clientPhone || '',
//     customerEmail: trip.clientEmail || '',

//     lastUpdated: trip.currentLocation?.timestamp || trip.updatedAt,
//   };
// }

// // ============================================================================
// // MAIN FUNCTION: fetchLiveVehicles — queries ALL 3 collections and merges
// // ============================================================================
// async function fetchLiveVehicles(db, date, statusFilter, companyFilter) {
//   try {
//     console.log('🔍 Querying all 3 trip collections...');

//     const dayStart = new Date(`${date}T00:00:00.000Z`);
//     const dayEnd = new Date(`${date}T23:59:59.999Z`);

//     // ── QUERY 1: roster-assigned-trips (uses scheduledDate string field) ──
//     const rosterQuery = {
//       scheduledDate: date,
//       status: statusFilter,
//     };

//     if (companyFilter && companyFilter !== 'all') {
//       rosterQuery['stops.customer.email'] = new RegExp(
//         `@${companyFilter}\\.`,
//         'i'
//       );
//     }

//     const rosterTrips = await db
//       .collection('roster-assigned-trips')
//       .find(rosterQuery)
//       .toArray();

//     console.log(`  roster-assigned-trips : ${rosterTrips.length} doc(s)`);

//     // ── QUERY 2: trips — manual trips from admin panel ────────────────────
//     const manualTrips = await db
//       .collection('trips')
//       .find({
//         status: statusFilter,
//         scheduledPickupTime: { $gte: dayStart, $lte: dayEnd },
//       })
//       .toArray();

//     console.log(`  trips (manual)        : ${manualTrips.length} doc(s)`);

//     // ── QUERY 3: client_created_trips ─────────────────────────────────────
//     const clientTrips = await db
//       .collection('client_created_trips')
//       .find({
//         status: statusFilter,
//         scheduledPickupTime: { $gte: dayStart, $lte: dayEnd },
//       })
//       .toArray();

//     console.log(`  client_created_trips  : ${clientTrips.length} doc(s)`);

//     // ── Normalise all 3 into the same shape ───────────────────────────────
//     const rosterNormalised = rosterTrips.map(normaliseRosterTrip);
//     const manualNormalised = manualTrips.map(normaliseManualTrip);
//     const clientNormalised = clientTrips.map(normaliseClientTrip);

//     // ── Merge & deduplicate by tripId ─────────────────────────────────────
//     const seen = new Set();
//     const merged = [];

//     for (const vehicle of [
//       ...rosterNormalised,
//       ...manualNormalised,
//       ...clientNormalised,
//     ]) {
//       if (!seen.has(vehicle.tripId)) {
//         seen.add(vehicle.tripId);
//         merged.push(vehicle);
//       }
//     }

//     console.log(`✅ Merged total: ${merged.length} vehicle trip(s)`);
//     return merged;
//   } catch (error) {
//     console.error('❌ Error in fetchLiveVehicles:', error);
//     throw error;
//   }
// }

// // ============================================================================
// // FUNCTION: checkVehicleAlerts — works on merged list from all 3 collections
// // ============================================================================
// async function checkVehicleAlerts(db, vehicles) {
//   const alerts = {
//     offline: [],
//     routeDeviation: [],
//     speeding: [],
//   };

//   const now = new Date();
//   const fiveMinutesAgo = new Date(now.getTime() - 5 * 60 * 1000);

//   for (const vehicle of vehicles) {
//     try {
//       if (vehicle.status === 'completed') continue;

//       // ── CHECK 1: Offline (>5 min no GPS update) ──────────────────────────
//       if (!vehicle.currentLocation || !vehicle.currentLocation.timestamp) {
//         alerts.offline.push({
//           vehicleId: vehicle.vehicleId,
//           vehicleNumber: vehicle.vehicleNumber,
//           driverName: vehicle.driverName,
//           tripId: vehicle.tripId,
//           source: vehicle.source,
//           offlineSince: vehicle.lastUpdated || null,
//           duration: 'Unknown',
//         });

//         await notifyVehicleOffline(db, vehicle, 'No GPS data');
//       } else {
//         const lastUpdate = new Date(vehicle.currentLocation.timestamp);

//         if (lastUpdate < fiveMinutesAgo) {
//           const minutesOffline = Math.floor((now - lastUpdate) / 1000 / 60);
//           const duration =
//             minutesOffline >= 60
//               ? `${Math.floor(minutesOffline / 60)}h ${minutesOffline % 60}m`
//               : `${minutesOffline} minutes`;

//           alerts.offline.push({
//             vehicleId: vehicle.vehicleId,
//             vehicleNumber: vehicle.vehicleNumber,
//             driverName: vehicle.driverName,
//             tripId: vehicle.tripId,
//             source: vehicle.source,
//             offlineSince: lastUpdate,
//             duration: duration,
//           });

//           await notifyVehicleOffline(db, vehicle, duration);
//         }
//       }

//       if (!vehicle.currentLocation) continue;

//       // ── CHECK 2: Route deviation (>5 km from next stop) ──────────────────
//       if (
//         vehicle.currentStop &&
//         vehicle.currentStop.location?.coordinates?.latitude
//       ) {
//         const currentLoc = vehicle.currentLocation;
//         const nextStopLoc = vehicle.currentStop.location.coordinates;

//         const distance = calculateDistance(
//           currentLoc.latitude,
//           currentLoc.longitude,
//           nextStopLoc.latitude,
//           nextStopLoc.longitude
//         );

//         if (distance > 5) {
//           alerts.routeDeviation.push({
//             vehicleId: vehicle.vehicleId,
//             vehicleNumber: vehicle.vehicleNumber,
//             driverName: vehicle.driverName,
//             tripId: vehicle.tripId,
//             source: vehicle.source,
//             deviation: distance.toFixed(2),
//             currentLocation: currentLoc,
//             nextStop: vehicle.currentStop.customer?.name || 'Next stop',
//           });

//           await notifyRouteDeviation(db, vehicle, distance);
//         }
//       }

//       // ── CHECK 3: Speed alert (>80 km/h) ──────────────────────────────────
//       if (
//         vehicle.currentLocation.speed &&
//         vehicle.currentLocation.speed > 80
//       ) {
//         alerts.speeding.push({
//           vehicleId: vehicle.vehicleId,
//           vehicleNumber: vehicle.vehicleNumber,
//           driverName: vehicle.driverName,
//           tripId: vehicle.tripId,
//           source: vehicle.source,
//           speed: vehicle.currentLocation.speed,
//           location: {
//             latitude: vehicle.currentLocation.latitude,
//             longitude: vehicle.currentLocation.longitude,
//           },
//         });

//         await notifySpeedAlert(db, vehicle, vehicle.currentLocation.speed);
//       }
//     } catch (alertError) {
//       console.error(
//         `⚠️ Error checking alerts for vehicle ${vehicle.vehicleId}:`,
//         alertError.message
//       );
//     }
//   }

//   return alerts;
// }

// // ============================================================================
// // FUNCTION: fetchVehicleDetails — checks all 3 collections in order
// // ============================================================================
// async function fetchVehicleDetails(db, vehicleId, date) {
//   try {
//     const dayStart = new Date(`${date}T00:00:00.000Z`);
//     const dayEnd = new Date(`${date}T23:59:59.999Z`);

//     let vehicleObjectId;
//     try {
//       vehicleObjectId = new ObjectId(vehicleId);
//     } catch (e) {
//       return null;
//     }

//     const activeStatuses = {
//       $in: ['assigned', 'started', 'in_progress', 'completed'],
//     };

//     // ── Try roster-assigned-trips ─────────────────────────────────────────
//     let trip = await db.collection('roster-assigned-trips').findOne({
//       vehicleId: vehicleObjectId,
//       scheduledDate: date,
//       status: activeStatuses,
//     });

//     if (trip) {
//       const normalised = normaliseRosterTrip(trip);
//       normalised.actualDistance = trip.actualDistance || null;
//       normalised.actualDuration = trip.actualDuration || null;
//       normalised.startOdometer = trip.startOdometer || null;
//       normalised.endOdometer = trip.endOdometer || null;
//       normalised.actualStartTime = trip.actualStartTime || null;
//       normalised.actualEndTime = trip.actualEndTime || null;
//       normalised.createdAt = trip.createdAt;
//       normalised.updatedAt = trip.updatedAt;
//       return normalised;
//     }

//     // ── Try trips (manual) ───────────────────────────────────────────────
//     trip = await db.collection('trips').findOne({
//       vehicleId: vehicleObjectId,
//       scheduledPickupTime: { $gte: dayStart, $lte: dayEnd },
//       status: activeStatuses,
//     });

//     if (trip) {
//       const normalised = normaliseManualTrip(trip);
//       normalised.actualDistance = trip.actualDistance || null;
//       normalised.actualDuration = trip.actualDuration || null;
//       normalised.startOdometer = trip.startOdometer || null;
//       normalised.endOdometer = trip.endOdometer || null;
//       normalised.actualStartTime = trip.actualStartTime || null;
//       normalised.actualEndTime = trip.actualEndTime || null;
//       normalised.createdAt = trip.createdAt;
//       normalised.updatedAt = trip.updatedAt;
//       return normalised;
//     }

//     // ── Try client_created_trips ─────────────────────────────────────────
//     trip = await db.collection('client_created_trips').findOne({
//       vehicleId: vehicleObjectId,
//       scheduledPickupTime: { $gte: dayStart, $lte: dayEnd },
//       status: activeStatuses,
//     });

//     if (trip) {
//       const normalised = normaliseClientTrip(trip);
//       normalised.actualDistance = trip.actualDistance || null;
//       normalised.actualDuration = trip.actualDuration || null;
//       normalised.startOdometer = trip.startOdometer || null;
//       normalised.endOdometer = trip.endOdometer || null;
//       normalised.actualStartTime = trip.actualStartTime || null;
//       normalised.actualEndTime = trip.actualEndTime || null;
//       normalised.createdAt = trip.createdAt;
//       normalised.updatedAt = trip.updatedAt;
//       return normalised;
//     }

//     return null;
//   } catch (error) {
//     console.error('❌ Error in fetchVehicleDetails:', error);
//     throw error;
//   }
// }

// // ============================================================================
// // FUNCTION: fetchLocationHistory — archive first, then all 3 collections
// // ============================================================================
// async function fetchLocationHistory(db, vehicleId, date, time) {
//   try {
//     const dayStart = new Date(`${date}T00:00:00.000Z`);
//     const dayEnd = new Date(`${date}T23:59:59.999Z`);

//     let vehicleObjectId;
//     try {
//       vehicleObjectId = new ObjectId(vehicleId);
//     } catch (e) {
//       return { vehicleId, date, locations: [] };
//     }

//     // ── STEP 1: Try 6-day archive collection first ────────────────────────
//     const archive = await db.collection('vehicle_location_archive').findOne({
//       vehicleId: vehicleObjectId,
//       date: date,
//     });

//     if (archive && archive.locations && archive.locations.length > 0) {
//       console.log(`📦 Found ${archive.locations.length} archived locations`);
//       const filtered = filterByTime(archive.locations, time);
//       return { vehicleId, date, locations: filtered };
//     }

//     // ── STEP 2: Fallback — roster-assigned-trips ──────────────────────────
//     let trip = await db.collection('roster-assigned-trips').findOne(
//       { vehicleId: vehicleObjectId, scheduledDate: date },
//       { projection: { locationHistory: 1 } }
//     );

//     if (trip && trip.locationHistory && trip.locationHistory.length > 0) {
//       console.log(
//         `📦 Found ${trip.locationHistory.length} locations in roster trip`
//       );
//       return { vehicleId, date, locations: filterByTime(trip.locationHistory, time) };
//     }

//     // ── STEP 3: Fallback — trips (manual) ────────────────────────────────
//     trip = await db.collection('trips').findOne(
//       {
//         vehicleId: vehicleObjectId,
//         scheduledPickupTime: { $gte: dayStart, $lte: dayEnd },
//       },
//       { projection: { locationHistory: 1 } }
//     );

//     if (trip && trip.locationHistory && trip.locationHistory.length > 0) {
//       console.log(
//         `📦 Found ${trip.locationHistory.length} locations in manual trip`
//       );
//       return { vehicleId, date, locations: filterByTime(trip.locationHistory, time) };
//     }

//     // ── STEP 4: Fallback — client_created_trips ───────────────────────────
//     trip = await db.collection('client_created_trips').findOne(
//       {
//         vehicleId: vehicleObjectId,
//         scheduledPickupTime: { $gte: dayStart, $lte: dayEnd },
//       },
//       { projection: { locationHistory: 1 } }
//     );

//     if (trip && trip.locationHistory && trip.locationHistory.length > 0) {
//       console.log(
//         `📦 Found ${trip.locationHistory.length} locations in client trip`
//       );
//       return { vehicleId, date, locations: filterByTime(trip.locationHistory, time) };
//     }

//     console.log('⚠️ No location history found in any collection');
//     return { vehicleId, date, locations: [] };
//   } catch (error) {
//     console.error('❌ Error in fetchLocationHistory:', error);
//     throw error;
//   }
// }

// // ============================================================================
// // FUNCTION: getFleetStatistics — counts across all 3 collections
// // ============================================================================
// async function getFleetStatistics(db, date) {
//   try {
//     const dayStart = new Date(`${date}T00:00:00.000Z`);
//     const dayEnd = new Date(`${date}T23:59:59.999Z`);
//     const now = new Date();

//     const [rosterTrips, manualTrips, clientTrips] = await Promise.all([
//       db
//         .collection('roster-assigned-trips')
//         .find({ scheduledDate: date })
//         .toArray(),
//       db
//         .collection('trips')
//         .find({ scheduledPickupTime: { $gte: dayStart, $lte: dayEnd } })
//         .toArray(),
//       db
//         .collection('client_created_trips')
//         .find({ scheduledPickupTime: { $gte: dayStart, $lte: dayEnd } })
//         .toArray(),
//     ]);

//     const allTrips = [...rosterTrips, ...manualTrips, ...clientTrips];

//     const stats = {
//       total: allTrips.length,
//       active: 0,
//       idle: 0,
//       completed: 0,
//       offline: 0,
//       totalPassengers: 0,
//       totalDistance: 0,
//       averageSpeed: 0,
//       bySource: {
//         roster: rosterTrips.length,
//         manual: manualTrips.length,
//         client: clientTrips.length,
//       },
//     };

//     let totalSpeed = 0;
//     let speedCount = 0;

//     for (const trip of allTrips) {
//       if (trip.status === 'started' || trip.status === 'in_progress') {
//         stats.active++;
//       } else if (trip.status === 'completed') {
//         stats.completed++;
//       }

//       if (trip.currentLocation && trip.currentLocation.timestamp) {
//         const lastUpdate = new Date(trip.currentLocation.timestamp);
//         const minutesSinceUpdate = (now - lastUpdate) / 1000 / 60;

//         if (minutesSinceUpdate > 10) stats.idle++;
//         if (minutesSinceUpdate > 5 && trip.status !== 'completed') {
//           stats.offline++;
//         }

//         if (trip.currentLocation.speed) {
//           totalSpeed += trip.currentLocation.speed;
//           speedCount++;
//         }
//       }

//       // Passenger count
//       if (trip.stops) {
//         stats.totalPassengers += trip.stops.filter(
//           (s) => s.type === 'pickup'
//         ).length;
//       } else if (
//         trip.customerName ||
//         trip.customer?.name ||
//         trip.clientName
//       ) {
//         stats.totalPassengers += 1;
//       }

//       stats.totalDistance +=
//         trip.totalDistance || trip.distance || 0;
//     }

//     if (speedCount > 0) {
//       stats.averageSpeed = Math.round(totalSpeed / speedCount);
//     }

//     return stats;
//   } catch (error) {
//     console.error('❌ Error in getFleetStatistics:', error);
//     throw error;
//   }
// }

// // ============================================================================
// // NOTIFICATION FUNCTIONS — all unchanged from original
// // ============================================================================

// async function getActiveAdmins(db) {
//   try {
//     return await db
//       .collection('employee_admins')
//       .find({ status: 'active' })
//       .toArray();
//   } catch (error) {
//     console.error('❌ Error fetching admins:', error);
//     return [];
//   }
// }

// async function notifyVehicleOffline(db, vehicle, duration) {
//   try {
//     const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);

//     const recentNotification = await db.collection('notifications').findOne({
//       type: 'vehicle_offline',
//       'data.vehicleId': vehicle.vehicleId,
//       createdAt: { $gte: oneHourAgo },
//     });

//     if (recentNotification) {
//       console.log(
//         `⏭️  Skipping duplicate offline notification for ${vehicle.vehicleNumber}`
//       );
//       return;
//     }

//     const admins = await getActiveAdmins(db);
//     const title = '🚨 Vehicle Offline';
//     const body = `Vehicle ${vehicle.vehicleNumber} has been offline for ${duration}`;

//     for (const admin of admins) {
//       try {
//         await db.collection('notifications').insertOne({
//           userEmail: admin.email,
//           userRole: 'admin',
//           type: 'vehicle_offline',
//           title,
//           body,
//           message: `Driver ${vehicle.driverName} (${vehicle.driverPhone}) - Vehicle ${vehicle.vehicleNumber} has not sent GPS updates for ${duration}. Last known location may be outdated.`,
//           data: {
//             vehicleId: vehicle.vehicleId,
//             vehicleNumber: vehicle.vehicleNumber,
//             driverName: vehicle.driverName,
//             driverPhone: vehicle.driverPhone,
//             tripId: vehicle.tripId,
//             source: vehicle.source,
//             offlineDuration: duration,
//           },
//           priority: 'urgent',
//           category: 'fleet_alert',
//           isRead: false,
//           createdAt: new Date(),
//           updatedAt: new Date(),
//           expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
//         });

//         const devices = await db
//           .collection('user_devices')
//           .find({ userEmail: admin.email, isActive: true })
//           .toArray();

//         for (const device of devices) {
//           try {
//             await notificationService.send({
//               deviceToken: device.deviceToken,
//               deviceType: device.deviceType || 'android',
//               title,
//               body,
//               data: {
//                 type: 'vehicle_offline',
//                 vehicleId: vehicle.vehicleId,
//                 vehicleNumber: vehicle.vehicleNumber,
//                 tripId: vehicle.tripId,
//               },
//               priority: 'high',
//             });
//           } catch (fcmError) {
//             // Ignore FCM errors silently
//           }
//         }
//       } catch (adminError) {
//         console.error(
//           `⚠️ Failed to notify admin ${admin.email}:`,
//           adminError.message
//         );
//       }
//     }

//     console.log(`📧 Offline alert sent for ${vehicle.vehicleNumber}`);
//   } catch (error) {
//     console.error('❌ Error in notifyVehicleOffline:', error);
//   }
// }

// async function notifyRouteDeviation(db, vehicle, deviation) {
//   try {
//     const thirtyMinutesAgo = new Date(Date.now() - 30 * 60 * 1000);

//     const recentNotification = await db.collection('notifications').findOne({
//       type: 'route_deviation',
//       'data.vehicleId': vehicle.vehicleId,
//       createdAt: { $gte: thirtyMinutesAgo },
//     });

//     if (recentNotification) return;

//     const admins = await getActiveAdmins(db);
//     const title = '⚠️ Route Deviation Alert';
//     const body = `Vehicle ${vehicle.vehicleNumber} is ${deviation.toFixed(1)}km off route`;

//     for (const admin of admins) {
//       try {
//         await db.collection('notifications').insertOne({
//           userEmail: admin.email,
//           userRole: 'admin',
//           type: 'route_deviation',
//           title,
//           body,
//           message: `Driver ${vehicle.driverName} driving ${vehicle.vehicleNumber} is currently ${deviation.toFixed(1)}km away from the next scheduled stop. Please check if assistance is needed.`,
//           data: {
//             vehicleId: vehicle.vehicleId,
//             vehicleNumber: vehicle.vehicleNumber,
//             driverName: vehicle.driverName,
//             tripId: vehicle.tripId,
//             source: vehicle.source,
//             deviation: deviation.toFixed(2),
//             currentLocation: vehicle.currentLocation,
//           },
//           priority: 'high',
//           category: 'fleet_alert',
//           isRead: false,
//           createdAt: new Date(),
//           updatedAt: new Date(),
//           expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
//         });
//       } catch (adminError) {
//         console.error(
//           `⚠️ Failed to notify admin ${admin.email}:`,
//           adminError.message
//         );
//       }
//     }

//     console.log(`📧 Route deviation alert sent for ${vehicle.vehicleNumber}`);
//   } catch (error) {
//     console.error('❌ Error in notifyRouteDeviation:', error);
//   }
// }

// async function notifySpeedAlert(db, vehicle, speed) {
//   try {
//     const fifteenMinutesAgo = new Date(Date.now() - 15 * 60 * 1000);

//     const recentNotification = await db.collection('notifications').findOne({
//       type: 'speed_alert',
//       'data.vehicleId': vehicle.vehicleId,
//       createdAt: { $gte: fifteenMinutesAgo },
//     });

//     if (recentNotification) return;

//     const admins = await getActiveAdmins(db);
//     const title = '⚡ Speed Limit Exceeded';
//     const body = `Vehicle ${vehicle.vehicleNumber} traveling at ${speed} km/h`;

//     for (const admin of admins) {
//       try {
//         await db.collection('notifications').insertOne({
//           userEmail: admin.email,
//           userRole: 'admin',
//           type: 'speed_alert',
//           title,
//           body,
//           message: `Driver ${vehicle.driverName} is driving ${vehicle.vehicleNumber} at ${speed} km/h, exceeding the recommended speed limit of 80 km/h.`,
//           data: {
//             vehicleId: vehicle.vehicleId,
//             vehicleNumber: vehicle.vehicleNumber,
//             driverName: vehicle.driverName,
//             tripId: vehicle.tripId,
//             source: vehicle.source,
//             speed,
//             speedLimit: 80,
//             location: {
//               latitude: vehicle.currentLocation.latitude,
//               longitude: vehicle.currentLocation.longitude,
//             },
//           },
//           priority: 'high',
//           category: 'fleet_alert',
//           isRead: false,
//           createdAt: new Date(),
//           updatedAt: new Date(),
//           expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
//         });
//       } catch (adminError) {
//         console.error(
//           `⚠️ Failed to notify admin ${admin.email}:`,
//           adminError.message
//         );
//       }
//     }

//     console.log(`📧 Speed alert sent for ${vehicle.vehicleNumber}`);
//   } catch (error) {
//     console.error('❌ Error in notifySpeedAlert:', error);
//   }
// }

// // ============================================================================
// // HELPERS
// // ============================================================================

// function filterByTime(locations, time) {
//   if (!time) return locations;
//   const targetMinutes = parseTimeToMinutes(time);
//   return locations.filter((loc) => {
//     const locTime = new Date(loc.timestamp);
//     const locMinutes = locTime.getUTCHours() * 60 + locTime.getUTCMinutes();
//     return Math.abs(locMinutes - targetMinutes) <= 5;
//   });
// }

// function parseTimeToMinutes(timeStr) {
//   if (!timeStr) return 0;
//   if (timeStr.includes(':')) {
//     const [hours, minutes] = timeStr.split(':').map(Number);
//     return hours * 60 + minutes;
//   }
//   const hours = parseInt(timeStr);
//   return !isNaN(hours) ? hours * 60 : 0;
// }

// // ============================================================================
// // EXPORTS
// // ============================================================================
// module.exports = {
//   fetchLiveVehicles,
//   checkVehicleAlerts,
//   fetchVehicleDetails,
//   fetchLocationHistory,
//   getFleetStatistics,
// };



// services/admin_live_tracking_service.js
// ============================================================================
// ADMIN LIVE TRACKING SERVICE
// Fetches ONLY genuinely active trips from ALL 3 collections:
//   1. roster-assigned-trips  — scheduledDate must be exactly today (string)
//   2. trips                  — scheduledPickupTime must fall within today's UTC window
//   3. client_created_trips   — scheduledPickupTime must fall within today's UTC window
//
// FIX: Stale/stuck roster trips from previous dates are excluded because
//      their scheduledDate string ("2026-02-17") won't match today ("2026-02-26").
//      The trips and client_created_trips use ISODate so we bound them to
//      dayStart..dayEnd of the requested date strictly.
// ============================================================================

const { ObjectId } = require('mongodb');
const notificationService = require('./fcm_service');

// ============================================================================
// UTILITY
// ============================================================================
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function toRad(deg) { return deg * (Math.PI / 180); }

function filterByTime(locations, time) {
  if (!time) return locations;
  const target = parseTimeToMinutes(time);
  return locations.filter(loc => {
    const t = new Date(loc.timestamp);
    const mins = t.getUTCHours() * 60 + t.getUTCMinutes();
    return Math.abs(mins - target) <= 5;
  });
}

function parseTimeToMinutes(timeStr) {
  if (!timeStr) return 0;
  if (timeStr.includes(':')) {
    const [h, m] = timeStr.split(':').map(Number);
    return h * 60 + m;
  }
  const h = parseInt(timeStr);
  return !isNaN(h) ? h * 60 : 0;
}

// ============================================================================
// NORMALISERS
// ============================================================================

function normaliseRosterTrip(trip) {
  const now = new Date();
  let isIdle = false;
  if (trip.currentLocation?.timestamp) {
    isIdle = (now - new Date(trip.currentLocation.timestamp)) / 60000 > 10;
  }

  const currentStopIndex = trip.currentStopIndex || 0;
  const stops = (trip.stops || []).map(stop => ({
    ...stop,
    location: {
      address: stop.location?.address || '',
      coordinates: {
        latitude:  stop.location?.coordinates?.latitude  || null,
        longitude: stop.location?.coordinates?.longitude || null,
      },
    },
  }));

  const completedStops = stops.filter(s => s.status === 'completed').length;
  const totalStops = stops.length;

  return {
    tripId:        trip._id.toString(),
    tripGroupId:   trip.tripGroupId || null,
    tripNumber:    trip.tripNumber  || 'N/A',
    source:        'roster',
    tripType:      trip.tripType    || 'pickup',

    vehicleId:     trip.vehicleId?.toString() || '',
    vehicleNumber: trip.vehicleNumber          || 'Unknown',

    driverId:      trip.driverId?.toString()   || '',
    driverName:    trip.driverName             || 'Unknown',
    driverPhone:   trip.driverPhone            || '',
    driverEmail:   trip.driverEmail            || '',

    status:        trip.status,
    isIdle,
    scheduledDate: trip.scheduledDate || null,

    currentLocation: trip.currentLocation  || null,
    locationHistory: (trip.locationHistory || []).slice(-50),

    stops,
    totalStops,
    completedStops,
    currentStopIndex,
    currentStop: stops[currentStopIndex] || null,
    progress:    totalStops > 0 ? (completedStops / totalStops) * 100 : 0,

    totalDistance:     trip.totalDistance     || 0,
    estimatedDuration: trip.estimatedDuration || 0,
    customerName:  null,
    customerPhone: null,
    customerEmail: null,

    lastUpdated: trip.currentLocation?.timestamp || trip.updatedAt,
  };
}

function normaliseManualTrip(trip) {
  const now = new Date();
  let isIdle = false;
  if (trip.currentLocation?.timestamp) {
    isIdle = (now - new Date(trip.currentLocation.timestamp)) / 60000 > 10;
  }

  const isActive = trip.status === 'started' || trip.status === 'in_progress';
  const stops = [];

  if (trip.pickupLocation) {
    stops.push({
      stopId: 'pickup', sequence: 1, type: 'pickup',
      status: isActive ? 'arrived' : 'pending',
      customer: {
        name:  trip.customerName  || trip.customer?.name  || 'Customer',
        email: trip.customerEmail || trip.customer?.email || '',
        phone: trip.customerPhone || trip.customer?.phone || '',
      },
      location: {
        address: trip.pickupLocation.address || '',
        coordinates: {
          latitude:  trip.pickupLocation.latitude  || trip.pickupLocation.coordinates?.coordinates?.[1] || null,
          longitude: trip.pickupLocation.longitude || trip.pickupLocation.coordinates?.coordinates?.[0] || null,
        },
      },
      estimatedTime: trip.scheduledPickupTime || null,
    });
  }

  if (trip.dropLocation) {
    stops.push({
      stopId: 'drop', sequence: 2, type: 'drop', status: 'pending',
      customer: {
        name:  trip.customerName  || trip.customer?.name  || 'Customer',
        email: trip.customerEmail || trip.customer?.email || '',
        phone: trip.customerPhone || trip.customer?.phone || '',
      },
      location: {
        address: trip.dropLocation.address || '',
        coordinates: {
          latitude:  trip.dropLocation.latitude  || trip.dropLocation.coordinates?.coordinates?.[1] || null,
          longitude: trip.dropLocation.longitude || trip.dropLocation.coordinates?.coordinates?.[0] || null,
        },
      },
      estimatedTime: trip.dropTime || trip.estimatedEndTime || null,
    });
  }

  return {
    tripId:      trip._id.toString(),
    tripGroupId: null,
    tripNumber:  trip.tripNumber || 'N/A',
    source:      'manual',
    tripType:    'manual',

    vehicleId:     trip.vehicleId?.toString() || '',
    vehicleNumber: trip.vehicleNumber          || 'Unknown',

    driverId:    trip.driverId?.toString() || '',
    driverName:  trip.driverName           || 'Unknown',
    driverPhone: trip.driverPhone          || '',
    driverEmail: trip.driverEmail          || '',

    status: trip.status,
    isIdle,
    scheduledDate: trip.scheduledPickupTime
      ? new Date(trip.scheduledPickupTime).toISOString().split('T')[0]
      : null,

    currentLocation: trip.currentLocation  || null,
    locationHistory: (trip.locationHistory || []).slice(-50),

    stops,
    totalStops:      stops.length,
    completedStops:  0,
    currentStopIndex: 0,
    currentStop:     stops[0] || null,
    progress:        trip.status === 'completed' ? 100 : 50,

    totalDistance:     trip.distance          || 0,
    estimatedDuration: trip.estimatedDuration || 0,

    customerName:  trip.customerName  || trip.customer?.name  || 'N/A',
    customerPhone: trip.customerPhone || trip.customer?.phone || '',
    customerEmail: trip.customerEmail || trip.customer?.email || '',

    pickupAddress: trip.pickupLocation?.address || '',
    dropAddress:   trip.dropLocation?.address   || '',

    lastUpdated: trip.currentLocation?.timestamp || trip.updatedAt,
  };
}

function normaliseClientTrip(trip) {
  const now = new Date();
  let isIdle = false;
  if (trip.currentLocation?.timestamp) {
    isIdle = (now - new Date(trip.currentLocation.timestamp)) / 60000 > 10;
  }

  const isActive = trip.status === 'started' || trip.status === 'in_progress';
  const stops = [];

  if (trip.pickupLocation) {
    stops.push({
      stopId: 'pickup', sequence: 1, type: 'pickup',
      status: isActive ? 'arrived' : 'pending',
      customer: {
        name:  trip.clientName  || 'Client',
        email: trip.clientEmail || '',
        phone: trip.clientPhone || '',
      },
      location: {
        address: trip.pickupLocation.address || '',
        coordinates: {
          latitude:  trip.pickupLocation.latitude  || trip.pickupLocation.coordinates?.coordinates?.[1] || null,
          longitude: trip.pickupLocation.longitude || trip.pickupLocation.coordinates?.coordinates?.[0] || null,
        },
      },
      estimatedTime: trip.scheduledPickupTime || null,
    });
  }

  if (trip.dropLocation) {
    stops.push({
      stopId: 'drop', sequence: 2, type: 'drop', status: 'pending',
      customer: {
        name:  trip.clientName  || 'Client',
        email: trip.clientEmail || '',
        phone: trip.clientPhone || '',
      },
      location: {
        address: trip.dropLocation.address || '',
        coordinates: {
          latitude:  trip.dropLocation.latitude  || trip.dropLocation.coordinates?.coordinates?.[1] || null,
          longitude: trip.dropLocation.longitude || trip.dropLocation.coordinates?.coordinates?.[0] || null,
        },
      },
      estimatedTime: trip.estimatedEndTime || trip.scheduledDropTime || null,
    });
  }

  return {
    tripId:      trip._id.toString(),
    tripGroupId: null,
    tripNumber:  trip.tripNumber || 'N/A',
    source:      'client',
    tripType:    'client_request',

    vehicleId:     trip.vehicleId?.toString() || '',
    vehicleNumber: trip.vehicleNumber          || 'Unknown',

    driverId:    trip.driverId?.toString() || '',
    driverName:  trip.driverName           || 'Unknown',
    driverPhone: trip.driverPhone          || '',
    driverEmail: trip.driverEmail          || '',

    status: trip.status,
    isIdle,
    scheduledDate: trip.scheduledPickupTime
      ? new Date(trip.scheduledPickupTime).toISOString().split('T')[0]
      : null,

    currentLocation: trip.currentLocation  || null,
    locationHistory: (trip.locationHistory || []).slice(-50),

    stops,
    totalStops:       stops.length,
    completedStops:   0,
    currentStopIndex: 0,
    currentStop:      stops[0] || null,
    progress:         trip.status === 'completed' ? 100 : 50,

    totalDistance:     trip.distance          || 0,
    estimatedDuration: trip.estimatedDuration || 0,

    // Map client→customer for uniform UI field access
    customerName:  trip.clientName  || 'N/A',
    customerPhone: trip.clientPhone || '',
    customerEmail: trip.clientEmail || '',

    pickupAddress: trip.pickupLocation?.address || '',
    dropAddress:   trip.dropLocation?.address   || '',

    lastUpdated: trip.currentLocation?.timestamp || trip.updatedAt,
  };
}

// ============================================================================
// fetchLiveVehicles — NEW APPROACH: Fetch ALL vehicles, then join with trips
// ============================================================================
async function fetchLiveVehicles(db, date, statusFilter, companyFilter) {
  try {
    console.log(`\n🔍 fetchLiveVehicles — date=${date} statusFilter=${statusFilter || 'all'}`);

    const now = new Date();
    const dayStart = new Date(`${date}T00:00:00.000Z`);
    const dayEnd   = new Date(`${date}T23:59:59.999Z`);

    // ── STEP 1: Fetch ALL active vehicles ──────────────────────────────────
    const vehicleQuery = { status: 'active' };
    if (companyFilter && companyFilter !== 'all') {
      vehicleQuery.companyId = companyFilter;
    }

    const allVehicles = await db.collection('vehicles').find(vehicleQuery).toArray();
    console.log(`  📦 Found ${allVehicles.length} active vehicles`);

    // ── STEP 2: Fetch ALL trips for today (no status filter in query) ──────
    const [rosterTrips, manualTrips, clientTrips] = await Promise.all([
      db.collection('roster-assigned-trips').find({ scheduledDate: date }).toArray(),
      db.collection('trips').find({
        $or: [
          { scheduledPickupTime: { $gte: dayStart, $lte: dayEnd } },
          { status: { $in: ['started', 'in_progress'] } }
        ]
      }).toArray(),
      db.collection('client_created_trips').find({
        $or: [
          { scheduledPickupTime: { $gte: dayStart, $lte: dayEnd } },
          { status: { $in: ['started', 'in_progress'] } }
        ]
      }).toArray(),
    ]);

    console.log(`  📦 roster-assigned-trips: ${rosterTrips.length}`);
    console.log(`  📦 trips (manual): ${manualTrips.length}`);
    console.log(`  📦 client_created_trips: ${clientTrips.length}`);

    // ── STEP 3: Build trip lookup map (by vehicleId AND vehicleNumber) ─────
    const tripMap = new Map();
    
    for (const trip of [...rosterTrips, ...manualTrips, ...clientTrips]) {
      const vidStr = trip.vehicleId?.toString();
      const vnum = trip.vehicleNumber;
      
      if (vidStr) tripMap.set(`id:${vidStr}`, trip);
      if (vnum) tripMap.set(`num:${vnum}`, trip);
    }

    // ── STEP 4: Join vehicles with trips and derive status ─────────────────
    const vehicleList = [];
    const summary = { total: 0, active: 0, idle: 0, assigned: 0, unassigned: 0, completed: 0 };

    for (const vehicle of allVehicles) {
      const vidStr = vehicle._id.toString();
      const vnum = vehicle.registrationNumber;

      // Try to find trip by ObjectId first, then by registration number
      let trip = tripMap.get(`id:${vidStr}`) || tripMap.get(`num:${vnum}`);

      let derivedStatus = 'unassigned';
      let gpsAgeMinutes = null;
      let currentLocation = null;

      if (trip) {
        // Check GPS staleness
        const tripGPS = trip.currentLocation?.timestamp;
        const vehicleGPS = vehicle.currentLocation?.timestamp;
        const latestGPS = tripGPS && vehicleGPS 
          ? (new Date(tripGPS) > new Date(vehicleGPS) ? tripGPS : vehicleGPS)
          : (tripGPS || vehicleGPS);

        if (latestGPS) {
          gpsAgeMinutes = Math.floor((now - new Date(latestGPS)) / 60000);
          currentLocation = trip.currentLocation || vehicle.currentLocation;
        }

        // Derive status based on trip status and GPS age
        if (trip.status === 'completed') {
          derivedStatus = 'completed';
        } else if (trip.status === 'assigned') {
          derivedStatus = 'assigned';
        } else if (trip.status === 'started' || trip.status === 'in_progress') {
          if (gpsAgeMinutes !== null && gpsAgeMinutes <= 10) {
            derivedStatus = 'active';
          } else {
            derivedStatus = 'idle';
          }
        }
      }

      // Build vehicle object
      const vehicleData = {
        vehicleId: vidStr,
        vehicleNumber: vnum || 'Unknown',
        vehicleNumber: vnum || 'Unknown',
        registrationNumber: vnum || 'Unknown',
        make: vehicle.make || '',
        model: vehicle.model || '',
        type: vehicle.type || '',
        driverName: trip?.driverName || vehicle.driverName || '',
        driverId: trip?.driverId?.toString() || vehicle.driverId?.toString() || '',
        driverPhone: trip?.driverPhone || vehicle.driverPhone || '',
        derivedStatus,
        tripId: trip?._id?.toString() || null,
        tripNumber: trip?.tripNumber || null,
        tripType: trip?.tripType || null,
        tripStatus: trip?.status || null,
        currentLocation,
        gpsAgeMinutes,
        scheduledDate: trip?.scheduledDate || null,
        startTime: trip?.scheduledPickupTime || null,
        endTime: trip?.estimatedEndTime || null,
        companyId: vehicle.companyId || null,
        companyName: vehicle.companyName || null,
      };

      vehicleList.push(vehicleData);
      summary.total++;
      summary[derivedStatus]++;
    }

    // ── STEP 5: Apply status filter IN MEMORY ──────────────────────────────
    let filteredVehicles = vehicleList;
    if (statusFilter && statusFilter !== 'all') {
      filteredVehicles = vehicleList.filter(v => v.derivedStatus === statusFilter);
    }

    console.log(`  ✅ Total vehicles: ${summary.total}, Filtered: ${filteredVehicles.length}`);
    console.log(`  📊 Summary: active=${summary.active}, idle=${summary.idle}, assigned=${summary.assigned}, unassigned=${summary.unassigned}, completed=${summary.completed}`);

    return { vehicles: filteredVehicles, summary };

  } catch (err) {
    console.error('❌ fetchLiveVehicles:', err);
    throw err;
  }
}

// ============================================================================
// checkVehicleAlerts
// ============================================================================
async function checkVehicleAlerts(db, vehicles) {
  const alerts = { offline: [], routeDeviation: [], speeding: [] };
  const now            = new Date();
  const fiveMinutesAgo = new Date(now - 5 * 60 * 1000);

  // ✅ Only vehicles actively on a trip need GPS tracking
  // assigned/accepted/confirmed = trip not started yet, driver not moving → NO alerts
  // started/in_progress = driver actively driving → YES alerts
  const GPS_REQUIRED_STATUSES = ['started', 'in_progress'];
  
  // ✅ We still want to show these in alerts panel but NOT send notifications
  const HAS_TRIP_STATUSES = ['assigned', 'accepted', 'confirmed', 'started', 'in_progress'];

  for (const vehicle of vehicles) {
    try {
      // Skip vehicles with no trip at all
      if (!vehicle.tripId) continue;
      if (!vehicle.tripStatus) continue;
      if (!HAS_TRIP_STATUSES.includes(vehicle.tripStatus)) continue;

      // ✅ OFFLINE: Only check vehicles whose trip has actually STARTED
      // A vehicle with status 'assigned' hasn't started yet — no GPS expected
      if (GPS_REQUIRED_STATUSES.includes(vehicle.tripStatus)) {
        if (!vehicle.currentLocation?.timestamp) {
          alerts.offline.push({
            vehicleId: vehicle.vehicleId,
            vehicleNumber: vehicle.vehicleNumber,
            driverName: vehicle.driverName,
            tripId: vehicle.tripId,
            source: vehicle.source,
            offlineSince: vehicle.lastUpdated || null,
            duration: 'Unknown',
          });
          await notifyVehicleOffline(db, vehicle, 'No GPS data');
        } else {
          const lastUpdate = new Date(vehicle.currentLocation.timestamp);
          if (lastUpdate < fiveMinutesAgo) {
            const mins = Math.floor((now - lastUpdate) / 60000);
            const duration = mins >= 60
              ? `${Math.floor(mins / 60)}h ${mins % 60}m`
              : `${mins} minutes`;
            alerts.offline.push({
              vehicleId: vehicle.vehicleId,
              vehicleNumber: vehicle.vehicleNumber,
              driverName: vehicle.driverName,
              tripId: vehicle.tripId,
              source: vehicle.source,
              offlineSince: lastUpdate,
              duration,
            });
            await notifyVehicleOffline(db, vehicle, duration);
          }
        }
      }

      if (!vehicle.currentLocation) continue;

      // ✅ ROUTE DEVIATION: Only started/in_progress
      if (
        GPS_REQUIRED_STATUSES.includes(vehicle.tripStatus) &&
        vehicle.currentStop?.location?.coordinates?.latitude
      ) {
        const dist = calculateDistance(
          vehicle.currentLocation.latitude, vehicle.currentLocation.longitude,
          vehicle.currentStop.location.coordinates.latitude,
          vehicle.currentStop.location.coordinates.longitude,
        );
        if (dist > 5) {
          alerts.routeDeviation.push({
            vehicleId: vehicle.vehicleId,
            vehicleNumber: vehicle.vehicleNumber,
            driverName: vehicle.driverName,
            tripId: vehicle.tripId,
            source: vehicle.source,
            deviation: dist.toFixed(2),
            currentLocation: vehicle.currentLocation,
            nextStop: vehicle.currentStop.customer?.name || 'Next stop',
          });
          await notifyRouteDeviation(db, vehicle, dist);
        }
      }

      // ✅ SPEEDING: Only started/in_progress
      if (
        GPS_REQUIRED_STATUSES.includes(vehicle.tripStatus) &&
        vehicle.currentLocation.speed > 80
      ) {
        alerts.speeding.push({
          vehicleId: vehicle.vehicleId,
          vehicleNumber: vehicle.vehicleNumber,
          driverName: vehicle.driverName,
          tripId: vehicle.tripId,
          source: vehicle.source,
          speed: vehicle.currentLocation.speed,
          location: {
            latitude: vehicle.currentLocation.latitude,
            longitude: vehicle.currentLocation.longitude,
          },
        });
        await notifySpeedAlert(db, vehicle, vehicle.currentLocation.speed);
      }

    } catch (e) {
      console.error(`⚠️ alert check for ${vehicle.vehicleId}:`, e.message);
    }
  }

  return alerts;
}

// ============================================================================
// fetchVehicleDetails — checks all 3 collections
// ============================================================================
async function fetchVehicleDetails(db, vehicleId, date) {
  try {
    const dayStart = new Date(`${date}T00:00:00.000Z`);
    const dayEnd   = new Date(`${date}T23:59:59.999Z`);
    let oid;
    try { oid = new ObjectId(vehicleId); } catch { return null; }

    const activeStatuses = { $in: ['assigned', 'started', 'in_progress', 'completed'] };

    const addExtra = (normalised, trip) => {
      normalised.actualDistance   = trip.actualDistance   || null;
      normalised.actualDuration   = trip.actualDuration   || null;
      normalised.startOdometer    = trip.startOdometer    || null;
      normalised.endOdometer      = trip.endOdometer      || null;
      normalised.actualStartTime  = trip.actualStartTime  || null;
      normalised.actualEndTime    = trip.actualEndTime    || null;
      normalised.createdAt        = trip.createdAt;
      normalised.updatedAt        = trip.updatedAt;
      return normalised;
    };

    let trip = await db.collection('roster-assigned-trips').findOne({
      vehicleId: oid, scheduledDate: date, status: activeStatuses,
    });
    if (trip) return addExtra(normaliseRosterTrip(trip), trip);

    trip = await db.collection('trips').findOne({
      vehicleId: oid, scheduledPickupTime: { $gte: dayStart, $lte: dayEnd }, status: activeStatuses,
    });
    if (trip) return addExtra(normaliseManualTrip(trip), trip);

    trip = await db.collection('client_created_trips').findOne({
      vehicleId: oid, scheduledPickupTime: { $gte: dayStart, $lte: dayEnd }, status: activeStatuses,
    });
    if (trip) return addExtra(normaliseClientTrip(trip), trip);

    return null;

  } catch (err) {
    console.error('❌ fetchVehicleDetails:', err);
    throw err;
  }
}

// ============================================================================
// fetchTripById — used by /live-track route to find any trip by its _id
// Searches all 3 collections
// ============================================================================
async function fetchTripById(db, tripId) {
  try {
    let oid;
    try { oid = new ObjectId(tripId); } catch { return null; }

    let trip = await db.collection('trips').findOne({ _id: oid });
    if (trip) return { ...normaliseManualTrip(trip), _raw: trip };

    trip = await db.collection('client_created_trips').findOne({ _id: oid });
    if (trip) return { ...normaliseClientTrip(trip), _raw: trip };

    trip = await db.collection('roster-assigned-trips').findOne({ _id: oid });
    if (trip) return { ...normaliseRosterTrip(trip), _raw: trip };

    return null;

  } catch (err) {
    console.error('❌ fetchTripById:', err);
    throw err;
  }
}

// ============================================================================
// fetchTripByGroupId — Search by tripGroupId (handles date suffix format)
// ============================================================================
async function fetchTripByGroupId(db, tripGroupId) {
  try {
    console.log(`🔍 Searching by tripGroupId: ${tripGroupId}`);

    // Search in all 3 collections by tripGroupId field
    let trip = await db.collection('trips').findOne({ tripGroupId: tripGroupId });
    if (trip) {
      console.log('✅ Found in trips collection');
      return { ...normaliseManualTrip(trip), _raw: trip };
    }

    trip = await db.collection('client_created_trips').findOne({ tripGroupId: tripGroupId });
    if (trip) {
      console.log('✅ Found in client_created_trips collection');
      return { ...normaliseClientTrip(trip), _raw: trip };
    }

    trip = await db.collection('roster-assigned-trips').findOne({ tripGroupId: tripGroupId });
    if (trip) {
      console.log('✅ Found in roster-assigned-trips collection');
      return { ...normaliseRosterTrip(trip), _raw: trip };
    }

    console.log('❌ Trip not found by tripGroupId');
    return null;

  } catch (err) {
    console.error('❌ fetchTripByGroupId:', err);
    throw err;
  }
}

// ============================================================================
// fetchLocationHistory — archive first, then all 3 collections
// ============================================================================
async function fetchLocationHistory(db, vehicleId, date, time) {
  try {
    const dayStart = new Date(`${date}T00:00:00.000Z`);
    const dayEnd   = new Date(`${date}T23:59:59.999Z`);
    let oid;
    try { oid = new ObjectId(vehicleId); } catch {
      return { vehicleId, date, locations: [] };
    }

    // Archive first
    const archive = await db.collection('vehicle_location_archive').findOne({
      vehicleId: oid, date,
    });
    if (archive?.locations?.length > 0) {
      console.log(`📦 archive: ${archive.locations.length} pts`);
      return { vehicleId, date, locations: filterByTime(archive.locations, time) };
    }

    // Roster fallback
    let trip = await db.collection('roster-assigned-trips').findOne(
      { vehicleId: oid, scheduledDate: date },
      { projection: { locationHistory: 1 } }
    );
    if (trip?.locationHistory?.length > 0) {
      return { vehicleId, date, locations: filterByTime(trip.locationHistory, time) };
    }

    // Manual fallback
    trip = await db.collection('trips').findOne(
      { vehicleId: oid, scheduledPickupTime: { $gte: dayStart, $lte: dayEnd } },
      { projection: { locationHistory: 1 } }
    );
    if (trip?.locationHistory?.length > 0) {
      return { vehicleId, date, locations: filterByTime(trip.locationHistory, time) };
    }

    // Client fallback
    trip = await db.collection('client_created_trips').findOne(
      { vehicleId: oid, scheduledPickupTime: { $gte: dayStart, $lte: dayEnd } },
      { projection: { locationHistory: 1 } }
    );
    if (trip?.locationHistory?.length > 0) {
      return { vehicleId, date, locations: filterByTime(trip.locationHistory, time) };
    }

    return { vehicleId, date, locations: [] };

  } catch (err) {
    console.error('❌ fetchLocationHistory:', err);
    throw err;
  }
}

// ============================================================================
// getFleetStatistics — all 3 collections
// ============================================================================
async function getFleetStatistics(db, date) {
  try {
    const dayStart = new Date(`${date}T00:00:00.000Z`);
    const dayEnd   = new Date(`${date}T23:59:59.999Z`);
    const now      = new Date();

    const [rosterTrips, manualTrips, clientTrips] = await Promise.all([
      db.collection('roster-assigned-trips').find({ scheduledDate: date }).toArray(),
      db.collection('trips').find({
        $or: [
          { scheduledPickupTime: { $gte: dayStart, $lte: dayEnd } },
          { status: { $in: ['started', 'in_progress'] } }
        ]
      }).toArray(),
      db.collection('client_created_trips').find({
        $or: [
          { scheduledPickupTime: { $gte: dayStart, $lte: dayEnd } },
          { status: { $in: ['started', 'in_progress'] } }
        ]
      }).toArray(),
    ]);

    const all = [...rosterTrips, ...manualTrips, ...clientTrips];
    const stats = {
      total: all.length, active: 0, idle: 0, completed: 0, offline: 0,
      totalPassengers: 0, totalDistance: 0, averageSpeed: 0,
      bySource: { roster: rosterTrips.length, manual: manualTrips.length, client: clientTrips.length },
    };

    let totalSpeed = 0, speedCount = 0;

    for (const t of all) {
      if (t.status === 'started' || t.status === 'in_progress') stats.active++;
      else if (t.status === 'completed') stats.completed++;

      if (t.currentLocation?.timestamp) {
        const mins = (now - new Date(t.currentLocation.timestamp)) / 60000;
        if (mins > 10) stats.idle++;
        if (mins > 5 && t.status !== 'completed') stats.offline++;
        if (t.currentLocation.speed) { totalSpeed += t.currentLocation.speed; speedCount++; }
      }

      if (t.stops) stats.totalPassengers += t.stops.filter(s => s.type === 'pickup').length;
      else if (t.customerName || t.clientName) stats.totalPassengers++;

      stats.totalDistance += t.totalDistance || t.distance || 0;
    }

    if (speedCount > 0) stats.averageSpeed = Math.round(totalSpeed / speedCount);
    return stats;

  } catch (err) {
    console.error('❌ getFleetStatistics:', err);
    throw err;
  }
}

// ============================================================================
// NOTIFICATION HELPERS
// ============================================================================
async function getActiveAdmins(db) {
  try {
    return await db.collection('employee_admins').find({ status: 'active' }).toArray();
  } catch { return []; }
}

async function notifyVehicleOffline(db, vehicle, duration) {
  try {
    const oneHourAgo = new Date(Date.now() - 3600000);
    const dup = await db.collection('notifications').findOne({
      type: 'vehicle_offline', 'data.vehicleId': vehicle.vehicleId,
      createdAt: { $gte: oneHourAgo },
    });
    if (dup) return;

    const admins = await getActiveAdmins(db);
    const title = '🚨 Vehicle Offline';
    const body  = `Vehicle ${vehicle.vehicleNumber} has been offline for ${duration}`;

    for (const admin of admins) {
      try {
        await db.collection('notifications').insertOne({
          userEmail: admin.email, userRole: 'admin', type: 'vehicle_offline',
          title, body,
          message: `Driver ${vehicle.driverName} (${vehicle.driverPhone}) — Vehicle ${vehicle.vehicleNumber} offline for ${duration}.`,
          data: { vehicleId: vehicle.vehicleId, vehicleNumber: vehicle.vehicleNumber,
                  driverName: vehicle.driverName, driverPhone: vehicle.driverPhone,
                  tripId: vehicle.tripId, source: vehicle.source, offlineDuration: duration },
          priority: 'urgent', category: 'fleet_alert', isRead: false,
          createdAt: new Date(), updatedAt: new Date(),
          expiresAt: new Date(Date.now() + 7 * 86400000),
        });

        const devices = await db.collection('user_devices')
          .find({ userEmail: admin.email, isActive: true }).toArray();

        for (const d of devices) {
          try {
            await notificationService.send({
              deviceToken: d.deviceToken, deviceType: d.deviceType || 'android',
              title, body,
              data: { type: 'vehicle_offline', vehicleId: vehicle.vehicleId,
                      vehicleNumber: vehicle.vehicleNumber, tripId: vehicle.tripId },
              priority: 'high',
            });
          } catch (_) {}
        }
      } catch (e) { console.error(`notifyVehicleOffline admin ${admin.email}:`, e.message); }
    }
    console.log(`📧 Offline alert — ${vehicle.vehicleNumber}`);
  } catch (e) { console.error('❌ notifyVehicleOffline:', e); }
}

async function notifyRouteDeviation(db, vehicle, deviation) {
  try {
    const ago = new Date(Date.now() - 30 * 60000);
    if (await db.collection('notifications').findOne({
      type: 'route_deviation', 'data.vehicleId': vehicle.vehicleId,
      createdAt: { $gte: ago },
    })) return;

    const admins = await getActiveAdmins(db);
    const title  = '⚠️ Route Deviation Alert';
    const body   = `Vehicle ${vehicle.vehicleNumber} is ${deviation.toFixed(1)}km off route`;

    for (const admin of admins) {
      try {
        await db.collection('notifications').insertOne({
          userEmail: admin.email, userRole: 'admin', type: 'route_deviation',
          title, body,
          message: `Driver ${vehicle.driverName} driving ${vehicle.vehicleNumber} is ${deviation.toFixed(1)}km from next stop.`,
          data: { vehicleId: vehicle.vehicleId, vehicleNumber: vehicle.vehicleNumber,
                  driverName: vehicle.driverName, tripId: vehicle.tripId,
                  source: vehicle.source, deviation: deviation.toFixed(2),
                  currentLocation: vehicle.currentLocation },
          priority: 'high', category: 'fleet_alert', isRead: false,
          createdAt: new Date(), updatedAt: new Date(),
          expiresAt: new Date(Date.now() + 7 * 86400000),
        });
      } catch (e) { console.error(`notifyRouteDeviation admin ${admin.email}:`, e.message); }
    }
    console.log(`📧 Route deviation — ${vehicle.vehicleNumber}`);
  } catch (e) { console.error('❌ notifyRouteDeviation:', e); }
}

async function notifySpeedAlert(db, vehicle, speed) {
  try {
    const ago = new Date(Date.now() - 15 * 60000);
    if (await db.collection('notifications').findOne({
      type: 'speed_alert', 'data.vehicleId': vehicle.vehicleId,
      createdAt: { $gte: ago },
    })) return;

    const admins = await getActiveAdmins(db);
    const title  = '⚡ Speed Limit Exceeded';
    const body   = `Vehicle ${vehicle.vehicleNumber} traveling at ${speed} km/h`;

    for (const admin of admins) {
      try {
        await db.collection('notifications').insertOne({
          userEmail: admin.email, userRole: 'admin', type: 'speed_alert',
          title, body,
          message: `Driver ${vehicle.driverName} driving ${vehicle.vehicleNumber} at ${speed} km/h (limit: 80 km/h).`,
          data: { vehicleId: vehicle.vehicleId, vehicleNumber: vehicle.vehicleNumber,
                  driverName: vehicle.driverName, tripId: vehicle.tripId,
                  source: vehicle.source, speed, speedLimit: 80,
                  location: { latitude: vehicle.currentLocation.latitude,
                              longitude: vehicle.currentLocation.longitude } },
          priority: 'high', category: 'fleet_alert', isRead: false,
          createdAt: new Date(), updatedAt: new Date(),
          expiresAt: new Date(Date.now() + 7 * 86400000),
        });
      } catch (e) { console.error(`notifySpeedAlert admin ${admin.email}:`, e.message); }
    }
    console.log(`📧 Speed alert — ${vehicle.vehicleNumber}`);
  } catch (e) { console.error('❌ notifySpeedAlert:', e); }
}

// ============================================================================
// EXPORTS
// ============================================================================
module.exports = {
  fetchLiveVehicles,
  checkVehicleAlerts,
  fetchVehicleDetails,
  fetchTripById,
  fetchTripByGroupId,
  fetchLocationHistory,
  getFleetStatistics,
};