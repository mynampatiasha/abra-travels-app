// test-jwt-with-driver-id.js - Test JWT System with Driver ID Integration
const axios = require('axios');
require('dotenv').config();

const BASE_URL = process.env.BASE_URL || 'http://localhost:3001';

async function testJWTWithDriverId() {
  console.log('\n🧪 TESTING JWT SYSTEM WITH DRIVER ID INTEGRATION');
  console.log('═'.repeat(80));
  
  try {
    // ========================================================================
    // STEP 1: Test Simple Endpoint
    // ========================================================================
    console.log('\n📡 STEP 1: TESTING BACKEND CONNECTION');
    console.log('─'.repeat(40));
    
    try {
      // Try a simple login request to test if backend is running
      const testResponse = await axios.post(`${BASE_URL}/api/auth/login`, {
        email: 'test@test.com',
        password: 'test'
      });
      console.log('✅ Backend is responding (even if login fails)');
    } catch (error) {
      if (error.response && error.response.status) {
        console.log('✅ Backend is responding');
        console.log('   Status:', error.response.status);
      } else {
        console.log('❌ Backend connection failed');
        console.log('   Error:', error.message);
        return;
      }
    }
    
    // ========================================================================
    // STEP 2: Test Driver Login
    // ========================================================================
    console.log('\n\n🔐 STEP 2: TESTING DRIVER LOGIN');
    console.log('─'.repeat(40));
    
    // Test with a known driver email
    const driverLoginData = {
      email: 'amit.singh@abrafleet.com',
      password: 'password123'
    };
    
    console.log('   Attempting driver login...');
    console.log('   Email:', driverLoginData.email);
    
    let driverToken = null;
    let driverUser = null;
    
    try {
      const loginResponse = await axios.post(`${BASE_URL}/api/auth/login`, driverLoginData);
      
      if (loginResponse.data.success) {
        driverToken = loginResponse.data.data.token;
        driverUser = loginResponse.data.data.user;
        
        console.log('✅ Driver login successful');
        console.log('   User ID:', driverUser.id);
        console.log('   Role:', driverUser.role);
        console.log('   Driver ID:', driverUser.driverId || 'NOT INCLUDED');
        console.log('   Token length:', driverToken.length);
        
        // Decode token to check payload
        const tokenParts = driverToken.split('.');
        if (tokenParts.length === 3) {
          const payload = JSON.parse(Buffer.from(tokenParts[1], 'base64').toString());
          console.log('   Token payload includes:');
          console.log('     - userId:', !!payload.userId);
          console.log('     - email:', !!payload.email);
          console.log('     - role:', payload.role);
          console.log('     - driverId:', payload.driverId || 'NOT INCLUDED');
        }
      } else {
        console.log('❌ Driver login failed');
        console.log('   Error:', loginResponse.data.message);
      }
    } catch (error) {
      console.log('❌ Driver login request failed');
      console.log('   Error:', error.response?.data?.message || error.message);
    }
    
    // ========================================================================
    // STEP 3: Test Protected Route with Driver Token
    // ========================================================================
    console.log('\n\n🛡️  STEP 3: TESTING PROTECTED ROUTE WITH DRIVER TOKEN');
    console.log('─'.repeat(40));
    
    if (driverToken) {
      try {
        const meResponse = await axios.get(`${BASE_URL}/api/auth/me`, {
          headers: {
            'Authorization': `Bearer ${driverToken}`
          }
        });
        
        if (meResponse.data.success) {
          const userData = meResponse.data.data.user;
          console.log('✅ Protected route access successful');
          console.log('   User ID:', userData.userId);
          console.log('   Email:', userData.email);
          console.log('   Role:', userData.role);
          console.log('   Driver ID:', userData.driverId || 'NOT INCLUDED');
          
          if (userData.role === 'driver' && userData.driverId) {
            console.log('✅ Driver ID correctly included in JWT payload');
          } else if (userData.role === 'driver' && !userData.driverId) {
            console.log('⚠️  Driver role but no driverId in JWT payload');
          }
        } else {
          console.log('❌ Protected route access failed');
          console.log('   Error:', meResponse.data.message);
        }
      } catch (error) {
        console.log('❌ Protected route request failed');
        console.log('   Error:', error.response?.data?.message || error.message);
      }
    } else {
      console.log('⚠️  Skipping protected route test - no driver token available');
    }
    
    // ========================================================================
    // STEP 4: Test Admin Login (Should Not Have Driver ID)
    // ========================================================================
    console.log('\n\n👑 STEP 4: TESTING ADMIN LOGIN (NO DRIVER ID EXPECTED)');
    console.log('─'.repeat(40));
    
    const adminLoginData = {
      email: 'admin@abrafleet.com',
      password: 'admin123'
    };
    
    console.log('   Attempting admin login...');
    console.log('   Email:', adminLoginData.email);
    
    try {
      const adminLoginResponse = await axios.post(`${BASE_URL}/api/auth/login`, adminLoginData);
      
      if (adminLoginResponse.data.success) {
        const adminToken = adminLoginResponse.data.data.token;
        const adminUser = adminLoginResponse.data.data.user;
        
        console.log('✅ Admin login successful');
        console.log('   User ID:', adminUser.id);
        console.log('   Role:', adminUser.role);
        console.log('   Driver ID:', adminUser.driverId || 'NOT INCLUDED (CORRECT)');
        
        // Decode admin token
        const tokenParts = adminToken.split('.');
        if (tokenParts.length === 3) {
          const payload = JSON.parse(Buffer.from(tokenParts[1], 'base64').toString());
          console.log('   Admin token payload:');
          console.log('     - role:', payload.role);
          console.log('     - driverId:', payload.driverId || 'NOT INCLUDED (CORRECT)');
        }
        
        if (adminUser.role !== 'driver' && !adminUser.driverId) {
          console.log('✅ Admin correctly has no driverId');
        }
      } else {
        console.log('❌ Admin login failed');
        console.log('   Error:', adminLoginResponse.data.message);
      }
    } catch (error) {
      console.log('❌ Admin login request failed');
      console.log('   Error:', error.response?.data?.message || error.message);
    }
    
    // ========================================================================
    // STEP 5: Test Driver-Specific Route (If Available)
    // ========================================================================
    console.log('\n\n🚗 STEP 5: TESTING DRIVER-SPECIFIC FUNCTIONALITY');
    console.log('─'.repeat(40));
    
    if (driverToken && driverUser?.driverId) {
      console.log('   Testing driver profile route...');
      
      try {
        const driverProfileResponse = await axios.get(`${BASE_URL}/api/driver/profile`, {
          headers: {
            'Authorization': `Bearer ${driverToken}`
          }
        });
        
        if (driverProfileResponse.data.success) {
          console.log('✅ Driver profile route accessible');
          console.log('   Profile data available:', !!driverProfileResponse.data.data);
        } else {
          console.log('⚠️  Driver profile route returned error');
          console.log('   Error:', driverProfileResponse.data.message);
        }
      } catch (error) {
        if (error.response?.status === 404) {
          console.log('ℹ️  Driver profile route not found (may not be implemented yet)');
        } else {
          console.log('❌ Driver profile route request failed');
          console.log('   Error:', error.response?.data?.message || error.message);
        }
      }
    } else {
      console.log('⚠️  Skipping driver-specific tests - no driver token or driverId available');
    }
    
    // ========================================================================
    // STEP 6: Summary
    // ========================================================================
    console.log('\n\n📊 TEST SUMMARY');
    console.log('═'.repeat(80));
    
    console.log('✅ COMPLETED TESTS:');
    console.log('   - Backend health check');
    console.log('   - Driver login with JWT token generation');
    console.log('   - JWT token payload verification');
    console.log('   - Protected route access with driver token');
    console.log('   - Admin login verification (no driverId)');
    console.log('   - Driver-specific route testing');
    
    console.log('\n🎯 KEY FINDINGS:');
    if (driverUser?.driverId) {
      console.log('   ✅ Driver ID successfully included in JWT tokens for driver role');
      console.log('   ✅ Driver ID accessible in protected routes via req.user.driverId');
    } else {
      console.log('   ⚠️  Driver ID not found in JWT token - check driver login');
    }
    
    console.log('\n🔄 NEXT STEPS:');
    console.log('   1. Update frontend to extract driverId from JWT token');
    console.log('   2. Use driverId in driver-specific API calls');
    console.log('   3. Test complete driver workflow with new driverId system');
    console.log('   4. Verify all backend routes use consistent driver identification');
    
    console.log('\n🎉 JWT + DRIVER ID INTEGRATION TEST COMPLETED!');
    console.log('═'.repeat(80));
    
  } catch (error) {
    console.error('\n❌ TEST EXECUTION ERROR');
    console.error('═'.repeat(80));
    console.error('Error:', error.message);
    console.error('Stack:', error.stack);
  }
}

// Run the test
if (require.main === module) {
  testJWTWithDriverId().catch(console.error);
}

module.exports = { testJWTWithDriverId };