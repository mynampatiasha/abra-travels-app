// models/roster_model.js
const { ObjectId } = require('mongodb');

class RosterModel {
  constructor(db) {
    this.collection = db.collection('rosters');
    this.driversCollection = db.collection('drivers');
    this.vehiclesCollection = db.collection('vehicles');
    
    // Create indexes for both old and new schema
    this.collection.createIndex({ driverId: 1, startTime: 1, endTime: 1 });
    this.collection.createIndex({ vehicleId: 1, startTime: 1, endTime: 1 });
    this.collection.createIndex({ userId: 1, startDate: 1, endDate: 1 });
    this.collection.createIndex({ rosterType: 1, status: 1 });
  }

  // Helper method to resolve driver ID (handles both ObjectId and custom driver codes)
  async resolveDriverId(driverIdOrCode) {
    // Check if it's already a valid ObjectId
    if (ObjectId.isValid(driverIdOrCode) && driverIdOrCode.length === 24) {
      return new ObjectId(driverIdOrCode);
    }
    
    // Otherwise, look up by custom driver code (e.g., "DRV-842143")
    const driver = await this.driversCollection.findOne({ 
      $or: [
        { driverCode: driverIdOrCode },
        { driverId: driverIdOrCode },
        { code: driverIdOrCode }
      ]
    });
    
    if (!driver) {
      throw new Error(`Driver not found with ID/code: ${driverIdOrCode}`);
    }
    
    return driver._id;
  }

  // Helper method to resolve vehicle ID (handles both ObjectId and custom vehicle codes)
  async resolveVehicleId(vehicleIdOrCode) {
    // Check if it's already a valid ObjectId
    if (ObjectId.isValid(vehicleIdOrCode) && vehicleIdOrCode.length === 24) {
      return new ObjectId(vehicleIdOrCode);
    }
    
    // Otherwise, look up by custom vehicle code
    const vehicle = await this.vehiclesCollection.findOne({ 
      $or: [
        { vehicleCode: vehicleIdOrCode },
        { vehicleId: vehicleIdOrCode },
        { registrationNumber: vehicleIdOrCode },
        { code: vehicleIdOrCode }
      ]
    });
    
    if (!vehicle) {
      throw new Error(`Vehicle not found with ID/code: ${vehicleIdOrCode}`);
    }
    
    return vehicle._id;
  }

  // Check for scheduling conflicts (existing method)
  async checkAvailability(driverId, vehicleId, startTime, endTime, excludeRosterId = null) {
    const query = {
      $or: [
        { 
          $and: [
            { startTime: { $lt: endTime } },
            { endTime: { $gt: startTime } }
          ]
        }
      ]
    };

    if (driverId) {
      query.driverId = new ObjectId(driverId);
    }
    if (vehicleId) {
      query.vehicleId = new ObjectId(vehicleId);
    }
    
    if (excludeRosterId) {
      query._id = { $ne: new ObjectId(excludeRosterId) };
    }

    const existingRoster = await this.collection.findOne(query);
    return !existingRoster;
  }

  // Create a new roster (existing method for driver-vehicle assignments)
  async create(rosterData) {
    const now = new Date();
    const roster = {
      ...rosterData,
      driverId: new ObjectId(rosterData.driverId),
      vehicleId: new ObjectId(rosterData.vehicleId),
      createdBy: new ObjectId(rosterData.createdBy),
      status: 'scheduled',
      createdAt: now,
      updatedAt: now
    };
    
    const result = await this.collection.insertOne(roster);
    return { ...roster, _id: result.insertedId };
  }

