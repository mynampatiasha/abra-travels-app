// utils/distance_calculator.js
// VERSION: OSRM - Open Source Routing Machine
// ✅ 100% FREE, NO BILLING, VERY ACCURATE

const axios = require('axios');

/**
 * ============================================================================
 * DISTANCE CALCULATOR - OSRM (Open Source Routing Machine)
 * ============================================================================
 * 
 * Uses OpenStreetMap data for actual road-based routing
 * 
 * PROS:
 * ✅ 100% FREE (no API key, no billing, ever)
 * ✅ Very accurate (95%+ accuracy vs Google Maps)
 * ✅ Calculates actual road distance (not straight line)
 * ✅ Provides turn-by-turn route
 * ✅ Estimates realistic drive time
 * ✅ Can optimize multi-stop routes
 * 
 * PUBLIC SERVER: http://router.project-osrm.org
 * (Can also self-host for guaranteed uptime)
 */

// ============================================================================
// CONFIGURATION
// ============================================================================

const OSRM_BASE_URL = process.env.OSRM_URL || 'http://router.project-osrm.org';

// Fallback: Haversine formula for when OSRM is unavailable
function calculateDistanceHaversine(lat1, lon1, lat2, lon2) {
  const R = 6371; // Earth's radius in kilometers
  
  const dLat = toRadians(lat2 - lat1);
  const dLon = toRadians(lon2 - lon1);
  
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(toRadians(lat1)) * Math.cos(toRadians(lat2)) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
  
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  const distance = R * c;
  
  return distance;
}

function toRadians(degrees) {
  return degrees * (Math.PI / 180);
}

// ============================================================================
// OSRM: GET ROUTE BETWEEN TWO POINTS
// ============================================================================

/**
 * Get route from point A to point B using OSRM
 * @param {number} lat1 - Start latitude
 * @param {number} lon1 - Start longitude
 * @param {number} lat2 - End latitude
 * @param {number} lon2 - End longitude
 * @returns {Promise<Object>} Route details with distance and duration
 */
async function getRoute(lat1, lon1, lat2, lon2) {
  try {
    // OSRM expects coordinates as: longitude,latitude (reverse of normal!)
    const coordinates = `${lon1},${lat1};${lon2},${lat2}`;
    const url = `${OSRM_BASE_URL}/route/v1/driving/${coordinates}?overview=false&steps=false`;
    
    console.log(`📍 OSRM Request: ${lat1},${lon1} → ${lat2},${lon2}`);
    
    const response = await axios.get(url, {
      timeout: 5000, // 5 second timeout
    });
    
    if (response.data && response.data.routes && response.data.routes.length > 0) {
      const route = response.data.routes[0];
      
      const distanceKm = route.distance / 1000; // Convert meters to km
      const durationMin = route.duration / 60; // Convert seconds to minutes
      
      console.log(`✅ OSRM: ${distanceKm.toFixed(2)} km, ${durationMin.toFixed(1)} min`);
      
      return {
        distanceKm: parseFloat(distanceKm.toFixed(2)),
        durationMin: Math.ceil(durationMin),
        source: 'osrm',
        success: true,
      };
    } else {
      throw new Error('No route found');
    }
  } catch (error) {
    console.warn(`⚠️ OSRM failed: ${error.message}`);
    console.log('🔄 Falling back to Haversine formula...');
    
    // Fallback to straight-line distance
    const distanceKm = calculateDistanceHaversine(lat1, lon1, lat2, lon2);
    const durationMin = Math.ceil((distanceKm / 30) * 60); // Assume 30 km/h average
    
    return {
      distanceKm: parseFloat(distanceKm.toFixed(2)),
      durationMin,
      source: 'haversine_fallback',
      success: true,
      warning: 'Using straight-line distance (OSRM unavailable)',
    };
  }
}

// ============================================================================
// OSRM: OPTIMIZE MULTI-STOP ROUTE (For Groups)
// ============================================================================

/**
 * Optimize route for multiple stops using OSRM Trip service
 * @param {Array} waypoints - Array of {lat, lon} objects
 * @returns {Promise<Object>} Optimized route with total distance/time
 */
