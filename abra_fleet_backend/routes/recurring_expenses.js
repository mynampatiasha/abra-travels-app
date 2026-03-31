// ============================================================================
// RECURRING EXPENSES SYSTEM - COMPLETE BACKEND IMPLEMENTATION (UPDATED)
// ============================================================================
// File: backend/routes/recurring_expenses.js
// Contains: Routes, Controllers, Models, Automatic Generation (Cron), PDF, Email
// Database: MongoDB with Mongoose
// Features:
// - Create, Edit, Pause, Resume, Stop recurring profiles
// - Automatic expense generation based on schedule (Cron Job)
// - Manual expense generation
// - PDF generation with ABRA Travels logo
// - Email notifications
// - Statistics and analytics
// - TAX SUPPORT: General Tax + GST with rates
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const cron = require('node-cron');
const PDFDocument = require('pdfkit');
const nodemailer = require('nodemailer');
const fs = require('fs');
const path = require('path');

// ============================================================================
// MONGOOSE MODELS
// ============================================================================

// Recurring Expense Profile Schema (UPDATED WITH TAX SUPPORT)
const recurringExpenseSchema = new mongoose.Schema({
  profileName: {
    type: String,
    required: true,
    trim: true
  },
  
  // Vendor Information
  vendorId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Vendor',
    required: true
  },
  vendorName: {
    type: String,
    required: true
  },
  vendorEmail: {
    type: String,
    default: ''
  },
  
  // Expense Details
  expenseAccount: {
    type: String,
    required: true,
    enum: [
      'Office Supplies',
      'Fuel',
      'Travel & Conveyance',
      'Advertising & Marketing',
      'Meals & Entertainment',
      'Utilities',
      'Rent',
      'Professional Fees',
      'Insurance',
      'Other Expenses'
    ]
  },
  paidThrough: {
    type: String,
    required: true,
    enum: [
      'Cash',
      'Petty Cash',
      'Bank - Current Account',
      'Bank - Savings Account',
      'Credit Card',
      'UPI'
    ]
  },
  amount: {
    type: Number,
    required: true,
    min: 0
  },
  
  // Billable flag
  isBillable: {
    type: Boolean,
    default: false
  },
  
  // Tax Settings (UPDATED)
  tax: {
    type: Number,
    default: 0,
    min: 0
  },
  gstRate: {
    type: Number,
    default: 0,
    min: 0
  },
  
  // Recurrence Settings
  repeatEvery: {
    type: Number,
    required: true,
    min: 1,
    default: 1
  },
  repeatUnit: {
    type: String,
    required: true,
    enum: ['day', 'week', 'month', 'year'],
    default: 'month'
  },
  startDate: {
    type: Date,
    required: true
  },
  endDate: {
    type: Date,
    default: null
  },
  maxOccurrences: {
    type: Number,
    default: null
  },
  
  // Next Expense Generation
  nextExpenseDate: {
    type: Date,
    required: true
  },
  
  // Status
  status: {
    type: String,
    enum: ['ACTIVE', 'PAUSED', 'STOPPED'],
    default: 'ACTIVE',
    index: true
  },
  
  // Tracking
  totalExpensesGenerated: {
    type: Number,
    default: 0
  },
  lastGeneratedDate: {
    type: Date,
    default: null
  },
  
  // Automation Settings
  expenseCreationMode: {
    type: String,
    enum: ['auto_create', 'draft'],
    default: 'auto_create'
  },
  
  // Additional Info
  notes: {
    type: String,
    default: ''
  },
  
  // Audit
  createdBy: {
    type: String,
    required: true
  },
  updatedBy: String,
  createdAt: {
    type: Date,
    default: Date.now
  },
  updatedAt: {
    type: Date,
    default: Date.now
  }
}, {
  timestamps: true
});

// Pre-save middleware to set nextExpenseDate
recurringExpenseSchema.pre('save', function(next) {
  if (this.isNew && !this.nextExpenseDate) {
    this.nextExpenseDate = this.startDate;
  }
  next();
});

// Indexes
recurringExpenseSchema.index({ status: 1, nextExpenseDate: 1 });
recurringExpenseSchema.index({ vendorId: 1 });

const RecurringExpense = mongoose.model('RecurringExpense', recurringExpenseSchema);

