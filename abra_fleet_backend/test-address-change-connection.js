// Test Address Change Feature Connection
// Run: node test-address-change-connection.js

const fs = require('fs');
const path = require('path');

console.log('\n' + '='.repeat(80));
console.log('🔍 ADDRESS CHANGE FEATURE CONNECTION TEST');
console.log('='.repeat(80) + '\n');

let allGood = true;

// 1. Check Backend Router File
console.log('1️⃣ Checking Backend Router...');
const routerPath = path.join(__dirname, 'routes', 'address_change_router.js');
if (fs.existsSync(routerPath)) {
  console.log('   ✅ address_change_router.js exists');
  
  // Check if it has the required endpoints
  const routerContent = fs.readFileSync(routerPath, 'utf8');
  const requiredEndpoints = [
    'POST.*customer/request',
    'GET.*customer/requests',
    'GET.*admin/requests',
    'PUT.*admin/request.*process',
    'PUT.*admin/request.*reject'
  ];
  
  requiredEndpoints.forEach(endpoint => {
    if (new RegExp(endpoint).test(routerContent)) {
      console.log(`   ✅ Endpoint found: ${endpoint.replace('.*', ' ')}`);
    } else {
      console.log(`   ❌ Endpoint missing: ${endpoint.replace('.*', ' ')}`);
      allGood = false;
    }
  });
} else {
  console.log('   ❌ address_change_router.js NOT FOUND');
  allGood = false;
}

// 2. Check Backend Registration in index.js
console.log('\n2️⃣ Checking Backend Registration...');
const indexPath = path.join(__dirname, 'index.js');
if (fs.existsSync(indexPath)) {
  const indexContent = fs.readFileSync(indexPath, 'utf8');
  
  if (indexContent.includes("require('./routes/address_change_router')")) {
    console.log('   ✅ Router imported in index.js');
  } else {
    console.log('   ❌ Router NOT imported in index.js');
    allGood = false;
  }
  
  if (indexContent.includes("app.use('/api/address-change'")) {
    console.log('   ✅ Route registered in index.js');
  } else {
    console.log('   ❌ Route NOT registered in index.js');
    allGood = false;
  }
} else {
  console.log('   ❌ index.js NOT FOUND');
  allGood = false;
}

// 3. Check Frontend Customer Screens
console.log('\n3️⃣ Checking Frontend Customer Screens...');
const screenPaths = [
  '../abra_fleet/lib/features/customer/dashboard/presentation/screens/address_change_request_screen.dart',
  '../abra_fleet/lib/features/customer/dashboard/presentation/screens/my_address_requests_screen.dart'
];

screenPaths.forEach(screenPath => {
  const fullPath = path.join(__dirname, screenPath);
  const screenName = path.basename(screenPath);
  
  if (fs.existsSync(fullPath)) {
    console.log(`   ✅ ${screenName} exists`);
  } else {
    console.log(`   ❌ ${screenName} NOT FOUND`);
    allGood = false;
  }
});

// 4. Check Navigation in My Trips Screen
console.log('\n4️⃣ Checking Navigation in My Trips Screen...');
const myTripsPath = path.join(__dirname, '../abra_fleet/lib/features/customer/dashboard/presentation/screens/my_trips_screen.dart');
if (fs.existsSync(myTripsPath)) {
  const myTripsContent = fs.readFileSync(myTripsPath, 'utf8');
  
  if (myTripsContent.includes('address_change_request_screen')) {
    console.log('   ✅ AddressChangeRequestScreen imported');
  } else {
    console.log('   ❌ AddressChangeRequestScreen NOT imported');
    allGood = false;
  }
  
  if (myTripsContent.includes('my_address_requests_screen')) {
    console.log('   ✅ MyAddressRequestsScreen imported');
  } else {
    console.log('   ❌ MyAddressRequestsScreen NOT imported');
    allGood = false;
  }
  
  if (myTripsContent.includes('Change Address')) {
    console.log('   ✅ "Change Address" menu item found');
  } else {
    console.log('   ❌ "Change Address" menu item NOT found');
    allGood = false;
  }
  
  if (myTripsContent.includes('_navigateToAddressChangeRequest')) {
    console.log('   ✅ Navigation method exists');
  } else {
    console.log('   ❌ Navigation method NOT found');
    allGood = false;
  }
} else {
  console.log('   ❌ my_trips_screen.dart NOT FOUND');
  allGood = false;
}

// 5. Check Repository Methods
console.log('\n5️⃣ Checking Repository Methods...');
const repoPath = path.join(__dirname, '../abra_fleet/lib/features/customer/dashboard/data/repositories/roster_repository.dart');
if (fs.existsSync(repoPath)) {
  const repoContent = fs.readFileSync(repoPath, 'utf8');
  
  if (repoContent.includes('submitAddressChangeRequest')) {
    console.log('   ✅ submitAddressChangeRequest method exists');
  } else {
    console.log('   ❌ submitAddressChangeRequest method NOT found');
    allGood = false;
  }
  
  if (repoContent.includes('getAddressChangeRequests')) {
    console.log('   ✅ getAddressChangeRequests method exists');
  } else {
    console.log('   ❌ getAddressChangeRequests method NOT found');
    allGood = false;
  }
} else {
  console.log('   ❌ roster_repository.dart NOT FOUND');
  allGood = false;
}

// Final Summary
console.log('\n' + '='.repeat(80));
if (allGood) {
  console.log('✅ ALL CHECKS PASSED - Address Change Feature is FULLY CONNECTED!');
  console.log('='.repeat(80));
  console.log('\n📱 Customer can now:');
  console.log('   1. Open mobile app');
  console.log('   2. Go to "My Trips"');
  console.log('   3. Tap menu (⋮) → "Change Address"');
  console.log('   4. Submit address change request');
  console.log('   5. Track status in "My Address Requests"');
  console.log('\n🔄 Next: Restart backend and Flutter app to use the feature');
} else {
  console.log('❌ SOME CHECKS FAILED - Review the issues above');
  console.log('='.repeat(80));
  console.log('\n🔧 Fix the missing components and run this test again');
}
console.log('='.repeat(80) + '\n');
