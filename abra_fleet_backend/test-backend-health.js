/**
 * Quick Backend Health Test
 * Tests basic functionality without starting the full server
 */

const path = require('path');

console.log('🔍 Testing Backend Health...\n');

// Test 1: Environment Variables
console.log('1️⃣ Testing Environment Variables...');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const requiredVars = ['MONGODB_URI', 'FIREBASE_PROJECT_ID'];
let envOk = true;

for (const varName of requiredVars) {
  const value = process.env[varName];
  if (!value) {
    console.log(`❌ ${varName}: NOT SET`);
    envOk = false;
  } else {
    console.log(`✅ ${varName}: SET`);
  }
}

if (!envOk) {
  console.log('\n❌ Environment test FAILED');
  process.exit(1);
}

// Test 2: MongoDB Connection
console.log('\n2️⃣ Testing MongoDB Connection...');
const { MongoClient } = require('mongodb');

async function testMongoDB() {
  try {
    const client = new MongoClient(process.env.MONGODB_URI);
    await client.connect();
    await client.db('abra_fleet').admin().ping();
    console.log('✅ MongoDB connection: SUCCESS');
    await client.close();
    return true;
  } catch (error) {
    console.log('❌ MongoDB connection: FAILED');
    console.log('   Error:', error.message);
    return false;
  }
}

// Test 3: Firebase Configuration
console.log('\n3️⃣ Testing Firebase Configuration...');
const fs = require('fs');

function testFirebase() {
  const serviceAccountPath = path.join(__dirname, 'serviceAccountKey.json');
  
  if (!fs.existsSync(serviceAccountPath)) {
    console.log('❌ Firebase service account: NOT FOUND');
    return false;
  }
  
  try {
    const serviceAccount = require(serviceAccountPath);
    if (!serviceAccount.project_id || !serviceAccount.private_key) {
      console.log('❌ Firebase service account: INVALID FORMAT');
      return false;
    }
    console.log('✅ Firebase service account: VALID');
    return true;
  } catch (error) {
    console.log('❌ Firebase service account: PARSE ERROR');
    console.log('   Error:', error.message);
    return false;
  }
}

// Test 4: Null Safety Utils
console.log('\n4️⃣ Testing Null Safety Utils...');
function testNullSafety() {
  try {
    const { safeGet, safeString, validateRequired } = require('./utils/null-safety');
    
    // Test safeGet
    const testObj = { user: { name: 'John' } };
    const name = safeGet(testObj, 'user.name', 'Unknown');
    const missing = safeGet(testObj, 'user.age', 25);
    
    if (name !== 'John' || missing !== 25) {
      console.log('❌ Null safety utils: FAILED');
      return false;
    }
    
    console.log('✅ Null safety utils: WORKING');
    return true;
  } catch (error) {
    console.log('❌ Null safety utils: ERROR');
    console.log('   Error:', error.message);
    return false;
  }
}

// Run all tests
async function runTests() {
  console.log('\n' + '='.repeat(50));
  console.log('RUNNING HEALTH TESTS');
  console.log('='.repeat(50));
  
  const mongoOk = await testMongoDB();
  const firebaseOk = testFirebase();
  const nullSafetyOk = testNullSafety();
  
  console.log('\n' + '='.repeat(50));
  console.log('TEST RESULTS');
  console.log('='.repeat(50));
  console.log('Environment Variables:', envOk ? '✅ PASS' : '❌ FAIL');
  console.log('MongoDB Connection:', mongoOk ? '✅ PASS' : '❌ FAIL');
  console.log('Firebase Config:', firebaseOk ? '✅ PASS' : '❌ FAIL');
  console.log('Null Safety Utils:', nullSafetyOk ? '✅ PASS' : '❌ FAIL');
  
  const allPassed = envOk && mongoOk && firebaseOk && nullSafetyOk;
  
  console.log('\n' + '='.repeat(50));
  if (allPassed) {
    console.log('🎉 ALL TESTS PASSED - Backend is ready!');
    console.log('You can now start the server with: npm start');
  } else {
    console.log('❌ SOME TESTS FAILED - Please fix the issues above');
  }
  console.log('='.repeat(50));
  
  process.exit(allPassed ? 0 : 1);
}

runTests().catch(error => {
  console.error('\n💥 Test runner crashed:', error.message);
  process.exit(1);
});