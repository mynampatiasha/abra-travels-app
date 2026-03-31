#!/usr/bin/env node

/**
 * TEST SCRIPT: Verify Pending Rosters Fix
 * 
 * This script tests that assigned customers are properly excluded from pending rosters
 */

const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function testPendingRostersFix() {
  console.log('🧪 TESTING PENDING ROSTERS FIX');
  console.log('='.repeat(50));
  
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db();
    
    console.log('✅ Connected to MongoDB');
    
    // 1. Check all rosters and their status
    console.log('\n📊 ROSTER STATUS ANALYSIS:');
    console.log('-'.repeat(30));
    
    const allRosters = await db.collection('rosters').find({}).toArray();
    console.log(`Total rosters in database: ${allRosters.length}`);
    
    const statusCounts = {};
    const assignedRosters = [];
    const pendingRosters = [];
    
    allRosters.forEach(roster => {
      const status = roster.status || 'unknown';
      statusCounts[status] = (statusCounts[status] || 0) + 1;
      
      if (status === 'assigned' || roster.vehicleId || roster.driverId) {
        assignedRosters.push({
          id: roster._id,
          name: roster.employeeDetails?.name || roster.customerName || 'Unknown',
          status: status,
          vehicleId: roster.vehicleId ? 'YES' : 'NO',
          driverId: roster.driverId ? 'YES' : 'NO',
          vehicleNumber: roster.vehicleNumber || 'N/A'
        });
      } else if (status === 'pending_assignment' || status === 'pending' || status === 'created') {
        pendingRosters.push({
          id: roster._id,
          name: roster.employeeDetails?.name || roster.customerName || 'Unknown',
          status: status,
          vehicleId: roster.vehicleId ? 'YES' : 'NO',
          driverId: roster.driverId ? 'YES' : 'NO'
        });
      }
    });
    
    console.log('\nStatus Distribution:');
    Object.entries(statusCounts).forEach(([status, count]) => {
      console.log(`  ${status}: ${count}`);
    });
    
    // 2. Test the pending rosters query (OLD vs NEW)
    console.log('\n🔍 TESTING PENDING ROSTERS QUERY:');
    console.log('-'.repeat(40));
    
    // OLD QUERY (problematic)
    const oldQuery = {
      status: { $in: ['pending_assignment', 'pending', 'created'] }
    };
    
    const oldResults = await db.collection('rosters').find(oldQuery).toArray();
    console.log(`OLD QUERY Results: ${oldResults.length} rosters`);
    
    // NEW QUERY (fixed)
    const newQuery = {
      status: { $in: ['pending_assignment', 'pending', 'created'] },
      $nor: [
        { status: 'assigned' },
        { status: 'scheduled' },
        { status: 'in_progress' },
        { status: 'started' },
        { status: 'active' },
        { status: 'completed' },
        { status: 'done' },
        { vehicleId: { $exists: true, $ne: null } },
        { driverId: { $exists: true, $ne: null } }
      ]
    };
    
    const newResults = await db.collection('rosters').find(newQuery).toArray();
    console.log(`NEW QUERY Results: ${newResults.length} rosters`);
    
    // 3. Identify problematic rosters
    console.log('\n⚠️  PROBLEMATIC ROSTERS (would show in old query but not new):');
    console.log('-'.repeat(60));
    
    const problematicRosters = oldResults.filter(oldRoster => {
      return !newResults.some(newRoster => 
        newRoster._id.toString() === oldRoster._id.toString()
      );
    });
    
    if (problematicRosters.length > 0) {
      console.log(`Found ${problematicRosters.length} problematic rosters:`);
      problematicRosters.forEach((roster, index) => {
        console.log(`  ${index + 1}. ${roster.employeeDetails?.name || roster.customerName || 'Unknown'}`);
        console.log(`     Status: ${roster.status}`);
        console.log(`     VehicleId: ${roster.vehicleId || 'null'}`);
        console.log(`     DriverId: ${roster.driverId || 'null'}`);
        console.log(`     VehicleNumber: ${roster.vehicleNumber || 'null'}`);
        console.log('');
      });
    } else {
      console.log('✅ No problematic rosters found - fix is working!');
    }
    
    // 4. Show assigned customers summary
    console.log('\n📋 ASSIGNED CUSTOMERS SUMMARY:');
    console.log('-'.repeat(35));
    
    if (assignedRosters.length > 0) {
      console.log(`Found ${assignedRosters.length} assigned customers:`);
      assignedRosters.forEach((roster, index) => {
        console.log(`  ${index + 1}. ${roster.name} → Vehicle: ${roster.vehicleNumber}`);
      });
    } else {
      console.log('No assigned customers found');
    }
    
    // 5. Show truly pending customers
    console.log('\n📋 TRULY PENDING CUSTOMERS:');
    console.log('-'.repeat(30));
    
    if (pendingRosters.length > 0) {
      console.log(`Found ${pendingRosters.length} truly pending customers:`);
      pendingRosters.forEach((roster, index) => {
        console.log(`  ${index + 1}. ${roster.name} (${roster.status})`);
      });
    } else {
      console.log('No pending customers found');
    }
    
    // 6. Final assessment
    console.log('\n🎯 FIX ASSESSMENT:');
    console.log('-'.repeat(20));
    
    if (problematicRosters.length === 0) {
      console.log('✅ SUCCESS: The fix is working correctly!');
      console.log('   - No assigned customers will appear in pending rosters');
      console.log('   - Smart grouping will only see truly pending customers');
    } else {
      console.log('⚠️  ISSUE: Some assigned customers might still appear as pending');
      console.log('   - This could cause the "already assigned" error');
      console.log('   - Consider running data cleanup script');
    }
    
  } catch (error) {
    console.error('❌ Test failed:', error);
  } finally {
    await client.close();
    console.log('\n🔌 Database connection closed');
  }
}

// Run the test
testPendingRostersFix().catch(console.error);