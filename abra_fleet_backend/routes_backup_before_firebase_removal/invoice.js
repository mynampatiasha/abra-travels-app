// ============================================================================
// INVOICE SYSTEM - COMPLETE BACKEND
// ============================================================================
// File: backend/routes/invoice.js
// Contains: Routes, Controllers, Models, PDF Generation, Email Service
// Database: MongoDB with Mongoose
// Features: Create, Edit, Send, Payment Recording, Status Management
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const PDFDocument = require('pdfkit');
const nodemailer = require('nodemailer');
const fs = require('fs');
const path = require('path');

// Import payment defaults
const DEFAULT_PAYMENT = require('../config/payment-defaults');

// ============================================================================
// MONGOOSE MODELS
// ============================================================================

// Invoice Schema
const invoiceSchema = new mongoose.Schema({
  invoiceNumber: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  customerId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Customer',
    required: true
  },
  customerName: String,
  customerEmail: String,
  customerPhone: String,
  billingAddress: {
    street: String,
    city: String,
    state: String,
    pincode: String,
    country: { type: String, default: 'India' }
  },
  shippingAddress: {
    street: String,
    city: String,
    state: String,
    pincode: String,
    country: { type: String, default: 'India' }
  },
  orderNumber: String,
  invoiceDate: {
    type: Date,
    required: true,
    default: Date.now
  },
  terms: {
    type: String,
    enum: ['Due on Receipt', 'Net 15', 'Net 30', 'Net 45', 'Net 60'],
    default: 'Net 30'
  },
  dueDate: {
    type: Date,
    required: true
  },
  salesperson: String,
  subject: String,
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
  customerNotes: String,
  termsAndConditions: String,
  paymentDetails: {
    bankAccount: String,
    ifscCode: String,
    bankName: String,
    accountHolder: String,
    upiId: String,
    officeAddress: String
  },
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
  
  // Status Management
  status: {
    type: String,
    enum: ['DRAFT', 'SENT', 'UNPAID', 'PARTIALLY_PAID', 'PAID', 'OVERDUE', 'CANCELLED'],
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
    paymentMethod: {
      type: String,
      enum: ['Cash', 'Cheque', 'Bank Transfer', 'UPI', 'Card', 'Online']
    },
    referenceNumber: String,
    notes: String,
    recordedBy: String,
    recordedAt: Date
  }],
  
  // Email tracking
  emailsSent: [{
    sentTo: String,
    sentAt: Date,
    emailType: {
      type: String,
      enum: ['invoice', 'reminder', 'payment_receipt']
    }
  }],
  
  // PDF Generation
  pdfPath: String,
  pdfGeneratedAt: Date,
  
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
invoiceSchema.pre('save', function(next) {
  // Calculate subtotal
  this.subTotal = this.items.reduce((sum, item) => sum + item.amount, 0);
  
  // Calculate TDS (Tax Deducted at Source) - Reduces total
  this.tdsAmount = (this.subTotal * this.tdsRate) / 100;
  
  // Calculate TCS (Tax Collected at Source) - Increases total
  this.tcsAmount = (this.subTotal * this.tcsRate) / 100;
  
  // Calculate GST
  const gstBase = this.subTotal - this.tdsAmount + this.tcsAmount;
  const gstAmount = (gstBase * this.gstRate) / 100;
  
  // For intra-state: CGST + SGST, for inter-state: IGST
  // Default to intra-state (CGST + SGST)
  this.cgst = gstAmount / 2;
  this.sgst = gstAmount / 2;
  this.igst = 0;
  
  // Calculate total
  this.totalAmount = this.subTotal - this.tdsAmount + this.tcsAmount + gstAmount;
  
  // Calculate amount due
  this.amountDue = this.totalAmount - this.amountPaid;
  
  // Auto-update status based on payment
  if (this.amountPaid === 0 && this.status !== 'DRAFT') {
    this.status = 'UNPAID';
  } else if (this.amountPaid > 0 && this.amountPaid < this.totalAmount) {
    this.status = 'PARTIALLY_PAID';
  } else if (this.amountPaid >= this.totalAmount) {
    this.status = 'PAID';
  }
  
  // Check for overdue
  if (this.status !== 'PAID' && this.status !== 'DRAFT' && this.dueDate < new Date()) {
    this.status = 'OVERDUE';
  }
  
  next();
});

// Indexes for performance
invoiceSchema.index({ customerId: 1, invoiceDate: -1 });
invoiceSchema.index({ status: 1, dueDate: 1 });
invoiceSchema.index({ createdAt: -1 });

const Invoice = mongoose.model('Invoice', invoiceSchema);

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

// Generate unique invoice number
async function generateInvoiceNumber() {
  const date = new Date();
  const year = date.getFullYear().toString().slice(-2);
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  
  // Find last invoice for this month
  const lastInvoice = await Invoice.findOne({
    invoiceNumber: new RegExp(`^INV-${year}${month}`)
  }).sort({ invoiceNumber: -1 });
  
  let sequence = 1;
  if (lastInvoice) {
    const lastSequence = parseInt(lastInvoice.invoiceNumber.split('-')[2]);
    sequence = lastSequence + 1;
  }
  
  return `INV-${year}${month}-${sequence.toString().padStart(4, '0')}`;
}

