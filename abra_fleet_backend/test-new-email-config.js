/**
 * Test Script for New Email Configuration
 * Tests: support@fleet.abra-travels.com
 * 
 * This script will:
 * 1. Load the new SMTP credentials from .env
 * 2. Attempt to connect to the SMTP server
 * 3. Send a test email
 * 4. Report success or any errors
 */

require('dotenv').config();
const nodemailer = require('nodemailer');

console.log('='.repeat(70));
console.log('📧 TESTING NEW EMAIL CONFIGURATION');
console.log('='.repeat(70));

// Display current configuration (without password)
console.log('\n📋 Current SMTP Configuration:');
console.log('   SMTP Host:', process.env.SMTP_HOST);
console.log('   SMTP Port:', process.env.SMTP_PORT);
console.log('   SMTP Secure:', process.env.SMTP_SECURE);
console.log('   SMTP User:', process.env.SMTP_USER);
console.log('   SMTP Password:', process.env.SMTP_PASSWORD ? '***' + process.env.SMTP_PASSWORD.slice(-4) : 'NOT SET');

async function testEmailConfiguration() {
  try {
    console.log('\n🔧 Step 1: Creating email transporter...');
    
    // Create transporter with new credentials
    const transporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST,
      port: parseInt(process.env.SMTP_PORT),
      secure: process.env.SMTP_SECURE === 'true',
      auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASSWORD,
      },
      tls: {
        rejectUnauthorized: false // For testing, accept self-signed certificates
      }
    });

    console.log('✅ Transporter created successfully');

    console.log('\n🔌 Step 2: Verifying SMTP connection...');
    
    // Verify connection
    await transporter.verify();
    console.log('✅ SMTP connection verified successfully!');
    console.log('   Server is ready to send emails');

    console.log('\n📨 Step 3: Sending test email...');
    
    // Send test email
    const testEmail = {
      from: `"ABRA Fleet Support" <${process.env.SMTP_USER}>`,
      to: process.env.SMTP_USER, // Send to self for testing
      subject: '✅ Email Configuration Test - Success!',
      html: `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
          <h2 style="color: #4CAF50;">🎉 Email Configuration Successful!</h2>
          <p>This is a test email to verify that your new email configuration is working correctly.</p>
          
          <div style="background-color: #f5f5f5; padding: 15px; border-radius: 5px; margin: 20px 0;">
            <h3 style="margin-top: 0;">Configuration Details:</h3>
            <ul style="list-style: none; padding: 0;">
              <li>📧 <strong>Email:</strong> ${process.env.SMTP_USER}</li>
              <li>🌐 <strong>SMTP Host:</strong> ${process.env.SMTP_HOST}</li>
              <li>🔌 <strong>Port:</strong> ${process.env.SMTP_PORT}</li>
              <li>🔒 <strong>Secure:</strong> ${process.env.SMTP_SECURE}</li>
            </ul>
          </div>

          <p>✅ If you received this email, your SMTP configuration is working perfectly!</p>
          
          <hr style="border: none; border-top: 1px solid #ddd; margin: 20px 0;">
          
          <p style="color: #666; font-size: 12px;">
            This is an automated test email sent from ABRA Fleet Management System.<br>
            Timestamp: ${new Date().toLocaleString()}
          </p>
        </div>
      `,
      text: `
Email Configuration Test - Success!

This is a test email to verify that your new email configuration is working correctly.

Configuration Details:
- Email: ${process.env.SMTP_USER}
- SMTP Host: ${process.env.SMTP_HOST}
- Port: ${process.env.SMTP_PORT}
- Secure: ${process.env.SMTP_SECURE}

If you received this email, your SMTP configuration is working perfectly!

Timestamp: ${new Date().toLocaleString()}
      `
    };

    const info = await transporter.sendMail(testEmail);
    
    console.log('✅ Test email sent successfully!');
    console.log('   Message ID:', info.messageId);
    console.log('   Response:', info.response);

    console.log('\n' + '='.repeat(70));
    console.log('🎉 SUCCESS! Email configuration is working correctly!');
    console.log('='.repeat(70));
    console.log('\n📬 Check your inbox at:', process.env.SMTP_USER);
    console.log('   You should receive a test email shortly.');
    console.log('\n✅ Your backend is now ready to send emails from:');
    console.log('   support@fleet.abra-travels.com');
    console.log('\n');

  } catch (error) {
    console.error('\n❌ ERROR: Email configuration test failed!');
    console.error('='.repeat(70));
    
    if (error.code === 'EAUTH') {
      console.error('\n🔐 Authentication Error:');
      console.error('   The username or password is incorrect.');
      console.error('\n   Please check:');
      console.error('   1. Email account exists: support@fleet.abra-travels.com');
      console.error('   2. Password is correct in .env file');
      console.error('   3. SMTP authentication is enabled in your hosting');
    } else if (error.code === 'ECONNECTION' || error.code === 'ETIMEDOUT') {
      console.error('\n🌐 Connection Error:');
      console.error('   Cannot connect to SMTP server.');
      console.error('\n   Please check:');
      console.error('   1. SMTP_HOST is correct: mail.abra-travels.com');
      console.error('   2. SMTP_PORT is correct: 587 or 465');
      console.error('   3. Your server can reach the SMTP server');
      console.error('   4. Firewall is not blocking the connection');
    } else if (error.code === 'ESOCKET') {
      console.error('\n🔌 Socket Error:');
      console.error('   Network connection issue.');
      console.error('\n   Please check:');
      console.error('   1. Internet connection is working');
      console.error('   2. DNS can resolve mail.abra-travels.com');
      console.error('   3. Try using IP address instead of hostname');
    } else {
      console.error('\n❓ Unknown Error:');
      console.error('   Error Code:', error.code);
      console.error('   Error Message:', error.message);
    }
    
    console.error('\n📋 Full Error Details:');
    console.error(error);
    console.error('\n');
    
    process.exit(1);
  }
}

// Run the test
testEmailConfiguration();
