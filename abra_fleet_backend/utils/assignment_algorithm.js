// utils/assignment_algorithm.js
const { getRedisClient } = require('../config/redis');
const { calculateRosterDistances, calculateGroupDistances } = require('./distance_calculator');

/**
 * ============================================================================
 * ASSIGNMENT ALGORITHM - VEHICLE SCORING ENGINE
 * ============================================================================
 * 
 * Scores vehicles based on 6 factors (0-100 total):
 * 1. Distance (40 points) - Closer is better
 * 2. Fuel Level (15 points) - Higher fuel is better
 * 3. Utilization (15 points) - Fewer trips is better (load balancing)
 * 4. Capacity Match (10 points) - Right size for group
 * 5. Driver Rating (10 points) - Higher rating is better
 * 6. Driver Hours (10 points) - More remaining hours is better
 * 
 * BONUSES:
 * - VIP Customer: +10 points for top-rated drivers (4.5+ stars)
 * - Urgent Pickup: Distance score × 1.5 if pickup < 30 min
 * - Consecutive Trip: +15 points if last drop near this pickup
 */

// ============================================================================
// STEP 1: FILTER COMPATIBLE VEHICLES
// ============================================================================

/**
 * Filter vehicles that CAN serve the roster(s)
 * @param {Array|Object} rosters - Single roster or array of rosters
 * @param {Array} allVehicles - All vehicles in system
 * @param {Object} db - Database connection
 * @returns {Promise<Object>} { compatible: [], rejected: [] }
 */
