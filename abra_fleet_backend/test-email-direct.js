// Direct test of email service
const emailService = require('./services/email_service');

async function testEmailDirect() {
  console.log('\n🧪 ========== TESTING EMAIL SERVICE DIRECTLY ==========\n');
  
  try {
    // Initialize email service
    console.log('1️⃣ Initializing email service...');
    const initialized = emailService.initialize();
    
    if (!initialized) {
      console.error('❌ Email service not initialized');
      console.error('   Check SMTP credentials in .env file');
      return;
    }
    
    console.log('✅ Email service initialized');
    
    // Verify connection
    console.log('\n2️⃣ Verifying SMTP connection...');
    const verified = await emailService.verifyConnection();
    
    if (!verified) {
      console.error('❌ SMTP connection failed');
      console.error('   Check SMTP settings in .env file');
      return;
    }
    
    console.log('✅ SMTP connection verified');
    
    // Send test email
    console.log('\n3️⃣ Sending test email...');
    const testEmail = 'ashamyuampat24@gmail.com'; // Driver's email
    
    const result = await emailService.sendEmail(
      testEmail,
      'Test Email from Abra Travels',
      'This is a test email to verify the email service is working.',
      '<h1>Test Email</h1><p>This is a test email to verify the email service is working.</p>'
    );
    
    if (result.success) {
      console.log('✅ Email sent successfully!');
      console.log('   Message ID:', result.messageId);
      console.log('   Recipient:', testEmail);
      console.log('\n📬 Check the inbox (and spam folder) of:', testEmail);
    } else {
      console.error('❌ Email sending failed');
      console.error('   Error:', result.error);
    }
    
  } catch (error) {
    console.error('\n❌ ERROR!');
    console.error('   Message:', error.message);
    console.error('   Code:', error.code);
    console.error('   Full error:', error);
  }
  
  console.log('\n========== TEST COMPLETE ==========\n');
  process.exit(0);
}

// Run the test
testEmailDirect();
