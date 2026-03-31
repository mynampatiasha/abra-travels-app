// File: models/trip_model.js
// ENHANCED TRIP MODEL WITH MULTI-TRIP SUPPORT (6-11 trips/day per vehicle)

const { ObjectId } = require('mongodb');

class TripModel {
  constructor(db) {
    if (!db) {
      throw new Error('Database connection is required for TripModel.');
    }
    this.collection = db.collection('trips');
    this.initializeIndexes();
  }

  /**
   * Initialize database indexes for efficient multi-trip queries
   */
  async initializeIndexes() {
    try {
      // Existing indexes
      await this.collection.createIndex({ customerId: 1, status: 1 });
      await this.collection.createIndex({ driverId: 1, status: 1 });
      await this.collection.createIndex({ createdAt: -1 });
      
      // NEW: Multi-trip indexes for time slot management
      await this.collection.createIndex({ vehicleId: 1, scheduledDate: 1, startTime: 1 });
      await this.collection.createIndex({ vehicleId: 1, scheduledDate: 1, status: 1 });
      await this.collection.createIndex({ 'customer.customerId': 1, scheduledDate: 1 });
      await this.collection.createIndex({ tripId: 1 }, { unique: true, sparse: true });
      await this.collection.createIndex({ tripNumber: 1 }, { unique: true, sparse: true }); // Keep for backward compatibility
      
      console.log('✅ Trip indexes created successfully');
    } catch (error) {
      console.error('❌ Error creating Trip indexes:', error);
    }
  }

  /**
   * Generate unique trip ID in format: Trip-XXXXX (where XXXXX is 5 random numbers)
   */
  generateTripId() {
    const randomNumbers = Math.floor(Math.random() * 100000).toString().padStart(5, '0');
    return `Trip-${randomNumbers}`;
  }

  /**
   * Generate unique trip number (e.g., TRIP-20250115-001) - DEPRECATED
   * Use generateTripId() instead for new Trip-XXXXX format
   */
  generateTripNumber() {
    const date = new Date().toISOString().split('T')[0].replace(/-/g, '');
    const random = Math.floor(Math.random() * 1000).toString().padStart(3, '0');
    return `TRIP-${date}-${random}`;
  }

  /**
   * ✅ NEW: Create trip from roster assignment
   * This is called after route optimization assigns rosters to vehicles
   */
  async createFromRosterAssignment(data) {
    const {
      rosterId,
      vehicleId,
      driverId,
      customerId,
      customerName,
      customerEmail,
      customerPhone,
      pickupLocation,
      dropLocation,
      scheduledDate,
      startTime,
      endTime,
      distance,
      estimatedDuration,
      tripType, // 'login' or 'logout'
      sequence, // Pickup sequence in multi-trip route
      organizationId,
      organizationName,
      assignedBy = 'system',
    } = data;

    const tripId = this.generateTripId();
    const now = new Date();

    const trip = {
      tripId,
      rosterId,
      
      // Vehicle & Driver Assignment
      vehicleId,
      driverId,
      
      // Customer Details
      customer: {
        customerId,
        name: customerName,
        email: customerEmail,
        phone: customerPhone,
      },
      
      // Location Details
      pickupLocation: {
        address: typeof pickupLocation === 'string' ? pickupLocation : pickupLocation.address,
        coordinates: pickupLocation.coordinates || null,
      },
      dropLocation: {
        address: typeof dropLocation === 'string' ? dropLocation : dropLocation.address,
        coordinates: dropLocation.coordinates || null,
      },
      
      // Schedule Details
      scheduledDate, // Date string: "2025-01-15"
      startTime, // Time string: "08:30"
      endTime, // Time string: "09:00"
      estimatedDuration, // Minutes
      distance, // Kilometers
      
      // Trip Type & Sequencing
      tripType, // 'login' or 'logout'
      sequence, // 1, 2, 3... (pickup order in route)
      
      // Organization Info
      organizationId,
      organizationName,
      
      // Status Tracking (RouteMatic workflow)
      status: 'assigned', // assigned → started → in_progress → completed
      
      // Timestamps
      assignedAt: now,
      actualStartTime: null,
      actualEndTime: null,
      
      // Location Tracking
      currentLocation: null,
      locationHistory: [],
      
      // Trip Metrics
      actualDistance: null,
      actualDuration: null,
      
      // Audit Trail
      createdAt: now,
      updatedAt: now,
      createdBy: assignedBy,
    };

    const result = await this.collection.insertOne(trip);
    return { ...trip, _id: result.insertedId };
  }

