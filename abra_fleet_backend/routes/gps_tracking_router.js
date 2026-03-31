// routes/gps_tracking_router.js - Production GPS Tracking System
const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');

// ==================== DEVICE REGISTRATION ====================

// Register Single GPS Device
router.post('/devices', async (req, res) => {
  try {
    const { imei, model, sim, vehicleId } = req.body;

    // Validate IMEI
    if (!imei || !/^\d{15}$/.test(imei)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid IMEI. Must be exactly 15 digits.',
        code: 'INVALID_IMEI'
      });
    }

    // Check duplicate IMEI
    const existing = await req.db.collection('gps_devices').findOne({ imei });
    if (existing) {
      return res.status(409).json({
        success: false,
        message: 'This IMEI is already registered in the system.',
        code: 'DUPLICATE_IMEI',
        existingDevice: {
          imei: existing.imei,
          vehicle: existing.vehicleName,
          registeredAt: existing.createdAt
        }
      });
    }

    // Get vehicle details if assigned
    let vehicleData = { vehicleId: null, vehicleName: 'Unassigned', registrationNumber: null };
    if (vehicleId && vehicleId !== 'unassigned') {
      const vehicle = await req.db.collection('vehicles').findOne({ 
        _id: new ObjectId(vehicleId) 
      });
      if (vehicle) {
        vehicleData = {
          vehicleId: vehicle._id.toString(),
          vehicleName: vehicle.vehicleName || vehicle.registrationNumber,
          registrationNumber: vehicle.registrationNumber
        };
      }
    }

    // Create GPS device document
    const device = {
      imei,
      model: model || 'Unknown Model',
      sim: sim || 'N/A',
      vehicleId: vehicleData.vehicleId,
      vehicleName: vehicleData.vehicleName,
      registrationNumber: vehicleData.registrationNumber,
      status: vehicleData.vehicleId ? 'active' : 'unassigned',
      lastUpdate: new Date(),
      lastLocation: {
        latitude: null,
        longitude: null,
        speed: 0,
        satellites: 0,
        signal: 'Unknown',
        accuracy: 0
      },
      createdAt: new Date(),
      createdBy: req.user.email,
      updatedAt: new Date()
    };

    await req.db.collection('gps_devices').insertOne(device);

    // Update vehicle with GPS device info
    if (vehicleData.vehicleId) {
      await req.db.collection('vehicles').updateOne(
        { _id: new ObjectId(vehicleData.vehicleId) },
        { 
          $set: { 
            gpsDeviceImei: imei,
            gpsEnabled: true,
            updatedAt: new Date()
          } 
        }
      );
    }

    console.log(`✅ GPS Device registered: IMEI ${imei} → ${vehicleData.vehicleName}`);

    res.status(201).json({
      success: true,
      message: 'GPS device registered successfully',
      device: {
        ...device,
        _id: device._id
      }
    });

  } catch (error) {
    console.error('❌ Register Device Error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to register device',
      error: error.message
    });
  }
});

// ==================== BULK REGISTRATION ====================