  // NEW: Create customer roster from Flutter app
  async createCustomerRoster(rosterData, userId) {
    const now = new Date();
    
    // Validate required fields
    const requiredFields = ['rosterType', 'officeLocation', 'weekdays', 'fromDate', 'toDate', 'fromTime', 'toTime'];
    for (const field of requiredFields) {
      if (!rosterData[field]) {
        throw new Error(`Missing required field: ${field}`);
      }
    }

    // ✅ FIXED: Validate location data based on roster type
    // Allow EITHER coordinates OR address (backend will geocode if needed)
    if (rosterData.rosterType === 'login' || rosterData.rosterType === 'both') {
      // Check if EITHER coordinates OR address is provided
      const hasPickupCoords = rosterData.loginPickupLocation && 
        (Array.isArray(rosterData.loginPickupLocation) ? rosterData.loginPickupLocation.length > 0 : true);
      const hasPickupAddress = rosterData.loginPickupAddress && rosterData.loginPickupAddress.trim() !== '';
      
      if (!hasPickupCoords && !hasPickupAddress) {
        throw new Error('Pickup location (coordinates or address) is required for login or both roster types');
      }
    }
    
    if (rosterData.rosterType === 'logout' || rosterData.rosterType === 'both') {
      // Check if EITHER coordinates OR address is provided
      const hasDropCoords = rosterData.logoutDropLocation && 
        (Array.isArray(rosterData.logoutDropLocation) ? rosterData.logoutDropLocation.length > 0 : true);
      const hasDropAddress = rosterData.logoutDropAddress && rosterData.logoutDropAddress.trim() !== '';
      
      if (!hasDropCoords && !hasDropAddress) {
        throw new Error('Drop location (coordinates or address) is required for logout or both roster types');
      }
    }

    const roster = {
      // Customer roster specific fields
      userId: userId, // Store Firebase UID as string
      rosterType: rosterData.rosterType, // 'login', 'logout', 'both'
      officeLocation: rosterData.officeLocation,
      weeklyOffDays: rosterData.weekdays, // Array of weekday strings
      
      // Date and time fields
      startDate: new Date(rosterData.fromDate),
      endDate: new Date(rosterData.toDate),
      startTime: rosterData.fromTime, // Store as string "HH:MM"
      endTime: rosterData.toTime, // Store as string "HH:MM"
      
      // Location data - Handle both array [lat, lng] and object {latitude, longitude} formats
      locations: {
        office: rosterData.officeLocationCoordinates ? {
          coordinates: {
            latitude: Array.isArray(rosterData.officeLocationCoordinates) 
              ? rosterData.officeLocationCoordinates[0] 
              : rosterData.officeLocationCoordinates.latitude,
            longitude: Array.isArray(rosterData.officeLocationCoordinates) 
              ? rosterData.officeLocationCoordinates[1] 
              : rosterData.officeLocationCoordinates.longitude
          },
          address: rosterData.officeLocation,
          timestamp: now
        } : null,
        pickup: rosterData.loginPickupLocation ? {
          coordinates: {
            latitude: Array.isArray(rosterData.loginPickupLocation) 
              ? rosterData.loginPickupLocation[0] 
              : rosterData.loginPickupLocation.latitude,
            longitude: Array.isArray(rosterData.loginPickupLocation) 
              ? rosterData.loginPickupLocation[1] 
              : rosterData.loginPickupLocation.longitude
          },
          address: rosterData.loginPickupAddress || '',
          timestamp: now
        } : null,
        drop: rosterData.logoutDropLocation ? {
          coordinates: {
            latitude: Array.isArray(rosterData.logoutDropLocation) 
              ? rosterData.logoutDropLocation[0] 
              : rosterData.logoutDropLocation.latitude,
            longitude: Array.isArray(rosterData.logoutDropLocation) 
              ? rosterData.logoutDropLocation[1] 
              : rosterData.logoutDropLocation.longitude
          },
          address: rosterData.logoutDropAddress || '',
          timestamp: now
        } : null
      },
      
      // Status and metadata
      status: 'pending_assignment', // Will be assigned driver/vehicle later
      requestType: 'customer_roster', // Distinguish from admin-created rosters
      
      // Assignment fields (to be filled later by admin)
      assignedDriver: null,
      assignedVehicle: null,
      assignmentDate: null,
      assignedBy: null,
      
      // Audit fields
      createdAt: now,
      updatedAt: now,
      createdBy: userId, // Store Firebase UID as string
      
      // Customer information
      customerName: rosterData.customerName || 'Unknown Customer',
      customerEmail: rosterData.customerEmail || '',
      
      // Additional metadata
      notes: rosterData.notes || '',
      priority: 'normal',
      isRecurring: true, // Since it has weekdays and date range
      
      // Store original request data for reference
      originalRequest: {
        ...rosterData,
        requestedAt: now
      }
    };
    
    const result = await this.collection.insertOne(roster);
    return { ...roster, _id: result.insertedId };
  }

  // Find customer rosters by user
  async findByUser(userId, filters = {}) {
    const query = { 
      userId: userId, // Query by Firebase UID string
      requestType: 'customer_roster'
    };
    
    if (filters.status) {
      query.status = filters.status;
    }
    
    if (filters.rosterType) {
      query.rosterType = filters.rosterType;
    }
    
    // Date range filter
    if (filters.startDate || filters.endDate) {
      query.startDate = {};
      if (filters.startDate) {
        query.startDate.$gte = new Date(filters.startDate);
      }
      if (filters.endDate) {
        query.startDate.$lte = new Date(filters.endDate);
      }
    }
    
    return await this.collection.find(query)
      .sort({ createdAt: -1 })
      .toArray();
  }

  // Find pending rosters for admin assignment
  async findPendingAssignments(filters = {}) {
    const query = { 
      requestType: 'customer_roster',
      status: 'pending_assignment'
    };
    
    if (filters.officeLocation) {
      query.officeLocation = filters.officeLocation;
    }
    
    if (filters.rosterType) {
      query.rosterType = filters.rosterType;
    }
    
    return await this.collection.find(query)
      .sort({ createdAt: 1 }) // Oldest first for FIFO processing
      .toArray();
  }