  /**
   * ✅ CRITICAL: Check if vehicle has time slot conflict
   * Prevents double-booking the same vehicle at the same time
   */
  async checkTimeSlotConflict(vehicleId, scheduledDate, startTime, endTime, excludeTripId = null) {
    const query = {
      vehicleId,
      scheduledDate,
      status: { $in: ['assigned', 'started', 'in_progress'] }, // Only active trips
      $or: [
        // New trip starts during existing trip
        { startTime: { $lte: startTime }, endTime: { $gt: startTime } },
        // New trip ends during existing trip
        { startTime: { $lt: endTime }, endTime: { $gte: endTime } },
        // New trip encompasses existing trip
        { startTime: { $gte: startTime }, endTime: { $lte: endTime } },
      ],
    };

    if (excludeTripId) {
      query._id = { $ne: new ObjectId(excludeTripId) };
    }

    const conflictingTrip = await this.collection.findOne(query);
    return conflictingTrip;
  }

  /**
   * ✅ NEW: Get vehicle's trips for a specific date
   * Used to show daily route and validate 6-11 trips limit
   */
  async getVehicleTripsForDate(vehicleId, scheduledDate) {
    return await this.collection
      .find({
        vehicleId,
        scheduledDate,
        status: { $nin: ['cancelled', 'rejected'] },
      })
      .sort({ startTime: 1 }) // Order by time
      .toArray();
  }

  /**
   * ✅ NEW: Count active trips for vehicle on date
   * Enforces 6-11 trips limit per day
   */
  async countVehicleTripsForDate(vehicleId, scheduledDate) {
    return await this.collection.countDocuments({
      vehicleId,
      scheduledDate,
      status: { $nin: ['cancelled', 'rejected', 'completed'] },
    });
  }

  /**
   * ✅ NEW: Validate if vehicle can take another trip
   * Returns { canTakeTrip: boolean, reason: string, currentTrips: number }
   */
  async canVehicleTakeTrip(vehicleId, scheduledDate, startTime, endTime) {
    const currentTrips = await this.countVehicleTripsForDate(vehicleId, scheduledDate);
    
    // RouteMatic allows 6-11 trips per day
    if (currentTrips >= 11) {
      return {
        canTakeTrip: false,
        reason: 'Vehicle has reached maximum daily trip limit (11 trips)',
        currentTrips,
      };
    }

    // Check for time slot conflict
    const conflict = await this.checkTimeSlotConflict(vehicleId, scheduledDate, startTime, endTime);
    if (conflict) {
      return {
        canTakeTrip: false,
        reason: `Time slot conflict with Trip #${conflict.tripNumber} (${conflict.startTime} - ${conflict.endTime})`,
        currentTrips,
        conflictingTrip: conflict,
      };
    }

    return {
      canTakeTrip: true,
      reason: null,
      currentTrips,
    };
  }

  /**
   * ✅ NEW: Get driver's active trip
   */
  async getDriverActiveTrip(driverId) {
    return await this.collection.findOne({
      driverId,
      status: { $in: ['started', 'in_progress'] },
    });
  }

  /**
   * ✅ NEW: Update trip status with timestamp tracking
   */
  async updateStatus(tripId, newStatus, additionalData = {}) {
    const updateData = {
      status: newStatus,
      updatedAt: new Date(),
      ...additionalData,
    };

    // Track status-specific timestamps
    if (newStatus === 'started') {
      updateData.actualStartTime = new Date();
    } else if (newStatus === 'completed') {
      updateData.actualEndTime = new Date();
    }

    const result = await this.collection.findOneAndUpdate(
      { $or: [{ _id: new ObjectId(tripId) }, { tripId: tripId }, { tripNumber: tripId }] },
      { $set: updateData },
      { returnDocument: 'after' }
    );

    return result.value;
  }

