const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');

// Driver Profile Routes
// Base route: /api/drivers

// GET /api/drivers/profile - Get current driver's profile (for authenticated drivers)
router.get('/profile', async (req, res) => {
  try {
    console.log('🔍 Driver profile request received');
    console.log('   - User:', JSON.stringify(req.user, null, 2));
    console.log('   - Headers:', req.headers.authorization ? 'Authorization header present' : 'No auth header');
    
    // Get the authenticated user from JWT token
    const user = req.user;
    if (!user) {
      console.log('❌ No authenticated user found');
      return res.status(401).json({
        success: false,
        message: 'Authentication required'
      });
    }
    
    console.log('✅ Authenticated user found:', user.userId);
    console.log('   - Email:', user.email);
    console.log('   - Role:', user.role);
    console.log('   - DriverId:', user.driverId);
    console.log('   - Collection:', user.collectionName);
    
    // Find driver by driverId first (most reliable), then other fields
    let driver = await req.db.collection('drivers').findOne({
      $or: [
        { driverId: user.driverId },           // Primary: use driverId from JWT
        { 'personalInfo.email': user.email }, // Secondary: match by email
        { firebaseUid: user.firebaseUid },    // Tertiary: legacy firebaseUid
        { firebaseUid: user.userId },         // Quaternary: userId as firebaseUid
        { _id: new ObjectId(user.userId) }    // Last resort: direct _id match
      ].filter(condition => {
        // Filter out conditions with null/undefined values
        const key = Object.keys(condition)[0];
        const value = Object.values(condition)[0];
        return value != null && value !== undefined && value !== '';
      })
    });
    
    if (!driver) {
      console.log('❌ Driver not found in drivers collection');
      console.log('   - Searched for driverId:', user.driverId);
      console.log('   - Searched for email:', user.email);
      console.log('   - Searched for userId:', user.userId);
      console.log('   - Searched for firebaseUid:', user.firebaseUid);
      
      // Try to find in admin_users and get corresponding driver
      const adminUser = await req.db.collection('admin_users').findOne({
        $or: [
          { _id: new ObjectId(user.userId) },
          { email: user.email },
          { firebaseUid: user.firebaseUid }
        ],
        role: 'driver'
      });
      
      if (adminUser) {
        console.log('✅ Found admin user, searching for corresponding driver...');
        console.log('   - Admin driverId:', adminUser.driverId);
        console.log('   - Admin email:', adminUser.email);
        
        driver = await req.db.collection('drivers').findOne({
          $or: [
            { driverId: adminUser.driverId },
            { 'personalInfo.email': adminUser.email },
            { firebaseUid: adminUser.firebaseUid }
          ]
        });
        
        if (!driver) {
          console.log('❌ No corresponding driver record found for admin user');
          return res.status(404).json({
            success: false,
            message: 'Driver profile not found. Please contact admin to complete your profile setup.'
          });
        }
      } else {
        return res.status(404).json({
          success: false,
          message: 'Driver profile not found'
        });
      }
    }
    
    console.log('✅ Driver found:', driver.driverId);
    console.log('   - Name:', `${driver.personalInfo?.firstName} ${driver.personalInfo?.lastName}`);
    console.log('   - Email:', driver.personalInfo?.email);
    
    // Get assigned vehicle details if any
    let assignedVehicle = null;
    if (driver.assignedVehicle) {
      assignedVehicle = await req.db.collection('vehicles').findOne(
        { vehicleId: driver.assignedVehicle },
        { 
          projection: { 
            vehicleId: 1, 
            registrationNumber: 1, 
            make: 1, 
            model: 1,
            type: 1,
            status: 1
          } 
        }
      );
      console.log('✅ Assigned vehicle found:', assignedVehicle?.vehicleId);
    }
    
    // Get recent trips
    const recentTrips = await req.db.collection('trips')
      .find({ driverId: driver.driverId })
      .sort({ startTime: -1 })
      .limit(5)
      .toArray();
    
    // Get performance stats
    const totalTrips = await req.db.collection('trips')
      .countDocuments({ driverId: driver.driverId });
    
    const completedTrips = await req.db.collection('trips')
      .countDocuments({ 
        driverId: driver.driverId, 
        status: 'completed' 
      });
    
    // Prepare response data compatible with frontend
    const profileData = {
      _id: driver._id,
      userId: user.userId,
      name: `${driver.personalInfo?.firstName || ''} ${driver.personalInfo?.lastName || ''}`.trim(),
      email: driver.personalInfo?.email,
      phoneNumber: driver.personalInfo?.phone,
      role: 'driver',
      status: driver.status || 'active',
      driverId: driver.driverId,
      personalInfo: driver.personalInfo,
      license: driver.license,
      emergencyContact: driver.emergencyContact,
      address: driver.address,
      assignedVehicle,
      stats: {
        totalTrips,
        completedTrips,
        completionRate: totalTrips > 0 ? Math.round((completedTrips / totalTrips) * 100) : 0
      },
      recentTrips,
      joinedDate: driver.joinedDate || driver.createdAt,
      createdAt: driver.createdAt,
      updatedAt: driver.updatedAt
    };
    
    console.log('✅ Profile data prepared successfully');
    
    res.json({
      success: true,
      data: profileData
    });
  } catch (error) {
    console.error('❌ Error fetching driver profile:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch driver profile',
      error: error.message
    });
  }
});

// PUT /api/drivers/profile - Update current driver's profile
router.put('/profile', async (req, res) => {
  try {
    console.log('🔄 Driver profile update request received');
    
    const user = req.user;
    if (!user) {
      return res.status(401).json({
        success: false,
        message: 'Authentication required'
      });
    }
    
    const { name, phoneNumber, address } = req.body;
    
    // Find driver
    let driver = await req.db.collection('drivers').findOne({
      $or: [
        { _id: new ObjectId(user.userId) },
        { 'personalInfo.email': user.email }
      ]
    });
    
    if (!driver) {
      return res.status(404).json({
        success: false,
        message: 'Driver profile not found'
      });
    }
    
    // Prepare update data
    const updateData = {
      updatedAt: new Date()
    };
    
    if (name) {
      const nameParts = name.trim().split(' ');
      updateData['personalInfo.firstName'] = nameParts[0];
      updateData['personalInfo.lastName'] = nameParts.slice(1).join(' ') || '';
    }
    
    if (phoneNumber) {
      updateData['personalInfo.phone'] = phoneNumber;
    }
    
    if (address) {
      updateData.address = address;
    }
    
    // Update driver
    const result = await req.db.collection('drivers').updateOne(
      { _id: driver._id },
      { $set: updateData }
    );
    
    if (result.modifiedCount > 0) {
      console.log('✅ Driver profile updated successfully');
      
      // Get updated driver
      const updatedDriver = await req.db.collection('drivers').findOne({ _id: driver._id });
      
      res.json({
        success: true,
        message: 'Profile updated successfully',
        data: {
          name: `${updatedDriver.personalInfo?.firstName || ''} ${updatedDriver.personalInfo?.lastName || ''}`.trim(),
          phoneNumber: updatedDriver.personalInfo?.phone,
          address: updatedDriver.address
        }
      });
    } else {
      res.json({
        success: true,
        message: 'No changes made'
      });
    }
  } catch (error) {
    console.error('❌ Error updating driver profile:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update driver profile',
      error: error.message
    });
  }
});

module.exports = router;