  // ✅ FIXED: Assign driver and vehicle to customer roster
  async assignDriverVehicle(rosterId, driverIdOrCode, vehicleIdOrCode, assignedBy) {
    console.log('📝 assignDriverVehicle called with:', {
      rosterId,
      driverIdOrCode,
      vehicleIdOrCode,
      assignedBy
    });

    try {
      // Validate roster ID
      if (!ObjectId.isValid(rosterId)) {
        throw new Error('Invalid roster ID format');
      }

      // ✅ Resolve driver ID (handles both ObjectId and custom codes like "DRV-842143")
      console.log('🔍 Resolving driver ID...');
      const driverObjectId = await this.resolveDriverId(driverIdOrCode);
      console.log('✅ Driver resolved to ObjectId:', driverObjectId);

      // ✅ Resolve vehicle ID (handles both ObjectId and custom codes)
      console.log('🔍 Resolving vehicle ID...');
      const vehicleObjectId = await this.resolveVehicleId(vehicleIdOrCode);
      console.log('✅ Vehicle resolved to ObjectId:', vehicleObjectId);

      // 🔧 FIX: Store as nested objects with driverId and vehicleId properties
      // This matches what the aggregation pipeline expects in roster_router.js
      const update = {
        $set: {
          assignedDriver: {
            driverId: driverObjectId,
            assignedAt: new Date()
          },
          assignedVehicle: {
            vehicleId: vehicleObjectId,
            assignedAt: new Date()
          },
          assignmentDate: new Date(),
          assignedBy: assignedBy, // Store Firebase UID as string
          status: 'assigned',
          updatedAt: new Date()
        }
      };
      
      console.log('🔄 Performing update with nested objects...');

      const result = await this.collection.findOneAndUpdate(
        { 
          _id: new ObjectId(rosterId),
          requestType: 'customer_roster'
        },
        update,
        { returnDocument: 'after' }
      );
      
      if (!result) {
        console.log('❌ Roster not found or update failed');
        return null;
      }

      console.log('✅ Update successful - assignedDriver:', result.assignedDriver);
      console.log('✅ Update successful - assignedVehicle:', result.assignedVehicle);
      
      return result;
    } catch (error) {
      console.error('❌ Error in assignDriverVehicle:', error.message);
      throw error;
    }
  }

  // Existing methods remain unchanged
 async findById(id) {
  // ✅ Return null instead of throwing for invalid IDs
  if (!id || !ObjectId.isValid(id) || (typeof id === 'string' && id.length !== 24)) {
    console.warn('⚠️ Invalid ID passed to findById:', id);
    return null;
  }
  
  try {
    return await this.collection.findOne({ _id: new ObjectId(id) });
  } catch (error) {
    console.error('❌ Error in findById:', error.message);
    return null;
  }
}
  async find(filters = {}) {
    const query = {};
    
    if (filters.driverId) {
      query.driverId = new ObjectId(filters.driverId);
    }
    
    if (filters.vehicleId) {
      query.vehicleId = new ObjectId(filters.vehicleId);
    }
    
    if (filters.status) {
      query.status = filters.status;
    }
    
    if (filters.startDate || filters.endDate) {
      query.startTime = {};
      if (filters.startDate) {
        query.startTime.$gte = new Date(filters.startDate);
      }
      if (filters.endDate) {
        query.startTime.$lte = new Date(filters.endDate);
      }
    }
    
    return await this.collection.find(query).sort({ startTime: 1 }).toArray();
  }

 async update(id, updateData) {
  // ✅ Return null instead of throwing for invalid IDs
  if (!id || !ObjectId.isValid(id) || (typeof id === 'string' && id.length !== 24)) {
    console.warn('⚠️ Invalid ID passed to update:', id);
    return null;
  }
  
  try {
    const update = {
      $set: {
        ...updateData,
        updatedAt: new Date()
      }
    };
    
    if (updateData.driverId) {
      update.$set.driverId = new ObjectId(updateData.driverId);
    }
    
    if (updateData.vehicleId) {
      update.$set.vehicleId = new ObjectId(updateData.vehicleId);
    }
    
    const result = await this.collection.findOneAndUpdate(
      { _id: new ObjectId(id) },
      update,
      { returnDocument: 'after' }
    );
    
    return result;
  } catch (error) {
    console.error('❌ Error in update:', error.message);
    return null;
  }
}

  async delete(id) {
  // ✅ Return false instead of throwing for invalid IDs
  if (!id || !ObjectId.isValid(id) || (typeof id === 'string' && id.length !== 24)) {
    console.warn('⚠️ Invalid ID passed to delete:', id);
    return false;
  }
  
  try {
    const result = await this.collection.deleteOne({ _id: new ObjectId(id) });
    return result.deletedCount > 0;
  } catch (error) {
    console.error('❌ Error in delete:', error.message);
    return false;
  }
}
}

module.exports = RosterModel;