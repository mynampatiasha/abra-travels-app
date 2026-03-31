// ============================================================================
// BILL SYSTEM - COMPLETE BACKEND
// ============================================================================
// File: backend/routes/bill.js
// Contains: Routes, Controllers, Models, PDF Generation, Email Service
// Database: MongoDB with Mongoose
// Features: Create, Edit, Send, Payment Recording, Recurring Bills, Status Management
// Mirrors Zoho Books Bill functionality exactly
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const PDFDocument = require('pdfkit');
const nodemailer = require('nodemailer');
const fs = require('fs');
const path = require('path');

// ✅ COA Helper
const { postTransactionToCOA, ChartOfAccount } = require('./chart_of_accounts');

async function getSystemAccountId(name) {
  try {
    const acc = await ChartOfAccount.findOne({
      accountName: name,
      isSystemAccount: true
    }).select('_id').lean();
    return acc ? acc._id : null;
  } catch (e) {
    console.error(`COA lookup error for "${name}":`, e.message);
    return null;
  }
}

// ============================================================================
// MONGOOSE MODELS
// ============================================================================

// Bill Schema - mirrors Zoho Books Bill structure
const billSchema = new mongoose.Schema({
  billNumber: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  vendorId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Vendor',
    required: true
  },
  vendorName: {
    type: String,
    required: true
  },
  vendorEmail: String,
  vendorPhone: String,
  vendorGSTIN: String,
  billingAddress: {
    street: String,
    city: String,
    state: String,
    pincode: String,
    country: { type: String, default: 'India' }
  },

  // Bill Details
  purchaseOrderNumber: String,   // Link to PO
  billDate: {
    type: Date,
    required: true,
    default: Date.now
  },
  dueDate: {
    type: Date,
    required: true
  },
  paymentTerms: {
    type: String,
    enum: ['Due on Receipt', 'Net 15', 'Net 30', 'Net 45', 'Net 60'],
    default: 'Net 30'
  },
  subject: String,
  notes: String,
  termsAndConditions: String,

  // Line Items
  items: [{
    itemDetails: {
      type: String,
      required: true
    },
    account: String,           // Expense account (e.g., Office Supplies)
    quantity: {
      type: Number,
      required: true,
      min: 0
    },
    rate: {
      type: Number,
      required: true,
      min: 0
    },
    discount: {
      type: Number,
      default: 0,
      min: 0
    },
    discountType: {
      type: String,
      enum: ['percentage', 'amount'],
      default: 'percentage'
    },
    amount: {
      type: Number,
      required: true
    }
  }],

  // Attachments
  attachments: [{
    filename: String,
    filepath: String,
    uploadedAt: Date
  }],

  // Financial Calculations
  subTotal: {
    type: Number,
    required: true,
    default: 0
  },
  tdsRate: {
    type: Number,
    default: 0,
    min: 0,
    max: 100
  },
  tdsAmount: {
    type: Number,
    default: 0
  },
  tcsRate: {
    type: Number,
    default: 0,
    min: 0,
    max: 100
  },
  tcsAmount: {
    type: Number,
    default: 0
  },
  gstRate: {
    type: Number,
    default: 18,
    min: 0,
    max: 100
  },
  cgst: {
    type: Number,
    default: 0
  },
  sgst: {
    type: Number,
    default: 0
  },
  igst: {
    type: Number,
    default: 0
  },
  totalAmount: {
    type: Number,
    required: true,
    default: 0
  },

  // Status Management - Zoho Books Bill statuses
  status: {
    type: String,
    enum: ['DRAFT', 'OPEN', 'PARTIALLY_PAID', 'PAID', 'OVERDUE', 'VOID', 'CANCELLED'],
    default: 'DRAFT',
    index: true
  },

  // Payment Information
  amountPaid: {
    type: Number,
    default: 0
  },
  amountDue: {
    type: Number,
    default: 0
  },
  payments: [{
    paymentId: mongoose.Schema.Types.ObjectId,
    amount: Number,
    paymentDate: Date,
    paymentMode: {
      type: String,
      enum: ['Cash', 'Cheque', 'Bank Transfer', 'UPI', 'Card', 'Online', 'NEFT', 'RTGS', 'IMPS']
    },
    referenceNumber: String,
    notes: String,
    recordedBy: String,
    recordedAt: Date
  }],

  // Vendor Credits Applied
  vendorCreditsApplied: [{
    creditId: mongoose.Schema.Types.ObjectId,
    amount: Number,
    appliedDate: Date
  }],

  // Recurring Bill Settings
  isRecurring: {
    type: Boolean,
    default: false
  },
  recurringProfileId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'RecurringBillProfile'
  },

  // PDF
  pdfPath: String,
  pdfGeneratedAt: Date,

  // Approval Workflow
  approvalStatus: {
    type: String,
    enum: ['PENDING_APPROVAL', 'APPROVED', 'REJECTED', null],
    default: null
  },
  approvedBy: String,
  approvedAt: Date,

  // Audit Trail
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

