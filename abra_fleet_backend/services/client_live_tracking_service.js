// services/client_live_tracking_service.js
// ============================================================================
// CLIENT LIVE TRACKING SERVICE - Business Logic Layer
// ============================================================================
// Domain-based filtering:
//   - Extracts domain from client's JWT email (e.g. abrafleet.com)
//   - Fetches from client_created_trips where clientEmail matches domain
//   - Fetches from roster-assigned-trips where stops[].customer.email matches domain
//
// Statuses shown: assigned, accepted, started, in_progress
// ============================================================================

const { ObjectId } = require('mongodb');

// ============================================================================
// UTILITY: Haversine distance (km)
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

// ============================================================================
// UTILITY: Extract domain from email
// e.g. "client123@abrafleet.com" → "abrafleet.com"
// ============================================================================
function extractDomain(email) {
  if (!email || !email.includes('@')) return null;
  return email.split('@')[1].toLowerCase().trim();
}

// ============================================================================
// NORMALISER: roster-assigned-trips → shared vehicle shape
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
    vehicleNumber: trip.vehicleNumber || 'Unknown',

    driverId:      trip.driverId?.toString() || '',
    driverName:    trip.driverName  || 'Unknown',
    driverPhone:   trip.driverPhone || '',
    driverEmail:   trip.driverEmail || '',

    status:        trip.status,
    tripStatus:    trip.status,
    isIdle,
    scheduledDate: trip.scheduledDate || null,

    currentLocation: trip.currentLocation  || null,
    locationHistory: (trip.locationHistory || []).slice(-50),

    stops,
    totalStops,
    completedStops,
    currentStopIndex,
    currentStop: stops[currentStopIndex] || null,
    progress: totalStops > 0 ? (completedStops / totalStops) * 100 : 0,

    totalDistance:     trip.totalDistance     || 0,
    estimatedDuration: trip.estimatedDuration || 0,

    customerName:  null,
    customerPhone: null,
    customerEmail: null,

    lastUpdated: trip.currentLocation?.timestamp || trip.updatedAt,
  };
}