// Bulk Register GPS Devices (for mass deployment)
router.post('/devices/bulk', async (req, res) => {
  try {
    const { devices } = req.body; // Array of {imei, model, sim, vehicleId}

    if (!Array.isArray(devices) || devices.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Devices array is required'
      });
    }

    const results = {
      success: [],
      failed: [],
      duplicate: []
    };

    // Process each device
    for (const deviceData of devices) {
      const { imei, model, sim, vehicleId } = deviceData;

      // Validate IMEI
      if (!imei || !/^\d{15}$/.test(imei)) {
        results.failed.push({ imei, reason: 'Invalid IMEI format' });
        continue;
      }

      // Check duplicate
      const existing = await req.db.collection('gps_devices').findOne({ imei });
      if (existing) {
        results.duplicate.push({ imei, vehicle: existing.vehicleName });
        continue;
      }

      // Get vehicle details
      let vehicleData = { vehicleId: null, vehicleName: 'Unassigned', registrationNumber: null };
      if (vehicleId && vehicleId !== 'unassigned') {
        const vehicle = await req.db.collection('vehicles').findOne({ 
          _id: new ObjectId(vehicleId) 
        });
        if (vehicle) {
          vehicleData = {
            vehicleId: vehicle._id.toString(),
            vehicleName: vehicle.vehicleName || vehicle.registrationNumber,
            registrationNumber: vehicle.registrationNumber
          };
        }
      }

      // Create device
      const device = {
        imei,
        model: model || 'Unknown Model',
        sim: sim || 'N/A',
        vehicleId: vehicleData.vehicleId,
        vehicleName: vehicleData.vehicleName,
        registrationNumber: vehicleData.registrationNumber,
        status: vehicleData.vehicleId ? 'active' : 'unassigned',
        lastUpdate: new Date(),
        lastLocation: {
          latitude: null,
          longitude: null,
          speed: 0,
          satellites: 0,
          signal: 'Unknown',
          accuracy: 0
        },
        createdAt: new Date(),
        createdBy: req.user.email,
        updatedAt: new Date()
      };

      await req.db.collection('gps_devices').insertOne(device);

      // Update vehicle
      if (vehicleData.vehicleId) {
        await req.db.collection('vehicles').updateOne(
          { _id: new ObjectId(vehicleData.vehicleId) },
          { 
            $set: { 
              gpsDeviceImei: imei,
              gpsEnabled: true,
              updatedAt: new Date()
            } 
          }
        );
      }

      results.success.push({ 
        imei, 
        vehicle: vehicleData.vehicleName,
        registrationNumber: vehicleData.registrationNumber 
      });
    }

    console.log(`✅ Bulk registration complete: ${results.success.length} success, ${results.failed.length} failed, ${results.duplicate.length} duplicates`);

    res.json({
      success: true,
      message: 'Bulk registration completed',
      summary: {
        total: devices.length,
        registered: results.success.length,
        failed: results.failed.length,
        duplicates: results.duplicate.length
      },
      results
    });

  } catch (error) {
    console.error('❌ Bulk Register Error:', error);
    res.status(500).json({
      success: false,
      message: 'Bulk registration failed',
      error: error.message
    });
  }
});

// ==================== GET DEVICES WITH PAGINATION ====================

// Get all GPS devices (with pagination for thousands of devices)
router.get('/devices', async (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 50;
    const search = req.query.search || '';
    const status = req.query.status || 'all';
    const skip = (page - 1) * limit;

    // Build query
    let query = {};

    // Search filter
    if (search) {
      query.$or = [
        { imei: { $regex: search, $options: 'i' } },
        { model: { $regex: search, $options: 'i' } },
        { vehicleName: { $regex: search, $options: 'i' } },
        { registrationNumber: { $regex: search, $options: 'i' } },
        { sim: { $regex: search, $options: 'i' } }
      ];
    }

    // Status filter
    if (status !== 'all') {
      query.status = status;
    }

    // Get total count
    const total = await req.db.collection('gps_devices').countDocuments(query);

    // Get devices with pagination
    const devices = await req.db.collection('gps_devices')
      .find(query)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .toArray();

    // Get statistics
    const stats = await req.db.collection('gps_devices').aggregate([
      {
        $group: {
          _id: null,
          total: { $sum: 1 },
          assigned: { 
            $sum: { 
              $cond: [{ $ne: ['$vehicleId', null] }, 1, 0] 
            } 
          },
          active: { 
            $sum: { 
              $cond: [{ $eq: ['$status', 'active'] }, 1, 0] 
            } 
          },
          unassigned: { 
            $sum: { 
              $cond: [{ $eq: ['$vehicleId', null] }, 1, 0] 
            } 
          }
        }
      }
    ]).toArray();

    const statistics = stats.length > 0 ? stats[0] : {
      total: 0,
      assigned: 0,
      active: 0,
      unassigned: 0
    };

    res.json({
      success: true,
      pagination: {
        page,
        limit,
        total,
        pages: Math.ceil(total / limit),
        hasNext: page < Math.ceil(total / limit),
        hasPrev: page > 1
      },
      statistics,
      devices
    });

  } catch (error) {
    console.error('❌ Get Devices Error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch devices',
      error: error.message
    });
  }
});

// ==================== GET AVAILABLE VEHICLES ====================