// Expense Schema (linked to recurring profiles) - UPDATED WITH TAX SUPPORT
const expenseSchema = new mongoose.Schema({
  expenseNumber: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  
  // Link to recurring profile
  recurringProfileId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'RecurringExpense',
    default: null
  },
  
  vendorId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Vendor',
    required: true
  },
  vendorName: String,
  
  // Expense Details
  expenseAccount: {
    type: String,
    required: true
  },
  paidThrough: {
    type: String,
    required: true
  },
  amount: {
    type: Number,
    required: true,
    min: 0
  },
  
  // Billable flag
  isBillable: {
    type: Boolean,
    default: false
  },
  
  // Tax Details (UPDATED)
  tax: {
    type: Number,
    default: 0,
    min: 0
  },
  gstRate: {
    type: Number,
    default: 0,
    min: 0
  },
  gstAmount: {
    type: Number,
    default: 0,
    min: 0
  },
  totalAmount: {
    type: Number,
    required: true
  },
  
  // Dates
  date: {
    type: Date,
    required: true,
    default: Date.now
  },
  
  // Status
  status: {
    type: String,
    enum: ['DRAFT', 'RECORDED'],
    default: 'RECORDED'
  },
  
  // Additional
  notes: String,
  
  // Audit
  createdBy: String,
  createdAt: {
    type: Date,
    default: Date.now
  }
}, {
  timestamps: true
});

// Pre-save to calculate total (UPDATED WITH TAX CALCULATION)
expenseSchema.pre('save', function(next) {
  // Calculate tax amount
  const taxAmount = this.tax || 0;
  
  // Calculate GST amount
  const gstBase = this.amount + taxAmount;
  this.gstAmount = gstBase * ((this.gstRate || 0) / 100);
  
  // Calculate total
  this.totalAmount = this.amount + taxAmount + this.gstAmount;
  
  next();
});

// Check if model already exists to avoid OverwriteModelError
const Expense = mongoose.models.Expense || mongoose.model('Expense', expenseSchema);

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

// Generate unique expense number
async function generateExpenseNumber() {
  const date = new Date();
  const year = date.getFullYear().toString().slice(-2);
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  
  const lastExpense = await Expense.findOne({
    expenseNumber: new RegExp(`^EXP-${year}${month}`)
  }).sort({ expenseNumber: -1 });
  
  let sequence = 1;
  if (lastExpense) {
    const lastSequence = parseInt(lastExpense.expenseNumber.split('-')[2]);
    sequence = lastSequence + 1;
  }
  
  return `EXP-${year}${month}-${sequence.toString().padStart(4, '0')}`;
}

// Calculate next expense date
function calculateNextExpenseDate(currentDate, repeatEvery, repeatUnit) {
  const nextDate = new Date(currentDate);
  
  switch (repeatUnit) {
    case 'day':
      nextDate.setDate(nextDate.getDate() + repeatEvery);
      break;
    case 'week':
      nextDate.setDate(nextDate.getDate() + (repeatEvery * 7));
      break;
    case 'month':
      nextDate.setMonth(nextDate.getMonth() + repeatEvery);
      break;
    case 'year':
      nextDate.setFullYear(nextDate.getFullYear() + repeatEvery);
      break;
  }
  
  return nextDate;
}

// Check if profile should generate expense
function shouldGenerateExpense(profile) {
  const now = new Date();
  
  // Check status
  if (profile.status !== 'ACTIVE') {
    return false;
  }
  
  // Check if nextExpenseDate has passed
  if (profile.nextExpenseDate > now) {
    return false;
  }
  
  // Check end date
  if (profile.endDate && now > profile.endDate) {
    return false;
  }
  
  // Check max occurrences
  if (profile.maxOccurrences && profile.totalExpensesGenerated >= profile.maxOccurrences) {
    return false;
  }
  
  return true;
}

// ============================================================================
// AUTOMATIC EXPENSE GENERATION (CRON JOB)
// ============================================================================

// Run every hour to check for expenses to generate
cron.schedule('0 * * * *', async () => {
  console.log('🔄 Running automatic expense generation check...');
  
  try {
    // Find all active profiles that need generation
    const profiles = await RecurringExpense.find({
      status: 'ACTIVE',
      nextExpenseDate: { $lte: new Date() }
    });
    
    console.log(`📊 Found ${profiles.length} profiles to process`);
    
    for (const profile of profiles) {
      try {
        if (shouldGenerateExpense(profile)) {
          await generateExpenseFromProfile(profile, 'system-cron');
          console.log(`✅ Generated expense for profile: ${profile.profileName}`);
        }
      } catch (error) {
        console.error(`❌ Error generating expense for ${profile.profileName}:`, error);
      }
    }
  } catch (error) {
    console.error('❌ Error in automatic expense generation:', error);
  }
});