  /**
   * ✅ NEW: Update trip location (real-time tracking)
   */
  async updateLocation(tripId, location) {
    const result = await this.collection.findOneAndUpdate(
      { $or: [{ _id: new ObjectId(tripId) }, { tripId: tripId }, { tripNumber: tripId }] },
      {
        $set: {
          currentLocation: {
            latitude: location.latitude,
            longitude: location.longitude,
            timestamp: new Date(),
          },
          updatedAt: new Date(),
        },
        $push: {
          locationHistory: {
            latitude: location.latitude,
            longitude: location.longitude,
            timestamp: new Date(),
            speed: location.speed || null,
            heading: location.heading || null,
          },
        },
      },
      { returnDocument: 'after' }
    );

    return result.value;
  }

  /**
   * ✅ NEW: Get today's trips for driver (for driver dashboard)
   */
  async getDriverTodayTrips(driverId) {
    const today = new Date().toISOString().split('T')[0]; // "2025-01-15"

    return await this.collection
      .find({
        driverId,
        scheduledDate: today,
        status: { $nin: ['cancelled', 'rejected'] },
      })
      .sort({ startTime: 1 })
      .toArray();
  }

  /**
   * Get trip by ID (existing method - enhanced)
   */
  async findById(id) {
    const query = ObjectId.isValid(id)
      ? { $or: [{ _id: new ObjectId(id) }, { tripId: id }, { tripNumber: id }] }
      : { $or: [{ tripId: id }, { tripNumber: id }] };

    return await this.collection.findOne(query);
  }

  /**
   * Get trips by customer ID
   */
  async findByCustomerId(customerId) {
    return await this.collection.find({ 'customer.customerId': customerId }).toArray();
  }

  /**
   * ✅ NEW: Get all trips with filters (for admin dashboard)
   */
  async findAll(filters = {}) {
    const query = {};

    if (filters.status) {
      query.status = filters.status;
    }
    if (filters.vehicleId) {
      query.vehicleId = filters.vehicleId;
    }
    if (filters.driverId) {
      query.driverId = filters.driverId;
    }
    if (filters.scheduledDate) {
      query.scheduledDate = filters.scheduledDate;
    }
    if (filters.organizationId) {
      query.organizationId = filters.organizationId;
    }

    const page = parseInt(filters.page) || 1;
    const limit = parseInt(filters.limit) || 20;
    const skip = (page - 1) * limit;

    const trips = await this.collection
      .find(query)
      .sort({ scheduledDate: -1, startTime: -1 })
      .skip(skip)
      .limit(limit)
      .toArray();

    const total = await this.collection.countDocuments(query);

    return {
      trips,
      pagination: {
        page,
        limit,
        total,
        pages: Math.ceil(total / limit),
      },
    };
  }

  /**
   * ✅ NEW: Calculate trip statistics (for dashboard)
   */
  async getTripStatistics(filters = {}) {
    const query = {};
    
    if (filters.driverId) {
      query.driverId = filters.driverId;
    }
    if (filters.vehicleId) {
      query.vehicleId = filters.vehicleId;
    }
    if (filters.dateFrom) {
      query.scheduledDate = { $gte: filters.dateFrom };
    }
    if (filters.dateTo) {
      query.scheduledDate = { ...query.scheduledDate, $lte: filters.dateTo };
    }

    const stats = await this.collection.aggregate([
      { $match: query },
      {
        $group: {
          _id: null,
          totalTrips: { $sum: 1 },
          completedTrips: {
            $sum: { $cond: [{ $eq: ['$status', 'completed'] }, 1, 0] }
          },
          totalDistance: { $sum: '$distance' },
          totalDuration: { $sum: '$estimatedDuration' },
        },
      },
    ]).toArray();

    return stats[0] || {
      totalTrips: 0,
      completedTrips: 0,
      totalDistance: 0,
      totalDuration: 0,
    };
  }

  /**
   * ✅ NEW: Batch create trips (used in route optimization)
   */
  async createBatch(tripsData) {
    const trips = tripsData.map(data => ({
      ...data,
      tripId: this.generateTripId(),
      status: 'assigned',
      assignedAt: new Date(),
      createdAt: new Date(),
      updatedAt: new Date(),
    }));

    const result = await this.collection.insertMany(trips);
    return result.insertedIds;
  }
}

module.exports = TripModel;