async function filterCompatibleVehicles(rosters, allVehicles, db) {
  console.log(`\n${'='.repeat(80)}`);
  console.log('🔍 FILTERING COMPATIBLE VEHICLES');
  console.log(`${'='.repeat(80)}`);
  
  const redis = getRedisClient();
  const compatible = [];
  const rejected = [];
  
  // Normalize rosters to array
  const rosterArray = Array.isArray(rosters) ? rosters : [rosters];
  const totalPassengers = rosterArray.length;
  
  // Get first roster for time/location reference
  const referenceRoster = rosterArray[0];
  const pickupLat = referenceRoster.locations?.pickup?.coordinates?.lat;
  const pickupLon = referenceRoster.locations?.pickup?.coordinates?.lon;
  const pickupTime = referenceRoster.startTime;
  const pickupDate = referenceRoster.startDate;
  
  console.log(`\n📋 Requirements:`);
  console.log(`   Passengers: ${totalPassengers}`);
  console.log(`   Pickup Location: ${pickupLat}, ${pickupLon}`);
  console.log(`   Pickup Time: ${pickupDate} ${pickupTime}`);
  
  // Calculate pickup datetime
  let pickupDateTime = null;
  try {
    pickupDateTime = new Date(`${pickupDate}T${pickupTime}`);
  } catch (e) {
    console.warn('⚠️ Could not parse pickup time');
  }
  
  console.log(`\n🔎 Checking ${allVehicles.length} vehicles...\n`);
  
  for (const vehicle of allVehicles) {
    let isCompatible = true;
    let rejectionReason = '';
    
    const vehicleId = vehicle._id.toString();
    const vehicleReg = vehicle.registrationNumber || vehicleId;
    
    console.log(`\n━━━ Checking ${vehicleReg} ━━━`);
    
    // ========================================================================
    // CHECK 1: Has Assigned Driver?
    // ========================================================================
    if (!vehicle.assignedDriver && !vehicle.driverId) {
      isCompatible = false;
      rejectionReason = 'No driver assigned';
      console.log(`   ❌ CHECK 1: ${rejectionReason}`);
    } else {
      console.log(`   ✅ CHECK 1: Has driver`);
    }
    
    // ========================================================================
    // CHECK 2: Has Enough Available Seats?
    // ========================================================================
    if (isCompatible) {
      const totalSeats = vehicle.seatingCapacity || 4;
      const assignedCustomers = vehicle.assignedCustomers || [];
      const assignedSeats = assignedCustomers.length;
      const availableSeats = totalSeats - 1 - assignedSeats; // -1 for driver
      
      if (availableSeats < totalPassengers) {
        isCompatible = false;
        rejectionReason = `Not enough seats (needs ${totalPassengers}, has ${availableSeats})`;
        console.log(`   ❌ CHECK 2: ${rejectionReason}`);
      } else {
        console.log(`   ✅ CHECK 2: Enough seats (${availableSeats}/${totalSeats} available)`);
      }
    }
    
    // ========================================================================
    // CHECK 3: Vehicle Available (Not on Active Trip)?
    // ========================================================================
    if (isCompatible && redis) {
      try {
        const currentTrip = await redis.get(`vehicle:${vehicleId}:current_trip`);
        if (currentTrip) {
          const tripData = JSON.parse(currentTrip);
          if (tripData.status === 'in-progress') {
            isCompatible = false;
            rejectionReason = `On active trip (${tripData.tripId})`;
            console.log(`   ❌ CHECK 3: ${rejectionReason}`);
          } else {
            console.log(`   ✅ CHECK 3: Not on active trip`);
          }
        } else {
          console.log(`   ✅ CHECK 3: No active trip`);
        }
      } catch (e) {
        console.log(`   ⚠️ CHECK 3: Could not check trip status (Redis error)`);
      }
    } else if (isCompatible) {
      // No Redis, check vehicle status field
      if (vehicle.status === 'on_trip' || vehicle.status === 'busy') {
        isCompatible = false;
        rejectionReason = `Vehicle status: ${vehicle.status}`;
        console.log(`   ❌ CHECK 3: ${rejectionReason}`);
      } else {
        console.log(`   ✅ CHECK 3: Vehicle idle/active`);
      }
    }
    
    // ========================================================================
    // CHECK 4: Can Reach Pickup Location in Time?
    // ========================================================================
    if (isCompatible && pickupLat && pickupLon && pickupDateTime) {
      const vehicleLat = vehicle.currentLocation?.lat || vehicle.lastKnownLocation?.lat;
      const vehicleLon = vehicle.currentLocation?.lon || vehicle.lastKnownLocation?.lon;
      
      if (vehicleLat && vehicleLon) {
        try {
          // Calculate distance to pickup (simplified - will be recalculated in scoring)
          const { calculateDistanceHaversine } = require('./distance_calculator');
          const distanceKm = calculateDistanceHaversine(vehicleLat, vehicleLon, pickupLat, pickupLon);
          
          // Estimate travel time (conservative: 25 km/h average in city)
          const travelTimeMin = (distanceKm / 25) * 60;
          
          // Time available until pickup
          const now = new Date();
          const minutesUntilPickup = (pickupDateTime - now) / (1000 * 60);
          
          // Need buffer time (15 minutes)
          const bufferMin = 15;
          
          if (travelTimeMin > (minutesUntilPickup - bufferMin)) {
            isCompatible = false;
            rejectionReason = `Cannot reach in time (needs ${Math.ceil(travelTimeMin)} min, has ${Math.floor(minutesUntilPickup)} min)`;
            console.log(`   ❌ CHECK 4: ${rejectionReason}`);
          } else {
            console.log(`   ✅ CHECK 4: Can reach on time (${Math.ceil(travelTimeMin)} min travel, ${Math.floor(minutesUntilPickup)} min available)`);
          }
        } catch (e) {
          console.log(`   ⚠️ CHECK 4: Could not verify time (assuming OK)`);
        }
      } else {
        console.log(`   ⚠️ CHECK 4: Vehicle location unknown (cannot verify time)`);
      }
    } else if (isCompatible) {
      console.log(`   ⚠️ CHECK 4: Skipped (missing pickup time/location)`);
    }
    
    // ========================================================================
    // CHECK 5: Driver Has Remaining Working Hours?
    // ========================================================================
    if (isCompatible) {
      // Get driver details
      let driver = null;
      try {
        const driverId = vehicle.assignedDriver || vehicle.driverId;
        if (driverId) {
          driver = await db.collection('drivers').findOne({ _id: driverId });
        }
      } catch (e) {
        console.log(`   ⚠️ Could not fetch driver details`);
      }
      
      if (driver) {
        const maxHours = driver.maxWorkingHours || 10;
        const usedHours = driver.currentWorkingHours || 0;
        const remainingHours = maxHours - usedHours;
        
        // Need at least 2 hours for a trip
        if (remainingHours < 2) {
          isCompatible = false;
          rejectionReason = `Driver has only ${remainingHours.toFixed(1)}h remaining (needs 2h minimum)`;
          console.log(`   ❌ CHECK 5: ${rejectionReason}`);
        } else {
          console.log(`   ✅ CHECK 5: Driver has ${remainingHours.toFixed(1)}h remaining`);
        }
      } else {
        console.log(`   ⚠️ CHECK 5: Could not verify driver hours (assuming OK)`);
      }
    }
    
    // ========================================================================
    // CHECK 6: Same Organization? (Email Domain Match)
    // ========================================================================
    if (isCompatible) {
      const vehicleOrg = vehicle.organization || 'unknown';
      const rosterOrg = referenceRoster.customerEmail?.split('@')[1] || 'unknown';
      
      // Allow if vehicle is from main fleet (abrafleet.com) or same org
      if (vehicleOrg !== rosterOrg && vehicleOrg !== 'abrafleet.com' && vehicleOrg !== 'unknown') {
        isCompatible = false;
        rejectionReason = `Different organization (vehicle: ${vehicleOrg}, customer: ${rosterOrg})`;
        console.log(`   ❌ CHECK 6: ${rejectionReason}`);
      } else {
        console.log(`   ✅ CHECK 6: Organization match (${vehicleOrg})`);
      }
    }
    
    // ========================================================================
    // RESULT
    // ========================================================================
    if (isCompatible) {
      compatible.push(vehicle);
      console.log(`   ✅ RESULT: COMPATIBLE`);
    } else {
      rejected.push({ vehicle, reason: rejectionReason });
      console.log(`   ❌ RESULT: REJECTED - ${rejectionReason}`);
    }
  }
  
  console.log(`\n${'='.repeat(80)}`);
  console.log(`✅ Compatible: ${compatible.length}`);
  console.log(`❌ Rejected: ${rejected.length}`);
  console.log(`${'='.repeat(80)}\n`);
  
  return { compatible, rejected };
}

