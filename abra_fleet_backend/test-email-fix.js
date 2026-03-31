// Test email service with fixed password format
require('dotenv').config();
const nodemailer = require('nodemailer');

async function testEmailConnection() {
  console.log('\n🧪 TESTING EMAIL CONNECTION WITH FIXED PASSWORD');
  console.log('='.repeat(60));
  
  // Test with password without spaces
  const passwordWithoutSpaces = process.env.SMTP_PASSWORD.replace(/\s/g, '');
  
  console.log('Original password:', process.env.SMTP_PASSWORD);
  console.log('Fixed password:', passwordWithoutSpaces);
  console.log('SMTP User:', process.env.SMTP_USER);
  
  const transporter = nodemailer.createTransport({
    host: 'smtp.gmail.com',
    port: 587,
    secure: false,
    auth: {
      user: process.env.SMTP_USER,
      pass: passwordWithoutSpaces,
    },
  });

  try {
    console.log('\n📡 Testing SMTP connection...');
    await transporter.verify();
    console.log('✅ SMTP connection successful!');
    
    // Send test email
    console.log('\n📧 Sending test email...');
    const info = await transporter.sendMail({
      from: `"Abra Travels Test" <${process.env.SMTP_USER}>`,
      to: process.env.SMTP_USER, // Send to self
      subject: '✅ Email Service Test - Success!',
      text: 'This is a test email to verify the email service is working correctly.',
      html: '<h2>✅ Email Service Test</h2><p>This is a test email to verify the email service is working correctly.</p>'
    });
    
    console.log('✅ Test email sent successfully!');
    console.log('Message ID:', info.messageId);
    console.log('Response:', info.response);
    
  } catch (error) {
    console.error('❌ Email test failed:', error.message);
    console.error('Error code:', error.code);
    
    if (error.code === 'EAUTH') {
      console.log('\n💡 SOLUTION NEEDED:');
      console.log('1. Go to https://myaccount.google.com/security');
      console.log('2. Enable 2-Factor Authentication');
      console.log('3. Go to https://myaccount.google.com/apppasswords');
      console.log('4. Generate new App Password for Mail');
      console.log('5. Update SMTP_PASSWORD in .env file');
    }
  }
}

testEmailConnection().then(() => {
  console.log('\n✅ Email test completed');
  process.exit(0);
}).catch(error => {
  console.error('❌ Test failed:', error);
  process.exit(1);
});