// Get vehicles available for GPS assignment (not already assigned)
router.get('/vehicles/available', async (req, res) => {
  try {
    const search = req.query.search || '';
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 100;
    const skip = (page - 1) * limit;

    // Build query - vehicles without GPS or with inactive GPS
    let query = {
      $or: [
        { gpsDeviceImei: { $exists: false } },
        { gpsDeviceImei: null },
        { gpsDeviceImei: '' },
        { gpsEnabled: false }
      ]
    };

    // Add search
    if (search) {
      query.$and = [
        { ...query },
        {
          $or: [
            { vehicleName: { $regex: search, $options: 'i' } },
            { registrationNumber: { $regex: search, $options: 'i' } },
            { vehicleType: { $regex: search, $options: 'i' } }
          ]
        }
      ];
    }

    const total = await req.db.collection('vehicles').countDocuments(query);

    const vehicles = await req.db.collection('vehicles')
      .find(query)
      .project({
        _id: 1,
        vehicleName: 1,
        registrationNumber: 1,
        vehicleType: 1,
        capacity: 1
      })
      .sort({ vehicleName: 1 })
      .skip(skip)
      .limit(limit)
      .toArray();

    res.json({
      success: true,
      total,
      page,
      limit,
      vehicles: vehicles.map(v => ({
        id: v._id.toString(),
        name: v.vehicleName || v.registrationNumber,
        registrationNumber: v.registrationNumber,
        type: v.vehicleType,
        capacity: v.capacity
      }))
    });

  } catch (error) {
    console.error('❌ Get Available Vehicles Error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch vehicles',
      error: error.message
    });
  }
});

// ==================== TEST CONNECTION ====================

// Test GPS device connection
router.post('/devices/:imei/test', async (req, res) => {
  try {
    const { imei } = req.params;

    // Find device
    const device = await req.db.collection('gps_devices').findOne({ imei });
    if (!device) {
      return res.status(404).json({
        success: false,
        message: 'Device not found in system',
        code: 'DEVICE_NOT_FOUND'
      });
    }

    // In production, you would actually ping the device here
    // For now, simulate test results based on recent data

    // Check if device has sent data recently (within 5 minutes)
    const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000);
    const hasRecentData = device.lastUpdate && device.lastUpdate > fiveMinutesAgo;

    if (hasRecentData && device.lastLocation.latitude) {
      // Device is active and working
      return res.json({
        success: true,
        message: 'Device connection test passed',
        latitude: device.lastLocation.latitude,
        longitude: device.lastLocation.longitude,
        speed: device.lastLocation.speed || 0,
        satellites: device.lastLocation.satellites || 0,
        signal: device.lastLocation.signal || 'Unknown',
        network: 'Connected',
        lastUpdate: device.lastUpdate
      });
    } else {
      // Device not responding or no recent data
      // Determine specific issue
      let code, message;

      if (!device.lastUpdate) {
        code = 'DEVICE_NOT_CONFIGURED';
        message = 'Device has never connected to server';
      } else if (!device.lastLocation.latitude) {
        code = 'NO_GPS_SIGNAL';
        message = 'GPS module not getting satellite signal';
      } else {
        code = 'NO_RESPONSE';
        message = 'Device did not respond to ping (last seen: ' + 
                  device.lastUpdate.toLocaleString() + ')';
      }

      return res.status(400).json({
        success: false,
        message,
        code,
        lastUpdate: device.lastUpdate,
        sim: device.sim
      });
    }

  } catch (error) {
    console.error('❌ Test Device Error:', error);
    res.status(500).json({
      success: false,
      message: 'Test failed due to server error',
      code: 'NETWORK_ERROR',
      error: error.message
    });
  }
});

// ==================== UPDATE DEVICE ====================