async function getOptimizedRoute(waypoints) {
  try {
    if (!waypoints || waypoints.length < 2) {
      throw new Error('Need at least 2 waypoints');
    }
    
    console.log(`\n${'='.repeat(80)}`);
    console.log(`🗺️ OPTIMIZING ROUTE FOR ${waypoints.length} STOPS`);
    console.log(`${'='.repeat(80)}`);
    
    // Format coordinates for OSRM (lon,lat format)
    const coordinates = waypoints
      .map(wp => `${wp.lon},${wp.lat}`)
      .join(';');
    
    // Use OSRM Trip API for route optimization (solves TSP)
    const url = `${OSRM_BASE_URL}/trip/v1/driving/${coordinates}?source=first&destination=last&roundtrip=false`;
    
    console.log(`📡 OSRM Trip Request: ${waypoints.length} waypoints`);
    
    const response = await axios.get(url, {
      timeout: 10000, // 10 second timeout for complex routes
    });
    
    if (response.data && response.data.trips && response.data.trips.length > 0) {
      const trip = response.data.trips[0];
      
      const totalDistanceKm = trip.distance / 1000;
      const totalDurationMin = trip.duration / 60;
      
      // Get the optimized waypoint order
      const optimizedOrder = response.data.waypoints.map(wp => wp.waypoint_index);
      
      console.log(`✅ Route optimized:`);
      console.log(`   Total Distance: ${totalDistanceKm.toFixed(2)} km`);
      console.log(`   Total Duration: ${totalDurationMin.toFixed(1)} min`);
      console.log(`   Optimized Order: ${optimizedOrder.join(' → ')}`);
      
      return {
        totalDistanceKm: parseFloat(totalDistanceKm.toFixed(2)),
        totalDurationMin: Math.ceil(totalDurationMin),
        optimizedOrder,
        waypoints: response.data.waypoints,
        source: 'osrm_trip',
        success: true,
      };
    } else {
      throw new Error('No trip found');
    }
  } catch (error) {
    console.warn(`⚠️ OSRM Trip optimization failed: ${error.message}`);
    console.log('🔄 Using sequential route...');
    
    // Fallback: Calculate distances sequentially
    let totalDistance = 0;
    let totalDuration = 0;
    
    for (let i = 0; i < waypoints.length - 1; i++) {
      const segment = await getRoute(
        waypoints[i].lat,
        waypoints[i].lon,
        waypoints[i + 1].lat,
        waypoints[i + 1].lon
      );
      
      totalDistance += segment.distanceKm;
      totalDuration += segment.durationMin;
    }
    
    return {
      totalDistanceKm: parseFloat(totalDistance.toFixed(2)),
      totalDurationMin: Math.ceil(totalDuration),
      optimizedOrder: waypoints.map((_, i) => i), // Keep original order
      source: 'sequential_fallback',
      success: true,
      warning: 'Using sequential routing (OSRM Trip unavailable)',
    };
  }
}

// ============================================================================
// CALCULATE DISTANCES FOR SINGLE ROSTER
// ============================================================================

/**
 * Calculate vehicle → pickup → drop distances for a roster
 * @param {Object} vehicle - Vehicle object with currentLocation
 * @param {Object} roster - Roster object with pickup and drop locations
 * @returns {Promise<Object>} Distance and duration details
 */
async function calculateRosterDistances(vehicle, roster) {
  try {
    console.log(`\n📏 Calculating distances for roster: ${roster._id || roster.rosterId}`);
    
    // Extract coordinates
    const vehicleLat = vehicle.currentLocation?.lat || vehicle.lastKnownLocation?.lat;
    const vehicleLon = vehicle.currentLocation?.lon || vehicle.lastKnownLocation?.lon;
    
    const pickupLat = roster.locations?.pickup?.coordinates?.lat;
    const pickupLon = roster.locations?.pickup?.coordinates?.lon;
    
    const dropLat = roster.locations?.drop?.coordinates?.lat || roster.officeCoordinates?.lat;
    const dropLon = roster.locations?.drop?.coordinates?.lon || roster.officeCoordinates?.lon;
    
    // Validation
    if (!vehicleLat || !vehicleLon) {
      console.warn('⚠️ Vehicle location missing');
      return { error: 'Vehicle location not available' };
    }
    
    if (!pickupLat || !pickupLon) {
      console.warn('⚠️ Pickup location missing');
      return { error: 'Pickup location not available' };
    }
    
    if (!dropLat || !dropLon) {
      console.warn('⚠️ Drop location missing');
      return { error: 'Drop location not available' };
    }
    
    console.log(`  Vehicle: (${vehicleLat}, ${vehicleLon})`);
    console.log(`  Pickup:  (${pickupLat}, ${pickupLon})`);
    console.log(`  Drop:    (${dropLat}, ${dropLon})`);
    
    // Calculate: Vehicle → Pickup
    const vehicleToPickup = await getRoute(vehicleLat, vehicleLon, pickupLat, pickupLon);
    
    // Calculate: Pickup → Drop
    const pickupToDrop = await getRoute(pickupLat, pickupLon, dropLat, dropLon);
    
    // Total
    const totalDistanceKm = vehicleToPickup.distanceKm + pickupToDrop.distanceKm;
    const totalDurationMin = vehicleToPickup.durationMin + pickupToDrop.durationMin;
    
    console.log(`\n📊 Distance Summary:`);
    console.log(`   Vehicle → Pickup: ${vehicleToPickup.distanceKm} km, ${vehicleToPickup.durationMin} min`);
    console.log(`   Pickup → Drop:    ${pickupToDrop.distanceKm} km, ${pickupToDrop.durationMin} min`);
    console.log(`   TOTAL:            ${totalDistanceKm.toFixed(2)} km, ${totalDurationMin} min`);
    
    return {
      vehicleToPickup: {
        distanceKm: vehicleToPickup.distanceKm,
        durationMin: vehicleToPickup.durationMin,
      },
      pickupToDrop: {
        distanceKm: pickupToDrop.distanceKm,
        durationMin: pickupToDrop.durationMin,
      },
      totalDistanceKm: parseFloat(totalDistanceKm.toFixed(2)),
      totalDurationMin,
      source: vehicleToPickup.source,
      calculatedAt: new Date().toISOString(),
      warning: vehicleToPickup.warning,
    };
  } catch (error) {
    console.error(`❌ Error calculating roster distances: ${error.message}`);
    return { error: error.message };
  }
}