// Generate expense from recurring profile (UPDATED WITH TAX SUPPORT)
async function generateExpenseFromProfile(profile, createdBy = 'system') {
  // Generate expense number
  const expenseNumber = await generateExpenseNumber();
  
  // Determine status based on creation mode
  const status = profile.expenseCreationMode === 'auto_create' ? 'RECORDED' : 'DRAFT';
  
  // Calculate tax amount
  const taxAmount = profile.tax || 0;
  
  // Calculate GST
  const gstRate = profile.gstRate || 0;
  const gstBase = profile.amount + taxAmount;
  const gstAmount = gstBase * (gstRate / 100);
  
  // Calculate total
  const totalAmount = profile.amount + taxAmount + gstAmount;
  
  // Create expense
  const expense = new Expense({
    expenseNumber,
    recurringProfileId: profile._id,
    vendorId: profile.vendorId,
    vendorName: profile.vendorName,
    expenseAccount: profile.expenseAccount,
    paidThrough: profile.paidThrough,
    amount: profile.amount,
    isBillable: profile.isBillable || false,  // NEW: Copy billable flag
    tax: taxAmount,
    gstRate: gstRate,
    gstAmount: gstAmount,
    totalAmount: totalAmount,
    date: profile.nextExpenseDate,
    status,
    notes: `Auto-generated from recurring profile: ${profile.profileName}`,
    createdBy
  });
  
  await expense.save();
  
  // Update recurring profile
  profile.totalExpensesGenerated += 1;
  profile.lastGeneratedDate = new Date();
  profile.nextExpenseDate = calculateNextExpenseDate(
    profile.nextExpenseDate,
    profile.repeatEvery,
    profile.repeatUnit
  );
  
  // Check if should stop
  if (profile.endDate && profile.nextExpenseDate > profile.endDate) {
    profile.status = 'STOPPED';
  }
  
  if (profile.maxOccurrences && profile.totalExpensesGenerated >= profile.maxOccurrences) {
    profile.status = 'STOPPED';
  }
  
  await profile.save();
  
  // Send email notification (if auto-create)
  if (status === 'RECORDED') {
    try {
      await sendExpenseGeneratedEmail(profile, expense);
    } catch (emailError) {
      console.warn('Failed to send email notification:', emailError.message);
    }
  }
  
  return expense;
}

// ============================================================================
// EMAIL SERVICE
// ============================================================================

const emailTransporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'smtp.gmail.com',
  port: process.env.SMTP_PORT || 587,
  secure: false,
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASSWORD
  }
});

// Get logo as base64
function getLogoBase64() {
  try {
    const possibleLogoPaths = [
      path.join(__dirname, '..', 'assets', 'abra.jpeg'),
      path.join(__dirname, '..', 'assets', 'abra.jpg'),
      path.join(__dirname, '..', 'assets', 'abra.png'),
      path.join(process.cwd(), 'assets', 'abra.jpeg'),
      path.join(process.cwd(), 'backend', 'assets', 'abra.jpeg')
    ];
    
    for (const logoPath of possibleLogoPaths) {
      if (fs.existsSync(logoPath)) {
        const imageBuffer = fs.readFileSync(logoPath);
        const base64 = imageBuffer.toString('base64');
        const ext = path.extname(logoPath).toLowerCase();
        const mimeType = ext === '.png' ? 'image/png' : 'image/jpeg';
        return `data:${mimeType};base64,${base64}`;
      }
    }
  } catch (error) {
    console.error('❌ Error reading logo:', error);
  }
  return null;
}

