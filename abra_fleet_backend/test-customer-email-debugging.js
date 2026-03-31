// test-customer-email-debugging.js
// Test script to verify email debugging for customer creation

const admin = require('firebase-admin');
const emailService = require('./services/email_service');

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  const serviceAccount = require('./serviceAccountKey.json');
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

async function testEmailDebugging() {
  console.log('\n' + '='.repeat(80));
  console.log('🧪 TESTING EMAIL DEBUGGING FOR CUSTOMER CREATION');
  console.log('='.repeat(80));
  console.log('This script tests the email debugging system');
  console.log('='.repeat(80) + '\n');

  // Test 1: Check if email service is initialized
  console.log('TEST 1: Email Service Initialization');
  console.log('-'.repeat(80));
  
  const isInitialized = emailService.initialize();
  
  if (isInitialized) {
    console.log('✅ Email service initialized successfully');
  } else {
    console.log('❌ Email service failed to initialize');
    console.log('⚠️  Check your .env file for SMTP credentials');
    return;
  }
  
  // Test 2: Verify email connection
  console.log('\nTEST 2: Email Server Connection');
  console.log('-'.repeat(80));
  
  const isConnected = await emailService.verifyConnection();
  
  if (isConnected) {
    console.log('✅ Email server connection verified');
  } else {
    console.log('❌ Email server connection failed');
    console.log('⚠️  Check your SMTP credentials and network connection');
    return;
  }
  
  // Test 3: Generate password reset link
  console.log('\nTEST 3: Password Reset Link Generation');
  console.log('-'.repeat(80));
  
  const testEmail = 'test@example.com'; // Change this to a real email for testing
  
  try {
    // First, check if user exists, if not create a test user
    let userRecord;
    try {
      userRecord = await admin.auth().getUserByEmail(testEmail);
      console.log('✅ Test user already exists:', testEmail);
    } catch (error) {
      if (error.code === 'auth/user-not-found') {
        console.log('⚠️  Test user not found, creating...');
        userRecord = await admin.auth().createUser({
          email: testEmail,
          password: 'TestPassword123!',
          displayName: 'Test User',
        });
        console.log('✅ Test user created:', testEmail);
      } else {
        throw error;
      }
    }
    
    const passwordResetLink = await admin.auth().generatePasswordResetLink(testEmail);
    console.log('✅ Password reset link generated successfully');
    console.log('   Link length:', passwordResetLink.length, 'characters');
    console.log('   Link preview:', passwordResetLink.substring(0, 60) + '...');
    
    // Test 4: Send test email
    console.log('\nTEST 4: Send Welcome Email');
    console.log('-'.repeat(80));
    console.log('⚠️  This will send a REAL email to:', testEmail);
    console.log('   Make sure this is a valid email address you can access');
    console.log('   Press Ctrl+C to cancel if needed');
    console.log('-'.repeat(80));
    
    // Wait 3 seconds to allow cancellation
    await new Promise(resolve => setTimeout(resolve, 3000));
    
    const emailResult = await emailService.sendCustomerApprovalEmail({
      email: testEmail,
      name: 'Test User',
      companyName: 'Test Company',
      passwordResetLink: passwordResetLink,
    });
    
    if (emailResult.success) {
      console.log('\n' + '='.repeat(80));
      console.log('✅ ALL TESTS PASSED!');
      console.log('='.repeat(80));
      console.log('Email debugging is working correctly');
      console.log('Message ID:', emailResult.messageId);
      console.log('Check the email inbox for:', testEmail);
      console.log('='.repeat(80) + '\n');
    } else {
      console.log('\n' + '='.repeat(80));
      console.log('❌ EMAIL SENDING FAILED');
      console.log('='.repeat(80));
      console.log('Error:', emailResult.error);
      console.log('='.repeat(80) + '\n');
    }
    
  } catch (error) {
    console.log('\n' + '='.repeat(80));
    console.log('❌ TEST FAILED');
    console.log('='.repeat(80));
    console.log('Error:', error.message);
    console.log('Code:', error.code);
    console.log('='.repeat(80) + '\n');
  }
}

// Run the test
testEmailDebugging()
  .then(() => {
    console.log('Test completed');
    process.exit(0);
  })
  .catch((error) => {
    console.error('Test failed with error:', error);
    process.exit(1);
  });