// Pre-save middleware to calculate amounts
billSchema.pre('save', function(next) {
  // Calculate subtotal
  this.subTotal = this.items.reduce((sum, item) => sum + item.amount, 0);

  // Calculate TDS (reduces total)
  this.tdsAmount = (this.subTotal * this.tdsRate) / 100;

  // Calculate TCS (increases total)
  this.tcsAmount = (this.subTotal * this.tcsRate) / 100;

  // Calculate GST on adjusted base
  const gstBase = this.subTotal - this.tdsAmount + this.tcsAmount;
  const gstAmount = (gstBase * this.gstRate) / 100;

  // Intra-state: CGST + SGST, inter-state: IGST
  this.cgst = gstAmount / 2;
  this.sgst = gstAmount / 2;
  this.igst = 0;

  // Calculate total
  this.totalAmount = this.subTotal - this.tdsAmount + this.tcsAmount + gstAmount;

  // Calculate amount due
  this.amountDue = this.totalAmount - this.amountPaid;

  // Auto-update status based on payment
  if (this.status !== 'DRAFT' && this.status !== 'VOID' && this.status !== 'CANCELLED') {
    if (this.amountPaid === 0) {
      this.status = 'OPEN';
    } else if (this.amountPaid > 0 && this.amountPaid < this.totalAmount) {
      this.status = 'PARTIALLY_PAID';
    } else if (this.amountPaid >= this.totalAmount) {
      this.status = 'PAID';
    }

    // Check overdue
    if (this.status !== 'PAID' && this.dueDate < new Date()) {
      this.status = 'OVERDUE';
    }
  }

  next();
});

// Indexes for performance
billSchema.index({ vendorId: 1, billDate: -1 });
billSchema.index({ status: 1, dueDate: 1 });
billSchema.index({ createdAt: -1 });

const Bill = mongoose.model('Bill', billSchema);

// ============================================================================
// VENDOR SCHEMA
// ============================================================================

const vendorSchema = new mongoose.Schema({
  vendorName: {
    type: String,
    required: true,
    trim: true,
    index: true
  },
  vendorEmail: {
    type: String,
    required: true,
    trim: true,
    lowercase: true,
    index: true
  },
  vendorPhone: {
    type: String,
    required: true,
    trim: true
  },
  companyName: {
    type: String,
    trim: true
  },
  gstNumber: {
    type: String,
    trim: true,
    uppercase: true
  },
  panNumber: {
    type: String,
    trim: true,
    uppercase: true
  },
  billingAddress: {
    street: { type: String, trim: true },
    city: { type: String, trim: true },
    state: { type: String, trim: true },
    pincode: { type: String, trim: true },
    country: { type: String, default: 'India', trim: true }
  },
  paymentTerms: {
    type: String,
    enum: ['Due on Receipt', 'Net 15', 'Net 30', 'Net 45', 'Net 60'],
    default: 'Net 30'
  },
  bankDetails: {
    accountHolder: String,
    accountNumber: String,
    ifscCode: String,
    bankName: String,
    upiId: String
  },
  notes: String,
  isActive: {
    type: Boolean,
    default: true,
    index: true
  },
  createdBy: { type: String, required: true },
  updatedBy: String,
  createdAt: { type: Date, default: Date.now },
  updatedAt: { type: Date, default: Date.now }
}, {
  timestamps: true,
  collection: 'vendors'
});

vendorSchema.index({ vendorName: 1, vendorEmail: 1 });
vendorSchema.index({ createdAt: -1 });

vendorSchema.pre('save', function(next) {
  this.updatedAt = new Date();
  next();
});

// Check if model exists before creating to avoid OverwriteModelError
const Vendor = mongoose.models.Vendor || mongoose.model('Vendor', vendorSchema);

// ============================================================================
// RECURRING BILL PROFILE SCHEMA
// ============================================================================

const recurringBillProfileSchema = new mongoose.Schema({
  profileName: {
    type: String,
    required: true
  },
  vendorId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Vendor',
    required: true
  },
  vendorName: String,
  vendorEmail: String,

  // Recurrence Settings
  repeatEvery: {
    type: Number,
    required: true,
    default: 1
  },
  repeatUnit: {
    type: String,
    enum: ['days', 'weeks', 'months', 'years'],
    default: 'months'
  },
  startDate: {
    type: Date,
    required: true
  },
  endDate: Date,
  maxOccurrences: Number,
  occurrencesCount: {
    type: Number,
    default: 0
  },

  // Bill Template
  billTemplate: {
    items: [{
      itemDetails: String,
      account: String,
      quantity: Number,
      rate: Number,
      discount: Number,
      discountType: String,
      amount: Number
    }],
    paymentTerms: String,
    subject: String,
    notes: String,
    tdsRate: Number,
    tcsRate: Number,
    gstRate: Number
  },

  // Status
  status: {
    type: String,
    enum: ['ACTIVE', 'PAUSED', 'EXPIRED', 'STOPPED'],
    default: 'ACTIVE'
  },

  // Next bill date
  nextBillDate: Date,
  lastBillDate: Date,

  // Bills generated from this profile
  generatedBills: [{
    billId: mongoose.Schema.Types.ObjectId,
    billNumber: String,
    createdDate: Date
  }],

  createdBy: String,
  updatedBy: String,
  createdAt: { type: Date, default: Date.now },
  updatedAt: { type: Date, default: Date.now }
}, { timestamps: true });

const RecurringBillProfile = mongoose.model('RecurringBillProfile', recurringBillProfileSchema);

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

// Generate unique bill number
async function generateBillNumber() {
  const date = new Date();
  const year = date.getFullYear().toString().slice(-2);
  const month = (date.getMonth() + 1).toString().padStart(2, '0');

  const lastBill = await Bill.findOne({
    billNumber: new RegExp(`^BILL-${year}${month}`)
  }).sort({ billNumber: -1 });

  let sequence = 1;
  if (lastBill) {
    const lastSequence = parseInt(lastBill.billNumber.split('-')[2]);
    sequence = lastSequence + 1;
  }

  return `BILL-${year}${month}-${sequence.toString().padStart(4, '0')}`;
}