// ============================================================================
// NORMALISER: client_created_trips → shared vehicle shape
// ============================================================================
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
      stopId: 'pickup',
      sequence: 1,
      type: 'pickup',
      status: isActive ? 'arrived' : 'pending',
      customer: {
        name:  trip.clientName  || 'Client',
        email: trip.clientEmail || '',
        phone: trip.clientPhone || '',
      },
      location: {
        address: trip.pickupLocation.address || '',
        coordinates: {
          latitude:  trip.pickupLocation.latitude  ||
                     trip.pickupLocation.coordinates?.coordinates?.[1] || null,
          longitude: trip.pickupLocation.longitude ||
                     trip.pickupLocation.coordinates?.coordinates?.[0] || null,
        },
      },
      estimatedTime: trip.scheduledPickupTime || null,
    });
  }

  if (trip.dropLocation) {
    stops.push({
      stopId: 'drop',
      sequence: 2,
      type: 'drop',
      status: 'pending',
      customer: {
        name:  trip.clientName  || 'Client',
        email: trip.clientEmail || '',
        phone: trip.clientPhone || '',
      },
      location: {
        address: trip.dropLocation.address || '',
        coordinates: {
          latitude:  trip.dropLocation.latitude  ||
                     trip.dropLocation.coordinates?.coordinates?.[1] || null,
          longitude: trip.dropLocation.longitude ||
                     trip.dropLocation.coordinates?.coordinates?.[0] || null,
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
    vehicleNumber: trip.vehicleNumber || 'Unknown',

    driverId:    trip.driverId?.toString() || '',
    driverName:  trip.driverName  || 'Unknown',
    driverPhone: trip.driverPhone || '',
    driverEmail: trip.driverEmail || '',

    status:     trip.status,
    tripStatus: trip.status,
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

    // Map client fields → common customer names for uniform UI
    customerName:  trip.clientName  || 'N/A',
    customerPhone: trip.clientPhone || '',
    customerEmail: trip.clientEmail || '',

    pickupAddress: trip.pickupLocation?.address || '',
    dropAddress:   trip.dropLocation?.address   || '',

    adminConfirmed: trip.adminConfirmed || false,

    lastUpdated: trip.currentLocation?.timestamp || trip.updatedAt,
  };
}

// ============================================================================
// MAIN FUNCTION: fetchClientLiveVehicles
// Fetches trips from BOTH collections filtered by client's email domain
// ============================================================================
async function fetchClientLiveVehicles(db, clientEmail, date, statusFilter) {
  try {
    const domain = extractDomain(clientEmail);

    if (!domain) {
      console.log('❌ Could not extract domain from email:', clientEmail);
      return { vehicles: [], summary: buildEmptySummary() };
    }

    console.log(`\n🔍 fetchClientLiveVehicles`);
    console.log(`   clientEmail : ${clientEmail}`);
    console.log(`   domain      : ${domain}`);
    console.log(`   date        : ${date}`);
    console.log(`   statusFilter: ${statusFilter || 'all'}`);

    const VISIBLE_STATUSES = ['assigned', 'accepted', 'started', 'in_progress'];

    const dayStart = new Date(`${date}T00:00:00.000Z`);
    const dayEnd   = new Date(`${date}T23:59:59.999Z`);

    // ── QUERY 1: client_created_trips ─────────────────────────────────────
    const clientTripQuery = {
      status: { $in: VISIBLE_STATUSES },
      $or: [
        { scheduledPickupTime: { $gte: dayStart, $lte: dayEnd } },
        { status: { $in: ['started', 'in_progress'] } }
      ]
    };

    const allClientTrips = await db
      .collection('client_created_trips')
      .find(clientTripQuery)
      .toArray();

    // Filter by domain
    const clientTrips = allClientTrips.filter(trip => {
      const tripDomain = extractDomain(trip.clientEmail);
      return tripDomain === domain;
    });

    console.log(`   client_created_trips (domain match): ${clientTrips.length} / ${allClientTrips.length}`);

    // ── QUERY 2: roster-assigned-trips ────────────────────────────────────
    const rosterQuery = {
      scheduledDate: date,
      status: { $in: VISIBLE_STATUSES },
    };

    const allRosterTrips = await db
      .collection('roster-assigned-trips')
      .find(rosterQuery)
      .toArray();

    // Filter by domain in stops
    const rosterTrips = allRosterTrips.filter(trip => {
      if (!Array.isArray(trip.stops)) return false;
      return trip.stops.some(stop => {
        const stopDomain = extractDomain(stop.customer?.email);
        return stopDomain === domain;
      });
    });

    console.log(`   roster-assigned-trips (domain match): ${rosterTrips.length} / ${allRosterTrips.length}`);

    // ── NORMALISE — gives full shape including stops, currentLocation ──────
    // This is the KEY FIX — use the full normalisers so stops and
    // currentLocation are included, exactly like live_track.js does
    const normalisedClient = clientTrips.map(normaliseClientTrip);
    const normalisedRoster = rosterTrips.map(normaliseRosterTrip);

    // ── MERGE & DEDUPLICATE by tripId ─────────────────────────────────────
    const seen   = new Set();
    const merged = [];

    for (const v of [...normalisedClient, ...normalisedRoster]) {
      if (!seen.has(v.tripId)) {
        seen.add(v.tripId);
        merged.push(v);
      }
    }

    console.log(`   merged total: ${merged.length}`);

    // ── APPLY STATUS FILTER IN MEMORY ─────────────────────────────────────
    let filtered = merged;
    if (statusFilter && statusFilter !== 'all') {
      const statusMap = {
        'active':      ['started', 'in_progress'],
        'assigned':    ['assigned', 'accepted'],
        'completed':   ['completed'],
        'started':     ['started', 'in_progress'],
        'in_progress': ['started', 'in_progress'],
      };
      const matchStatuses = statusMap[statusFilter] || [statusFilter];
      filtered = merged.filter(v => matchStatuses.includes(v.status));
    }

    // ── BUILD SUMMARY ─────────────────────────────────────────────────────
    const summary = buildSummary(merged);

    console.log(`   filtered: ${filtered.length}`);
    console.log(`   summary: active=${summary.active}, assigned=${summary.assigned}, completed=${summary.completed}, idle=${summary.idle}`);

    return { vehicles: filtered, summary };

  } catch (err) {
    console.error('❌ fetchClientLiveVehicles:', err);
    throw err;
  }
}

// ============================================================================
// fetchClientVehicleDetails — fetch a single trip by tripId
// Only returns if it belongs to the client's domain
// ============================================================================
async function fetchClientVehicleDetails(db, tripId, clientEmail) {
  try {
    const domain = extractDomain(clientEmail);
    if (!domain) return null;

    let oid;
    try { oid = new ObjectId(tripId); } catch { return null; }

    // Try client_created_trips first
    let trip = await db.collection('client_created_trips').findOne({ _id: oid });
    if (trip) {
      const tripDomain = extractDomain(trip.clientEmail);
      if (tripDomain !== domain) {
        console.log('⛔ Trip does not belong to client domain');
        return null;
      }
      const normalised = normaliseClientTrip(trip);
      normalised.actualDistance  = trip.actualDistance  || null;
      normalised.actualDuration  = trip.actualDuration  || null;
      normalised.actualStartTime = trip.actualStartTime || null;
      normalised.actualEndTime   = trip.actualEndTime   || null;
      normalised.createdAt       = trip.createdAt;
      normalised.updatedAt       = trip.updatedAt;
      return normalised;
    }

    // Try roster-assigned-trips
    trip = await db.collection('roster-assigned-trips').findOne({ _id: oid });
    if (trip) {
      // Verify at least one stop belongs to domain
      const hasMatch = (trip.stops || []).some(
        s => extractDomain(s.customer?.email) === domain
      );
      if (!hasMatch) {
        console.log('⛔ Roster trip does not belong to client domain');
        return null;
      }
      const normalised = normaliseRosterTrip(trip);
      normalised.actualDistance  = trip.actualDistance  || null;
      normalised.actualDuration  = trip.actualDuration  || null;
      normalised.actualStartTime = trip.actualStartTime || null;
      normalised.actualEndTime   = trip.actualEndTime   || null;
      normalised.createdAt       = trip.createdAt;
      normalised.updatedAt       = trip.updatedAt;
      return normalised;
    }

    return null;

  } catch (err) {
    console.error('❌ fetchClientVehicleDetails:', err);
    throw err;
  }
}

// ============================================================================
// fetchClientLocationHistory
// ============================================================================
async function fetchClientLocationHistory(db, vehicleId, date, time, clientEmail) {
  try {
    const domain = extractDomain(clientEmail);
    if (!domain) return { vehicleId, date, locations: [] };

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
      return { vehicleId, date, locations: filterByTime(archive.locations, time) };
    }

    // client_created_trips fallback
    const clientTrip = await db.collection('client_created_trips').findOne(
      { vehicleId: oid, scheduledPickupTime: { $gte: dayStart, $lte: dayEnd } },
      { projection: { locationHistory: 1, clientEmail: 1 } }
    );
    if (clientTrip?.locationHistory?.length > 0) {
      const tripDomain = extractDomain(clientTrip.clientEmail);
      if (tripDomain === domain) {
        return { vehicleId, date, locations: filterByTime(clientTrip.locationHistory, time) };
      }
    }

    // roster-assigned-trips fallback
    const rosterTrip = await db.collection('roster-assigned-trips').findOne(
      { vehicleId: oid, scheduledDate: date },
      { projection: { locationHistory: 1, stops: 1 } }
    );
    if (rosterTrip?.locationHistory?.length > 0) {
      const hasMatch = (rosterTrip.stops || []).some(
        s => extractDomain(s.customer?.email) === domain
      );
      if (hasMatch) {
        return { vehicleId, date, locations: filterByTime(rosterTrip.locationHistory, time) };
      }
    }

    return { vehicleId, date, locations: [] };

  } catch (err) {
    console.error('❌ fetchClientLocationHistory:', err);
    throw err;
  }
}

// ============================================================================
// checkClientVehicleAlerts
// Only fires for started/in_progress trips
// ============================================================================
async function checkClientVehicleAlerts(vehicles) {
  const alerts = { offline: [], routeDeviation: [], speeding: [] };
  const now            = new Date();
  const fiveMinutesAgo = new Date(now - 5 * 60 * 1000);
  const GPS_REQUIRED   = ['started', 'in_progress'];

  for (const vehicle of vehicles) {
    try {
      if (!GPS_REQUIRED.includes(vehicle.tripStatus || vehicle.status)) continue;

      // OFFLINE
      if (!vehicle.currentLocation?.timestamp) {
        alerts.offline.push({
          vehicleId:     vehicle.vehicleId,
          vehicleNumber: vehicle.vehicleNumber,
          driverName:    vehicle.driverName,
          tripId:        vehicle.tripId,
          source:        vehicle.source,
          offlineSince:  vehicle.lastUpdated || null,
          duration:      'Unknown',
        });
      } else {
        const lastUpdate = new Date(vehicle.currentLocation.timestamp);
        if (lastUpdate < fiveMinutesAgo) {
          const mins = Math.floor((now - lastUpdate) / 60000);
          const duration = mins >= 60
            ? `${Math.floor(mins / 60)}h ${mins % 60}m`
            : `${mins} minutes`;
          alerts.offline.push({
            vehicleId:     vehicle.vehicleId,
            vehicleNumber: vehicle.vehicleNumber,
            driverName:    vehicle.driverName,
            tripId:        vehicle.tripId,
            source:        vehicle.source,
            offlineSince:  lastUpdate,
            duration,
          });
        }
      }

      if (!vehicle.currentLocation) continue;

      // ROUTE DEVIATION
      if (vehicle.currentStop?.location?.coordinates?.latitude) {
        const dist = calculateDistance(
          vehicle.currentLocation.latitude,
          vehicle.currentLocation.longitude,
          vehicle.currentStop.location.coordinates.latitude,
          vehicle.currentStop.location.coordinates.longitude,
        );
        if (dist > 5) {
          alerts.routeDeviation.push({
            vehicleId:       vehicle.vehicleId,
            vehicleNumber:   vehicle.vehicleNumber,
            driverName:      vehicle.driverName,
            tripId:          vehicle.tripId,
            source:          vehicle.source,
            deviation:       dist.toFixed(2),
            currentLocation: vehicle.currentLocation,
            nextStop:        vehicle.currentStop.customer?.name || 'Next stop',
          });
        }
      }

      // SPEEDING
      if (vehicle.currentLocation.speed > 80) {
        alerts.speeding.push({
          vehicleId:     vehicle.vehicleId,
          vehicleNumber: vehicle.vehicleNumber,
          driverName:    vehicle.driverName,
          tripId:        vehicle.tripId,
          source:        vehicle.source,
          speed:         vehicle.currentLocation.speed,
          location: {
            latitude:  vehicle.currentLocation.latitude,
            longitude: vehicle.currentLocation.longitude,
          },
        });
      }

    } catch (e) {
      console.error(`⚠️ alert check ${vehicle.vehicleId}:`, e.message);
    }
  }

  return alerts;
}

// ============================================================================
// HELPERS
// ============================================================================
function buildSummary(vehicles) {
  const summary = { total: 0, active: 0, assigned: 0, idle: 0, completed: 0, offline: 0 };
  const now = new Date();

  for (const v of vehicles) {
    summary.total++;
    const s = v.status;
    if (s === 'started' || s === 'in_progress') {
      summary.active++;
    } else if (s === 'assigned' || s === 'accepted') {
      summary.assigned++;
    } else if (s === 'completed') {
      summary.completed++;
    }
    if (v.isIdle) summary.idle++;
    if (v.currentLocation?.timestamp) {
      const mins = (now - new Date(v.currentLocation.timestamp)) / 60000;
      if (mins > 5 && (s === 'started' || s === 'in_progress')) summary.offline++;
    }
  }

  return summary;
}

function buildEmptySummary() {
  return { total: 0, active: 0, assigned: 0, idle: 0, completed: 0, offline: 0 };
}

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
// EXPORTS
// ============================================================================
module.exports = {
  fetchClientLiveVehicles,
  fetchClientVehicleDetails,
  fetchClientLocationHistory,
  checkClientVehicleAlerts,
  extractDomain,
};