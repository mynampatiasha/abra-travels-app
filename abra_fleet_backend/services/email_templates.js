// Email templates for Abra Travels

/**
 * Email template for customer approval (when customer registered themselves)
 */
function getApprovalEmailTemplate(name, email, companyName) {
  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
    .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }
    .info-box { background: white; padding: 15px; border-left: 4px solid #667eea; margin: 20px 0; }
    .footer { text-align: center; color: #666; font-size: 12px; margin-top: 30px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🎉 Welcome to Abra Travels!</h1>
    </div>
    <div class="content">
      <p>Dear <strong>${name}</strong>,</p>
      
      <p>Great news! Your Abra Travels account has been approved by our administrator.</p>
      
      <p>You can now login and access all features of our fleet management system.</p>
      
      <div class="info-box">
        <h3>📋 Your Account Details:</h3>
        <p><strong>Email:</strong> ${email}</p>
        <p><strong>Company:</strong> ${companyName || 'N/A'}</p>
        <p><strong>Status:</strong> Active ✅</p>
      </div>
      
      <p><strong>What's Next?</strong></p>
      <ul>
        <li>Login with your registered email and password</li>
        <li>Complete your profile setup</li>
        <li>Start booking trips and managing your fleet needs</li>
      </ul>
      
      <p>If you have any questions or need assistance, please don't hesitate to contact our support team.</p>
      
      <p>Best regards,<br><strong>The Abra Travels Team</strong></p>
    </div>
    <div class="footer">
      <p>© ${new Date().getFullYear()} Abra Travels. All rights reserved.</p>
    </div>
  </div>
</body>
</html>
  `;
}

/**
 * Email template for welcome + password setup (when customer is added by admin/client/bulk)
 */
function getWelcomeWithPasswordSetupTemplate(name, email, companyName, passwordResetLink) {
  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
    .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }
    .info-box { background: white; padding: 15px; border-left: 4px solid #667eea; margin: 20px 0; }
    .warning-box { background: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin: 20px 0; }
    .button { display: inline-block; background: #667eea; color: white; padding: 15px 40px; text-decoration: none; border-radius: 5px; margin: 20px 0; font-weight: bold; }
    .button:hover { background: #5568d3; }
    .footer { text-align: center; color: #666; font-size: 12px; margin-top: 30px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🎉 Welcome to Abra Travels!</h1>
    </div>
    <div class="content">
      <p>Dear <strong>${name}</strong>,</p>
      
      <p>Your account has been created and approved! We're excited to have you on board.</p>
      
      <div class="info-box">
        <h3>📋 Your Account Details:</h3>
        <p><strong>Email:</strong> ${email}</p>
        <p><strong>Company:</strong> ${companyName || 'N/A'}</p>
        <p><strong>Status:</strong> Active ✅</p>
      </div>
      
      <div class="warning-box">
        <h3>⚠️ Important: Set Your Password</h3>
        <p>Before you can login, you need to set your password. This is a one-time setup to secure your account.</p>
      </div>
      
      <div style="text-align: center;">
        <a href="${passwordResetLink}" class="button">🔐 Set Your Password</a>
      </div>
      
      <p><small><strong>Note:</strong> This link will expire in 1 hour for security reasons. If it expires, you can request a new password reset link from the login page.</small></p>
      
      <p><strong>After setting your password, you can:</strong></p>
      <ul>
        <li>Login with your email and new password</li>
        <li>Access all fleet management features</li>
        <li>Book trips and manage your transportation needs</li>
        <li>Track your trips in real-time</li>
      </ul>
      
      <p>If you have any questions or need assistance, please don't hesitate to contact our support team.</p>
      
      <p>Best regards,<br><strong>The Abra Travels Team</strong></p>
    </div>
    <div class="footer">
      <p>© ${new Date().getFullYear()} Abra Travels. All rights reserved.</p>
      <p>If you didn't request this account, please ignore this email.</p>
    </div>
  </div>
</body>
</html>
  `;
}

/**
 * Plain text version for approval email
 */
function getApprovalEmailText(name, email, companyName) {
  return `
Welcome to Abra Travels!

Dear ${name},

Great news! Your Abra Travels account has been approved by our administrator.

Account Details:
- Email: ${email}
- Company: ${companyName || 'N/A'}
- Status: Active

You can now login and access all features of our fleet management system.

What's Next?
- Login with your registered email and password
- Complete your profile setup
- Start booking trips and managing your fleet needs

If you have any questions, please contact our support team.

Best regards,
The Abra Travels Team

© ${new Date().getFullYear()} Abra Travels. All rights reserved.
  `;
}

/**
 * Plain text version for welcome + password setup email
 */
function getWelcomeWithPasswordSetupText(name, email, companyName, passwordResetLink) {
  return `
Welcome to Abra Travels!

Dear ${name},

Your account has been created and approved! We're excited to have you on board.

Account Details:
- Email: ${email}
- Company: ${companyName || 'N/A'}
- Status: Active

IMPORTANT: Set Your Password
Before you can login, you need to set your password.

Click this link to set your password:
${passwordResetLink}

Note: This link will expire in 1 hour for security reasons.

After setting your password, you can:
- Login with your email and new password
- Access all fleet management features
- Book trips and manage your transportation needs
- Track your trips in real-time

If you have any questions, please contact our support team.

Best regards,
The Abra Travels Team

© ${new Date().getFullYear()} Abra Travels. All rights reserved.
If you didn't request this account, please ignore this email.
  `;
}

/**
 * Email template for customer rejection
 */
function getRejectionEmailTemplate(name, email, reason) {
  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: #ef4444; color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
    .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }
    .reason-box { background: #fee2e2; border-left: 4px solid #ef4444; padding: 15px; margin: 20px 0; }
    .footer { text-align: center; color: #666; font-size: 12px; margin-top: 30px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>Account Registration Update</h1>
    </div>
    <div class="content">
      <p>Dear <strong>${name}</strong>,</p>
      
      <p>Thank you for your interest in Abra Travels. After reviewing your registration, we regret to inform you that your account application has not been approved at this time.</p>
      
      ${reason ? `
      <div class="reason-box">
        <h3>Reason:</h3>
        <p>${reason}</p>
      </div>
      ` : ''}
      
      <p>If you believe this is an error or would like to discuss this decision, please contact our support team.</p>
      
      <p>Best regards,<br><strong>The Abra Travels Team</strong></p>
    </div>
    <div class="footer">
      <p>© ${new Date().getFullYear()} Abra Travels. All rights reserved.</p>
    </div>
  </div>
</body>
</html>
  `;
}

/**
 * Email template for driver welcome + password setup
 */
function getDriverWelcomeTemplate(firstName, lastName, email, driverId, passwordResetLink) {
  const fullName = `${firstName} ${lastName}`;
  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #0D47A1 0%, #1565C0 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
    .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }
    .info-box { background: white; padding: 15px; border-left: 4px solid #0D47A1; margin: 20px 0; }
    .warning-box { background: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin: 20px 0; }
    .button { display: inline-block; background: #0D47A1; color: white; padding: 15px 40px; text-decoration: none; border-radius: 5px; margin: 20px 0; font-weight: bold; }
    .button:hover { background: #1565C0; }
    .footer { text-align: center; color: #666; font-size: 12px; margin-top: 30px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🚗 Welcome to Abra Travels Driver Portal!</h1>
    </div>
    <div class="content">
      <p>Dear <strong>${fullName}</strong>,</p>
      
      <p>Welcome aboard! Your driver account has been created in the Abra Travels system.</p>
      
      <div class="info-box">
        <h3>📋 Your Driver Account Details:</h3>
        <p><strong>Driver ID:</strong> ${driverId}</p>
        <p><strong>Email:</strong> ${email}</p>
        <p><strong>Status:</strong> Active ✅</p>
      </div>
      
      <div class="warning-box">
        <h3>⚠️ Important: Set Your Password</h3>
        <p>Before you can login to the driver portal, you need to set your password. This is a one-time setup to secure your account.</p>
      </div>
      
      <div style="text-align: center;">
        <a href="${passwordResetLink}" class="button">🔐 Set Your Password</a>
      </div>
      
      <p><small><strong>Note:</strong> This link will expire in 1 hour for security reasons. If it expires, you can request a new password reset link from the login page.</small></p>
      
      <p><strong>After setting your password, you can:</strong></p>
      <ul>
        <li>Login to the driver mobile app or web portal</li>
        <li>View your assigned trips and schedules</li>
        <li>Update trip status and locations</li>
        <li>Manage your profile and documents</li>
        <li>Track your performance and earnings</li>
      </ul>
      
      <p><strong>Getting Started:</strong></p>
      <ol>
        <li>Click the "Set Your Password" button above</li>
        <li>Create a strong password for your account</li>
        <li>Download the Abra Travels Driver app (if using mobile)</li>
        <li>Login with your email and new password</li>
      </ol>
      
      <p>If you have any questions or need assistance, please contact your fleet administrator or our support team.</p>
      
      <p>Safe driving!<br><strong>The Abra Travels Team</strong></p>
    </div>
    <div class="footer">
      <p>© ${new Date().getFullYear()} Abra Travels. All rights reserved.</p>
      <p>If you didn't expect this email, please contact your fleet administrator.</p>
    </div>
  </div>
</body>
</html>
  `;
}

/**
 * Plain text version for driver welcome email
 */
function getDriverWelcomeText(firstName, lastName, email, driverId, passwordResetLink) {
  const fullName = `${firstName} ${lastName}`;
  return `
Welcome to Abra Travels Driver Portal!

Dear ${fullName},

Welcome aboard! Your driver account has been created in the Abra Travels system.

Your Driver Account Details:
- Driver ID: ${driverId}
- Email: ${email}
- Status: Active

IMPORTANT: Set Your Password
Before you can login to the driver portal, you need to set your password.

Click this link to set your password:
${passwordResetLink}

Note: This link will expire in 1 hour for security reasons.

After setting your password, you can:
- Login to the driver mobile app or web portal
- View your assigned trips and schedules
- Update trip status and locations
- Manage your profile and documents
- Track your performance and earnings

Getting Started:
1. Click the password setup link above
2. Create a strong password for your account
3. Download the Abra Travels Driver app (if using mobile)
4. Login with your email and new password

If you have any questions, please contact your fleet administrator or our support team.

Safe driving!
The Abra Travels Team

© ${new Date().getFullYear()} Abra Travels. All rights reserved.
If you didn't expect this email, please contact your fleet administrator.
  `;
}

/**
 * Email template for password reset
 */
function getPasswordResetTemplate(name, resetLink) {
  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { 
      font-family: Arial, sans-serif; 
      line-height: 1.6; 
      color: #333; 
      margin: 0;
      padding: 0;
      background-color: #f4f4f4;
    }
    .container { 
      max-width: 600px; 
      margin: 20px auto; 
      background: white;
      border-radius: 10px;
      overflow: hidden;
      box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    }
    .header { 
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
      color: white; 
      padding: 40px 30px; 
      text-align: center;
    }
    .header h1 {
      margin: 0;
      font-size: 28px;
    }
    .content { 
      padding: 40px 30px;
    }
    .button-container {
      text-align: center;
      margin: 30px 0;
    }
    .button { 
      display: inline-block; 
      background: #667eea; 
      color: white !important; 
      padding: 15px 40px; 
      text-decoration: none; 
      border-radius: 8px;
      font-weight: bold;
      font-size: 16px;
      box-shadow: 0 4px 6px rgba(102, 126, 234, 0.3);
    }
    .button:hover {
      background: #5568d3;
    }
    .info-box { 
      background: #fff3cd; 
      padding: 20px; 
      border-left: 4px solid #ffc107; 
      margin: 25px 0;
      border-radius: 4px;
    }
    .info-box p {
      margin: 0;
      color: #856404;
    }
    .footer { 
      text-align: center; 
      color: #666; 
      font-size: 12px; 
      padding: 20px 30px;
      background: #f9f9f9;
      border-top: 1px solid #eee;
    }
    .security-note {
      background: #e7f3ff;
      padding: 15px;
      border-left: 4px solid #2196F3;
      margin: 20px 0;
      border-radius: 4px;
    }
    .security-note p {
      margin: 0;
      color: #0d47a1;
      font-size: 14px;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🔐 Password Reset Request</h1>
    </div>
    <div class="content">
      <p>Hello <strong>${name}</strong>,</p>
      
      <p>We received a request to reset your password for your Abra Travels account.</p>
      
      <p>Click the button below to reset your password:</p>
      
      <div class="button-container">
        <a href="${resetLink}" class="button">Reset My Password</a>
      </div>
      
      <div class="info-box">
        <p><strong>⏰ This link will expire in 1 hour</strong> for security reasons.</p>
      </div>
      
      <div class="security-note">
        <p><strong>🔒 Security Tips:</strong></p>
        <ul style="margin: 10px 0 0 0; padding-left: 20px;">
          <li>Never share your password with anyone</li>
          <li>Use a strong, unique password</li>
          <li>If you didn't request this reset, please ignore this email</li>
        </ul>
      </div>
      
      <p style="margin-top: 30px;">If the button doesn't work, copy and paste this link into your browser:</p>
      <p style="word-break: break-all; color: #667eea; font-size: 12px;">${resetLink}</p>
      
      <p style="margin-top: 30px;">If you didn't request a password reset, you can safely ignore this email. Your password will remain unchanged.</p>
      
      <p style="margin-top: 20px;">Best regards,<br><strong>The Abra Travels Team</strong></p>
    </div>
    <div class="footer">
      <p>This is an automated message from Abra Travels Management System</p>
      <p>© ${new Date().getFullYear()} Abra Travels. All rights reserved.</p>
    </div>
  </div>
</body>
</html>
  `;
}

/**
 * Plain text version for password reset email
 */
function getPasswordResetText(name, resetLink) {
  return `
🔐 Password Reset Request

Hello ${name},

We received a request to reset your password for your Abra Travels account.

Click the link below to reset your password:
${resetLink}

⏰ This link will expire in 1 hour for security reasons.

🔒 Security Tips:
- Never share your password with anyone
- Use a strong, unique password
- If you didn't request this reset, please ignore this email

If you didn't request a password reset, you can safely ignore this email. Your password will remain unchanged.

Best regards,
The Abra Travels Team

---
This is an automated message from Abra Travels Management System
© ${new Date().getFullYear()} Abra Travels. All rights reserved.
  `;
}

module.exports = {
  getApprovalEmailTemplate,
  getWelcomeWithPasswordSetupTemplate,
  getApprovalEmailText,
  getWelcomeWithPasswordSetupText,
  getRejectionEmailTemplate,
  getDriverWelcomeTemplate,
  getDriverWelcomeText,
  getPasswordResetTemplate,
  getPasswordResetText,
};
