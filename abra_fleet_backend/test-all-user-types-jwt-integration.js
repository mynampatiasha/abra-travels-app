// test-all-user-types-jwt-integration.js - Test JWT Integration for All User Types
const { MongoClient } = require('mongodb');
const axios = require('axios');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI;
const BASE_URL = process.env.BASE_URL || 'http://localhost:3001';

async function testAllUserTypesJWTIntegration() {
  console.log('\n🧪 TESTING JWT INTEGRATION FOR ALL USER TYPES');
  console.log('═'.repeat(80));
  
  let client;
  
  try {
    // Connect to MongoDB
    console.log('📡 Connecting to MongoDB...');
    client = new MongoClient(MONGODB_URI);
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('✅ Connected to MongoDB');
    console.log('─'.repeat(80));
    
    // ========================================================================
    // STEP 1: Check Current User Types and Their ID Fields
    // ========================================================================
    console.log('\n📂 STEP 1: ANALYZING USER TYPES AND ID FIELDS');
    console.log('─'.repeat(40));
    
    const userTypes = [
      { 
        collection: 'drivers', 
        role: 'driver', 
        idField: 'driverId',
        expectedFormat: /^DRV-\d{6}$/
      },
      { 
        collection: 'customers', 
        role: 'customer', 
        idField: 'customerId',
        expectedFormat: /^CUST-\d{6}$/
      },
      { 
        collection: 'clients', 
        role: 'client', 
        idField: 'clientId',
        expectedFormat: /^CLI-\d{6}$/
      },
      { 
        collection: 'employee_admins', 
        role: 'employee', 
        idField: 'employeeId',
        expectedFormat: /^EMP-\d{6}$/
      },
      { 
        collection: 'admin_users', 
        role: 'admin', 
        idField: null, // Admins don't need specific IDs
        expectedFormat: null
      }
    ];
    
    const userAnalysis = [];
    
    for (const userType of userTypes) {
      console.log(`\n   📋 Analyzing ${userType.collection}:`);
      
      const users = await db.collection(userType.collection).find({}).limit(5).toArray();
      console.log(`      Total users: ${users.length}`);
      
      if (users.length > 0) {
        const sampleUser = users[0];
        const hasIdField = userType.idField && sampleUser[userType.idField];
        const idValue = hasIdField ? sampleUser[userType.idField] : 'N/A';
        const matchesFormat = hasIdField && userType.expectedFormat ? 
          userType.expectedFormat.test(idValue) : 'N/A';
        
        console.log(`      Sample user ID: ${sampleUser._id}`);
        console.log(`      ${userType.idField || 'No ID field'}: ${idValue}`);
        console.log(`      Format match: ${matchesFormat}`);
        console.log(`      Email: ${sampleUser.email || 'N/A'}`);
        console.log(`      Name: ${sampleUser.name || sampleUser.personalInfo?.firstName || 'N/A'}`);
        
        // Count users with proper ID format
        let usersWithProperIds = 0;
        let usersWithoutIds = 0;
        
        if (userType.idField) {
          for (const user of users) {
            if (user[userType.idField] && userType.expectedFormat.test(user[userType.idField])) {
              usersWithProperIds++;
            } else {
              usersWithoutIds++;
            }
          }
          
          console.log(`      Users with proper ${userType.idField}: ${usersWithProperIds}`);
          console.log(`      Users without proper ${userType.idField}: ${usersWithoutIds}`);
        }
        
        userAnalysis.push({
          ...userType,
          totalUsers: users.length,
          sampleUser: sampleUser,
          usersWithProperIds,
          usersWithoutIds,
          needsIdGeneration: usersWithoutIds > 0
        });
      } else {
        console.log(`      ⚠️  No users found in ${userType.collection}`);
        userAnalysis.push({
          ...userType,
          totalUsers: 0,
          needsIdGeneration: false
        });
      }
    }
    
    // ========================================================================
    // STEP 2: Generate Missing IDs for User Types
    // ========================================================================
    console.log('\n\n🔧 STEP 2: GENERATING MISSING USER IDs');
    console.log('─'.repeat(40));
    
    for (const analysis of userAnalysis) {
      if (analysis.needsIdGeneration && analysis.idField) {
        console.log(`\n   Generating ${analysis.idField}s for ${analysis.collection}...`);
        
        // Get users without proper IDs
        const usersWithoutIds = await db.collection(analysis.collection).find({
          $or: [
            { [analysis.idField]: { $exists: false } },
            { [analysis.idField]: null },
            { [analysis.idField]: '' },
            { [analysis.idField]: { $not: analysis.expectedFormat } }
          ]
        }).toArray();
        
        console.log(`   Found ${usersWithoutIds.length} users needing ${analysis.idField}`);
        
        if (usersWithoutIds.length > 0) {
          // Get the highest existing ID number
          const existingUsers = await db.collection(analysis.collection).find({
            [analysis.idField]: analysis.expectedFormat
          }).toArray();
          
          let maxNumber = 100000; // Starting number
          const prefix = analysis.idField.replace('Id', '').toUpperCase();
          
          existingUsers.forEach(user => {
            const idValue = user[analysis.idField];
            const match = idValue.match(new RegExp(`^${prefix.substring(0, 3)}-(\d{6})$`));
            if (match) {
              const number = parseInt(match[1]);
              if (number > maxNumber) {
                maxNumber = number;
              }
            }
          });
          
          console.log(`   Next available ${analysis.idField} number: ${maxNumber + 1}`);
          
          // Generate IDs for users without them
          for (let i = 0; i < usersWithoutIds.length; i++) {
            const user = usersWithoutIds[i];
            const newId = `${prefix.substring(0, 3)}-${String(maxNumber + 1 + i).padStart(6, '0')}`;
            
            console.log(`   Assigning ${newId} to user ${user._id}`);
            
            await db.collection(analysis.collection).updateOne(
              { _id: user._id },
              { 
                $set: { 
                  [analysis.idField]: newId,
                  updatedAt: new Date()
                } 
              }
            );
          }
          
          console.log(`   ✅ Generated ${usersWithoutIds.length} ${analysis.idField}s`);
        }
      }
    }
    
    // ========================================================================
    // STEP 3: Setup Test Users with Known Passwords
    // ========================================================================
    console.log('\n\n🔑 STEP 3: SETTING UP TEST USERS');
    console.log('─'.repeat(40));
    
    const bcrypt = require('bcryptjs');
    const testPassword = 'password123';
    const hashedPassword = await bcrypt.hash(testPassword, 12);
    
    const testUsers = [
      {
        collection: 'drivers',
        email: 'testdriver@abrafleet.com',
        name: 'Test Driver',
        role: 'driver',
        idField: 'driverId'
      },
      {
        collection: 'customers',
        email: 'testcustomer@abrafleet.com',
        name: 'Test Customer',
        role: 'customer',
        idField: 'customerId'
      },
      {
        collection: 'clients',
        email: 'testclient@abrafleet.com',
        name: 'Test Client',
        role: 'client',
        idField: 'clientId'
      },
      {
        collection: 'employee_admins',
        email: 'testemployee@abrafleet.com',
        name: 'Test Employee',
        role: 'employee',
        idField: 'employeeId'
      },
      {
        collection: 'admin_users',
        email: 'testadmin@abrafleet.com',
        name: 'Test Admin',
        role: 'admin',
        idField: null
      }
    ];
    
    const createdTestUsers = [];
    
    for (const testUser of testUsers) {
      console.log(`\n   Setting up test user: ${testUser.email}`);
      
      // Check if user already exists
      const existingUser = await db.collection(testUser.collection).findOne({
        email: testUser.email
      });
      
      if (existingUser) {
        console.log(`   User already exists, updating password...`);
        
        const updateData = {
          password: hashedPassword,
          name: testUser.name,
          role: testUser.role,
          status: 'active',
          isActive: true,
          updatedAt: new Date()
        };
        
        await db.collection(testUser.collection).updateOne(
          { _id: existingUser._id },
          { $set: updateData }
        );
        
        createdTestUsers.push({
          ...testUser,
          userId: existingUser._id,
          specificId: existingUser[testUser.idField] || null
        });
      } else {
        console.log(`   Creating new test user...`);
        
        // Generate specific ID if needed
        let specificId = null;
        if (testUser.idField) {
          const prefix = testUser.idField.replace('Id', '').toUpperCase().substring(0, 3);
          const existingIds = await db.collection(testUser.collection).find({
            [testUser.idField]: new RegExp(`^${prefix}-\\d{6}$`)
          }).toArray();
          
          let maxNumber = 100000;
          existingIds.forEach(user => {
            const match = user[testUser.idField].match(new RegExp(`^${prefix}-(\\d{6})$`));
            if (match) {
              const number = parseInt(match[1]);
              if (number > maxNumber) {
                maxNumber = number;
              }
            }
          });
          
          specificId = `${prefix}-${String(maxNumber + 1).padStart(6, '0')}`;
        }
        
        const newUser = {
          email: testUser.email,
          password: hashedPassword,
          name: testUser.name,
          role: testUser.role,
          status: 'active',
          isActive: true,
          modules: [],
          permissions: {},
          createdAt: new Date(),
          updatedAt: new Date()
        };
        
        if (specificId) {
          newUser[testUser.idField] = specificId;
        }
        
        const result = await db.collection(testUser.collection).insertOne(newUser);
        
        console.log(`   ✅ Created user with ID: ${result.insertedId}`);
        if (specificId) {
          console.log(`   ${testUser.idField}: ${specificId}`);
        }
        
        createdTestUsers.push({
          ...testUser,
          userId: result.insertedId,
          specificId: specificId
        });
      }
    }
    
    // ========================================================================
    // STEP 4: Test JWT Login for All User Types
    // ========================================================================
    console.log('\n\n🔐 STEP 4: TESTING JWT LOGIN FOR ALL USER TYPES');
    console.log('─'.repeat(40));
    
    const loginResults = [];
    
    for (const testUser of createdTestUsers) {
      console.log(`\n   Testing login for ${testUser.role}: ${testUser.email}`);
      
      try {
        const loginResponse = await axios.post(`${BASE_URL}/api/auth/login`, {
          email: testUser.email,
          password: testPassword
        });
        
        if (loginResponse.data.success) {
          const token = loginResponse.data.data.token;
          const user = loginResponse.data.data.user;
          
          console.log(`   ✅ Login successful`);
          console.log(`   User ID: ${user.id}`);
          console.log(`   Role: ${user.role}`);
          
          if (testUser.idField) {
            const specificIdInResponse = user[testUser.idField];
            console.log(`   ${testUser.idField}: ${specificIdInResponse || 'NOT INCLUDED'}`);
            
            if (specificIdInResponse) {
              console.log(`   ✅ ${testUser.idField} included in response`);
            } else {
              console.log(`   ❌ ${testUser.idField} missing from response`);
            }
          }
          
          // Decode JWT token to check payload
          const tokenParts = token.split('.');
          if (tokenParts.length === 3) {
            const payload = JSON.parse(Buffer.from(tokenParts[1], 'base64').toString());
            console.log(`   Token payload includes:`);
            console.log(`     - userId: ${!!payload.userId}`);
            console.log(`     - email: ${!!payload.email}`);
            console.log(`     - role: ${payload.role}`);
            
            if (testUser.idField) {
              const specificIdInToken = payload[testUser.idField];
              console.log(`     - ${testUser.idField}: ${specificIdInToken || 'NOT INCLUDED'}`);
              
              if (specificIdInToken) {
                console.log(`   ✅ ${testUser.idField} included in JWT token`);
              } else {
                console.log(`   ❌ ${testUser.idField} missing from JWT token`);
              }
            }
          }
          
          loginResults.push({
            ...testUser,
            loginSuccess: true,
            token: token,
            user: user,
            hasSpecificIdInResponse: testUser.idField ? !!user[testUser.idField] : true,
            hasSpecificIdInToken: testUser.idField ? !!JSON.parse(Buffer.from(token.split('.')[1], 'base64').toString())[testUser.idField] : true
          });
        } else {
          console.log(`   ❌ Login failed: ${loginResponse.data.message}`);
          loginResults.push({
            ...testUser,
            loginSuccess: false,
            error: loginResponse.data.message
          });
        }
      } catch (error) {
        console.log(`   ❌ Login request failed: ${error.response?.data?.message || error.message}`);
        loginResults.push({
          ...testUser,
          loginSuccess: false,
          error: error.response?.data?.message || error.message
        });
      }
    }
    
    // ========================================================================
    // STEP 5: Summary and Recommendations
    // ========================================================================
    console.log('\n\n📊 SUMMARY AND RECOMMENDATIONS');
    console.log('═'.repeat(80));
    
    console.log('🔍 USER TYPE ANALYSIS:');
    loginResults.forEach(result => {
      console.log(`\n   ${result.role.toUpperCase()} (${result.collection}):`);
      console.log(`     Login: ${result.loginSuccess ? '✅ SUCCESS' : '❌ FAILED'}`);
      
      if (result.loginSuccess) {
        if (result.idField) {
          console.log(`     ${result.idField} in response: ${result.hasSpecificIdInResponse ? '✅ YES' : '❌ NO'}`);
          console.log(`     ${result.idField} in JWT token: ${result.hasSpecificIdInToken ? '✅ YES' : '❌ NO'}`);
        } else {
          console.log(`     No specific ID required: ✅ CORRECT`);
        }
      } else {
        console.log(`     Error: ${result.error}`);
      }
    });
    
    console.log('\n💡 RECOMMENDATIONS:');
    
    const needsJWTUpdate = loginResults.some(result => 
      result.loginSuccess && result.idField && (!result.hasSpecificIdInResponse || !result.hasSpecificIdInToken)
    );
    
    if (needsJWTUpdate) {
      console.log('   1. Update JWT router to include specific IDs for all user types');
      console.log('   2. Ensure generateToken() includes customerId, clientId, employeeId');
      console.log('   3. Update verifyJWT middleware to include all specific IDs');
      console.log('   4. Update login/register responses to include specific IDs');
    } else {
      console.log('   ✅ All user types have proper JWT integration');
    }
    
    console.log('\n🎯 TEST CREDENTIALS FOR FRONTEND:');
    createdTestUsers.forEach(user => {
      console.log(`   ${user.role.toUpperCase()}:`);
      console.log(`     Email: ${user.email}`);
      console.log(`     Password: ${testPassword}`);
      if (user.specificId) {
        console.log(`     ${user.idField}: ${user.specificId}`);
      }
      console.log('');
    });
    
    console.log('═'.repeat(80));
    
  } catch (error) {
    console.error('\n❌ ERROR TESTING ALL USER TYPES JWT INTEGRATION');
    console.error('═'.repeat(80));
    console.error('Error:', error.message);
    console.error('Stack:', error.stack);
  } finally {
    if (client) {
      await client.close();
      console.log('📡 MongoDB connection closed');
    }
  }
}

// Run the test
if (require.main === module) {
  testAllUserTypesJWTIntegration().catch(console.error);
}

module.exports = { testAllUserTypesJWTIntegration };