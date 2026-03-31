// test-send-to-me.js - Send test email to your own email
require('dotenv').config();
const emailService = require('./services/email_service');

async function sendTestEmail() {
  console.log('📧 Sending test approval email...\n');
  
  // Initialize email service
  const initialized = emailService.initialize();
  if (!initialized) {
    console.error('❌ Email service not configured');
    return;
  }
  
  // CHANGE THIS TO YOUR EMAIL ADDRESS
  const yourEmail = 'hostelmatrix19@gmail.com'; // ← Change this to test with different email
  
  console.log(`Sending test email to: ${yourEmail}\n`);
  
  // Send approval email
  const result = await emailService.sendCustomerApprovalEmail({
    email: yourEmail,
    name: 'Test User',
    companyName: 'Test Company',
  });
  
  if (result.success) {
    console.log('✅ Email sent successfully!');
    console.log(`   Check your inbox: ${yourEmail}`);
    console.log(`   Message ID: ${result.messageId}`);
    console.log('\n📬 Check your email now!');
  } else {
    console.error('❌ Failed to send email');
    console.error(`   Error: ${result.error}`);
  }
}

sendTestEmail().catch(console.error);
