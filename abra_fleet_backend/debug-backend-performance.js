// Debug script to check backend performance and identify slow endpoints
const axios = require('axios');
require('dotenv').config();

const BASE_URL = process.env.API_BASE_URL || 'http://localhost:3001';

async function debugBackendPerformance() {
  console.log('\n🔍 DEBUGGING BACKEND PERFORMANCE ISSUES');
  console.log('='.repeat(60));
  
  // Test endpoints that are timing out
  const endpoints = [
    { name: 'Health Check', url: '/api/health', method: 'GET' },
    { name: 'Vehicles (limit 10)', url: '/api/admin/vehicles?page=1&limit=10', method: 'GET' },
    { name: 'Drivers (limit 10)', url: '/api/admin/drivers?page=1&limit=10', method: 'GET' },
    { name: 'GPS Devices (limit 5)', url: '/api/gps/devices?page=1&limit=5', method: 'GET' },
    { name: 'Pending Rosters (limit 5)', url: '/api/roster/pending?page=1&limit=5', method: 'GET' },
    { name: 'Roster Stats', url: '/api/roster/admin/stats', method: 'GET' }
  ];
  
  // Get admin token first
  let token = null;
  try {
    console.log('🔐 Getting admin token...');
    const loginResponse = await axios.post(`${BASE_URL}/api/auth/login`, {
      email: 'admin@abrafleet.com',
      password: 'admin123'
    }, { timeout: 10000 });
    
    token = loginResponse.data.token;
    console.log('✅ Admin token obtained');
  } catch (error) {
    console.log('❌ Failed to get admin token:', error.message);
    console.log('   Testing without authentication...');
  }
  
  console.log('\n📊 TESTING ENDPOINT PERFORMANCE:');
  console.log('-'.repeat(60));
  
  for (const endpoint of endpoints) {
    try {
      console.log(`\n🧪 Testing: ${endpoint.name}`);
      console.log(`   URL: ${BASE_URL}${endpoint.url}`);
      
      const startTime = Date.now();
      
      const config = {
        timeout: 15000, // 15 second timeout
        headers: {}
      };
      
      if (token) {
        config.headers.Authorization = `Bearer ${token}`;
      }
      
      const response = await axios({
        method: endpoint.method,
        url: `${BASE_URL}${endpoint.url}`,
        ...config
      });
      
      const endTime = Date.now();
      const duration = endTime - startTime;
      
      console.log(`   ✅ SUCCESS: ${response.status} (${duration}ms)`);
      
      if (duration > 5000) {
        console.log(`   ⚠️  SLOW: Response took ${duration}ms (>5s)`);
      }
      
      if (response.data && response.data.data) {
        const dataLength = Array.isArray(response.data.data) ? response.data.data.length : 'N/A';
        console.log(`   📊 Data count: ${dataLength}`);
      }
      
    } catch (error) {
      const duration = Date.now() - Date.now();
      
      if (error.code === 'ECONNABORTED') {
        console.log(`   ❌ TIMEOUT: Request timed out after 15s`);
      } else if (error.response) {
        console.log(`   ❌ ERROR: ${error.response.status} - ${error.response.statusText}`);
      } else {
        console.log(`   ❌ ERROR: ${error.message}`);
      }
    }
  }
  
  // Test the specific group-similar endpoint that's failing
  console.log('\n🎯 TESTING PROBLEMATIC ENDPOINT:');
  console.log('-'.repeat(60));
  
  try {
    console.log('\n🧪 Testing: Smart Grouping (group-similar)');
    console.log(`   URL: ${BASE_URL}/api/roster/admin/group-similar`);
    
    const startTime = Date.now();
    
    // Test with minimal data
    const testPayload = {
      rosters: [
        { _id: '694a8a867dad313c6ad8b998', customerName: 'Test Customer' }
      ]
    };
    
    const response = await axios.post(
      `${BASE_URL}/api/roster/admin/group-similar`,
      testPayload,
      {
        timeout: 15000,
        headers: token ? { Authorization: `Bearer ${token}` } : {}
      }
    );
    
    const endTime = Date.now();
    const duration = endTime - startTime;
    
    console.log(`   ✅ SUCCESS: ${response.status} (${duration}ms)`);
    
  } catch (error) {
    if (error.code === 'ECONNABORTED') {
      console.log(`   ❌ TIMEOUT: Smart grouping timed out after 15s`);
      console.log(`   💡 This endpoint needs optimization`);
    } else if (error.response) {
      console.log(`   ❌ ERROR: ${error.response.status} - ${error.response.data?.message || error.response.statusText}`);
    } else {
      console.log(`   ❌ ERROR: ${error.message}`);
    }
  }
  
  console.log('\n💡 PERFORMANCE ANALYSIS:');
  console.log('-'.repeat(60));
  console.log('If you see timeouts or slow responses (>5s):');
  console.log('1. Check MongoDB performance');
  console.log('2. Check for missing database indexes');
  console.log('3. Optimize slow queries');
  console.log('4. Consider pagination limits');
  console.log('5. Check server resources (CPU/Memory)');
  
}

debugBackendPerformance();