// Calculate due date based on payment terms
function calculateDueDate(billDate, terms) {
  const date = new Date(billDate);
  switch (terms) {
    case 'Due on Receipt': return date;
    case 'Net 15': date.setDate(date.getDate() + 15); return date;
    case 'Net 30': date.setDate(date.getDate() + 30); return date;
    case 'Net 45': date.setDate(date.getDate() + 45); return date;
    case 'Net 60': date.setDate(date.getDate() + 60); return date;
    default: date.setDate(date.getDate() + 30); return date;
  }
}

// Calculate item amount
function calculateItemAmount(item) {
  let amount = item.quantity * item.rate;
  if (item.discount > 0) {
    if (item.discountType === 'percentage') {
      amount = amount - (amount * item.discount / 100);
    } else {
      amount = amount - item.discount;
    }
  }
  return Math.round(amount * 100) / 100;
}

// ============================================================================
// PDF GENERATION
// ============================================================================

async function generateBillPDF(bill) {
  return new Promise((resolve, reject) => {
    try {
      const uploadsDir = path.join(__dirname, '..', 'uploads', 'bills');
      if (!fs.existsSync(uploadsDir)) {
        fs.mkdirSync(uploadsDir, { recursive: true });
      }

      const filename = `bill-${bill.billNumber}.pdf`;
      const filepath = path.join(uploadsDir, filename);
      const doc = new PDFDocument({ size: 'A4', margin: 50 });
      const stream = fs.createWriteStream(filepath);

      doc.pipe(stream);

      // Header
      doc.fontSize(24).fillColor('#2C3E50').text('ABRA FLEET', 50, 50)
         .fontSize(10).fillColor('#7F8C8D')
         .text('Fleet Management Solutions', 50, 80)
         .text('GST: 29XXXXX1234X1Z5', 50, 95);

      // Bill Title
      doc.fontSize(28).fillColor('#2C3E50').text('BILL', 400, 50, { align: 'right' });

      // Bill Details
      doc.fontSize(10).fillColor('#34495E')
         .text(`Bill #: ${bill.billNumber}`, 400, 90, { align: 'right' })
         .text(`Date: ${new Date(bill.billDate).toLocaleDateString('en-IN')}`, 400, 105, { align: 'right' })
         .text(`Due Date: ${new Date(bill.dueDate).toLocaleDateString('en-IN')}`, 400, 120, { align: 'right' });

      if (bill.purchaseOrderNumber) {
        doc.text(`PO #: ${bill.purchaseOrderNumber}`, 400, 135, { align: 'right' });
      }

      // Separator
      doc.moveTo(50, 160).lineTo(545, 160).strokeColor('#BDC3C7').stroke();

      // Vendor Info
      doc.fontSize(12).fillColor('#2C3E50').text('VENDOR:', 50, 180);
      doc.fontSize(11).fillColor('#34495E').text(bill.vendorName, 50, 200)
         .fontSize(10).fillColor('#7F8C8D');

      let yPos = 215;
      if (bill.billingAddress) {
        if (bill.billingAddress.street) { doc.text(bill.billingAddress.street, 50, yPos); yPos += 15; }
        const cityLine = [bill.billingAddress.city, bill.billingAddress.state, bill.billingAddress.pincode].filter(Boolean).join(', ');
        if (cityLine) { doc.text(cityLine, 50, yPos); yPos += 15; }
      }
      if (bill.vendorEmail) { doc.text(`Email: ${bill.vendorEmail}`, 50, yPos); yPos += 15; }
      if (bill.vendorPhone) { doc.text(`Phone: ${bill.vendorPhone}`, 50, yPos); }
      if (bill.vendorGSTIN) { doc.text(`GSTIN: ${bill.vendorGSTIN}`, 50, yPos + 15); }

      // Items Table Header
      yPos = 310;
      doc.fontSize(10).fillColor('#FFFFFF').rect(50, yPos, 495, 25).fill('#34495E');
      doc.fillColor('#FFFFFF')
         .text('ITEM DETAILS', 60, yPos + 8)
         .text('ACCOUNT', 250, yPos + 8)
         .text('QTY', 340, yPos + 8, { width: 40, align: 'center' })
         .text('RATE', 390, yPos + 8, { width: 60, align: 'right' })
         .text('AMOUNT', 460, yPos + 8, { width: 75, align: 'right' });

      // Items
      yPos += 35;
      doc.fillColor('#34495E');
      bill.items.forEach((item) => {
        if (yPos > 680) { doc.addPage(); yPos = 50; }
        doc.fontSize(10)
           .text(item.itemDetails, 60, yPos, { width: 180 })
           .text(item.account || '-', 250, yPos, { width: 80 })
           .text(item.quantity.toString(), 340, yPos, { width: 40, align: 'center' })
           .text(`Rs.${item.rate.toFixed(2)}`, 390, yPos, { width: 60, align: 'right' })
           .text(`Rs.${item.amount.toFixed(2)}`, 460, yPos, { width: 75, align: 'right' });
        yPos += 25;
        doc.moveTo(50, yPos).lineTo(545, yPos).strokeColor('#ECF0F1').stroke();
        yPos += 5;
      });

      // Summary
      yPos += 20;
      const summaryX = 360;
      doc.fontSize(10).fillColor('#7F8C8D').text('Sub Total:', summaryX, yPos)
         .fillColor('#34495E').text(`Rs.${bill.subTotal.toFixed(2)}`, summaryX + 110, yPos, { align: 'right' });
      yPos += 20;

      if (bill.tdsAmount > 0) {
        doc.fillColor('#7F8C8D').text(`TDS (${bill.tdsRate}%):`, summaryX, yPos)
           .fillColor('#E74C3C').text(`- Rs.${bill.tdsAmount.toFixed(2)}`, summaryX + 110, yPos, { align: 'right' });
        yPos += 20;
      }
      if (bill.tcsAmount > 0) {
        doc.fillColor('#7F8C8D').text(`TCS (${bill.tcsRate}%):`, summaryX, yPos)
           .fillColor('#34495E').text(`Rs.${bill.tcsAmount.toFixed(2)}`, summaryX + 110, yPos, { align: 'right' });
        yPos += 20;
      }
      if (bill.cgst > 0) {
        doc.fillColor('#7F8C8D').text(`CGST (${(bill.gstRate / 2).toFixed(1)}%):`, summaryX, yPos)
           .fillColor('#34495E').text(`Rs.${bill.cgst.toFixed(2)}`, summaryX + 110, yPos, { align: 'right' });
        yPos += 15;
        doc.fillColor('#7F8C8D').text(`SGST (${(bill.gstRate / 2).toFixed(1)}%):`, summaryX, yPos)
           .fillColor('#34495E').text(`Rs.${bill.sgst.toFixed(2)}`, summaryX + 110, yPos, { align: 'right' });
        yPos += 20;
      }

      // Total line
      doc.moveTo(summaryX, yPos).lineTo(545, yPos).strokeColor('#34495E').lineWidth(2).stroke();
      yPos += 15;
      doc.fontSize(14).fillColor('#2C3E50')
         .text('Total Amount:', summaryX, yPos)
         .text(`Rs.${bill.totalAmount.toFixed(2)}`, summaryX + 110, yPos, { align: 'right' });

      // Amount Due
      yPos += 30;
      if (bill.amountDue > 0) {
        doc.fontSize(12).fillColor('#E74C3C')
           .text(`Amount Due: Rs.${bill.amountDue.toFixed(2)}`, summaryX, yPos, { align: 'right' });
        yPos += 20;
      }

      // Status Badge
      let statusColor;
      switch (bill.status) {
        case 'PAID': statusColor = '#27AE60'; break;
        case 'PARTIALLY_PAID': statusColor = '#F39C12'; break;
        case 'OVERDUE': statusColor = '#E74C3C'; break;
        default: statusColor = '#95A5A6';
      }
      doc.rect(summaryX, yPos, 175, 25).fill(statusColor);
      doc.fontSize(12).fillColor('#FFFFFF').text(bill.status.replace('_', ' '), summaryX, yPos + 7, { width: 175, align: 'center' });

      // Notes
      if (bill.notes || bill.termsAndConditions) {
        yPos += 50;
        if (yPos > 650) { doc.addPage(); yPos = 50; }
        if (bill.notes) {
          doc.fontSize(11).fillColor('#2C3E50').text('Notes:', 50, yPos);
          doc.fontSize(10).fillColor('#7F8C8D').text(bill.notes, 50, yPos + 20, { width: 495 });
          yPos += 60;
        }
        if (bill.termsAndConditions) {
          doc.fontSize(11).fillColor('#2C3E50').text('Terms & Conditions:', 50, yPos);
          doc.fontSize(9).fillColor('#7F8C8D').text(bill.termsAndConditions, 50, yPos + 20, { width: 495 });
        }
      }

      // Footer
      doc.fontSize(9).fillColor('#95A5A6')
         .text('This is a bill received from vendor.', 50, 750, { align: 'center', width: 495 })
         .text('For queries, contact: billing@abrafleet.com | +91-XXXXXXXXXX', 50, 765, { align: 'center', width: 495 });

      doc.end();
      stream.on('finish', () => {
        resolve({ filename, filepath, relativePath: `/uploads/bills/${filename}` });
      });
      stream.on('error', reject);
    } catch (error) {
      reject(error);
    }
  });
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

async function sendBillEmail(bill, pdfPath) {
  const emailHtml = `
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #2C3E50 0%, #34495E 100%); color: white; padding: 30px; text-align: center; border-radius: 8px 8px 0 0; }
    .content { background: #f8f9fa; padding: 30px; border-radius: 0 0 8px 8px; }
    .bill-box { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; border-left: 4px solid #E74C3C; }
    .bill-detail { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid #ecf0f1; }
    .total-amount { font-size: 24px; color: #E74C3C; text-align: center; margin: 20px 0; padding: 15px; background: #fdedec; border-radius: 8px; }
    .footer { text-align: center; color: #95a5a6; font-size: 12px; margin-top: 30px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🚗 ABRA FLEET</h1>
      <p style="margin: 10px 0 0 0; opacity: 0.9;">Fleet Management Solutions</p>
    </div>
    <div class="content">
      <h2 style="color: #2c3e50; margin-top: 0;">Bill from ${bill.vendorName}</h2>
      <p>Dear Team,</p>
      <p>A new bill has been recorded from <strong>${bill.vendorName}</strong>. Please find the details below:</p>
      <div class="bill-box">
        <div class="bill-detail"><span>Bill Number:</span><span><strong>${bill.billNumber}</strong></span></div>
        <div class="bill-detail"><span>Bill Date:</span><span>${new Date(bill.billDate).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}</span></div>
        <div class="bill-detail"><span>Due Date:</span><span>${new Date(bill.dueDate).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}</span></div>
        <div class="bill-detail"><span>Payment Terms:</span><span>${bill.paymentTerms}</span></div>
        <div class="bill-detail"><span>Status:</span><span><strong>${bill.status}</strong></span></div>
      </div>
      <div class="total-amount">
        <div style="font-size: 14px; color: #7f8c8d; margin-bottom: 5px;">Total Amount Due</div>
        <strong>₹${bill.totalAmount.toFixed(2)}</strong>
      </div>
      <p>The bill PDF is attached to this email for your records.</p>
    </div>
    <div class="footer">
      <p><strong>Abra Fleet Management Solutions</strong></p>
      <p>This is an automated email from the billing system.</p>
    </div>
  </div>
</body>
</html>`;

  return emailTransporter.sendMail({
    from: `"Abra Fleet Billing" <${process.env.SMTP_USER}>`,
    to: process.env.BILLING_EMAIL || process.env.SMTP_USER,
    subject: `Bill ${bill.billNumber} from ${bill.vendorName} - ₹${bill.totalAmount.toFixed(2)}`,
    html: emailHtml,
    attachments: [{ filename: `Bill-${bill.billNumber}.pdf`, path: pdfPath }]
  });
}

async function sendPaymentConfirmationEmail(bill, payment) {
  const emailHtml = `
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #27ae60 0%, #229954 100%); color: white; padding: 30px; text-align: center; border-radius: 8px 8px 0 0; }
    .content { background: #f8f9fa; padding: 30px; border-radius: 0 0 8px 8px; }
    .success-badge { background: #d4edda; color: #155724; padding: 15px; border-radius: 8px; text-align: center; margin: 20px 0; }
    .payment-box { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; }
    .payment-detail { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid #ecf0f1; }
    .footer { text-align: center; color: #95a5a6; font-size: 12px; margin-top: 30px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header"><h1>✅ Payment Recorded</h1></div>
    <div class="content">
      <div class="success-badge">
        <h2 style="margin: 0;">Payment of ₹${payment.amount.toFixed(2)} recorded</h2>
        <p>For Bill: ${bill.billNumber}</p>
      </div>
      <div class="payment-box">
        <div class="payment-detail"><span>Bill Number:</span><span>${bill.billNumber}</span></div>
        <div class="payment-detail"><span>Vendor:</span><span>${bill.vendorName}</span></div>
        <div class="payment-detail"><span>Amount Paid:</span><span>₹${payment.amount.toFixed(2)}</span></div>
        <div class="payment-detail"><span>Payment Date:</span><span>${new Date(payment.paymentDate).toLocaleDateString('en-IN')}</span></div>
        <div class="payment-detail"><span>Payment Mode:</span><span>${payment.paymentMode}</span></div>
        ${payment.referenceNumber ? `<div class="payment-detail"><span>Reference:</span><span>${payment.referenceNumber}</span></div>` : ''}
        <div class="payment-detail" style="border:none; font-weight:bold; font-size:18px; color:#27ae60; margin-top:10px;">
          <span>Remaining Balance:</span><span>₹${bill.amountDue.toFixed(2)}</span>
        </div>
      </div>
    </div>
    <div class="footer"><p>Abra Fleet Management | billing@abrafleet.com</p></div>
  </div>
</body>
</html>`;

  return emailTransporter.sendMail({
    from: `"Abra Fleet Billing" <${process.env.SMTP_USER}>`,
    to: process.env.BILLING_EMAIL || process.env.SMTP_USER,
    subject: `Payment Recorded - ${bill.billNumber} - ₹${payment.amount.toFixed(2)}`,
    html: emailHtml
  });
}

// ============================================================================
// API ROUTES - BILLS
// ============================================================================

// GET /api/bills - List all bills with filters
router.get('/', async (req, res) => {
  try {
    const { status, vendorId, fromDate, toDate, search, page = 1, limit = 20 } = req.query;
    const query = {};

    if (status && status !== 'All') query.status = status;
    if (vendorId) query.vendorId = vendorId;
    if (fromDate || toDate) {
      query.billDate = {};
      if (fromDate) query.billDate.$gte = new Date(fromDate);
      if (toDate) query.billDate.$lte = new Date(toDate);
    }
    if (search) {
      query.$or = [
        { billNumber: { $regex: search, $options: 'i' } },
        { vendorName: { $regex: search, $options: 'i' } },
        { purchaseOrderNumber: { $regex: search, $options: 'i' } }
      ];
    }

    const skip = (parseInt(page) - 1) * parseInt(limit);
    const bills = await Bill.find(query).sort({ createdAt: -1 }).skip(skip).limit(parseInt(limit)).select('-__v');
    const total = await Bill.countDocuments(query);

    res.json({
      success: true,
      data: bills,
      pagination: { total, page: parseInt(page), limit: parseInt(limit), pages: Math.ceil(total / parseInt(limit)) }
    });
  } catch (error) {
    console.error('Error fetching bills:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/bills/stats
router.get('/stats', async (req, res) => {
  try {
    const stats = await Bill.aggregate([
      { $group: { _id: '$status', count: { $sum: 1 }, totalAmount: { $sum: '$totalAmount' }, totalPaid: { $sum: '$amountPaid' }, totalDue: { $sum: '$amountDue' } } }
    ]);

    const overallStats = { totalBills: 0, totalPayable: 0, totalPaid: 0, totalDue: 0, byStatus: {} };
    stats.forEach(stat => {
      overallStats.totalBills += stat.count;
      overallStats.totalPayable += stat.totalAmount;
      overallStats.totalPaid += stat.totalPaid;
      overallStats.totalDue += stat.totalDue;
      overallStats.byStatus[stat._id] = { count: stat.count, amount: stat.totalAmount };
    });

    res.json({ success: true, data: overallStats });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// VENDOR ROUTES - Before /:id to avoid conflicts
// ============================================================================

// GET /api/bills/vendors
router.get('/vendors', async (req, res) => {
  try {
    const { search, page = 1, limit = 50, active = 'true' } = req.query;
    const query = {};
    if (active !== 'all') query.isActive = active === 'true';
    if (search) {
      query.$or = [
        { vendorName: { $regex: search, $options: 'i' } },
        { vendorEmail: { $regex: search, $options: 'i' } },
        { companyName: { $regex: search, $options: 'i' } }
      ];
    }

    const skip = (parseInt(page) - 1) * parseInt(limit);
    const vendors = await Vendor.find(query).sort({ vendorName: 1 }).skip(skip).limit(parseInt(limit)).select('-__v');
    const total = await Vendor.countDocuments(query);

    res.json({ success: true, data: vendors, pagination: { total, page: parseInt(page), limit: parseInt(limit), pages: Math.ceil(total / parseInt(limit)) } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/bills/vendors
router.post('/vendors', async (req, res) => {
  try {
    const vendorData = req.body;
    if (!vendorData.vendorName || !vendorData.vendorEmail || !vendorData.vendorPhone) {
      return res.status(400).json({ success: false, error: 'Vendor name, email, and phone are required' });
    }

    const existingVendor = await Vendor.findOne({ vendorEmail: vendorData.vendorEmail.toLowerCase(), isActive: true });
    if (existingVendor) {
      return res.status(400).json({ success: false, error: 'Vendor with this email already exists' });
    }

    vendorData.createdBy = req.user?.email || req.user?.uid || 'system';
    const vendor = new Vendor(vendorData);
    await vendor.save();

    res.status(201).json({ success: true, message: 'Vendor created successfully', data: vendor });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/bills/vendors/:id
router.put('/vendors/:id', async (req, res) => {
  try {
    const vendor = await Vendor.findById(req.params.id);
    if (!vendor) return res.status(404).json({ success: false, error: 'Vendor not found' });

    const updates = req.body;
    updates.updatedBy = req.user?.email || req.user?.uid || 'system';
    Object.assign(vendor, updates);
    await vendor.save();

    res.json({ success: true, message: 'Vendor updated successfully', data: vendor });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/bills/vendors/:id - Soft delete
router.delete('/vendors/:id', async (req, res) => {
  try {
    const vendor = await Vendor.findById(req.params.id);
    if (!vendor) return res.status(404).json({ success: false, error: 'Vendor not found' });

    vendor.isActive = false;
    vendor.updatedBy = req.user?.email || req.user?.uid || 'system';
    await vendor.save();

    res.json({ success: true, message: 'Vendor deactivated successfully' });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/bills/vendors/:id
router.get('/vendors/:id', async (req, res) => {
  try {
    const vendor = await Vendor.findById(req.params.id);
    if (!vendor) return res.status(404).json({ success: false, error: 'Vendor not found' });
    res.json({ success: true, data: vendor });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// RECURRING BILL PROFILE ROUTES
// ============================================================================

// GET /api/bills/recurring-profiles
router.get('/recurring-profiles', async (req, res) => {
  try {
    const { status } = req.query;
    const query = {};
    if (status) query.status = status;

    const profiles = await RecurringBillProfile.find(query).sort({ createdAt: -1 });
    res.json({ success: true, data: profiles });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/bills/recurring-profiles
router.post('/recurring-profiles', async (req, res) => {
  try {
    const profileData = req.body;
    profileData.createdBy = req.user?.email || req.user?.uid || 'system';

    // Calculate next bill date
    const startDate = new Date(profileData.startDate);
    profileData.nextBillDate = startDate;

    const profile = new RecurringBillProfile(profileData);
    await profile.save();

    res.status(201).json({ success: true, message: 'Recurring profile created', data: profile });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/bills/recurring-profiles/:id/pause
router.put('/recurring-profiles/:id/pause', async (req, res) => {
  try {
    const profile = await RecurringBillProfile.findById(req.params.id);
    if (!profile) return res.status(404).json({ success: false, error: 'Profile not found' });
    profile.status = 'PAUSED';
    await profile.save();
    res.json({ success: true, message: 'Profile paused', data: profile });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/bills/recurring-profiles/:id/resume
router.put('/recurring-profiles/:id/resume', async (req, res) => {
  try {
    const profile = await RecurringBillProfile.findById(req.params.id);
    if (!profile) return res.status(404).json({ success: false, error: 'Profile not found' });
    profile.status = 'ACTIVE';
    await profile.save();
    res.json({ success: true, message: 'Profile resumed', data: profile });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/bills/recurring-profiles/:id
router.delete('/recurring-profiles/:id', async (req, res) => {
  try {
    const profile = await RecurringBillProfile.findById(req.params.id);
    if (!profile) return res.status(404).json({ success: false, error: 'Profile not found' });
    profile.status = 'STOPPED';
    await profile.save();
    res.json({ success: true, message: 'Profile stopped' });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// BILL CRUD ROUTES
// ============================================================================

// GET /api/bills/:id
router.get('/:id', async (req, res) => {
  try {
    const bill = await Bill.findById(req.params.id);
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });
    res.json({ success: true, data: bill });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/bills - Create new bill
router.post('/', async (req, res) => {
  try {
    const billData = req.body;

    // Handle vendorId
    if (billData.vendorId) {
      if (typeof billData.vendorId === 'string') {
        if (mongoose.Types.ObjectId.isValid(billData.vendorId)) {
          billData.vendorId = new mongoose.Types.ObjectId(billData.vendorId);
        } else {
          billData.vendorId = new mongoose.Types.ObjectId();
        }
      }
    } else {
      billData.vendorId = new mongoose.Types.ObjectId();
    }

    // Generate bill number
    if (!billData.billNumber) {
      billData.billNumber = await generateBillNumber();
    }

    // Calculate due date
    if (!billData.dueDate) {
      billData.dueDate = calculateDueDate(billData.billDate || new Date(), billData.paymentTerms || 'Net 30');
    }

    // Calculate item amounts
    if (billData.items) {
      billData.items = billData.items.map(item => ({
        ...item,
        amount: calculateItemAmount(item)
      }));
    }

    billData.createdBy = req.user?.email || req.user?.uid || 'system';

    const bill = new Bill(billData);
    await bill.save();

// ✅ COA: Debit Expense + Credit Accounts Payable + TDS + TCS
try {
  const [expenseId, apId, taxId, tdsPayableId, tdsReceivableId] = await Promise.all([
    getSystemAccountId('Cost of Goods Sold'),
    getSystemAccountId('Accounts Payable'),
    getSystemAccountId('Tax Payable'),
    getSystemAccountId('TDS Payable'),
    getSystemAccountId('TDS Receivable'),
  ]);
  const txnDate = new Date(bill.billDate);

  if (expenseId) await postTransactionToCOA({
    accountId: expenseId, date: txnDate,
    description: `Bill ${bill.billNumber} - ${bill.vendorName}`,
    referenceType: 'Bill', referenceId: bill._id,
    referenceNumber: bill.billNumber,
    debit: bill.subTotal, credit: 0
  });

  if (apId) await postTransactionToCOA({
    accountId: apId, date: txnDate,
    description: `Bill ${bill.billNumber} - ${bill.vendorName}`,
    referenceType: 'Bill', referenceId: bill._id,
    referenceNumber: bill.billNumber,
    debit: 0, credit: bill.totalAmount
  });

  if (taxId && (bill.cgst + bill.sgst) > 0) await postTransactionToCOA({
    accountId: taxId, date: txnDate,
    description: `GST on Bill ${bill.billNumber}`,
    referenceType: 'Bill', referenceId: bill._id,
    referenceNumber: bill.billNumber,
    debit: bill.cgst + bill.sgst, credit: 0
  });

  if (tdsPayableId && bill.tdsAmount > 0) await postTransactionToCOA({
    accountId: tdsPayableId, date: txnDate,
    description: `TDS on Bill ${bill.billNumber} - ${bill.vendorName}`,
    referenceType: 'Bill', referenceId: bill._id,
    referenceNumber: bill.billNumber,
    debit: 0, credit: bill.tdsAmount
  });

  if (tdsReceivableId && bill.tcsAmount > 0) await postTransactionToCOA({
    accountId: tdsReceivableId, date: txnDate,
    description: `TCS on Bill ${bill.billNumber} - ${bill.vendorName}`,
    referenceType: 'Bill', referenceId: bill._id,
    referenceNumber: bill.billNumber,
    debit: bill.tcsAmount, credit: 0
  });

  console.log(`✅ COA posted for bill: ${bill.billNumber}`);
} catch (coaErr) {
  console.error('⚠️ COA post error (bill create):', coaErr.message);
}

    console.log(`✅ Bill created: ${bill.billNumber}`);
    res.status(201).json({ success: true, message: 'Bill created successfully', data: bill });
  } catch (error) {
    console.error('Error creating bill:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/bills/:id - Update bill
router.put('/:id', async (req, res) => {
  try {
    const bill = await Bill.findById(req.params.id);
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });

    if (bill.status === 'PAID') {
      return res.status(400).json({ success: false, error: 'Cannot edit paid bills' });
    }

    const updates = req.body;

    if (updates.items) {
      updates.items = updates.items.map(item => ({
        ...item,
        amount: calculateItemAmount(item)
      }));
    }

    if (updates.paymentTerms && updates.paymentTerms !== bill.paymentTerms) {
      updates.dueDate = calculateDueDate(updates.billDate || bill.billDate, updates.paymentTerms);
    }

    updates.updatedBy = req.user?.email || req.user?.uid || 'system';
    Object.assign(bill, updates);
    await bill.save();

    res.json({ success: true, message: 'Bill updated successfully', data: bill });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/bills/:id/submit - Submit draft for approval or to Open
router.post('/:id/submit', async (req, res) => {
  try {
    const bill = await Bill.findById(req.params.id);
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });

    if (bill.status !== 'DRAFT') {
      return res.status(400).json({ success: false, error: 'Only draft bills can be submitted' });
    }

    bill.status = 'OPEN';
    await bill.save();

    res.json({ success: true, message: 'Bill submitted successfully', data: bill });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/bills/:id/void - Void a bill
router.post('/:id/void', async (req, res) => {
  try {
    const bill = await Bill.findById(req.params.id);
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });

    if (bill.status === 'PAID') {
      return res.status(400).json({ success: false, error: 'Cannot void a paid bill' });
    }

    bill.status = 'VOID';
    await bill.save();

    res.json({ success: true, message: 'Bill voided successfully', data: bill });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/bills/:id/send - Generate PDF and send notification
router.post('/:id/send', async (req, res) => {
  try {
    const bill = await Bill.findById(req.params.id);
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });

    let pdfInfo;
    if (!bill.pdfPath || !fs.existsSync(bill.pdfPath)) {
      pdfInfo = await generateBillPDF(bill);
      bill.pdfPath = pdfInfo.filepath;
      bill.pdfGeneratedAt = new Date();
    }

    try {
      await sendBillEmail(bill, bill.pdfPath);
    } catch (emailErr) {
      console.warn('Email send failed:', emailErr.message);
    }

    if (bill.status === 'DRAFT') bill.status = 'OPEN';
    await bill.save();

    res.json({ success: true, message: 'Bill sent successfully', data: bill });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/bills/:id/payment - Record payment against bill
router.post('/:id/payment', async (req, res) => {
  try {
    const bill = await Bill.findById(req.params.id);
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });

    const { amount, paymentDate, paymentMode, referenceNumber, notes } = req.body;

    if (!amount || amount <= 0) {
      return res.status(400).json({ success: false, error: 'Invalid payment amount' });
    }

    if (bill.amountDue < amount) {
      return res.status(400).json({ success: false, error: `Payment exceeds due amount (₹${bill.amountDue.toFixed(2)})` });
    }

    const payment = {
      paymentId: new mongoose.Types.ObjectId(),
      amount: parseFloat(amount),
      paymentDate: paymentDate ? new Date(paymentDate) : new Date(),
      paymentMode: paymentMode || 'Bank Transfer',
      referenceNumber,
      notes,
      recordedBy: req.user?.email || req.user?.uid || 'system',
      recordedAt: new Date()
    };

    bill.payments.push(payment);
    bill.amountPaid += payment.amount;
    await bill.save();


    // ✅ COA: Debit Accounts Payable + Credit Undeposited Funds
try {
  const [apId, cashId] = await Promise.all([
    getSystemAccountId('Accounts Payable'),
    getSystemAccountId('Undeposited Funds'),
  ]);
  const txnDate = new Date(payment.paymentDate);
  if (apId) await postTransactionToCOA({
    accountId: apId, date: txnDate,
    description: `Payment made - ${bill.billNumber}`,
    referenceType: 'Payment', referenceId: payment.paymentId,
    referenceNumber: bill.billNumber,
    debit: payment.amount, credit: 0
  });
  if (cashId) await postTransactionToCOA({
    accountId: cashId, date: txnDate,
    description: `Payment made - ${bill.billNumber}`,
    referenceType: 'Payment', referenceId: payment.paymentId,
    referenceNumber: bill.billNumber,
    debit: 0, credit: payment.amount
  });
  console.log(`✅ COA posted for payment on: ${bill.billNumber}`);
} catch (coaErr) {
  console.error('⚠️ COA post error (bill payment):', coaErr.message);
}

    try {
      await sendPaymentConfirmationEmail(bill, payment);
    } catch (emailErr) {
      console.warn('Payment email failed:', emailErr.message);
    }

    res.json({ success: true, message: 'Payment recorded successfully', data: { bill, payment } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/bills/:id/pdf - Download PDF
router.get('/:id/pdf', async (req, res) => {
  try {
    const bill = await Bill.findById(req.params.id);
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });

    if (!bill.pdfPath || !fs.existsSync(bill.pdfPath)) {
      const pdfInfo = await generateBillPDF(bill);
      bill.pdfPath = pdfInfo.filepath;
      bill.pdfGeneratedAt = new Date();
      await bill.save();
    }

    res.download(bill.pdfPath, `Bill-${bill.billNumber}.pdf`);
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/bills/:id/clone - Clone a bill
router.post('/:id/clone', async (req, res) => {
  try {
    const sourceBill = await Bill.findById(req.params.id);
    if (!sourceBill) return res.status(404).json({ success: false, error: 'Bill not found' });

    const cloneData = sourceBill.toObject();
    delete cloneData._id;
    delete cloneData.billNumber;
    delete cloneData.pdfPath;
    delete cloneData.pdfGeneratedAt;
    delete cloneData.payments;
    delete cloneData.amountPaid;
    delete cloneData.amountDue;
    cloneData.status = 'DRAFT';
    cloneData.billDate = new Date();
    cloneData.dueDate = calculateDueDate(new Date(), cloneData.paymentTerms);
    cloneData.billNumber = await generateBillNumber();
    cloneData.createdBy = req.user?.email || req.user?.uid || 'system';
    cloneData.amountPaid = 0;

    const clonedBill = new Bill(cloneData);
    await clonedBill.save();

    res.status(201).json({ success: true, message: 'Bill cloned successfully', data: clonedBill });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/bills/:id - Delete (only drafts)
router.delete('/:id', async (req, res) => {
  try {
    const bill = await Bill.findById(req.params.id);
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });

    if (bill.status !== 'DRAFT') {
      return res.status(400).json({ success: false, error: 'Only draft bills can be deleted' });
    }

    await bill.deleteOne();
    res.json({ success: true, message: 'Bill deleted successfully' });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// BULK IMPORT BILLS
// ============================================================================

router.post('/bulk-import', async (req, res) => {
  try {
    const { bills } = req.body;
    if (!bills || !Array.isArray(bills) || bills.length === 0) {
      return res.status(400).json({ success: false, error: 'No bills data provided' });
    }

    let successCount = 0;
    let failedCount = 0;
    const errors = [];

    for (const billData of bills) {
      try {
        billData.vendorId = billData.vendorId || new mongoose.Types.ObjectId();
        if (typeof billData.vendorId === 'string' && !mongoose.Types.ObjectId.isValid(billData.vendorId)) {
          billData.vendorId = new mongoose.Types.ObjectId();
        }

        if (!billData.billNumber) {
          billData.billNumber = await generateBillNumber();
        }

        if (!billData.dueDate) {
          billData.dueDate = calculateDueDate(billData.billDate || new Date(), billData.paymentTerms || 'Net 30');
        }

        if (!billData.items || billData.items.length === 0) {
          billData.items = [{ itemDetails: 'Imported Bill', quantity: 1, rate: billData.totalAmount || 0, amount: billData.totalAmount || 0 }];
        }

        billData.createdBy = req.user?.email || req.user?.uid || 'system';

        const bill = new Bill(billData);
        await bill.save();
        successCount++;
      } catch (err) {
        failedCount++;
        errors.push(`Bill ${billData.billNumber || 'unknown'}: ${err.message}`);
      }
    }

    res.json({
      success: true,
      message: `Import complete: ${successCount} succeeded, ${failedCount} failed`,
      data: { totalProcessed: bills.length, successCount, failedCount, errors }
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

module.exports = router;