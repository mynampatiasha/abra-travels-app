// ============================================================================
// CREDIT NOTES SYSTEM - COMPLETE WITH MODEL
// ============================================================================
// File: backend/routes/credit-notes.js
// Features:
// ✅ Complete CRUD operations
// ✅ Create from invoice or manual
// ✅ Refund tracking
// ✅ Credit application to future invoices
// ✅ PDF generation
// ✅ Email notifications
// ✅ Import/Export functionality
// ✅ Status management (Open, Closed, Refunded, Void)
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const PDFDocument = require('pdfkit');
const nodemailer = require('nodemailer');
const fs = require('fs');
const path = require('path');
const multer = require('multer');
const csv = require('csv-parser');
const { Parser } = require('json2csv');

// ============================================================================
// MONGOOSE MODEL - CREDIT NOTE SCHEMA
// ============================================================================

const creditNoteSchema = new mongoose.Schema({
  creditNoteNumber: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  
  // Customer Information
  customerId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Customer',
    required: true
  },
  customerName: {
    type: String,
    required: true
  },
  customerEmail: String,
  customerPhone: String,
  billingAddress: {
    street: String,
    city: String,
    state: String,
    pincode: String,
    country: { type: String, default: 'India' }
  },
  
  // Reference Information
  invoiceId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Invoice'
  },
  invoiceNumber: String,
  referenceNumber: String,
  
  // Dates
  creditNoteDate: {
    type: Date,
    required: true,
    default: Date.now
  },
  
  // Reason for Credit Note
  reason: {
    type: String,
    enum: ['Product Returned', 'Order Cancelled', 'Pricing Error', 'Damaged Goods', 'Quality Issue', 'Other'],
    required: true
  },
  reasonDescription: String,
  
  // Items
  items: [{
    itemDetails: {
      type: String,
      required: true
    },
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
  
  // Notes
  customerNotes: String,
  internalNotes: String,
  
  // Tax Calculations
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
  
  // Credit Status & Usage
  status: {
    type: String,
    enum: ['DRAFT', 'OPEN', 'CLOSED', 'REFUNDED', 'VOID'],
    default: 'DRAFT',
    index: true
  },
  
  creditBalance: {
    type: Number,
    default: 0
  },
  
  creditUsed: {
    type: Number,
    default: 0
  },
  
  // Refund Information
  refunds: [{
    refundId: mongoose.Schema.Types.ObjectId,
    amount: Number,
    refundDate: Date,
    refundMethod: {
      type: String,
      enum: ['Cash', 'Cheque', 'Bank Transfer', 'UPI', 'Card', 'Online']
    },
    referenceNumber: String,
    notes: String,
    recordedBy: String,
    recordedAt: Date
  }],
  
  // Credit Applications (when applied to future invoices)
  creditApplications: [{
    invoiceId: mongoose.Schema.Types.ObjectId,
    invoiceNumber: String,
    amount: Number,
    appliedDate: Date,
    appliedBy: String
  }],
  
  // Email tracking
  emailsSent: [{
    sentTo: String,
    sentAt: Date,
    emailType: {
      type: String,
      enum: ['credit_note', 'refund_confirmation']
    }
  }],
  
  // PDF & Files
  pdfPath: String,
  pdfGeneratedAt: Date,
  
  attachments: [{
    filename: String,
    filepath: String,
    uploadedAt: Date
  }],
  
  // Audit fields
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

// ============================================================================
// PRE-SAVE MIDDLEWARE - AUTO CALCULATIONS
// ============================================================================

creditNoteSchema.pre('save', function(next) {
  // Calculate subtotal
  this.subTotal = this.items.reduce((sum, item) => sum + item.amount, 0);
  
  // Calculate TDS (reduces total)
  this.tdsAmount = (this.subTotal * this.tdsRate) / 100;
  
  // Calculate TCS (increases total)
  this.tcsAmount = (this.subTotal * this.tcsRate) / 100;
  
  // Calculate GST on adjusted base
  const gstBase = this.subTotal - this.tdsAmount + this.tcsAmount;
  const gstAmount = (gstBase * this.gstRate) / 100;
  
  this.cgst = gstAmount / 2;
  this.sgst = gstAmount / 2;
  this.igst = 0;
  
  // Calculate total
  this.totalAmount = this.subTotal - this.tdsAmount + this.tcsAmount + gstAmount;
  
  // Calculate credit balance
  const totalRefunded = this.refunds.reduce((sum, refund) => sum + refund.amount, 0);
  const totalApplied = this.creditApplications.reduce((sum, app) => sum + app.amount, 0);
  
  this.creditUsed = totalRefunded + totalApplied;
  this.creditBalance = this.totalAmount - this.creditUsed;
  
  // Auto-update status based on credit balance
  if (this.creditBalance <= 0 && this.status === 'OPEN') {
    this.status = 'CLOSED';
  }
  
  next();
});

// Create indexes
creditNoteSchema.index({ customerId: 1, creditNoteDate: -1 });
creditNoteSchema.index({ status: 1, creditNoteDate: -1 });
creditNoteSchema.index({ createdAt: -1 });

const CreditNote = mongoose.model('CreditNote', creditNoteSchema);

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

// Generate credit note number
async function generateCreditNoteNumber() {
  const date = new Date();
  const year = date.getFullYear().toString().slice(-2);
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  
  const lastCreditNote = await CreditNote.findOne({
    creditNoteNumber: new RegExp(`^CN-${year}${month}`)
  }).sort({ creditNoteNumber: -1 });
  
  let sequence = 1;
  if (lastCreditNote) {
    const lastSequence = parseInt(lastCreditNote.creditNoteNumber.split('-')[2]);
    sequence = lastSequence + 1;
  }
  
  return `CN-${year}${month}-${sequence.toString().padStart(4, '0')}`;
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

// Logo path resolver
let CACHED_LOGO_PATH = null;

function findLogoPath() {
  const possiblePaths = [
    path.join(__dirname, '..', 'assets', 'abra.jpeg'),
    path.join(__dirname, '..', 'assets', 'abra.jpg'),
    path.join(__dirname, '..', 'assets', 'abra.png'),
    path.join(process.cwd(), 'assets', 'abra.jpeg'),
  ];
  
  for (const testPath of possiblePaths) {
    try {
      if (fs.existsSync(testPath)) {
        return testPath;
      }
    } catch (err) {
      // Continue
    }
  }
  
  return null;
}

function getLogoPath() {
  if (!CACHED_LOGO_PATH) {
    CACHED_LOGO_PATH = findLogoPath();
  }
  return CACHED_LOGO_PATH;
}

// ============================================================================
// PDF GENERATION - CREDIT NOTE
// ============================================================================

async function generateCreditNotePDF(creditNote) {
  return new Promise((resolve, reject) => {
    try {
      console.log('📄 Generating Credit Note PDF:', creditNote.creditNoteNumber);
      
      const uploadsDir = path.join(__dirname, '..', 'uploads', 'credit-notes');
      if (!fs.existsSync(uploadsDir)) {
        fs.mkdirSync(uploadsDir, { recursive: true });
      }
      
      const filename = `credit-note-${creditNote.creditNoteNumber}.pdf`;
      const filepath = path.join(uploadsDir, filename);
      
      const doc = new PDFDocument({
        size: 'A4',
        margin: 40,
        bufferPages: true
      });
      
      const stream = fs.createWriteStream(filepath);
      doc.pipe(stream);
      
      // Logo
      const logoPath = getLogoPath();
      if (logoPath) {
        try {
          doc.image(logoPath, 40, 35, { width: 120, height: 60, fit: [120, 60] });
        } catch (err) {
          console.warn('Logo load failed, using text');
        }
      }
      
      // Company details
      doc.fontSize(8)
         .fillColor('#555555')
         .font('Helvetica')
         .text('Bangalore, Karnataka, India', 40, 105)
         .text('GST: 29AABCT1332L1ZM', 40, 116)
         .text('Contact: +91 88672 88076', 40, 127)
         .text('Email: info@abratravels.com', 40, 138);
      
      // CREDIT NOTE Title
      doc.fontSize(32)
         .fillColor('#E74C3C')
         .font('Helvetica-Bold')
         .text('CREDIT NOTE', 350, 40, { align: 'right' });
      
      // Status badge
      const statusColors = {
        'OPEN': '#3498DB',
        'CLOSED': '#95A5A6',
        'REFUNDED': '#27AE60',
        'VOID': '#7F8C8D',
        'DRAFT': '#F39C12'
      };
      
      const statusColor = statusColors[creditNote.status] || '#95A5A6';
      doc.fontSize(10)
         .fillColor(statusColor)
         .font('Helvetica-Bold')
         .text(creditNote.status, 350, 80, { align: 'right' });
      
      // Credit Note Details Box
      let boxY = 155;
      
      doc.rect(40, boxY, 515, 60)
         .fillAndStroke('#FFF5F5', '#DDDDDD');
      
      doc.rect(40, boxY, 515, 2)
         .fillAndStroke('#E74C3C', '#E74C3C');
      
      doc.fontSize(8)
         .fillColor('#2C3E50')
         .font('Helvetica-Bold');
      
      // Left column
      doc.text('Credit Note Number:', 50, boxY + 12);
      doc.text('Credit Note Date:', 50, boxY + 27);
      doc.text('Reason:', 50, boxY + 42);
      
      doc.fillColor('#000000')
         .font('Helvetica');
      
      doc.text(creditNote.creditNoteNumber || 'N/A', 145, boxY + 12);
      doc.text(new Date(creditNote.creditNoteDate).toLocaleDateString('en-IN', {
        day: '2-digit', month: 'short', year: 'numeric'
      }), 145, boxY + 27);
      doc.text(creditNote.reason || 'N/A', 145, boxY + 42);
      
      // Right column
      doc.fillColor('#2C3E50')
         .font('Helvetica-Bold');
      
      doc.text('Invoice Number:', 305, boxY + 12);
      doc.text('Reference Number:', 305, boxY + 27);
      doc.text('Credit Balance:', 305, boxY + 42);
      
      doc.fillColor('#000000')
         .font('Helvetica');
      
      doc.text(creditNote.invoiceNumber || 'N/A', 400, boxY + 12);
      doc.text(creditNote.referenceNumber || 'N/A', 400, boxY + 27);
      doc.fillColor('#27AE60')
         .font('Helvetica-Bold')
         .text(`₹${creditNote.creditBalance.toFixed(2)}`, 400, boxY + 42);
      
      // Customer Information
      let customerY = boxY + 72;
      
      doc.fontSize(11)
         .fillColor('#E74C3C')
         .font('Helvetica-Bold')
         .text('CUSTOMER DETAILS:', 40, customerY);
      
      doc.fontSize(10)
         .fillColor('#000000')
         .font('Helvetica-Bold')
         .text(creditNote.customerName || 'N/A', 40, customerY + 18);
      
      doc.fontSize(8)
         .fillColor('#555555')
         .font('Helvetica');
      
      customerY += 32;
      
      if (creditNote.billingAddress) {
        const addr = creditNote.billingAddress;
        if (addr.street) {
          doc.text(addr.street, 40, customerY);
          customerY += 11;
        }
        if (addr.city || addr.state || addr.pincode) {
          doc.text(`${addr.city || ''}, ${addr.state || ''} ${addr.pincode || ''}`, 40, customerY);
          customerY += 11;
        }
      }
      
      if (creditNote.customerEmail) {
        doc.text(`Email: ${creditNote.customerEmail}`, 40, customerY);
        customerY += 11;
      }
      
      if (creditNote.customerPhone) {
        doc.text(`Phone: ${creditNote.customerPhone}`, 40, customerY);
      }
      
      // Items Table
      const tableTop = 360;
      
      doc.rect(40, tableTop, 515, 22)
         .fillAndStroke('#E74C3C', '#E74C3C');
      
      doc.fontSize(8)
         .fillColor('#FFFFFF')
         .font('Helvetica-Bold');
      
      doc.text('ITEM DETAILS', 50, tableTop + 8);
      doc.text('QTY', 330, tableTop + 8, { width: 40, align: 'center' });
      doc.text('RATE', 380, tableTop + 8, { width: 60, align: 'right' });
      doc.text('AMOUNT', 455, tableTop + 8, { width: 90, align: 'right' });
      
      let yPosition = tableTop + 22;
      
      creditNote.items.forEach((item, index) => {
        const rowColor = index % 2 === 0 ? '#FFFFFF' : '#FFF5F5';
        
        doc.rect(40, yPosition, 515, 26)
           .fillAndStroke(rowColor, '#E8E8E8');
        
        doc.fontSize(8)
           .fillColor('#000000')
           .font('Helvetica');
        
        doc.text(item.itemDetails || 'N/A', 50, yPosition + 9, { width: 260, ellipsis: true });
        doc.text(item.quantity?.toString() || '0', 330, yPosition + 9, { width: 40, align: 'center' });
        doc.text(`₹${(item.rate || 0).toFixed(2)}`, 380, yPosition + 9, { width: 60, align: 'right' });
        doc.text(`₹${(item.amount || 0).toFixed(2)}`, 455, yPosition + 9, { width: 90, align: 'right' });
        
        yPosition += 26;
      });
      
      // Totals Section
      const startY = yPosition + 20;
      const labelX = 370;
      const valueX = 485;
      let currentY = startY;
      
      doc.fontSize(8)
         .fillColor('#2C3E50')
         .font('Helvetica-Bold');
      
      // Subtotal
      doc.text('Subtotal:', labelX, currentY);
      doc.fillColor('#000000')
         .font('Helvetica')
         .text(`₹ ${creditNote.subTotal.toFixed(2)}`, valueX, currentY, { width: 70, align: 'right' });
      
      currentY += 14;
      
      // CGST
      if (creditNote.cgst > 0) {
        doc.fillColor('#2C3E50')
           .font('Helvetica-Bold')
           .text('CGST:', labelX, currentY);
        doc.fillColor('#000000')
           .font('Helvetica')
           .text(`₹ ${creditNote.cgst.toFixed(2)}`, valueX, currentY, { width: 70, align: 'right' });
        currentY += 14;
      }
      
      // SGST
      if (creditNote.sgst > 0) {
        doc.fillColor('#2C3E50')
           .font('Helvetica-Bold')
           .text('SGST:', labelX, currentY);
        doc.fillColor('#000000')
           .font('Helvetica')
           .text(`₹ ${creditNote.sgst.toFixed(2)}`, valueX, currentY, { width: 70, align: 'right' });
        currentY += 14;
      }
      
      // Divider
      doc.moveTo(370, currentY + 3)
         .lineTo(555, currentY + 3)
         .strokeColor('#E74C3C')
         .lineWidth(1)
         .stroke();
      
      currentY += 10;
      
      // Total Amount
      doc.rect(370, currentY, 185, 22)
         .strokeColor('#E74C3C')
         .lineWidth(2)
         .stroke();
      
      doc.fontSize(10)
         .fillColor('#2C3E50')
         .font('Helvetica-Bold')
         .text('Credit Amount:', labelX + 5, currentY + 6);
      
      doc.fontSize(12)
         .fillColor('#E74C3C')
         .font('Helvetica-Bold')
         .text(`₹ ${creditNote.totalAmount.toFixed(2)}`, valueX, currentY + 5, { width: 65, align: 'right' });
      
      currentY += 28;
      
      // Credit Used
      if (creditNote.creditUsed > 0) {
        doc.fontSize(8)
           .fillColor('#2C3E50')
           .font('Helvetica-Bold')
           .text('Credit Used:', labelX, currentY);
        doc.fillColor('#E74C3C')
           .font('Helvetica')
           .text(`₹ ${creditNote.creditUsed.toFixed(2)}`, valueX, currentY, { width: 70, align: 'right' });
        currentY += 14;
      }
      
      // Balance
      if (creditNote.creditBalance > 0) {
        doc.rect(370, currentY - 2, 185, 20)
           .strokeColor('#27AE60')
           .lineWidth(2)
           .stroke();
        
        doc.fontSize(9)
           .fillColor('#2C3E50')
           .font('Helvetica-Bold')
           .text('Available Balance:', labelX + 5, currentY + 2);
        doc.fillColor('#27AE60')
           .font('Helvetica-Bold')
           .text(`₹ ${creditNote.creditBalance.toFixed(2)}`, valueX, currentY + 2, { width: 65, align: 'right' });
      }
      
      // Notes
      if (creditNote.customerNotes || creditNote.reasonDescription) {
        const notesY = 675;
        
        doc.fontSize(9)
           .fillColor('#E74C3C')
           .font('Helvetica-Bold')
           .text('Notes:', 40, notesY);
        
        doc.fontSize(8)
           .fillColor('#555555')
           .font('Helvetica')
           .text(creditNote.reasonDescription || creditNote.customerNotes || '', 40, notesY + 14, {
             width: 515,
             align: 'left'
           });
      }
      
      // Footer
      const footerY = 730;
      
      doc.moveTo(40, footerY)
         .lineTo(555, footerY)
         .lineWidth(1.5)
         .strokeColor('#E74C3C')
         .stroke();
      
      doc.fontSize(8)
         .fillColor('#2C3E50')
         .font('Helvetica-Bold')
         .text('This is a Credit Note - Customer Credit Available', 40, footerY + 8, {
           align: 'center',
           width: 515
         });
      
      doc.fontSize(6)
         .fillColor('#888888')
         .font('Helvetica')
         .text('ABRA Travels | YOUR JOURNEY, OUR COMMITMENT', 40, footerY + 20, {
           align: 'center',
           width: 515
         });
      
      doc.fontSize(6)
         .fillColor('#AAAAAA')
         .text('www.abratravels.com | info@abratravels.com | +91 88672 88076', 40, footerY + 30, {
           align: 'center',
           width: 515
         });
      
      doc.end();
      
      stream.on('finish', () => {
        console.log(`✅ Credit Note PDF generated: ${filename}`);
        resolve({
          filename: filename,
          filepath: filepath,
          relativePath: `/uploads/credit-notes/${filename}`
        });
      });
      
      stream.on('error', (error) => {
        console.error('❌ PDF generation error:', error);
        reject(error);
      });
      
    } catch (error) {
      console.error('❌ PDF generation error:', error);
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

async function sendCreditNoteEmail(creditNote, pdfPath) {
  console.log('📧 Sending credit note email to:', creditNote.customerEmail);
  
  const emailHtml = `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Credit Note ${creditNote.creditNoteNumber}</title>
</head>
<body style="margin: 0; padding: 0; font-family: Arial, sans-serif; background-color: #f4f4f4;">
  <table width="100%" cellpadding="20" cellspacing="0" border="0" style="background-color: #f4f4f4;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" border="0" style="background-color: #ffffff; border-radius: 10px; overflow: hidden;">
          
          <!-- Header -->
          <tr>
            <td style="background: linear-gradient(135deg, #e74c3c 0%, #c0392b 100%); color: white; padding: 35px; text-align: center;">
              <h1 style="margin: 0; font-size: 32px;">CREDIT NOTE ISSUED</h1>
              <p style="margin: 10px 0 0 0; font-size: 16px;">Credit Available for Future Use</p>
            </td>
          </tr>
          
          <!-- Content -->
          <tr>
            <td style="padding: 40px;">
              
              <h2 style="color: #2c3e50; margin: 0 0 10px 0;">Dear ${creditNote.customerName},</h2>
              
              <p style="color: #555; line-height: 1.8;">
                We have issued a <strong>Credit Note ${creditNote.creditNoteNumber}</strong> for your account.
              </p>
              
              <!-- Credit Note Details -->
              <table width="100%" cellpadding="15" cellspacing="0" border="0" style="background: #fff5f5; border-radius: 8px; margin: 20px 0; border: 2px solid #e74c3c;">
                <tr>
                  <td>
                    <table width="100%" cellpadding="5" cellspacing="0" border="0">
                      <tr>
                        <td style="color: #666; font-size: 14px; padding: 8px 0;"><strong>Credit Note Number:</strong></td>
                        <td style="text-align: right; color: #2c3e50; font-weight: bold; font-size: 14px; padding: 8px 0;">${creditNote.creditNoteNumber}</td>
                      </tr>
                      <tr>
                        <td style="color: #666; font-size: 14px; padding: 8px 0;"><strong>Date:</strong></td>
                        <td style="text-align: right; color: #2c3e50; font-size: 14px; padding: 8px 0;">${new Date(creditNote.creditNoteDate).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}</td>
                      </tr>
                      ${creditNote.invoiceNumber ? `
                      <tr>
                        <td style="color: #666; font-size: 14px; padding: 8px 0;"><strong>Related Invoice:</strong></td>
                        <td style="text-align: right; color: #2c3e50; font-size: 14px; padding: 8px 0;">${creditNote.invoiceNumber}</td>
                      </tr>
                      ` : ''}
                      <tr>
                        <td style="color: #666; font-size: 14px; padding: 8px 0;"><strong>Reason:</strong></td>
                        <td style="text-align: right; color: #2c3e50; font-size: 14px; padding: 8px 0;">${creditNote.reason}</td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>
              
              <!-- Amount Summary -->
              <table width="100%" cellpadding="20" cellspacing="0" border="0" style="background: linear-gradient(135deg, #d4edda 0%, #c3e6cb 100%); border-radius: 8px; margin: 20px 0; border: 2px solid #27ae60;">
                <tr>
                  <td style="text-align: center;">
                    <p style="margin: 0; font-size: 14px; color: #155724;">💰 <strong>Credit Amount</strong></p>
                    <p style="margin: 10px 0 0 0; font-size: 32px; font-weight: bold; color: #27ae60;">₹${creditNote.totalAmount.toFixed(2)}</p>
                    ${creditNote.creditBalance > 0 ? `
                    <p style="margin: 10px 0 0 0; font-size: 14px; color: #155724;">Available Balance: <strong>₹${creditNote.creditBalance.toFixed(2)}</strong></p>
                    ` : ''}
                  </td>
                </tr>
              </table>
              
              <!-- How to Use -->
              <table width="100%" cellpadding="20" cellspacing="0" border="0" style="background: #e3f2fd; border-radius: 8px; margin: 20px 0; border-left: 4px solid #2196f3;">
                <tr>
                  <td>
                    <h3 style="margin: 0 0 15px 0; color: #1976d2;">💡 How to Use This Credit</h3>
                    <ul style="margin: 0; padding-left: 20px; color: #555;">
                      <li style="margin: 8px 0;">This credit will be <strong>automatically applied</strong> to your next invoice</li>
                      <li style="margin: 8px 0;">You can request a <strong>refund</strong> by contacting our support team</li>
                      <li style="margin: 8px 0;">Credits are valid for <strong>12 months</strong> from the issue date</li>
                    </ul>
                  </td>
                </tr>
              </table>
              
              ${creditNote.reasonDescription ? `
              <table width="100%" cellpadding="15" cellspacing="0" border="0" style="background: #fff9c4; border-radius: 6px; border-left: 4px solid #fbc02d; margin: 20px 0;">
                <tr>
                  <td>
                    <p style="margin: 0 0 5px 0; color: #f57f17; font-weight: bold;">📝 Note:</p>
                    <p style="margin: 0; color: #555;">${creditNote.reasonDescription}</p>
                  </td>
                </tr>
              </table>
              ` : ''}
              
              <p style="color: #555; line-height: 1.8; margin-top: 25px;">
                📎 The credit note PDF is attached to this email for your records.
              </p>
              
              <p style="color: #555; line-height: 1.8;">
                If you have any questions, please don't hesitate to contact us.
              </p>
              
              <p style="font-size: 16px; font-weight: bold; color: #e74c3c; text-align: center; margin: 25px 0;">
                Thank you for your business! 🙏
              </p>
              
            </td>
          </tr>
          
          <!-- Footer -->
          <tr>
            <td style="background-color: #2c3e50; color: #ffffff; padding: 30px; text-align: center;">
              <p style="margin: 0; font-weight: bold; font-size: 16px;">ABRA Travels</p>
              <p style="margin: 8px 0; font-style: italic; color: #ecf0f1; font-size: 12px;">YOUR JOURNEY, OUR COMMITMENT</p>
              <p style="margin: 8px 0; color: #95a5a6; font-size: 12px;">📧 info@abratravels.com | 📱 +91 88672 88076</p>
              <p style="margin-top: 15px; color: #7f8c8d; font-size: 11px;">© ${new Date().getFullYear()} ABRA Travels. All rights reserved.</p>
            </td>
          </tr>
          
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
  
  const mailOptions = {
    from: `"ABRA Travels - Billing" <${process.env.SMTP_USER}>`,
    to: creditNote.customerEmail,
    subject: `💳 Credit Note ${creditNote.creditNoteNumber} - ₹${creditNote.totalAmount.toFixed(2)} Available`,
    html: emailHtml,
    attachments: [
      {
        filename: `CreditNote-${creditNote.creditNoteNumber}.pdf`,
        path: pdfPath
      }
    ]
  };
  
  console.log('   📤 Sending email...');
  const result = await emailTransporter.sendMail(mailOptions);
  console.log('   ✅ Email sent! Message ID:', result.messageId);
  
  return result;
}

// ============================================================================
// API ROUTES
// ============================================================================

// GET all credit notes with filters
router.get('/', async (req, res) => {
  try {
    const { status, customerId, fromDate, toDate, page = 1, limit = 20, search } = req.query;
    
    const query = {};
    
    if (status) query.status = status;
    if (customerId) query.customerId = customerId;
    if (fromDate || toDate) {
      query.creditNoteDate = {};
      if (fromDate) query.creditNoteDate.$gte = new Date(fromDate);
      if (toDate) query.creditNoteDate.$lte = new Date(toDate);
    }
    if (search) {
      query.$or = [
        { creditNoteNumber: new RegExp(search, 'i') },
        { customerName: new RegExp(search, 'i') },
        { invoiceNumber: new RegExp(search, 'i') }
      ];
    }
    
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    const creditNotes = await CreditNote.find(query)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .select('-__v');
    
    const total = await CreditNote.countDocuments(query);
    
    res.json({
      success: true,
      data: creditNotes,
      pagination: {
        total,
        page: parseInt(page),
        limit: parseInt(limit),
        pages: Math.ceil(total / parseInt(limit))
      }
    });
  } catch (error) {
    console.error('Error fetching credit notes:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET statistics
router.get('/stats', async (req, res) => {
  try {
    const stats = await CreditNote.aggregate([
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 },
          totalAmount: { $sum: '$totalAmount' },
          totalBalance: { $sum: '$creditBalance' },
          totalUsed: { $sum: '$creditUsed' }
        }
      }
    ]);
    
    const overallStats = {
      totalCreditNotes: 0,
      totalCreditAmount: 0,
      totalCreditBalance: 0,
      totalCreditUsed: 0,
      byStatus: {}
    };
    
    stats.forEach(stat => {
      overallStats.totalCreditNotes += stat.count;
      overallStats.totalCreditAmount += stat.totalAmount;
      overallStats.totalCreditBalance += stat.totalBalance;
      overallStats.totalCreditUsed += stat.totalUsed;
      overallStats.byStatus[stat._id] = {
        count: stat.count,
        amount: stat.totalAmount
      };
    });
    
    res.json({ success: true, data: overallStats });
  } catch (error) {
    console.error('Error fetching stats:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET single credit note
router.get('/:id', async (req, res) => {
  try {
    const creditNote = await CreditNote.findById(req.params.id);
    
    if (!creditNote) {
      return res.status(404).json({ success: false, error: 'Credit note not found' });
    }
    
    res.json({ success: true, data: creditNote });
  } catch (error) {
    console.error('Error fetching credit note:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// CREATE new credit note
router.post('/', async (req, res) => {
  try {
    const creditNoteData = req.body;
    
    // Handle customer ID
    if (creditNoteData.customerId) {
      if (typeof creditNoteData.customerId === 'string') {
        if (mongoose.Types.ObjectId.isValid(creditNoteData.customerId)) {
          creditNoteData.customerId = new mongoose.Types.ObjectId(creditNoteData.customerId);
        } else {
          creditNoteData.customerId = new mongoose.Types.ObjectId();
        }
      }
    } else {
      creditNoteData.customerId = new mongoose.Types.ObjectId();
    }
    
    // Generate credit note number
    if (!creditNoteData.creditNoteNumber) {
      creditNoteData.creditNoteNumber = await generateCreditNoteNumber();
    }
    
    // Calculate item amounts
    if (creditNoteData.items) {
      creditNoteData.items = creditNoteData.items.map(item => ({
        ...item,
        amount: calculateItemAmount(item)
      }));
    }
    
    creditNoteData.createdBy = req.user?.email || req.user?.uid || 'system';
    
    const creditNote = new CreditNote(creditNoteData);
    await creditNote.save();
    
    console.log(`✅ Credit Note created: ${creditNote.creditNoteNumber}`);
    
    res.status(201).json({
      success: true,
      message: 'Credit note created successfully',
      data: creditNote
    });
  } catch (error) {
    console.error('Error creating credit note:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// UPDATE credit note
router.put('/:id', async (req, res) => {
  try {
    const creditNote = await CreditNote.findById(req.params.id);
    
    if (!creditNote) {
      return res.status(404).json({ success: false, error: 'Credit note not found' });
    }
    
    if (creditNote.status === 'CLOSED' || creditNote.status === 'VOID') {
      return res.status(400).json({
        success: false,
        error: 'Cannot edit closed or void credit notes'
      });
    }
    
    const updates = req.body;
    
    // Calculate item amounts
    if (updates.items) {
      updates.items = updates.items.map(item => ({
        ...item,
        amount: calculateItemAmount(item)
      }));
    }
    
    updates.updatedBy = req.user?.email || req.user?.uid || 'system';
    
    Object.assign(creditNote, updates);
    await creditNote.save();
    
    console.log(`✅ Credit Note updated: ${creditNote.creditNoteNumber}`);
    
    res.json({
      success: true,
      message: 'Credit note updated successfully',
      data: creditNote
    });
  } catch (error) {
    console.error('Error updating credit note:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// SEND credit note via email
router.post('/:id/send', async (req, res) => {
  try {
    const creditNote = await CreditNote.findById(req.params.id);
    
    if (!creditNote) {
      return res.status(404).json({ success: false, error: 'Credit note not found' });
    }
    
    if (!creditNote.customerEmail) {
      return res.status(400).json({ success: false, error: 'Customer email not found' });
    }
    
    // Generate PDF if not exists
    let pdfInfo;
    if (!creditNote.pdfPath || !fs.existsSync(creditNote.pdfPath)) {
      pdfInfo = await generateCreditNotePDF(creditNote);
      creditNote.pdfPath = pdfInfo.filepath;
      creditNote.pdfGeneratedAt = new Date();
    }
    
    // Send email
    await sendCreditNoteEmail(creditNote, creditNote.pdfPath);
    
    // Update status
    if (creditNote.status === 'DRAFT') {
      creditNote.status = 'OPEN';
    }
    
    creditNote.emailsSent.push({
      sentTo: creditNote.customerEmail,
      sentAt: new Date(),
      emailType: 'credit_note'
    });
    
    await creditNote.save();
    
    console.log(`✅ Credit Note sent: ${creditNote.creditNoteNumber}`);
    
    res.json({
      success: true,
      message: 'Credit note sent successfully',
      data: creditNote
    });
  } catch (error) {
    console.error('Error sending credit note:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// RECORD refund
router.post('/:id/refund', async (req, res) => {
  try {
    const creditNote = await CreditNote.findById(req.params.id);
    
    if (!creditNote) {
      return res.status(404).json({ success: false, error: 'Credit note not found' });
    }
    
    const { amount, refundDate, refundMethod, referenceNumber, notes } = req.body;
    
    if (!amount || amount <= 0) {
      return res.status(400).json({ success: false, error: 'Invalid refund amount' });
    }
    
    if (creditNote.creditBalance < amount) {
      return res.status(400).json({
        success: false,
        error: `Refund amount exceeds available balance (₹${creditNote.creditBalance.toFixed(2)})`
      });
    }
    
    const refund = {
      refundId: new mongoose.Types.ObjectId(),
      amount: parseFloat(amount),
      refundDate: refundDate ? new Date(refundDate) : new Date(),
      refundMethod: refundMethod || 'Bank Transfer',
      referenceNumber,
      notes,
      recordedBy: req.user?.email || req.user?.uid || 'system',
      recordedAt: new Date()
    };
    
    creditNote.refunds.push(refund);
    await creditNote.save();
    
    console.log(`✅ Refund recorded: ${creditNote.creditNoteNumber} - ₹${amount}`);
    
    res.json({
      success: true,
      message: 'Refund recorded successfully',
      data: {
        creditNote,
        refund
      }
    });
  } catch (error) {
    console.error('Error recording refund:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// APPLY credit to invoice
router.post('/:id/apply', async (req, res) => {
  try {
    const creditNote = await CreditNote.findById(req.params.id);
    
    if (!creditNote) {
      return res.status(404).json({ success: false, error: 'Credit note not found' });
    }
    
    const { invoiceId, invoiceNumber, amount } = req.body;
    
    if (!amount || amount <= 0) {
      return res.status(400).json({ success: false, error: 'Invalid amount' });
    }
    
    if (creditNote.creditBalance < amount) {
      return res.status(400).json({
        success: false,
        error: `Amount exceeds available balance (₹${creditNote.creditBalance.toFixed(2)})`
      });
    }
    
    const application = {
      invoiceId: invoiceId ? new mongoose.Types.ObjectId(invoiceId) : null,
      invoiceNumber,
      amount: parseFloat(amount),
      appliedDate: new Date(),
      appliedBy: req.user?.email || req.user?.uid || 'system'
    };
    
    creditNote.creditApplications.push(application);
    await creditNote.save();
    
    console.log(`✅ Credit applied: ${creditNote.creditNoteNumber} to ${invoiceNumber} - ₹${amount}`);
    
    res.json({
      success: true,
      message: 'Credit applied successfully',
      data: {
        creditNote,
        application
      }
    });
  } catch (error) {
    console.error('Error applying credit:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// DOWNLOAD PDF
router.get('/:id/pdf', async (req, res) => {
  try {
    const creditNote = await CreditNote.findById(req.params.id);
    
    if (!creditNote) {
      return res.status(404).json({ success: false, error: 'Credit note not found' });
    }
    
    if (!creditNote.pdfPath || !fs.existsSync(creditNote.pdfPath)) {
      const pdfInfo = await generateCreditNotePDF(creditNote);
      creditNote.pdfPath = pdfInfo.filepath;
      creditNote.pdfGeneratedAt = new Date();
      await creditNote.save();
    }
    
    res.download(creditNote.pdfPath, `CreditNote-${creditNote.creditNoteNumber}.pdf`);
  } catch (error) {
    console.error('Error downloading PDF:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET PDF download URL
router.get('/:id/download-url', async (req, res) => {
  try {
    const creditNote = await CreditNote.findById(req.params.id);
    
    if (!creditNote) {
      return res.status(404).json({ success: false, error: 'Credit note not found' });
    }
    
    if (!creditNote.pdfPath || !fs.existsSync(creditNote.pdfPath)) {
      const pdfInfo = await generateCreditNotePDF(creditNote);
      creditNote.pdfPath = pdfInfo.filepath;
      creditNote.pdfGeneratedAt = new Date();
      await creditNote.save();
    }
    
    const baseUrl = process.env.BASE_URL || `${req.protocol}://${req.get('host')}`;
    const downloadUrl = `${baseUrl}/uploads/credit-notes/${path.basename(creditNote.pdfPath)}`;
    
    res.json({
      success: true,
      downloadUrl: downloadUrl,
      filename: `CreditNote-${creditNote.creditNoteNumber}.pdf`
    });
  } catch (error) {
    console.error('Error generating PDF URL:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE credit note (only drafts)
router.delete('/:id', async (req, res) => {
  try {
    const creditNote = await CreditNote.findById(req.params.id);
    
    if (!creditNote) {
      return res.status(404).json({ success: false, error: 'Credit note not found' });
    }
    
    if (creditNote.status !== 'DRAFT') {
      return res.status(400).json({
        success: false,
        error: 'Only draft credit notes can be deleted'
      });
    }
    
    await creditNote.deleteOne();
    
    console.log(`✅ Credit Note deleted: ${creditNote.creditNoteNumber}`);
    
    res.json({
      success: true,
      message: 'Credit note deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting credit note:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// IMPORT/EXPORT ROUTES
// ============================================================================

// Configure multer for CSV upload
const upload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => {
      const uploadDir = path.join(__dirname, '..', 'uploads', 'temp');
      if (!fs.existsSync(uploadDir)) {
        fs.mkdirSync(uploadDir, { recursive: true });
      }
      cb(null, uploadDir);
    },
    filename: (req, file, cb) => {
      cb(null, `import-${Date.now()}-${file.originalname}`);
    }
  }),
  fileFilter: (req, file, cb) => {
    if (file.mimetype === 'text/csv' || file.originalname.endsWith('.csv')) {
      cb(null, true);
    } else {
      cb(new Error('Only CSV files are allowed'));
    }
  }
});

// DOWNLOAD import template
router.get('/template/download', async (req, res) => {
  try {
    const templateData = [
      {
        'Customer Name': 'John Doe',
        'Customer Email': 'john@example.com',
        'Customer Phone': '+91 9876543210',
        'Invoice Number': 'INV-2501-0001',
        'Credit Note Date': '2025-01-15',
        'Reason': 'Product Returned',
        'Reason Description': 'Customer returned defective product',
        'Item Details': 'Laptop Dell Inspiron 15',
        'Quantity': '1',
        'Rate': '45000',
        'Discount': '0',
        'Discount Type': 'percentage',
        'GST Rate': '18',
        'Customer Notes': 'Refund processed to original payment method'
      },
      {
        'Customer Name': 'Jane Smith',
        'Customer Email': 'jane@example.com',
        'Customer Phone': '+91 8765432109',
        'Invoice Number': 'INV-2501-0002',
        'Credit Note Date': '2025-01-16',
        'Reason': 'Order Cancelled',
        'Reason Description': 'Order cancelled by customer before delivery',
        'Item Details': 'Office Chair Premium',
        'Quantity': '2',
        'Rate': '8500',
        'Discount': '5',
        'Discount Type': 'percentage',
        'GST Rate': '18',
        'Customer Notes': 'Credit available for future purchases'
      }
    ];
    
    const parser = new Parser();
    const csv = parser.parse(templateData);
    
    res.header('Content-Type', 'text/csv');
    res.header('Content-Disposition', 'attachment; filename=credit_notes_import_template.csv');
    res.send(csv);
    
    console.log('✅ Template downloaded');
  } catch (error) {
    console.error('Error generating template:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// IMPORT credit notes from CSV
router.post('/import', upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, error: 'No file uploaded' });
    }
    
    console.log('📥 Processing import file:', req.file.filename);
    
    const results = [];
    const errors = [];
    let lineNumber = 1;
    
    // Parse CSV
    const stream = fs.createReadStream(req.file.path)
      .pipe(csv());
    
    for await (const row of stream) {
      lineNumber++;
      
      try {
        // Validate required fields
        if (!row['Customer Name'] || !row['Customer Email']) {
          throw new Error('Customer Name and Email are required');
        }
        
        // Prepare credit note data
        const creditNoteData = {
          customerId: new mongoose.Types.ObjectId(),
          customerName: row['Customer Name'].trim(),
          customerEmail: row['Customer Email'].trim(),
          customerPhone: row['Customer Phone']?.trim(),
          invoiceNumber: row['Invoice Number']?.trim(),
          creditNoteDate: row['Credit Note Date'] ? new Date(row['Credit Note Date']) : new Date(),
          reason: row['Reason']?.trim() || 'Other',
          reasonDescription: row['Reason Description']?.trim(),
          items: [{
            itemDetails: row['Item Details']?.trim() || 'Item',
            quantity: parseFloat(row['Quantity']) || 1,
            rate: parseFloat(row['Rate']) || 0,
            discount: parseFloat(row['Discount']) || 0,
            discountType: row['Discount Type']?.trim() || 'percentage',
            amount: 0 // Will be calculated by pre-save
          }],
          gstRate: parseFloat(row['GST Rate']) || 18,
          customerNotes: row['Customer Notes']?.trim(),
          status: 'OPEN',
          createdBy: req.user?.email || 'import'
        };
        
        // Calculate item amount
        creditNoteData.items[0].amount = calculateItemAmount(creditNoteData.items[0]);
        
        // Generate credit note number
        creditNoteData.creditNoteNumber = await generateCreditNoteNumber();
        
        // Create credit note
        const creditNote = new CreditNote(creditNoteData);
        await creditNote.save();
        
        results.push({
          line: lineNumber,
          creditNoteNumber: creditNote.creditNoteNumber,
          customerName: creditNote.customerName,
          amount: creditNote.totalAmount
        });
        
      } catch (error) {
        errors.push({
          line: lineNumber,
          error: error.message,
          data: row
        });
      }
    }
    
    // Delete temp file
    fs.unlinkSync(req.file.path);
    
    console.log(`✅ Import completed: ${results.length} successful, ${errors.length} failed`);
    
    res.json({
      success: true,
      message: 'Import completed',
      successCount: results.length,
      errorCount: errors.length,
      results,
      errors
    });
    
  } catch (error) {
    console.error('Error importing credit notes:', error);
    
    // Clean up temp file
    if (req.file && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }
    
    res.status(500).json({ success: false, error: error.message });
  }
});

// EXPORT credit notes to CSV
router.get('/export', async (req, res) => {
  try {
    const { status, customerId, fromDate, toDate } = req.query;
    
    const query = {};
    
    if (status) query.status = status;
    if (customerId) query.customerId = customerId;
    if (fromDate || toDate) {
      query.creditNoteDate = {};
      if (fromDate) query.creditNoteDate.$gte = new Date(fromDate);
      if (toDate) query.creditNoteDate.$lte = new Date(toDate);
    }
    
    const creditNotes = await CreditNote.find(query).sort({ createdAt: -1 });
    
    if (creditNotes.length === 0) {
      return res.status(404).json({ success: false, error: 'No credit notes to export' });
    }
    
    const exportData = creditNotes.map(cn => ({
      'Credit Note Number': cn.creditNoteNumber,
      'Customer Name': cn.customerName,
      'Customer Email': cn.customerEmail || '',
      'Invoice Number': cn.invoiceNumber || '',
      'Credit Note Date': cn.creditNoteDate.toISOString().split('T')[0],
      'Reason': cn.reason,
      'Status': cn.status,
      'Subtotal': cn.subTotal.toFixed(2),
      'CGST': cn.cgst.toFixed(2),
      'SGST': cn.sgst.toFixed(2),
      'Total Amount': cn.totalAmount.toFixed(2),
      'Credit Used': cn.creditUsed.toFixed(2),
      'Credit Balance': cn.creditBalance.toFixed(2),
      'Created Date': cn.createdAt.toISOString().split('T')[0]
    }));
    
    const parser = new Parser();
    const csv = parser.parse(exportData);
    
    const filename = `credit_notes_export_${Date.now()}.csv`;
    
    res.header('Content-Type', 'text/csv');
    res.header('Content-Disposition', `attachment; filename=${filename}`);
    res.send(csv);
    
    console.log(`✅ Exported ${creditNotes.length} credit notes`);
    
  } catch (error) {
    console.error('Error exporting credit notes:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

module.exports = router;