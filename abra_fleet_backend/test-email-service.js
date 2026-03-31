// Test email service configuration
require('dotenv').config();
const emailService = require('./services/email_service');

async function testEmailService() {
  console.log('\n🧪 TESTING EMAIL SERVICE');
  console.log('═'.repeat(80));
  
  try {
    // Initialize email service
    console.log('1️⃣ Initializing email service...');
    const initialized = emailService.initialize();
    
    if (!initialized) {
      console.log('❌ Email service initialization failed');
      console.log('   Check your SMTP credentials in .env file');
      return;
    }
    
    console.log('✅ Email service initialized successfully');
    
    // Verify connection
    console.log('\n2️⃣ Verifying SMTP connection...');
    const verified = await emailService.verifyConnection();
    
    if (!verified) {
      console.log('❌ SMTP connection verification failed');
      console.log('   Check your SMTP credentials and network connection');
      return;
    }
    
    console.log('✅ SMTP connection verified successfully');
    
    // Send test email
    console.log('\n3️⃣ Sending test email...');
    const testEmail = 'chandrika123@abrafleet.com'; // Use the test user email
    
    const result = await emailService.sendCustomerApprovalEmail({
      email: testEmail,
      name: 'Chandrika Test User',
      companyName: 'Abra Travels',
      passwordResetLink: null // No password reset needed for existing users
    });
    
    if (result.success) {
      console.log('✅ Test email sent successfully!');
      console.log('   Message ID:', result.messageId);
      console.log('   Recipient:', testEmail);
    } else {
      console.log('❌ Test email failed:', result.error);
    }
    
    console.log('\n🎉 EMAIL SERVICE TEST COMPLETE');
    console.log('═'.repeat(80));
    
  } catch (error) {
    console.error('❌ Email service test failed:', error.message);
    console.error('   Full error:', error);
  }
}

// Run the test
testEmailService().then(() => {
  console.log('\n✅ Email service test completed');
  process.exit(0);
}).catch((error) => {
  console.error('❌ Email service test error:', error);
  process.exit(1);
});