// ============================================================================
// STEP 2: SCORE COMPATIBLE VEHICLES
// ============================================================================

/**
 * Score a vehicle for serving roster(s)
 * @param {Object} vehicle - Vehicle object
 * @param {Array|Object} rosters - Single roster or array
 * @param {Object} db - Database connection
 * @returns {Promise<Object>} Score breakdown and total
 */
async function scoreVehicle(vehicle, rosters, db) {
  const vehicleId = vehicle._id.toString();
  const vehicleReg = vehicle.registrationNumber || vehicleId;
  
  console.log(`\n${'━'.repeat(80)}`);
  console.log(`📊 SCORING: ${vehicleReg}`);
  console.log(`${'━'.repeat(80)}`);
  
  const scores = {
    distance: 0,
    fuel: 0,
    utilization: 0,
    capacity: 0,
    driverRating: 0,
    driverHours: 0,
  };
  
  // Normalize rosters to array
  const rosterArray = Array.isArray(rosters) ? rosters : [rosters];
  const referenceRoster = rosterArray[0];
  const totalPassengers = rosterArray.length;
  
  // ──────────────────────────────────────────────────────────────────────
  // FACTOR 1: DISTANCE SCORE (40 points max)
  // ──────────────────────────────────────────────────────────────────────
  console.log(`\n1️⃣ DISTANCE SCORE (40 points max)`);
  
  let distanceKm = 0;
  let distanceDetails = null;
  
  try {
    if (rosterArray.length === 1) {
      // Single roster - calculate vehicle → pickup → drop
      distanceDetails = await calculateRosterDistances(vehicle, referenceRoster);
      distanceKm = distanceDetails.vehicleToPickup?.distanceKm || 0;
    } else {
      // Multiple rosters - calculate optimized group route
      distanceDetails = await calculateGroupDistances(vehicle, rosterArray);
      distanceKm = distanceDetails.totalDistanceKm || 0;
    }
    
    // Score: 40 - (distance × 4)
    // Examples: 0km=40pts, 1km=36pts, 5km=20pts, 10km=0pts
    scores.distance = Math.max(0, 40 - (distanceKm * 4));
    
    console.log(`   Distance to pickup: ${distanceKm.toFixed(2)} km`);
    console.log(`   Formula: 40 - (${distanceKm.toFixed(2)} × 4) = ${scores.distance.toFixed(1)}`);
    console.log(`   Score: ${scores.distance.toFixed(1)}/40 ${'⭐'.repeat(Math.ceil(scores.distance / 10))}`);
  } catch (error) {
    console.log(`   ⚠️ Could not calculate distance: ${error.message}`);
    scores.distance = 20; // Default mid-score if distance unknown
  }
  
  // ──────────────────────────────────────────────────────────────────────
  // FACTOR 2: FUEL SCORE (15 points max)
  // ──────────────────────────────────────────────────────────────────────
  console.log(`\n2️⃣ FUEL SCORE (15 points max)`);
  
  const fuelPercent = vehicle.fuelLevel || 100;
  scores.fuel = (fuelPercent / 100) * 15;
  
  console.log(`   Fuel Level: ${fuelPercent}%`);
  console.log(`   Formula: (${fuelPercent} / 100) × 15 = ${scores.fuel.toFixed(1)}`);
  console.log(`   Score: ${scores.fuel.toFixed(1)}/15 ${'⭐'.repeat(Math.ceil(scores.fuel / 4))}`);
  
  if (fuelPercent < 30) {
    console.log(`   ⚠️ WARNING: Low fuel!`);
  }
  
  // ──────────────────────────────────────────────────────────────────────
  // FACTOR 3: UTILIZATION SCORE (15 points max)
  // ──────────────────────────────────────────────────────────────────────
  console.log(`\n3️⃣ UTILIZATION SCORE (15 points max)`);
  
  const tripsToday = vehicle.tripsCompletedToday || 0;
  scores.utilization = Math.max(0, 15 - (tripsToday * 2));
  
  console.log(`   Trips Today: ${tripsToday}`);
  console.log(`   Formula: 15 - (${tripsToday} × 2) = ${scores.utilization.toFixed(1)}`);
  console.log(`   Score: ${scores.utilization.toFixed(1)}/15 ${'⭐'.repeat(Math.ceil(scores.utilization / 4))}`);
  console.log(`   Purpose: Load balancing across fleet`);
  
  // ──────────────────────────────────────────────────────────────────────
  // FACTOR 4: CAPACITY MATCH SCORE (10 points max)
  // ──────────────────────────────────────────────────────────────────────
  console.log(`\n4️⃣ CAPACITY MATCH SCORE (10 points max)`);
  
  const totalSeats = vehicle.seatingCapacity || 4;
  const assignedSeats = (vehicle.assignedCustomers || []).length;
  const availableSeats = totalSeats - 1 - assignedSeats; // -1 for driver
  const overage = availableSeats - totalPassengers;
  
  if (overage === 0) {
    scores.capacity = 10; // Perfect match!
  } else if (overage === 1) {
    scores.capacity = 8;
  } else if (overage === 2) {
    scores.capacity = 6;
  } else {
    scores.capacity = Math.max(0, 10 - (overage * 2));
  }
  
  console.log(`   Needs: ${totalPassengers} seats`);
  console.log(`   Available: ${availableSeats} seats (${totalSeats} total - 1 driver - ${assignedSeats} assigned)`);
  console.log(`   Overage: ${overage} seats`);
  console.log(`   Score: ${scores.capacity.toFixed(1)}/10 ${'⭐'.repeat(Math.ceil(scores.capacity / 3))}`);
  
  if (overage > 3) {
    console.log(`   ⚠️ NOTE: Using large vehicle for small group (wasteful)`);
  }
  
  // ──────────────────────────────────────────────────────────────────────
  // FACTOR 5: DRIVER RATING SCORE (10 points max)
  // ──────────────────────────────────────────────────────────────────────
  console.log(`\n5️⃣ DRIVER RATING SCORE (10 points max)`);
  
  let driverRating = 4.0; // Default
  let driverName = 'Unknown';
  
  try {
    const driverId = vehicle.assignedDriver || vehicle.driverId;
    if (driverId) {
      const driver = await db.collection('drivers').findOne({ _id: driverId });
      if (driver) {
        driverRating = driver.rating || 4.0;
        driverName = driver.name || 'Unknown';
      }
    }
  } catch (e) {
    console.log(`   ⚠️ Could not fetch driver details`);
  }
  
  scores.driverRating = (driverRating / 5) * 10;
  
  console.log(`   Driver: ${driverName}`);
  console.log(`   Rating: ${driverRating.toFixed(1)} ⭐`);
  console.log(`   Formula: (${driverRating.toFixed(1)} / 5) × 10 = ${scores.driverRating.toFixed(1)}`);
  console.log(`   Score: ${scores.driverRating.toFixed(1)}/10 ${'⭐'.repeat(Math.ceil(scores.driverRating / 3))}`);
  
  // ──────────────────────────────────────────────────────────────────────
  // FACTOR 6: DRIVER HOURS SCORE (10 points max)
  // ──────────────────────────────────────────────────────────────────────
  console.log(`\n6️⃣ DRIVER HOURS SCORE (10 points max)`);
  
  let maxHours = 10;
  let usedHours = 0;
  
  try {
    const driverId = vehicle.assignedDriver || vehicle.driverId;
    if (driverId) {
      const driver = await db.collection('drivers').findOne({ _id: driverId });
      if (driver) {
        maxHours = driver.maxWorkingHours || 10;
        usedHours = driver.currentWorkingHours || 0;
      }
    }
  } catch (e) {
    console.log(`   ⚠️ Could not fetch driver hours`);
  }
  
  const remainingHours = maxHours - usedHours;
  scores.driverHours = (remainingHours / maxHours) * 10;
  
  console.log(`   Max Hours: ${maxHours}h`);
  console.log(`   Used: ${usedHours.toFixed(1)}h`);
  console.log(`   Remaining: ${remainingHours.toFixed(1)}h`);
  console.log(`   Formula: (${remainingHours.toFixed(1)} / ${maxHours}) × 10 = ${scores.driverHours.toFixed(1)}`);
  console.log(`   Score: ${scores.driverHours.toFixed(1)}/10 ${'⭐'.repeat(Math.ceil(scores.driverHours / 3))}`);
  
  // ──────────────────────────────────────────────────────────────────────
  // CALCULATE TOTAL BASE SCORE
  // ──────────────────────────────────────────────────────────────────────
  const baseScore = 
    scores.distance +
    scores.fuel +
    scores.utilization +
    scores.capacity +
    scores.driverRating +
    scores.driverHours;
  
  console.log(`\n${'─'.repeat(80)}`);
  console.log(`📊 BASE SCORE: ${baseScore.toFixed(1)}/100`);
  console.log(`${'─'.repeat(80)}`);
  
  // ──────────────────────────────────────────────────────────────────────
  // APPLY BONUSES
  // ──────────────────────────────────────────────────────────────────────
  let finalScore = baseScore;
  const bonuses = [];
  
  console.log(`\n🎁 BONUSES:`);
  
  // BONUS 1: VIP Customer (+10 points for high-rated drivers)
  const priority = referenceRoster.priority?.toLowerCase();
  if (priority === 'high' || priority === 'vip') {
    if (driverRating >= 4.5) {
      const bonus = 10;
      finalScore += bonus;
      bonuses.push({ type: 'VIP Customer', points: bonus });
      console.log(`   ✅ VIP Customer + High-Rated Driver: +${bonus} points`);
    }
  }
  
  // BONUS 2: Urgent Pickup (Distance score × 1.5 if pickup < 30 min)
  try {
    const pickupTime = new Date(`${referenceRoster.startDate}T${referenceRoster.startTime}`);
    const minutesUntilPickup = (pickupTime - new Date()) / (1000 * 60);
    
    if (minutesUntilPickup < 30 && minutesUntilPickup > 0) {
      const bonus = scores.distance * 0.5;
      finalScore += bonus;
      bonuses.push({ type: 'Urgent Pickup', points: bonus });
      console.log(`   ✅ Urgent Pickup (${Math.floor(minutesUntilPickup)} min): +${bonus.toFixed(1)} points`);
    }
  } catch (e) {
    // Could not parse pickup time
  }
  
  // BONUS 3: Consecutive Trip (+15 if last drop near this pickup)
  if (vehicle.lastDropLocation) {
    try {
      const { calculateDistanceHaversine } = require('./distance_calculator');
      const pickupLat = referenceRoster.locations?.pickup?.coordinates?.lat;
      const pickupLon = referenceRoster.locations?.pickup?.coordinates?.lon;
      
      if (pickupLat && pickupLon) {
        const distanceFromLastDrop = calculateDistanceHaversine(
          vehicle.lastDropLocation.lat,
          vehicle.lastDropLocation.lon,
          pickupLat,
          pickupLon
        );
        
        if (distanceFromLastDrop < 1) { // Within 1 km
          const bonus = 15;
          finalScore += bonus;
          bonuses.push({ type: 'Consecutive Trip', points: bonus });
          console.log(`   ✅ Consecutive Trip (${distanceFromLastDrop.toFixed(2)} km from last drop): +${bonus} points`);
        }
      }
    } catch (e) {
      // Could not calculate
    }
  }
  
  if (bonuses.length === 0) {
    console.log(`   No bonuses applied`);
  }
  
  // Cap at 100
  finalScore = Math.min(100, finalScore);
  
  console.log(`\n${'═'.repeat(80)}`);
  console.log(`🏆 FINAL SCORE: ${finalScore.toFixed(1)}/100`);
  console.log(`${'═'.repeat(80)}\n`);
  
  return {
    vehicleId,
    vehicleReg,
    totalScore: Math.round(finalScore),
    baseScore: Math.round(baseScore),
    breakdown: {
      distance: Math.round(scores.distance),
      fuel: Math.round(scores.fuel),
      utilization: Math.round(scores.utilization),
      capacity: Math.round(scores.capacity),
      driverRating: Math.round(scores.driverRating),
      driverHours: Math.round(scores.driverHours),
    },
    bonuses,
    details: {
      distanceKm,
      fuelPercent,
      tripsToday,
      driverName,
      driverRating: driverRating.toFixed(1),
      availableSeats,
      totalSeats,
      distanceDetails,
    },
  };
}