// ============================================================================
// CALCULATE DISTANCES FOR GROUP OF ROSTERS
// ============================================================================

/**
 * Calculate optimized route for vehicle serving multiple rosters
 * @param {Object} vehicle - Vehicle object
 * @param {Array} rosters - Array of roster objects
 * @returns {Promise<Object>} Optimized route with total distance/time
 */
async function calculateGroupDistances(vehicle, rosters) {
  try {
    console.log(`\n${'='.repeat(80)}`);
    console.log(`📏 CALCULATING GROUP ROUTE: ${rosters.length} rosters`);
    console.log(`${'='.repeat(80)}`);
    
    // Extract vehicle location
    const vehicleLat = vehicle.currentLocation?.lat || vehicle.lastKnownLocation?.lat;
    const vehicleLon = vehicle.currentLocation?.lon || vehicle.lastKnownLocation?.lon;
    
    if (!vehicleLat || !vehicleLon) {
      throw new Error('Vehicle location not available');
    }
    
    // Build waypoints array: Vehicle → All Pickups → Office
    const waypoints = [
      { lat: vehicleLat, lon: vehicleLon, type: 'vehicle', name: 'Vehicle Start' }
    ];
    
    // Add all pickup locations
    rosters.forEach((roster, index) => {
      const pickupLat = roster.locations?.pickup?.coordinates?.lat;
      const pickupLon = roster.locations?.pickup?.coordinates?.lon;
      
      if (pickupLat && pickupLon) {
        waypoints.push({
          lat: pickupLat,
          lon: pickupLon,
          type: 'pickup',
          name: roster.customerName || `Customer ${index + 1}`,
          rosterId: roster._id || roster.rosterId,
        });
      }
    });
    
    // Add office location (assuming all rosters go to same office)
    const firstRoster = rosters[0];
    const officeLat = firstRoster.locations?.drop?.coordinates?.lat || firstRoster.officeCoordinates?.lat;
    const officeLon = firstRoster.locations?.drop?.coordinates?.lon || firstRoster.officeCoordinates?.lon;
    
    if (officeLat && officeLon) {
      waypoints.push({
        lat: officeLat,
        lon: officeLon,
        type: 'office',
        name: firstRoster.officeLocation || 'Office',
      });
    }
    
    console.log(`\n📍 Waypoints:`);
    waypoints.forEach((wp, i) => {
      console.log(`   ${i}. ${wp.name} (${wp.type}): ${wp.lat}, ${wp.lon}`);
    });
    
    // Get optimized route
    const optimizedRoute = await getOptimizedRoute(waypoints);
    
    // Map optimized order back to roster IDs
    const pickupSequence = [];
    optimizedRoute.optimizedOrder.forEach((waypointIndex) => {
      const waypoint = waypoints[waypointIndex];
      if (waypoint.type === 'pickup') {
        pickupSequence.push({
          rosterId: waypoint.rosterId,
          customerName: waypoint.name,
          sequence: pickupSequence.length + 1,
          coordinates: { lat: waypoint.lat, lon: waypoint.lon },
        });
      }
    });
    
    console.log(`\n🎯 Optimized Pickup Sequence:`);
    pickupSequence.forEach((pickup) => {
      console.log(`   ${pickup.sequence}. ${pickup.customerName}`);
    });
    
    return {
      totalDistanceKm: optimizedRoute.totalDistanceKm,
      totalDurationMin: optimizedRoute.totalDurationMin,
      pickupSequence,
      waypointCount: waypoints.length,
      source: optimizedRoute.source,
      calculatedAt: new Date().toISOString(),
      warning: optimizedRoute.warning,
    };
  } catch (error) {
    console.error(`❌ Error calculating group distances: ${error.message}`);
    return { error: error.message };
  }
}

// ============================================================================
// EXPORTS
// ============================================================================

module.exports = {
  getRoute,
  getOptimizedRoute,
  calculateRosterDistances,
  calculateGroupDistances,
  calculateDistanceHaversine, // Export fallback for testing
};