// Calculate due date based on terms
function calculateDueDate(invoiceDate, terms) {
  const date = new Date(invoiceDate);
  
  switch (terms) {
    case 'Due on Receipt':
      return date;
    case 'Net 15':
      date.setDate(date.getDate() + 15);
      return date;
    case 'Net 30':
      date.setDate(date.getDate() + 30);
      return date;
    case 'Net 45':
      date.setDate(date.getDate() + 45);
      return date;
    case 'Net 60':
      date.setDate(date.getDate() + 60);
      return date;
    default:
      date.setDate(date.getDate() + 30);
      return date;
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

async function generateInvoicePDF(invoice) {
  return new Promise((resolve, reject) => {
    try {
      // Create uploads directory if it doesn't exist
      const uploadsDir = path.join(__dirname, '..', 'uploads', 'invoices');
      if (!fs.existsSync(uploadsDir)) {
        fs.mkdirSync(uploadsDir, { recursive: true });
      }
      
      const filename = `invoice-${invoice.invoiceNumber}.pdf`;
      const filepath = path.join(uploadsDir, filename);
      
      // Create PDF document
      const doc = new PDFDocument({ size: 'A4', margin: 50 });
      const stream = fs.createWriteStream(filepath);
      
      doc.pipe(stream);
      
      // Company Header
      doc.fontSize(24)
         .fillColor('#2C3E50')
         .text('ABRA FLEET', 50, 50)
         .fontSize(10)
         .fillColor('#7F8C8D')
         .text('Fleet Management Solutions', 50, 80)
         .text('GST: 29XXXXX1234X1Z5', 50, 95)
         .moveDown();
      
      // Invoice Title
      doc.fontSize(28)
         .fillColor('#2C3E50')
         .text('INVOICE', 400, 50, { align: 'right' });
      
      // Invoice Details Box
      doc.fontSize(10)
         .fillColor('#34495E')
         .text(`Invoice #: ${invoice.invoiceNumber}`, 400, 90, { align: 'right' })
         .text(`Date: ${new Date(invoice.invoiceDate).toLocaleDateString('en-IN')}`, 400, 105, { align: 'right' })
         .text(`Due Date: ${new Date(invoice.dueDate).toLocaleDateString('en-IN')}`, 400, 120, { align: 'right' });
      
      if (invoice.orderNumber) {
        doc.text(`Order #: ${invoice.orderNumber}`, 400, 135, { align: 'right' });
      }
      
      // Line separator
      doc.moveTo(50, 160)
         .lineTo(545, 160)
         .strokeColor('#BDC3C7')
         .stroke();
      
      // Bill To Section
      doc.fontSize(12)
         .fillColor('#2C3E50')
         .text('BILL TO:', 50, 180);
      
      doc.fontSize(11)
         .fillColor('#34495E')
         .text(invoice.customerName, 50, 200)
         .fontSize(10)
         .fillColor('#7F8C8D');
      
      let yPos = 215;
      if (invoice.billingAddress) {
        if (invoice.billingAddress.street) {
          doc.text(invoice.billingAddress.street, 50, yPos);
          yPos += 15;
        }
        const cityLine = [
          invoice.billingAddress.city,
          invoice.billingAddress.state,
          invoice.billingAddress.pincode
        ].filter(Boolean).join(', ');
        if (cityLine) {
          doc.text(cityLine, 50, yPos);
          yPos += 15;
        }
      }
      if (invoice.customerEmail) {
        doc.text(`Email: ${invoice.customerEmail}`, 50, yPos);
        yPos += 15;
      }
      if (invoice.customerPhone) {
        doc.text(`Phone: ${invoice.customerPhone}`, 50, yPos);
      }
      
      // Items Table Header
      yPos = 310;
      doc.fontSize(10)
         .fillColor('#FFFFFF')
         .rect(50, yPos, 495, 25)
         .fill('#34495E');
      
      doc.fillColor('#FFFFFF')
         .text('ITEM DETAILS', 60, yPos + 8)
         .text('QTY', 320, yPos + 8, { width: 40, align: 'center' })
         .text('RATE', 370, yPos + 8, { width: 60, align: 'right' })
         .text('DISCOUNT', 440, yPos + 8, { width: 50, align: 'right' })
         .text('AMOUNT', 500, yPos + 8, { width: 55, align: 'right' });
      
      // Items
      yPos += 35;
      doc.fillColor('#34495E');
      
      invoice.items.forEach((item, index) => {
        if (yPos > 700) {
          doc.addPage();
          yPos = 50;
        }
        
        doc.fontSize(10)
           .text(item.itemDetails, 60, yPos, { width: 240 })
           .text(item.quantity.toString(), 320, yPos, { width: 40, align: 'center' })
           .text(`Rs.${item.rate.toFixed(2)}`, 370, yPos, { width: 60, align: 'right' })
           .text(item.discount > 0 ? `${item.discount}${item.discountType === 'percentage' ? '%' : 'Rs.'}` : '-', 440, yPos, { width: 50, align: 'right' })
           .text(`Rs.${item.amount.toFixed(2)}`, 500, yPos, { width: 55, align: 'right' });
        
        yPos += 25;
        
        // Line separator
        doc.moveTo(50, yPos)
           .lineTo(545, yPos)
           .strokeColor('#ECF0F1')
           .stroke();
        
        yPos += 5;
      });
      
      // Summary Section
      yPos += 20;
      const summaryX = 380;
      
      doc.fontSize(10)
         .fillColor('#7F8C8D')
         .text('Sub Total:', summaryX, yPos, { align: 'left' })
         .fillColor('#34495E')
         .text(`Rs.${invoice.subTotal.toFixed(2)}`, summaryX + 100, yPos, { align: 'right' });
      
      yPos += 20;
      
      // TDS
      if (invoice.tdsAmount > 0) {
        doc.fillColor('#7F8C8D')
           .text(`TDS (${invoice.tdsRate}%):`, summaryX, yPos, { align: 'left' })
           .fillColor('#E74C3C')
           .text(`- Rs.${invoice.tdsAmount.toFixed(2)}`, summaryX + 100, yPos, { align: 'right' });
        yPos += 20;
      }
      
      // TCS
      if (invoice.tcsAmount > 0) {
        doc.fillColor('#7F8C8D')
           .text(`TCS (${invoice.tcsRate}%):`, summaryX, yPos, { align: 'left' })
           .fillColor('#34495E')
           .text(`Rs.${invoice.tcsAmount.toFixed(2)}`, summaryX + 100, yPos, { align: 'right' });
        yPos += 20;
      }
      
      // GST
      if (invoice.cgst > 0) {
        doc.fillColor('#7F8C8D')
           .text(`CGST (${(invoice.gstRate / 2).toFixed(1)}%):`, summaryX, yPos, { align: 'left' })
           .fillColor('#34495E')
           .text(`Rs.${invoice.cgst.toFixed(2)}`, summaryX + 100, yPos, { align: 'right' });
        yPos += 15;
        
        doc.fillColor('#7F8C8D')
           .text(`SGST (${(invoice.gstRate / 2).toFixed(1)}%):`, summaryX, yPos, { align: 'left' })
           .fillColor('#34495E')
           .text(`Rs.${invoice.sgst.toFixed(2)}`, summaryX + 100, yPos, { align: 'right' });
        yPos += 20;
      }
      
      if (invoice.igst > 0) {
        doc.fillColor('#7F8C8D')
           .text(`IGST (${invoice.gstRate}%):`, summaryX, yPos, { align: 'left' })
           .fillColor('#34495E')
           .text(`Rs.${invoice.igst.toFixed(2)}`, summaryX + 100, yPos, { align: 'right' });
        yPos += 20;
      }
      
      // Total line
      doc.moveTo(summaryX, yPos)
         .lineTo(545, yPos)
         .strokeColor('#34495E')
         .lineWidth(2)
         .stroke();
      
      yPos += 15;
      
      // Total Amount
      doc.fontSize(14)
         .fillColor('#2C3E50')
         .text('Total Amount:', summaryX, yPos, { align: 'left' })
         .text(`Rs.${invoice.totalAmount.toFixed(2)}`, summaryX + 100, yPos, { align: 'right' });
      
      // Payment Status Badge
      yPos += 30;
      let statusColor, statusText;
      
      switch (invoice.status) {
        case 'PAID':
          statusColor = '#27AE60';
          statusText = 'PAID';
          break;
        case 'PARTIALLY_PAID':
          statusColor = '#F39C12';
          statusText = 'PARTIALLY PAID';
          break;
        case 'OVERDUE':
          statusColor = '#E74C3C';
          statusText = 'OVERDUE';
          break;
        default:
          statusColor = '#95A5A6';
          statusText = 'UNPAID';
      }
      
      doc.rect(summaryX, yPos, 165, 25)
         .fill(statusColor);
      
      doc.fontSize(12)
         .fillColor('#FFFFFF')
         .text(statusText, summaryX, yPos + 7, { width: 165, align: 'center' });
      
      // Notes Section
      if (invoice.customerNotes || invoice.termsAndConditions) {
        yPos += 50;
        
        if (yPos > 650) {
          doc.addPage();
          yPos = 50;
        }
        
        if (invoice.customerNotes) {
          doc.fontSize(11)
             .fillColor('#2C3E50')
             .text('Notes:', 50, yPos);
          
          doc.fontSize(10)
             .fillColor('#7F8C8D')
             .text(invoice.customerNotes, 50, yPos + 20, { width: 495 });
          
          yPos += 60;
        }
        
        if (invoice.termsAndConditions) {
          doc.fontSize(11)
             .fillColor('#2C3E50')
             .text('Terms & Conditions:', 50, yPos);
          
          doc.fontSize(9)
             .fillColor('#7F8C8D')
             .text(invoice.termsAndConditions, 50, yPos + 20, { width: 495 });
        }
      }
      
      // Footer
      doc.fontSize(9)
         .fillColor('#95A5A6')
         .text('Thank you for your business!', 50, 750, { align: 'center', width: 495 })
         .text('For queries, contact: billing@abrafleet.com | +91-XXXXXXXXXX', 50, 765, { align: 'center', width: 495 });
      
      doc.end();
      
      stream.on('finish', () => {
        resolve({
          filename: filename,
          filepath: filepath,
          relativePath: `/uploads/invoices/${filename}`
        });
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

// Email transporter configuration
const emailTransporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'smtp.gmail.com',
  port: process.env.SMTP_PORT || 587,
  secure: false,
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASSWORD
  }
});

// Send invoice email
async function sendInvoiceEmail(invoice, pdfPath) {
  // Use custom payment details if provided, otherwise use defaults
  const paymentInfo = invoice.paymentDetails && Object.keys(invoice.paymentDetails).length > 0
    ? invoice.paymentDetails
    : {
        accountHolder: DEFAULT_PAYMENT.bankAccount.accountHolder,
        bankAccount: DEFAULT_PAYMENT.bankAccount.accountNumber,
        ifscCode: DEFAULT_PAYMENT.bankAccount.ifscCode,
        bankName: DEFAULT_PAYMENT.bankAccount.bankName,
        upiId: DEFAULT_PAYMENT.upi.upiId,
        officeAddress: DEFAULT_PAYMENT.office.fullAddress
      };

  const emailHtml = `
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #2C3E50 0%, #34495E 100%); color: white; padding: 30px; text-align: center; border-radius: 8px 8px 0 0; }
    .header h1 { margin: 0; font-size: 28px; }
    .content { background: #f8f9fa; padding: 30px; border-radius: 0 0 8px 8px; }
    .invoice-box { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; border-left: 4px solid #3498DB; }
    .invoice-detail { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid #ecf0f1; }
    .invoice-detail:last-child { border-bottom: none; }
    .label { font-weight: bold; color: #7f8c8d; }
    .value { color: #2c3e50; font-weight: 600; }
    .total-amount { font-size: 24px; color: #27ae60; text-align: center; margin: 20px 0; padding: 15px; background: #e8f8f5; border-radius: 8px; }
    .payment-section { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; border: 2px solid #3498DB; }
    .payment-method { background: #f8f9fa; padding: 15px; border-radius: 8px; margin: 10px 0; border-left: 4px solid #3498DB; }
    .payment-method h4 { margin: 0 0 10px 0; color: #2c3e50; }
    .payment-detail-item { padding: 5px 0; }
    .button { display: inline-block; padding: 12px 30px; background: #3498DB; color: white; text-decoration: none; border-radius: 5px; margin: 20px 0; }
    .button:hover { background: #2980B9; }
    .footer { text-align: center; color: #95a5a6; font-size: 12px; margin-top: 30px; padding-top: 20px; border-top: 1px solid #ecf0f1; }
    .warning-box { background: #fff3cd; padding: 15px; border-radius: 8px; border-left: 4px solid #ffc107; margin: 20px 0; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🚗 ABRA FLEET</h1>
      <p style="margin: 10px 0 0 0; opacity: 0.9;">Fleet Management Solutions</p>
    </div>
    
    <div class="content">
      <h2 style="color: #2c3e50; margin-top: 0;">Invoice from Abra Fleet</h2>
      
      <p>Dear <strong>${invoice.customerName}</strong>,</p>
      
      <p>Thank you for your business! Please find your invoice details below:</p>
      
      <div class="invoice-box">
        <div class="invoice-detail">
          <span class="label">Invoice Number:</span>
          <span class="value">${invoice.invoiceNumber}</span>
        </div>
        <div class="invoice-detail">
          <span class="label">Invoice Date:</span>
          <span class="value">${new Date(invoice.invoiceDate).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}</span>
        </div>
        <div class="invoice-detail">
          <span class="label">Due Date:</span>
          <span class="value">${new Date(invoice.dueDate).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}</span>
        </div>
        <div class="invoice-detail">
          <span class="label">Payment Terms:</span>
          <span class="value">${invoice.terms}</span>
        </div>
      </div>
      
      <div class="total-amount">
        <div style="font-size: 14px; color: #7f8c8d; margin-bottom: 5px;">Total Amount Due</div>
        <strong>₹${invoice.totalAmount.toFixed(2)}</strong>
      </div>
      
      <div class="warning-box">
        <strong>⚠️ Payment Instructions:</strong><br>
        Please make the payment before <strong>${new Date(invoice.dueDate).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}</strong> to avoid late fees.
      </div>
      
      <div class="payment-section">
        <h3 style="color: #2c3e50; margin-top: 0; text-align: center;">💳 Payment Methods</h3>
        
        <!-- Bank Transfer -->
        <div class="payment-method">
          <h4>🏦 Option 1: Bank Transfer / NEFT / RTGS / IMPS</h4>
          <div class="payment-detail-item"><strong>Account Holder:</strong> ${paymentInfo.accountHolder || 'Abra Fleet Management'}</div>
          <div class="payment-detail-item"><strong>Account Number:</strong> ${paymentInfo.bankAccount || 'Not provided'}</div>
          <div class="payment-detail-item"><strong>IFSC Code:</strong> ${paymentInfo.ifscCode || 'Not provided'}</div>
          <div class="payment-detail-item"><strong>Bank Name:</strong> ${paymentInfo.bankName || 'Not provided'}</div>
          <div style="margin-top: 10px; padding: 10px; background: #e8f4f8; border-radius: 5px; font-size: 13px;">
            💡 <strong>Note:</strong> Please mention invoice number <strong>${invoice.invoiceNumber}</strong> in payment remarks
          </div>
        </div>
        
        <!-- UPI Payment -->
        ${paymentInfo.upiId ? `
        <div class="payment-method">
          <h4>📱 Option 2: UPI Payment</h4>
          <div class="payment-detail-item"><strong>UPI ID:</strong> <span style="color: #3498DB; font-weight: bold;">${paymentInfo.upiId}</span></div>
          <div style="margin-top: 10px; padding: 10px; background: #e8f4f8; border-radius: 5px; font-size: 13px;">
            💡 Pay instantly using Google Pay, PhonePe, Paytm, or any UPI app
          </div>
        </div>
        ` : ''}
        
        <!-- Cash/Cheque -->
        ${paymentInfo.officeAddress ? `
        <div class="payment-method">
          <h4>💵 Option 3: Cash / Cheque Payment</h4>
          <div class="payment-detail-item"><strong>Visit Office:</strong></div>
          <div style="padding: 10px; background: #f8f9fa; border-radius: 5px; margin-top: 5px;">
            ${paymentInfo.officeAddress}
          </div>
          <div style="margin-top: 10px; padding: 10px; background: #e8f4f8; border-radius: 5px; font-size: 13px;">
            💡 Cheques should be drawn in favor of "<strong>${paymentInfo.accountHolder || 'Abra Fleet Management'}</strong>"
          </div>
        </div>
        ` : ''}
        
        <!-- Payment Proof -->
        <div style="margin-top: 20px; padding: 15px; background: #fff3cd; border-radius: 8px; border-left: 4px solid #ffc107;">
          <strong>📸 Important:</strong> Please share payment proof (screenshot/receipt) after making the payment:
          <ul style="margin: 10px 0;">
            <li>📧 Email: ${DEFAULT_PAYMENT.additional.contactEmail}</li>
            <li>📞 WhatsApp: ${DEFAULT_PAYMENT.additional.contactPhone}</li>
          </ul>
        </div>
      </div>
      
      <div style="text-align: center; margin: 30px 0;">
        <a href="${process.env.FRONTEND_URL || 'http://localhost:3000'}/view-invoice/${invoice.invoiceNumber}" class="button">
          📄 View Invoice Online
        </a>
      </div>
      
      <p style="margin-top: 30px;">The invoice PDF is attached to this email for your records.</p>
      
      <div style="background: white; padding: 20px; border-radius: 8px; margin-top: 20px;">
        <h3 style="color: #2c3e50; margin-top: 0;">📞 Need Help?</h3>
        <p>If you have any questions about this invoice, please contact us:</p>
        <ul style="list-style: none; padding: 0;">
          <li style="padding: 5px 0;">📧 Email: ${DEFAULT_PAYMENT.additional.contactEmail}</li>
          <li style="padding: 5px 0;">📞 Phone: ${DEFAULT_PAYMENT.additional.contactPhone}</li>
          <li style="padding: 5px 0;">🕐 Business Hours: Mon-Fri, 9 AM - 6 PM IST</li>
        </ul>
      </div>
    </div>
    
    <div class="footer">
      <p><strong>Abra Fleet Management Solutions</strong></p>
      <p>GST: ${DEFAULT_PAYMENT.additional.gstNumber}</p>
      <p>This is an automated email. Please do not reply to this message.</p>
    </div>
  </div>
</body>
</html>
  `;
  
  const mailOptions = {
    from: `"Abra Fleet Billing" <${process.env.SMTP_USER}>`,
    to: invoice.customerEmail,
    subject: `Invoice ${invoice.invoiceNumber} from Abra Fleet - ₹${invoice.totalAmount.toFixed(2)}`,
    html: emailHtml,
    attachments: [
      {
        filename: `Invoice-${invoice.invoiceNumber}.pdf`,
        path: pdfPath
      }
    ]
  };
  
  return emailTransporter.sendMail(mailOptions);
}

// Send payment receipt email
async function sendPaymentReceiptEmail(invoice, payment) {
  const emailHtml = `
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #27ae60 0%, #229954 100%); color: white; padding: 30px; text-align: center; border-radius: 8px 8px 0 0; }
    .content { background: #f8f9fa; padding: 30px; border-radius: 0 0 8px 8px; }
    .success-badge { background: #d4edda; color: #155724; padding: 15px; border-radius: 8px; text-align: center; margin: 20px 0; border: 1px solid #c3e6cb; }
    .payment-box { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; }
            .payment-detail { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid #ecf0f1; }
    .footer { text-align: center; color: #95a5a6; font-size: 12px; margin-top: 30px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>✅ Payment Received</h1>
      <p>Thank you for your payment!</p>
    </div>
    <div class="content">
      <div class="success-badge">
        <h2 style="margin: 0;">Payment Successful</h2>
        <p style="margin: 10px 0 0 0;">We have received your payment of ₹${payment.amount.toFixed(2)}</p>
      </div>
      <div class="payment-box">
        <h3>Payment Details:</h3>
        <div class="payment-detail"><span>Invoice:</span><span>${invoice.invoiceNumber}</span></div>
        <div class="payment-detail"><span>Amount Paid:</span><span>₹${payment.amount.toFixed(2)}</span></div>
        <div class="payment-detail"><span>Payment Date:</span><span>${new Date(payment.paymentDate).toLocaleDateString('en-IN')}</span></div>
        <div class="payment-detail"><span>Method:</span><span>${payment.paymentMethod}</span></div>
        ${payment.referenceNumber ? `<div class="payment-detail"><span>Reference:</span><span>${payment.referenceNumber}</span></div>` : ''}
        <div class="payment-detail" style="border: none; font-weight: bold; font-size: 18px; color: #27ae60; margin-top: 10px;">
          <span>Remaining Balance:</span><span>₹${invoice.amountDue.toFixed(2)}</span>
        </div>
      </div>
    </div>
    <div class="footer">
      <p>Abra Fleet Management | billing@abrafleet.com</p>
    </div>
  </div>
</body>
</html>
  `;
  
  return emailTransporter.sendMail({
    from: `"Abra Fleet Billing" <${process.env.SMTP_USER}>`,
    to: invoice.customerEmail,
    subject: `Payment Receipt - ${invoice.invoiceNumber}`,
    html: emailHtml
  });
}

// ============================================================================
// API ROUTES
// ============================================================================

// GET /api/invoices - List all invoices with filters
router.get('/', async (req, res) => {
  try {
    const { status, customerId, fromDate, toDate, page = 1, limit = 20 } = req.query;
    
    const query = {};
    
    if (status) query.status = status;
    if (customerId) query.customerId = customerId;
    if (fromDate || toDate) {
      query.invoiceDate = {};
      if (fromDate) query.invoiceDate.$gte = new Date(fromDate);
      if (toDate) query.invoiceDate.$lte = new Date(toDate);
    }
    
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    const invoices = await Invoice.find(query)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .select('-__v');
    
    const total = await Invoice.countDocuments(query);
    
    res.json({
      success: true,
      data: invoices,
      pagination: {
        total,
        page: parseInt(page),
        limit: parseInt(limit),
        pages: Math.ceil(total / parseInt(limit))
      }
    });
  } catch (error) {
    console.error('Error fetching invoices:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/invoices/stats - Get invoice statistics
router.get('/stats', async (req, res) => {
  try {
    const stats = await Invoice.aggregate([
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 },
          totalAmount: { $sum: '$totalAmount' },
          totalPaid: { $sum: '$amountPaid' },
          totalDue: { $sum: '$amountDue' }
        }
      }
    ]);
    
    const overallStats = {
      totalInvoices: 0,
      totalRevenue: 0,
      totalPaid: 0,
      totalDue: 0,
      byStatus: {}
    };
    
    stats.forEach(stat => {
      overallStats.totalInvoices += stat.count;
      overallStats.totalRevenue += stat.totalAmount;
      overallStats.totalPaid += stat.totalPaid;
      overallStats.totalDue += stat.totalDue;
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

// ============================================================================
// BILLING CUSTOMERS API ROUTES - Must be before /:id route
// ============================================================================

// GET /api/invoices/customers - Get all billing customers
router.get('/customers', async (req, res) => {
  try {
    const { search, page = 1, limit = 50, active = 'true' } = req.query;
    
    const query = {};
    
    // Filter by active status
    if (active !== 'all') {
      query.isActive = active === 'true';
    }
    
    // Search functionality
    if (search) {
      query.$or = [
        { customerName: { $regex: search, $options: 'i' } },
        { customerEmail: { $regex: search, $options: 'i' } },
        { companyName: { $regex: search, $options: 'i' } },
        { customerPhone: { $regex: search, $options: 'i' } }
      ];
    }
    
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    const customers = await BillingCustomer.find(query)
      .sort({ customerName: 1 })
      .skip(skip)
      .limit(parseInt(limit))
      .select('-__v');
    
    const total = await BillingCustomer.countDocuments(query);
    
    console.log(`📋 Retrieved ${customers.length} billing customers`);
    
    res.json({
      success: true,
      data: customers,
      pagination: {
        total,
        page: parseInt(page),
        limit: parseInt(limit),
        pages: Math.ceil(total / parseInt(limit))
      }
    });
  } catch (error) {
    console.error('❌ Error fetching billing customers:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

// GET /api/invoices/customers-stats - Get customer statistics
router.get('/customers-stats', async (req, res) => {
  try {
    const stats = await BillingCustomer.aggregate([
      {
        
        $group: {
          _id: null,
          totalCustomers: { $sum: 1 },
          activeCustomers: {
            $sum: { $cond: [{ $eq: ['$isActive', true] }, 1, 0] }
          },
          inactiveCustomers: {
            $sum: { $cond: [{ $eq: ['$isActive', false] }, 1, 0] }
          }
        }
      }
    ]);
    
    const result = stats[0] || {
      totalCustomers: 0,
      activeCustomers: 0,
      inactiveCustomers: 0
    };
    
    res.json({ 
      success: true, 
      data: result 
    });
  } catch (error) {
    console.error('❌ Error fetching customer stats:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

// GET /api/invoices/customers/:id - Get single billing customer
router.get('/customers/:id', async (req, res) => {
  try {
    const customer = await BillingCustomer.findById(req.params.id);
    
    if (!customer) {
      return res.status(404).json({ 
        success: false, 
        error: 'Customer not found' 
      });
    }
    
    res.json({ 
      success: true, 
      data: customer 
    });
  } catch (error) {
    console.error('❌ Error fetching billing customer:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

// POST /api/invoices/customers - Create new billing customer
router.post('/customers', async (req, res) => {
  try {
    const customerData = req.body;
    
    // Validate required fields
    if (!customerData.customerName || !customerData.customerEmail || !customerData.customerPhone) {
      return res.status(400).json({
        success: false,
        error: 'Customer name, email, and phone are required'
      });
    }
    
    // Check for duplicate email
    const existingCustomer = await BillingCustomer.findOne({ 
      customerEmail: customerData.customerEmail.toLowerCase(),
      isActive: true
    });
    
    if (existingCustomer) {
      return res.status(400).json({
        success: false,
        error: 'Customer with this email already exists'
      });
    }
    
    // Set creator
    customerData.createdBy = req.user?.email || req.user?.uid || 'system';
    
    const customer = new BillingCustomer(customerData);
    await customer.save();
    
    console.log(`✅ Billing customer created: ${customer.customerName} (${customer.customerEmail})`);
    
    res.status(201).json({
      success: true,
      message: 'Customer created successfully',
      data: customer
    });
  } catch (error) {
    console.error('❌ Error creating billing customer:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

// PUT /api/invoices/customers/:id - Update billing customer
router.put('/customers/:id', async (req, res) => {
  try {
    const customer = await BillingCustomer.findById(req.params.id);
    
    if (!customer) {
      return res.status(404).json({ 
        success: false, 
        error: 'Customer not found' 
      });
    }
    
    const updates = req.body;
    
    // Check for duplicate email if email is being updated
    if (updates.customerEmail && updates.customerEmail !== customer.customerEmail) {
      const existingCustomer = await BillingCustomer.findOne({ 
        customerEmail: updates.customerEmail.toLowerCase(),
        _id: { $ne: req.params.id },
        isActive: true
      });
      
      if (existingCustomer) {
        return res.status(400).json({
          success: false,
          error: 'Customer with this email already exists'
        });
      }
    }
    
    updates.updatedBy = req.user?.email || req.user?.uid || 'system';
    
    Object.assign(customer, updates);
    await customer.save();
    
    console.log(`✅ Billing customer updated: ${customer.customerName}`);
    
    res.json({
      success: true,
      message: 'Customer updated successfully',
      data: customer
    });
  } catch (error) {
    console.error('❌ Error updating billing customer:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

// DELETE /api/invoices/customers/:id - Soft delete billing customer
router.delete('/customers/:id', async (req, res) => {
  try {
    const customer = await BillingCustomer.findById(req.params.id);
    
    if (!customer) {
      return res.status(404).json({ 
        success: false, 
        error: 'Customer not found' 
      });
    }
    
    customer.isActive = false;
    customer.updatedBy = req.user?.email || req.user?.uid || 'system';
    await customer.save();
    
    console.log(`✅ Billing customer deactivated: ${customer.customerName}`);
    
    res.json({
      success: true,
      message: 'Customer deactivated successfully'
    });
  } catch (error) {
    console.error('❌ Error deactivating billing customer:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

// POST /api/invoices/customers/:id/activate - Reactivate billing customer
router.post('/customers/:id/activate', async (req, res) => {
  try {
    const customer = await BillingCustomer.findById(req.params.id);
    
    if (!customer) {
      return res.status(404).json({ 
        success: false, 
        error: 'Customer not found' 
      });
    }
    
    customer.isActive = true;
    customer.updatedBy = req.user?.email || req.user?.uid || 'system';
    await customer.save();
    
    console.log(`✅ Billing customer reactivated: ${customer.customerName}`);
    
    res.json({
      success: true,
      message: 'Customer reactivated successfully',
      data: customer
    });
  } catch (error) {
    console.error('❌ Error reactivating billing customer:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

// GET /api/invoices/:id - Get single invoice
router.get('/:id', async (req, res) => {
  try {
    const invoice = await Invoice.findById(req.params.id);
    
    if (!invoice) {
      return res.status(404).json({ success: false, error: 'Invoice not found' });
    }
    
    res.json({ success: true, data: invoice });
  } catch (error) {
    console.error('Error fetching invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/invoices - Create new invoice
router.post('/', async (req, res) => {
  try {
    const invoiceData = req.body;
    
    // Handle customerId - convert string to ObjectId or create new ObjectId
    if (invoiceData.customerId) {
      if (typeof invoiceData.customerId === 'string') {
        // If it's a string that looks like an ObjectId, try to convert it
        if (mongoose.Types.ObjectId.isValid(invoiceData.customerId)) {
          invoiceData.customerId = new mongoose.Types.ObjectId(invoiceData.customerId);
        } else {
          // If it's not a valid ObjectId, create a new one
          // This handles cases like "new_customer_1767775133099"
          invoiceData.customerId = new mongoose.Types.ObjectId();
          console.log(`📝 Created new ObjectId for customer: ${invoiceData.customerId}`);
        }
      }
    } else {
      // If no customerId provided, create a new one
      invoiceData.customerId = new mongoose.Types.ObjectId();
    }
    
    // Generate invoice number if not provided
    if (!invoiceData.invoiceNumber) {
      invoiceData.invoiceNumber = await generateInvoiceNumber();
    }
    
    // Calculate due date
    if (!invoiceData.dueDate) {
      invoiceData.dueDate = calculateDueDate(
        invoiceData.invoiceDate || new Date(),
        invoiceData.terms || 'Net 30'
      );
    }
    
    // Calculate item amounts
    if (invoiceData.items) {
      invoiceData.items = invoiceData.items.map(item => ({
        ...item,
        amount: calculateItemAmount(item)
      }));
    }
    
    // Set creator
    invoiceData.createdBy = req.user?.email || req.user?.uid || 'system';
    
    const invoice = new Invoice(invoiceData);
    await invoice.save();
    
    console.log(`✅ Invoice created: ${invoice.invoiceNumber} for customer: ${invoiceData.customerName}`);
    
    res.status(201).json({
      success: true,
      message: 'Invoice created successfully',
      data: invoice
    });
  } catch (error) {
    console.error('Error creating invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/invoices/:id - Update invoice
router.put('/:id', async (req, res) => {
  try {
    const invoice = await Invoice.findById(req.params.id);
    
    if (!invoice) {
      return res.status(404).json({ success: false, error: 'Invoice not found' });
    }
    
    // Prevent editing paid invoices
    if (invoice.status === 'PAID') {
      return res.status(400).json({
        success: false,
        error: 'Cannot edit paid invoices'
      });
    }
    
    const updates = req.body;
    
    // Recalculate item amounts if items changed
    if (updates.items) {
      updates.items = updates.items.map(item => ({
        ...item,
        amount: calculateItemAmount(item)
      }));
    }
    
    // Recalculate due date if terms changed
    if (updates.terms && updates.terms !== invoice.terms) {
      updates.dueDate = calculateDueDate(
        updates.invoiceDate || invoice.invoiceDate,
        updates.terms
      );
    }
    
    updates.updatedBy = req.user?.email || req.user?.uid || 'system';
    
    Object.assign(invoice, updates);
    await invoice.save();
    
    console.log(`✅ Invoice updated: ${invoice.invoiceNumber}`);
    
    res.json({
      success: true,
      message: 'Invoice updated successfully',
      data: invoice
    });
  } catch (error) {
    console.error('Error updating invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/invoices/:id/send - Send invoice via email
router.post('/:id/send', async (req, res) => {
  try {
    const invoice = await Invoice.findById(req.params.id);
    
    if (!invoice) {
      return res.status(404).json({ success: false, error: 'Invoice not found' });
    }
    
    // Generate PDF if not exists
    let pdfInfo;
    if (!invoice.pdfPath || !fs.existsSync(invoice.pdfPath)) {
      pdfInfo = await generateInvoicePDF(invoice);
      invoice.pdfPath = pdfInfo.filepath;
      invoice.pdfGeneratedAt = new Date();
    }
    
    // Send email
    await sendInvoiceEmail(invoice, invoice.pdfPath);
    
    // Update invoice status
    if (invoice.status === 'DRAFT') {
      invoice.status = 'SENT';
    }
    
    invoice.emailsSent.push({
      sentTo: invoice.customerEmail,
      sentAt: new Date(),
      emailType: 'invoice'
    });
    
    await invoice.save();
    
    console.log(`✅ Invoice sent: ${invoice.invoiceNumber} to ${invoice.customerEmail}`);
    
    res.json({
      success: true,
      message: 'Invoice sent successfully',
      data: invoice
    });
  } catch (error) {
    console.error('Error sending invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/invoices/:id/payment - Record payment
router.post('/:id/payment', async (req, res) => {
  try {
    const invoice = await Invoice.findById(req.params.id);
    
    if (!invoice) {
      return res.status(404).json({ success: false, error: 'Invoice not found' });
    }
    
    const { amount, paymentDate, paymentMethod, referenceNumber, notes } = req.body;
    
    if (!amount || amount <= 0) {
      return res.status(400).json({ success: false, error: 'Invalid payment amount' });
    }
    
    if (invoice.amountDue < amount) {
      return res.status(400).json({
        success: false,
        error: `Payment amount exceeds due amount (₹${invoice.amountDue.toFixed(2)})`
      });
    }
    
    const payment = {
      paymentId: new mongoose.Types.ObjectId(),
      amount: parseFloat(amount),
      paymentDate: paymentDate ? new Date(paymentDate) : new Date(),
      paymentMethod: paymentMethod || 'Bank Transfer',
      referenceNumber,
      notes,
      recordedBy: req.user?.email || req.user?.uid || 'system',
      recordedAt: new Date()
    };
    
    invoice.payments.push(payment);
    invoice.amountPaid += payment.amount;
    await invoice.save();
    
    // Send payment receipt email
    try {
      await sendPaymentReceiptEmail(invoice, payment);
    } catch (emailError) {
      console.warn('Failed to send payment receipt email:', emailError.message);
    }
    
    console.log(`✅ Payment recorded: ${invoice.invoiceNumber} - ₹${amount}`);
    
    res.json({
      success: true,
      message: 'Payment recorded successfully',
      data: {
        invoice,
        payment
      }
    });
  } catch (error) {
    console.error('Error recording payment:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/invoices/:id/pdf - Download PDF
router.get('/:id/pdf', async (req, res) => {
  try {
    const invoice = await Invoice.findById(req.params.id);
    
    if (!invoice) {
      return res.status(404).json({ success: false, error: 'Invoice not found' });
    }
    
    // Generate PDF if not exists
    if (!invoice.pdfPath || !fs.existsSync(invoice.pdfPath)) {
      const pdfInfo = await generateInvoicePDF(invoice);
      invoice.pdfPath = pdfInfo.filepath;
      invoice.pdfGeneratedAt = new Date();
      await invoice.save();
    }
    
    res.download(invoice.pdfPath, `Invoice-${invoice.invoiceNumber}.pdf`);
  } catch (error) {
    console.error('Error downloading PDF:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/invoices/:id - Delete invoice (only drafts)
router.delete('/:id', async (req, res) => {
  try {
    const invoice = await Invoice.findById(req.params.id);
    
    if (!invoice) {
      return res.status(404).json({ success: false, error: 'Invoice not found' });
    }
    
    if (invoice.status !== 'DRAFT') {
      return res.status(400).json({
        success: false,
        error: 'Only draft invoices can be deleted'
      });
    }
    
    await invoice.deleteOne();
    
    console.log(`✅ Invoice deleted: ${invoice.invoiceNumber}`);
    
    res.json({
      success: true,
      message: 'Invoice deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// BILLING CUSTOMERS SCHEMA AND MODEL
// ============================================================================

// Billing Customer Schema for invoice system
const billingCustomerSchema = new mongoose.Schema({
  customerName: {
    type: String,
    required: true,
    trim: true,
    index: true
  },
  customerEmail: {
    type: String,
    required: true,
    trim: true,
    lowercase: true,
    index: true
  },
  customerPhone: {
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
  
  // Billing Address
  billingAddress: {
    street: {
      type: String,
      trim: true
    },
    city: {
      type: String,
      trim: true
    },
    state: {
      type: String,
      trim: true
    },
    pincode: {
      type: String,
      trim: true
    },
    country: {
      type: String,
      default: 'India',
      trim: true
    }
  },
  
  // Shipping Address (optional, can be same as billing)
  shippingAddress: {
    street: {
      type: String,
      trim: true
    },
    city: {
      type: String,
      trim: true
    },
    state: {
      type: String,
      trim: true
    },
    pincode: {
      type: String,
      trim: true
    },
    country: {
      type: String,
      default: 'India',
      trim: true
    }
  },
  
  // Additional Info
  contactPerson: {
    type: String,
    trim: true
  },
  website: {
    type: String,
    trim: true
  },
  notes: {
    type: String,
    trim: true
  },
  
  // Status
  isActive: {
    type: Boolean,
    default: true,
    index: true
  },
  
  // Audit Trail
  createdBy: {
    type: String,
    required: true
  },
  updatedBy: {
    type: String
  },
  createdAt: {
    type: Date,
    default: Date.now,
    index: true
  },
  updatedAt: {
    type: Date,
    default: Date.now
  }
}, {
  timestamps: true,
  collection: 'billing-customers'
});

// Indexes for better performance
billingCustomerSchema.index({ customerName: 1, customerEmail: 1 });
billingCustomerSchema.index({ companyName: 1 });
billingCustomerSchema.index({ createdAt: -1 });

// Pre-save middleware
billingCustomerSchema.pre('save', function(next) {
  this.updatedAt = new Date();
  next();
});

const BillingCustomer = mongoose.model('BillingCustomer', billingCustomerSchema);

module.exports = router;