// Send expense generated email (UPDATED WITH TAX INFO)
async function sendExpenseGeneratedEmail(profile, expense) {
  const logoBase64 = getLogoBase64();
  
  // Calculate tax breakdown
  const taxAmount = expense.tax || 0;
  const gstAmount = expense.gstAmount || 0;
  const cgst = gstAmount / 2;
  const sgst = gstAmount / 2;
  
  const emailHtml = `
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { 
      background: linear-gradient(135deg, #e74c3c 0%, #c0392b 100%); 
      color: white; 
      padding: 35px; 
      text-align: left; 
      border-radius: 10px 10px 0 0; 
    }
    .logo { max-width: 180px; height: auto; margin-bottom: 10px; display: block; }
    .content { background: #f8f9fa; padding: 35px; border-radius: 0 0 10px 10px; }
    .info-box { background: white; padding: 25px; border-radius: 10px; margin: 20px 0; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
    .detail-row { display: flex; justify-content: space-between; padding: 12px 0; border-bottom: 1px solid #ecf0f1; }
    .footer { text-align: center; color: #95a5a6; font-size: 12px; margin-top: 30px; padding-top: 20px; border-top: 2px solid #e74c3c; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      ${logoBase64 ? `<img src="${logoBase64}" alt="ABRA Travels" class="logo" style="filter: brightness(0) invert(1);">` : `
        <h1 style="color: #ffffff; margin: 0; font-size: 28px;">ABRA Travels</h1>
      `}
      <p style="color: #ffffff; margin: 5px 0 0 0; letter-spacing: 1px;">YOUR JOURNEY, OUR COMMITMENT</p>
      <h1 style="margin: 20px 0 0 0; font-size: 28px;">💰 Expense Generated</h1>
      <p style="margin: 5px 0 0 0;">From Recurring Profile</p>
    </div>
    <div class="content">
      <p>A new expense has been automatically generated from your recurring profile.</p>
      
      <div class="info-box">
        <h3 style="color: #e74c3c; margin-top: 0;">Expense Details:</h3>
        <div class="detail-row">
          <span><strong>Expense Number:</strong></span>
          <span>${expense.expenseNumber}</span>
        </div>
        <div class="detail-row">
          <span><strong>Profile Name:</strong></span>
          <span>${profile.profileName}</span>
        </div>
        <div class="detail-row">
          <span><strong>Vendor:</strong></span>
          <span>${profile.vendorName}</span>
        </div>
        <div class="detail-row">
          <span><strong>Category:</strong></span>
          <span>${profile.expenseAccount}</span>
        </div>
        <div class="detail-row">
          <span><strong>Date:</strong></span>
          <span>${new Date(expense.date).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}</span>
        </div>
        <div class="detail-row">
          <span><strong>Amount:</strong></span>
          <span>₹${expense.amount.toFixed(2)}</span>
        </div>
        ${taxAmount > 0 ? `
        <div class="detail-row">
          <span><strong>Tax:</strong></span>
          <span>₹${taxAmount.toFixed(2)}</span>
        </div>
        ` : ''}
        ${gstAmount > 0 ? `
        <div class="detail-row">
          <span><strong>CGST (${(profile.gstRate / 2).toFixed(1)}%):</strong></span>
          <span>₹${cgst.toFixed(2)}</span>
        </div>
        <div class="detail-row">
          <span><strong>SGST (${(profile.gstRate / 2).toFixed(1)}%):</strong></span>
          <span>₹${sgst.toFixed(2)}</span>
        </div>
        ` : ''}
        <div class="detail-row" style="border: none; background: #ffe6e6; padding: 15px; margin-top: 10px; border-radius: 6px;">
          <span style="font-size: 16px;"><strong>Total Amount:</strong></span>
          <span style="color: #e74c3c; font-weight: bold; font-size: 18px;">₹${expense.totalAmount.toFixed(2)}</span>
        </div>
      </div>
      
      <div class="info-box">
        <h3 style="color: #e74c3c; margin-top: 0;">Recurring Schedule:</h3>
        <div class="detail-row">
          <span><strong>Frequency:</strong></span>
          <span>Every ${profile.repeatEvery} ${profile.repeatUnit}(s)</span>
        </div>
        <div class="detail-row">
          <span><strong>Next Expense:</strong></span>
          <span>${new Date(profile.nextExpenseDate).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}</span>
        </div>
        <div class="detail-row">
          <span><strong>Total Generated:</strong></span>
          <span>${profile.totalExpensesGenerated}</span>
        </div>
      </div>
      
      <p style="margin-top: 25px; text-align: center; color: #555;">
        This expense has been automatically ${expense.status === 'RECORDED' ? 'recorded' : 'saved as draft'} in your system.
      </p>
    </div>
    <div class="footer">
      <p><strong>ABRA Travels</strong> | YOUR JOURNEY, OUR COMMITMENT</p>
      <p>info@abratravels.com | +91 88672 88076</p>
      <p style="margin-top: 15px;">© ${new Date().getFullYear()} ABRA Travels. All rights reserved.</p>
    </div>
  </div>
</body>
</html>
  `;
  
  return emailTransporter.sendMail({
    from: `"ABRA Travels - Expense System" <${process.env.SMTP_USER}>`,
    to: process.env.ADMIN_EMAIL || process.env.SMTP_USER,
    subject: `💰 Expense ${expense.expenseNumber} Generated - ${profile.profileName}`,
    html: emailHtml
  });
}

