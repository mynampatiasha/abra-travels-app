#!/usr/bin/env node

/**
 * CLEANUP SCRIPT: Fix Assigned Rosters Data Inconsistencies
 * 
 * This script ensures that all assigned rosters have proper status and fields
 */

const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function cleanupAssignedRosters() {
  console.log('🧹 CLEANING UP ASSIGNED ROSTERS DATA');
  console.log('='.repeat(50));
  
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db();
    
    console.log('✅ Connected to MongoDB');
    
    // 1. Find rosters with vehicle/driver but wrong status
    console.log('\n🔍 FINDING INCONSISTENT ROSTERS...');
    
    const inconsistentRosters = await db.collection('rosters').find({
      $or: [
        // Has vehicle/driver but status is not assigned
        {
          $and: [
            { $or: [{ vehicleId: { $exists: true, $ne: null } }, { driverId: { $exists: true, $ne: null } }] },
            { status: { $nin: ['assigned', 'scheduled', 'in_progress', 'started', 'active'] } }
          ]
        },
        // Has assignedDriverId/assignedVehicleId but status is pending
        {
          $and: [
            { $or: [{ assignedDriverId: { $exists: true, $ne: null } }, { assignedVehicleId: { $exists: true, $ne: null } }] },
            { status: { $in: ['pending_assignment', 'pending', 'created'] } }
          ]
        }
      ]
    }).toArray();
    
    console.log(`Found ${inconsistentRosters.length} inconsistent rosters`);
    
    if (inconsistentRosters.length > 0) {
      console.log('\n📋 INCONSISTENT ROSTERS:');
      inconsistentRosters.forEach((roster, index) => {
        console.log(`  ${index + 1}. ${roster.employeeDetails?.name || roster.customerName || 'Unknown'}`);
        console.log(`     Current Status: ${roster.status}`);
        console.log(`     VehicleId: ${roster.vehicleId || 'null'}`);
        console.log(`     DriverId: ${roster.driverId || 'null'}`);
        console.log(`     AssignedVehicleId: ${roster.assignedVehicleId || 'null'}`);
        console.log(`     AssignedDriverId: ${roster.assignedDriverId || 'null'}`);
        console.log('');
      });
      
      // 2. Fix the inconsistencies
      console.log('🔧 FIXING INCONSISTENCIES...');
      
      let fixedCount = 0;
      
      for (const roster of inconsistentRosters) {
        try {
          const hasAssignment = roster.vehicleId || roster.driverId || 
                               roster.assignedVehicleId || roster.assignedDriverId;
          
          if (hasAssignment && roster.status !== 'assigned') {
            // Update status to assigned
            await db.collection('rosters').updateOne(
              { _id: roster._id },
              {
                $set: {
                  status: 'assigned',
                  updatedAt: new Date(),
                  fixedBy: 'cleanup-script',
                  fixedAt: new Date()
                }
              }
            );
            
            console.log(`  ✅ Fixed: ${roster.employeeDetails?.name || roster.customerName || 'Unknown'} → status: assigned`);
            fixedCount++;
          }
        } catch (error) {
          console.log(`  ❌ Failed to fix: ${roster.employeeDetails?.name || roster.customerName || 'Unknown'} - ${error.message}`);
        }
      }
      
      console.log(`\n✅ Fixed ${fixedCount} out of ${inconsistentRosters.length} rosters`);
    }
    
    // 3. Find and fix rosters with status=assigned but no vehicle/driver
    console.log('\n🔍 FINDING ASSIGNED ROSTERS WITHOUT VEHICLE/DRIVER...');
    
    const assignedWithoutVehicle = await db.collection('rosters').find({
      status: 'assigned',
      $and: [
        { $or: [{ vehicleId: { $exists: false } }, { vehicleId: null }] },
        { $or: [{ driverId: { $exists: false } }, { driverId: null }] },
        { $or: [{ assignedVehicleId: { $exists: false } }, { assignedVehicleId: null }] },
        { $or: [{ assignedDriverId: { $exists: false } }, { assignedDriverId: null }] }
      ]
    }).toArray();
    
    console.log(`Found ${assignedWithoutVehicle.length} assigned rosters without vehicle/driver`);
    
    if (assignedWithoutVehicle.length > 0) {
      console.log('\n📋 ASSIGNED BUT NO VEHICLE/DRIVER:');
      assignedWithoutVehicle.forEach((roster, index) => {
        console.log(`  ${index + 1}. ${roster.employeeDetails?.name || roster.customerName || 'Unknown'} (ID: ${roster._id})`);
      });
      
      // Fix by setting status back to pending_assignment
      console.log('\n🔧 FIXING BY SETTING STATUS TO PENDING...');
      
      const result = await db.collection('rosters').updateMany(
        {
          status: 'assigned',
          $and: [
            { $or: [{ vehicleId: { $exists: false } }, { vehicleId: null }] },
            { $or: [{ driverId: { $exists: false } }, { driverId: null }] },
            { $or: [{ assignedVehicleId: { $exists: false } }, { assignedVehicleId: null }] },
            { $or: [{ assignedDriverId: { $exists: false } }, { assignedDriverId: null }] }
          ]
        },
        {
          $set: {
            status: 'pending_assignment',
            updatedAt: new Date(),
            fixedBy: 'cleanup-script',
            fixedAt: new Date()
          }
        }
      );
      
      console.log(`✅ Fixed ${result.modifiedCount} rosters by setting status to pending_assignment`);
    }
    
    // 4. Verify the fix
    console.log('\n🔍 VERIFYING CLEANUP...');
    
    const remainingInconsistent = await db.collection('rosters').find({
      $or: [
        {
          $and: [
            { $or: [{ vehicleId: { $exists: true, $ne: null } }, { driverId: { $exists: true, $ne: null } }] },
            { status: { $nin: ['assigned', 'scheduled', 'in_progress', 'started', 'active'] } }
          ]
        },
        {
          $and: [
            { $or: [{ assignedDriverId: { $exists: true, $ne: null } }, { assignedVehicleId: { $exists: true, $ne: null } }] },
            { status: { $in: ['pending_assignment', 'pending', 'created'] } }
          ]
        }
      ]
    }).toArray();
    
    if (remainingInconsistent.length === 0) {
      console.log('✅ SUCCESS: All data inconsistencies have been fixed!');
    } else {
      console.log(`⚠️  WARNING: ${remainingInconsistent.length} inconsistencies still remain`);
    }
    
    // 5. Final summary
    console.log('\n📊 FINAL SUMMARY:');
    console.log('-'.repeat(20));
    
    const finalStats = await db.collection('rosters').aggregate([
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 }
        }
      },
      { $sort: { _id: 1 } }
    ]).toArray();
    
    console.log('Roster Status Distribution:');
    finalStats.forEach(stat => {
      console.log(`  ${stat._id || 'null'}: ${stat.count}`);
    });
    
    const trulyPending = await db.collection('rosters').countDocuments({
      status: { $in: ['pending_assignment', 'pending', 'created'] },
      $nor: [
        { status: 'assigned' },
        { vehicleId: { $exists: true, $ne: null } },
        { driverId: { $exists: true, $ne: null } }
      ]
    });
    
    console.log(`\n✅ Truly pending rosters: ${trulyPending}`);
    console.log('   (These should be the only ones showing in pending rosters screen)');
    
  } catch (error) {
    console.error('❌ Cleanup failed:', error);
  } finally {
    await client.close();
    console.log('\n🔌 Database connection closed');
  }
}

// Run the cleanup
cleanupAssignedRosters().catch(console.error);