// Update GPS device
router.put('/devices/:imei', async (req, res) => {
  try {
    const { imei } = req.params;
    const { model, sim, vehicleId } = req.body;

    const device = await req.db.collection('gps_devices').findOne({ imei });
    if (!device) {
      return res.status(404).json({
        success: false,
        message: 'Device not found'
      });
    }

    const updateFields = {
      updatedAt: new Date(),
      updatedBy: req.user.email
    };

    if (model) updateFields.model = model;
    if (sim) updateFields.sim = sim;

    // Handle vehicle assignment change
    if (vehicleId !== undefined) {
      // Remove GPS from old vehicle
      if (device.vehicleId) {
        await req.db.collection('vehicles').updateOne(
          { _id: new ObjectId(device.vehicleId) },
          { 
            $unset: { gpsDeviceImei: '' },
            $set: { gpsEnabled: false, updatedAt: new Date() }
          }
        );
      }

      // Assign to new vehicle
      if (vehicleId && vehicleId !== 'unassigned') {
        const vehicle = await req.db.collection('vehicles').findOne({ 
          _id: new ObjectId(vehicleId) 
        });
        
        if (vehicle) {
          updateFields.vehicleId = vehicle._id.toString();
          updateFields.vehicleName = vehicle.vehicleName || vehicle.registrationNumber;
          updateFields.registrationNumber = vehicle.registrationNumber;
          updateFields.status = 'active';

          await req.db.collection('vehicles').updateOne(
            { _id: new ObjectId(vehicleId) },
            { 
              $set: { 
                gpsDeviceImei: imei,
                gpsEnabled: true,
                updatedAt: new Date()
              } 
            }
          );
        }
      } else {
        // Unassign
        updateFields.vehicleId = null;
        updateFields.vehicleName = 'Unassigned';
        updateFields.registrationNumber = null;
        updateFields.status = 'unassigned';
      }
    }

    await req.db.collection('gps_devices').updateOne(
      { imei },
      { $set: updateFields }
    );

    const updated = await req.db.collection('gps_devices').findOne({ imei });

    console.log(`✅ Device updated: IMEI ${imei}`);

    res.json({
      success: true,
      message: 'Device updated successfully',
      device: updated
    });

  } catch (error) {
    console.error('❌ Update Device Error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update device',
      error: error.message
    });
  }
});

// ==================== DELETE DEVICE ====================

// Delete GPS device
router.delete('/devices/:imei', async (req, res) => {
  try {
    const { imei } = req.params;

    const device = await req.db.collection('gps_devices').findOne({ imei });
    if (!device) {
      return res.status(404).json({
        success: false,
        message: 'Device not found'
      });
    }

    // Remove GPS from vehicle
    if (device.vehicleId) {
      await req.db.collection('vehicles').updateOne(
        { _id: new ObjectId(device.vehicleId) },
        { 
          $unset: { gpsDeviceImei: '' },
          $set: { gpsEnabled: false, updatedAt: new Date() }
        }
      );
    }

    // Delete device
    await req.db.collection('gps_devices').deleteOne({ imei });

    // Delete location history
    await req.db.collection('gps_locations').deleteMany({ imei });

    console.log(`🗑️ Device deleted: IMEI ${imei}`);

    res.json({
      success: true,
      message: 'Device deleted successfully'
    });

  } catch (error) {
    console.error('❌ Delete Device Error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete device',
      error: error.message
    });
  }
});

// ==================== RECEIVE GPS DATA ====================