// ============================================================================
// API ROUTES
// ============================================================================

// GET /api/recurring-expenses - List all recurring expense profiles
router.get('/', async (req, res) => {
  try {
    const { status, fromDate, toDate, page = 1, limit = 20 } = req.query;
    
    const query = {};
    
    if (status && status !== 'All') {
      query.status = status;
    }
    
    if (fromDate || toDate) {
      query.startDate = {};
      if (fromDate) query.startDate.$gte = new Date(fromDate);
      if (toDate) query.startDate.$lte = new Date(toDate);
    }
    
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    const profiles = await RecurringExpense.find(query)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .select('-__v');
    
    const total = await RecurringExpense.countDocuments(query);
    
    res.json({
      success: true,
      data: profiles,
      pagination: {
        total,
        page: parseInt(page),
        limit: parseInt(limit),
        pages: Math.ceil(total / parseInt(limit))
      }
    });
  } catch (error) {
    console.error('Error fetching recurring expenses:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/recurring-expenses/stats - Get statistics
router.get('/stats', async (req, res) => {
  try {
    const totalProfiles = await RecurringExpense.countDocuments();
    const activeProfiles = await RecurringExpense.countDocuments({ status: 'ACTIVE' });
    const pausedProfiles = await RecurringExpense.countDocuments({ status: 'PAUSED' });
    const stoppedProfiles = await RecurringExpense.countDocuments({ status: 'STOPPED' });
    
    // Calculate total expenses generated and amount (UPDATED WITH TAX)
    const generationStats = await RecurringExpense.aggregate([
      {
        $group: {
          _id: null,
          totalExpensesGenerated: { $sum: '$totalExpensesGenerated' },
          totalAmount: { 
            $sum: { 
              $multiply: [
                '$totalExpensesGenerated',
                {
                  $add: [
                    '$amount',
                    { $ifNull: ['$tax', 0] },
                    {
                      $multiply: [
                        { $add: ['$amount', { $ifNull: ['$tax', 0] }] },
                        { $divide: [{ $ifNull: ['$gstRate', 0] }, 100] }
                      ]
                    }
                  ]
                }
              ]
            } 
          }
        }
      }
    ]);
    
    const stats = {
      totalProfiles,
      activeProfiles,
      pausedProfiles,
      stoppedProfiles,
      totalExpensesGenerated: generationStats[0]?.totalExpensesGenerated || 0,
      totalAmountGenerated: generationStats[0]?.totalAmount || 0
    };
    
    res.json({ success: true, data: stats });
  } catch (error) {
    console.error('Error fetching stats:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/recurring-expenses/:id - Get single recurring expense
router.get('/:id', async (req, res) => {
  try {
    const profile = await RecurringExpense.findById(req.params.id);
    
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Recurring expense not found' });
    }
    
    res.json({ success: true, data: profile });
  } catch (error) {
    console.error('Error fetching recurring expense:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/recurring-expenses - Create new recurring expense
router.post('/', async (req, res) => {
  try {
    const profileData = req.body;
    
    // Handle vendorId
    if (profileData.vendorId) {
      if (typeof profileData.vendorId === 'string') {
        if (mongoose.Types.ObjectId.isValid(profileData.vendorId)) {
          profileData.vendorId = new mongoose.Types.ObjectId(profileData.vendorId);
        } else {
          profileData.vendorId = new mongoose.Types.ObjectId();
        }
      }
    }
    
    // Set creator
    profileData.createdBy = req.user?.email || req.user?.uid || 'system';
    
    // Set initial nextExpenseDate to startDate
    if (!profileData.nextExpenseDate) {
      profileData.nextExpenseDate = profileData.startDate;
    }
    
    // Ensure tax fields are numbers
    if (profileData.tax) {
      profileData.tax = Number(profileData.tax);
    }
    if (profileData.gstRate) {
      profileData.gstRate = Number(profileData.gstRate);
    }
    
    const profile = new RecurringExpense(profileData);
    await profile.save();
    
    console.log(`✅ Recurring expense profile created: ${profile.profileName}`);
    
    res.status(201).json({
      success: true,
      message: 'Recurring expense profile created successfully',
      data: profile
    });
  } catch (error) {
    console.error('Error creating recurring expense:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/recurring-expenses/:id - Update recurring expense
router.put('/:id', async (req, res) => {
  try {
    const profile = await RecurringExpense.findById(req.params.id);
    
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Recurring expense not found' });
    }
    
    const updates = req.body;
    updates.updatedBy = req.user?.email || req.user?.uid || 'system';
    
    // Ensure tax fields are numbers
    if (updates.tax) {
      updates.tax = Number(updates.tax);
    }
    if (updates.gstRate) {
      updates.gstRate = Number(updates.gstRate);
    }
    
    Object.assign(profile, updates);
    await profile.save();
    
    console.log(`✅ Recurring expense updated: ${profile.profileName}`);
    
    res.json({
      success: true,
      message: 'Recurring expense updated successfully',
      data: profile
    });
  } catch (error) {
    console.error('Error updating recurring expense:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/recurring-expenses/:id/pause - Pause profile
router.post('/:id/pause', async (req, res) => {
  try {
    const profile = await RecurringExpense.findById(req.params.id);
    
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Recurring expense not found' });
    }
    
    if (profile.status !== 'ACTIVE') {
      return res.status(400).json({ success: false, error: 'Only active profiles can be paused' });
    }
    
    profile.status = 'PAUSED';
    profile.updatedBy = req.user?.email || req.user?.uid || 'system';
    await profile.save();
    
    console.log(`⏸️ Recurring expense paused: ${profile.profileName}`);
    
    res.json({
      success: true,
      message: 'Recurring expense paused successfully',
      data: profile
    });
  } catch (error) {
    console.error('Error pausing recurring expense:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/recurring-expenses/:id/resume - Resume profile
router.post('/:id/resume', async (req, res) => {
  try {
    const profile = await RecurringExpense.findById(req.params.id);
    
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Recurring expense not found' });
    }
    
    if (profile.status !== 'PAUSED') {
      return res.status(400).json({ success: false, error: 'Only paused profiles can be resumed' });
    }
    
    profile.status = 'ACTIVE';
    profile.updatedBy = req.user?.email || req.user?.uid || 'system';
    await profile.save();
    
    console.log(`▶️ Recurring expense resumed: ${profile.profileName}`);
    
    res.json({
      success: true,
      message: 'Recurring expense resumed successfully',
      data: profile
    });
  } catch (error) {
    console.error('Error resuming recurring expense:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/recurring-expenses/:id/stop - Stop profile permanently
router.post('/:id/stop', async (req, res) => {
  try {
    const profile = await RecurringExpense.findById(req.params.id);
    
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Recurring expense not found' });
    }
    
    profile.status = 'STOPPED';
    profile.updatedBy = req.user?.email || req.user?.uid || 'system';
    await profile.save();
    
    console.log(`⏹️ Recurring expense stopped: ${profile.profileName}`);
    
    res.json({
      success: true,
      message: 'Recurring expense stopped successfully',
      data: profile
    });
  } catch (error) {
    console.error('Error stopping recurring expense:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/recurring-expenses/:id/generate - Generate expense manually
router.post('/:id/generate', async (req, res) => {
  try {
    const profile = await RecurringExpense.findById(req.params.id);
    
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Recurring expense not found' });
    }
    
    const createdBy = req.user?.email || req.user?.uid || 'manual-generation';
    const expense = await generateExpenseFromProfile(profile, createdBy);
    
    console.log(`✅ Manual expense generated: ${expense.expenseNumber}`);
    
    res.status(201).json({
      success: true,
      message: 'Expense generated successfully',
      data: {
        expenseId: expense._id,
        expenseNumber: expense.expenseNumber,
        amount: expense.totalAmount,
        expenseDate: expense.date
      }
    });
  } catch (error) {
    console.error('Error generating expense:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/recurring-expenses/:id/child-expenses - Get child expenses
router.get('/:id/child-expenses', async (req, res) => {
  try {
    const expenses = await Expense.find({
      recurringProfileId: req.params.id
    }).sort({ date: -1 });
    
    res.json({
      success: true,
      data: expenses
    });
  } catch (error) {
    console.error('Error fetching child expenses:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/recurring-expenses/:id - Delete profile
router.delete('/:id', async (req, res) => {
  try {
    const profile = await RecurringExpense.findById(req.params.id);
    
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Recurring expense not found' });
    }
    
    await profile.deleteOne();
    
    console.log(`✅ Recurring expense deleted: ${profile.profileName}`);
    
    res.json({
      success: true,
      message: 'Recurring expense deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting recurring expense:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// EXPORT MODULE
// ============================================================================

module.exports = router;