// ============================================================================
// STEP 3: FIND BEST MATCHES
// ============================================================================

/**
 * Find and rank best vehicle matches for roster(s)
 * @param {Array|Object} rosters - Single roster or array
 * @param {Object} db - Database connection
 * @returns {Promise<Object>} Ranked matches with scores
 */
async function findBestMatches(rosters, db) {
  console.log(`\n${'█'.repeat(80)}`);
  console.log(`🎯 FINDING BEST MATCHES`);
  console.log(`${'█'.repeat(80)}`);
  
  // Normalize to array
  const rosterArray = Array.isArray(rosters) ? rosters : [rosters];
  console.log(`\nRosters to match: ${rosterArray.length}`);
  
  // Get all active vehicles
  console.log(`\n📦 Fetching vehicles from database...`);
  const allVehicles = await db.collection('vehicles').find({
    status: { $in: ['idle', 'active'] }
  }).toArray();
  
  console.log(`Found ${allVehicles.length} vehicles in system`);
  
  // Filter compatible vehicles
  const { compatible, rejected } = await filterCompatibleVehicles(rosterArray, allVehicles, db);
  
  if (compatible.length === 0) {
    console.log(`\n❌ No compatible vehicles found!`);
    return {
      bestMatch: null,
      alternatives: [],
      allOptions: [],
      rejected,
      message: 'No compatible vehicles available',
    };
  }
  
  console.log(`\n✅ ${compatible.length} compatible vehicles found`);
  console.log(`\n${'─'.repeat(80)}`);
  console.log(`SCORING COMPATIBLE VEHICLES`);
  console.log(`${'─'.repeat(80)}`);
  
  // Score each compatible vehicle
  const scoredVehicles = [];
  for (const vehicle of compatible) {
    const score = await scoreVehicle(vehicle, rosterArray, db);
    scoredVehicles.push({
      vehicle,
      ...score,
    });
  }
  
  // Sort by score (highest first)
  scoredVehicles.sort((a, b) => b.totalScore - a.totalScore);
  
  console.log(`\n${'═'.repeat(80)}`);
  console.log(`📊 FINAL RANKINGS`);
  console.log(`${'═'.repeat(80)}\n`);
  
  scoredVehicles.forEach((scored, index) => {
    const medal = index === 0 ? '🥇' : index === 1 ? '🥈' : index === 2 ? '🥉' : `${index + 1}.`;
    console.log(`${medal} ${scored.vehicleReg}: ${scored.totalScore}/100`);
    console.log(`   Driver: ${scored.details.driverName} (⭐ ${scored.details.driverRating})`);
    console.log(`   Distance: ${scored.details.distanceKm?.toFixed(2)} km`);
    console.log(`   Fuel: ${scored.details.fuelPercent}%`);
    console.log(``);
  });
  
  return {
    bestMatch: scoredVehicles[0] || null,
    alternatives: scoredVehicles.slice(1, 3),
    allOptions: scoredVehicles,
    rejected,
    totalChecked: allVehicles.length,
    compatibleCount: compatible.length,
  };
}

// ============================================================================
// EXPORTS
// ============================================================================

module.exports = {
  filterCompatibleVehicles,
  scoreVehicle,
  findBestMatches,
};
// ```

// ---

// ## **✅ WHAT THIS FILE DOES:**
// ```
// 1️⃣ FILTERS Compatible Vehicles
//    └─ 6 checks: Driver, Seats, Active Trip, Time, Hours, Organization

// 2️⃣ SCORES Each Vehicle (0-100)
//    └─ 6 factors: Distance, Fuel, Utilization, Capacity, Rating, Hours

// 3️⃣ APPLIES BONUSES
//    └─ VIP customers, Urgent pickups, Consecutive trips

// 4️⃣ RANKS & RETURNS
//    └─ Best match + alternatives + all options