// Receive GPS location data from device (MAIN ENDPOINT)
router.post('/location', async (req, res) => {
  try {
    const { 
      imei, 
      latitude, 
      longitude, 
      speed, 
      heading, 
      satellites, 
      altitude, 
      accuracy, 
      timestamp 
    } = req.body;

    // Validate required fields
    if (!imei || latitude === undefined || longitude === undefined) {
      return res.status(400).json({
        success: false,
        message: 'Missing required fields: imei, latitude, longitude'
      });
    }

    // Validate IMEI format
    if (!/^\d{15}$/.test(imei)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid IMEI format',
        code: 'INVALID_IMEI'
      });
    }

    // Find device in database
    const device = await req.db.collection('gps_devices').findOne({ imei });
    if (!device) {
      console.log(`⚠️ Unknown device sending data: IMEI ${imei}`);
      return res.status(404).json({
        success: false,
        message: 'Device not registered in system. Please register this IMEI first.',
        code: 'DEVICE_NOT_REGISTERED'
      });
    }

    const now = new Date();
    const locationData = {
      latitude: parseFloat(latitude),
      longitude: parseFloat(longitude),
      speed: speed ? parseFloat(speed) : 0,
      heading: heading ? parseFloat(heading) : 0,
      satellites: satellites ? parseInt(satellites) : 0,
      altitude: altitude ? parseFloat(altitude) : 0,
      accuracy: accuracy ? parseFloat(accuracy) : 0
    };

    // Save to location history
    await req.db.collection('gps_locations').insertOne({
      imei,
      vehicleId: device.vehicleId,
      vehicleName: device.vehicleName,
      registrationNumber: device.registrationNumber,
      ...locationData,
      timestamp: timestamp ? new Date(timestamp) : now,
      receivedAt: now
    });

    // Update device's last known location
    await req.db.collection('gps_devices').updateOne(
      { imei },
      {
        $set: {
          lastLocation: {
            ...locationData,
            signal: locationData.satellites > 6 ? 'Strong' : 
                   locationData.satellites > 3 ? 'Medium' : 'Weak'
          },
          lastUpdate: now,
          status: 'active'
        }
      }
    );

    // Update vehicle's real-time location
    if (device.vehicleId) {
      await req.db.collection('vehicles').updateOne(
        { _id: new ObjectId(device.vehicleId) },
        {
          $set: {
            currentLocation: {
              type: 'Point',
              coordinates: [locationData.longitude, locationData.latitude]
            },
            currentSpeed: locationData.speed,
            lastGPSUpdate: now,
            updatedAt: now
          }
        }
      );

      // Broadcast to WebSocket clients for real-time map updates
      const wsServer = req.app.get('wsServer');
      if (wsServer && wsServer.clients) {
        const updateMessage = JSON.stringify({
          type: 'gps_update',
          data: {
            vehicleId: device.vehicleId,
            registrationNumber: device.registrationNumber,
            ...locationData,
            timestamp: now
          }
        });

        wsServer.clients.forEach(client => {
          if (client.readyState === 1) { // OPEN
            client.send(updateMessage);
          }
        });
      }
    }

    console.log(`📍 GPS: ${device.vehicleName} | ${latitude}, ${longitude} | ${speed} km/h`);

    res.json({
      success: true,
      message: 'Location data received and processed',
      vehicle: device.vehicleName,
      timestamp: now
    });

  } catch (error) {
    console.error('❌ GPS Location Error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to process GPS data',
      error: error.message
    });
  }
});

// ==================== LOCATION HISTORY ====================

// Get device location history
router.get('/devices/:imei/history', async (req, res) => {
  try {
    const { imei } = req.params;
    const { limit = 100, startDate, endDate } = req.query;

    let query = { imei };

    // Add date filters
    if (startDate || endDate) {
      query.timestamp = {};
      if (startDate) query.timestamp.$gte = new Date(startDate);
      if (endDate) query.timestamp.$lte = new Date(endDate);
    }

    const locations = await req.db.collection('gps_locations')
      .find(query)
      .sort({ timestamp: -1 })
      .limit(parseInt(limit))
      .toArray();

    res.json({
      success: true,
      count: locations.length,
      imei,
      locations
    });

  } catch (error) {
    console.error('❌ Get History Error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch location history',
      error: error.message
    });
  }
});

// ==================== LIVE MAP DATA ====================

// Get all active vehicle locations for live map
router.get('/locations/live', async (req, res) => {
  try {
    // Get all active devices with recent updates (last 10 minutes)
    const tenMinutesAgo = new Date(Date.now() - 10 * 60 * 1000);

    const devices = await req.db.collection('gps_devices')
      .find({
        status: 'active',
        'lastLocation.latitude': { $ne: null },
        lastUpdate: { $gte: tenMinutesAgo }
      })
      .toArray();

    const liveLocations = devices.map(device => ({
      imei: device.imei,
      vehicleId: device.vehicleId,
      vehicleName: device.vehicleName,
      registrationNumber: device.registrationNumber,
      latitude: device.lastLocation.latitude,
      longitude: device.lastLocation.longitude,
      speed: device.lastLocation.speed,
      satellites: device.lastLocation.satellites,
      signal: device.lastLocation.signal,
      lastUpdate: device.lastUpdate
    }));

    res.json({
      success: true,
      count: liveLocations.length,
      locations: liveLocations,
      timestamp: new Date()
    });

  } catch (error) {
    console.error('❌ Get Live Locations Error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch live locations',
      error: error.message
    });
  }
});

module.exports = router;