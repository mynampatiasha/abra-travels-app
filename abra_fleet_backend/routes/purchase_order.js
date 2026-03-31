// ============================================================================
// PURCHASE ORDER SYSTEM - COMPLETE BACKEND
// ============================================================================
// File: backend/routes/purchase_order.js
// Contains: Routes, Controllers, Schema, PDF Generation, Email Service
// Database: MongoDB with Mongoose
// Features: Create, Edit, Send, Record Receive, Convert to Bill,
//           Issue, Cancel, Close, Bulk Import, Stats, PDF Download
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
// MONGOOSE SCHEMAS
// ============================================================================

// Purchase Order Schema
const purchaseOrderSchema = new mongoose.Schema({
  purchaseOrderNumber: {
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
  vendorName: { type: String, required: true },
  vendorEmail: String,
  vendorPhone: String,

  referenceNumber: String,

  purchaseOrderDate: {
    type: Date,
    required: true,
    default: Date.now
  },
  expectedDeliveryDate: Date,

  paymentTerms: {
    type: String,
    enum: ['Due on Receipt', 'Net 15', 'Net 30', 'Net 45', 'Net 60'],
    default: 'Net 30'
  },

  deliveryAddress: String,
  shipmentPreference: String,
  salesperson: String,
  subject: String,

  items: [{
    itemDetails: { type: String, required: true },
    quantity: { type: Number, required: true, min: 0 },
    rate: { type: Number, required: true, min: 0 },
    discount: { type: Number, default: 0, min: 0 },
    discountType: {
      type: String,
      enum: ['percentage', 'amount'],
      default: 'percentage'
    },
    amount: { type: Number, required: true }
  }],

  vendorNotes: String,
  termsAndConditions: String,

  // Financial
  subTotal: { type: Number, required: true, default: 0 },
  tdsRate: { type: Number, default: 0, min: 0, max: 100 },
  tdsAmount: { type: Number, default: 0 },
  tcsRate: { type: Number, default: 0, min: 0, max: 100 },
  tcsAmount: { type: Number, default: 0 },
  gstRate: { type: Number, default: 18, min: 0, max: 100 },
  cgst: { type: Number, default: 0 },
  sgst: { type: Number, default: 0 },
  igst: { type: Number, default: 0 },
  totalAmount: { type: Number, required: true, default: 0 },

  // Status
  status: {
    type: String,
    enum: [
      'DRAFT',
      'ISSUED',
      'PARTIALLY_RECEIVED',
      'RECEIVED',
      'PARTIALLY_BILLED',
      'BILLED',
      'CLOSED',
      'CANCELLED'
    ],
    default: 'DRAFT',
    index: true
  },

  receiveStatus: {
    type: String,
    enum: ['NOT_RECEIVED', 'PARTIALLY_RECEIVED', 'RECEIVED'],
    default: 'NOT_RECEIVED'
  },

  billingStatus: {
    type: String,
    enum: ['NOT_BILLED', 'PARTIALLY_BILLED', 'BILLED'],
    default: 'NOT_BILLED'
  },

  // Purchase Receives
  receives: [{
    receiveId: { type: mongoose.Schema.Types.ObjectId, default: () => new mongoose.Types.ObjectId() },
    receiveDate: { type: Date, required: true },
    items: [{
      itemDetails: String,
      quantityOrdered: Number,
      quantityReceived: Number
    }],
    notes: String,
    recordedBy: String,
    recordedAt: { type: Date, default: Date.now }
  }],

  // Linked Bills
  linkedBills: [{
    billId: mongoose.Schema.Types.ObjectId,
    billNumber: String,
    createdAt: { type: Date, default: Date.now }
  }],

  // Email Tracking
  emailsSent: [{
    sentTo: String,
    sentAt: Date,
    emailType: {
      type: String,
      enum: ['purchase_order', 'reminder']
    }
  }],

  // PDF
  pdfPath: String,
  pdfGeneratedAt: Date,

  // Audit
  createdBy: { type: String, required: true },
  updatedBy: String

}, { timestamps: true });

// Pre-save: calculate amounts
purchaseOrderSchema.pre('save', function (next) {
  // Subtotal
  this.subTotal = this.items.reduce((sum, item) => sum + (item.amount || 0), 0);

  // TDS (reduces total)
  this.tdsAmount = (this.subTotal * this.tdsRate) / 100;

  // TCS (increases total)
  this.tcsAmount = (this.subTotal * this.tcsRate) / 100;

  // GST
  const gstBase = this.subTotal - this.tdsAmount + this.tcsAmount;
  const gstAmount = (gstBase * this.gstRate) / 100;

  // Intra-state: CGST + SGST
  this.cgst = gstAmount / 2;
  this.sgst = gstAmount / 2;
  this.igst = 0;

  // Total
  this.totalAmount = this.subTotal - this.tdsAmount + this.tcsAmount + gstAmount;

  next();
});

purchaseOrderSchema.index({ vendorId: 1, purchaseOrderDate: -1 });
purchaseOrderSchema.index({ status: 1, expectedDeliveryDate: 1 });
purchaseOrderSchema.index({ createdAt: -1 });

const PurchaseOrder = mongoose.model('PurchaseOrder', purchaseOrderSchema);

// ============================================================================
// VENDOR SCHEMA
// ============================================================================

const vendorSchema = new mongoose.Schema({
  vendorName: { type: String, required: true, trim: true, index: true },
  vendorEmail: { type: String, required: true, trim: true, lowercase: true, index: true },
  vendorPhone: { type: String, required: true, trim: true },
  companyName: { type: String, trim: true },
  gstNumber: { type: String, trim: true, uppercase: true },
  billingAddress: {
    street: String,
    city: String,
    state: String,
    pincode: String,
    country: { type: String, default: 'India' }
  },
  isActive: { type: Boolean, default: true, index: true },
  createdBy: { type: String, required: true },
  updatedBy: String
}, { timestamps: true, collection: 'vendors' });

// Check if model exists before creating to avoid OverwriteModelError
const Vendor = mongoose.models.Vendor || mongoose.model('Vendor', vendorSchema);

// ============================================================================
// HELPERS
// ============================================================================

async function generatePONumber() {
  const date = new Date();
  const year = date.getFullYear().toString().slice(-2);
  const month = (date.getMonth() + 1).toString().padStart(2, '0');

  const lastPO = await PurchaseOrder.findOne({
    purchaseOrderNumber: new RegExp(`^PO-${year}${month}`)
  }).sort({ purchaseOrderNumber: -1 });

  let seq = 1;
  if (lastPO) {
    const lastSeq = parseInt(lastPO.purchaseOrderNumber.split('-')[2]);
    seq = lastSeq + 1;
  }

  return `PO-${year}${month}-${seq.toString().padStart(4, '0')}`;
}

function calcItemAmount(item) {
  let amount = (item.quantity || 0) * (item.rate || 0);
  if (item.discount > 0) {
    if (item.discountType === 'percentage') {
      amount = amount - (amount * item.discount / 100);
    } else {
      amount = amount - item.discount;
    }
  }
  return Math.round(amount * 100) / 100;
}

function getCreator(req) {
  return req.user?.email || req.user?.uid || 'system';
}

// ============================================================================
// PDF GENERATION
// ============================================================================

async function generatePurchaseOrderPDF(po) {
  return new Promise((resolve, reject) => {
    try {
      const uploadsDir = path.join(__dirname, '..', 'uploads', 'purchase-orders');
      if (!fs.existsSync(uploadsDir)) {
        fs.mkdirSync(uploadsDir, { recursive: true });
      }

      const filename = `po-${po.purchaseOrderNumber}.pdf`;
      const filepath = path.join(uploadsDir, filename);

      const doc = new PDFDocument({ size: 'A4', margin: 50 });
      const stream = fs.createWriteStream(filepath);
      doc.pipe(stream);

      // Header
      doc.fontSize(24).fillColor('#2C3E50').text('ABRA FLEET', 50, 50);
      doc.fontSize(10).fillColor('#7F8C8D')
        .text('Fleet Management Solutions', 50, 80)
        .text('GST: 29XXXXX1234X1Z5', 50, 95);

      doc.fontSize(28).fillColor('#2C3E50').text('PURCHASE ORDER', 300, 50, { align: 'right' });

      doc.fontSize(10).fillColor('#34495E')
        .text(`PO#: ${po.purchaseOrderNumber}`, 400, 90, { align: 'right' })
        .text(`Date: ${new Date(po.purchaseOrderDate).toLocaleDateString('en-IN')}`, 400, 105, { align: 'right' });

      if (po.expectedDeliveryDate) {
        doc.text(`Expected Delivery: ${new Date(po.expectedDeliveryDate).toLocaleDateString('en-IN')}`, 400, 120, { align: 'right' });
      }
      if (po.referenceNumber) {
        doc.text(`Reference#: ${po.referenceNumber}`, 400, 135, { align: 'right' });
      }

      // Separator
      doc.moveTo(50, 165).lineTo(545, 165).strokeColor('#BDC3C7').stroke();

      // Vendor section
      doc.fontSize(12).fillColor('#2C3E50').text('VENDOR:', 50, 185);
      doc.fontSize(11).fillColor('#34495E').text(po.vendorName, 50, 205);
      doc.fontSize(10).fillColor('#7F8C8D');
      let yPos = 220;
      if (po.vendorEmail) { doc.text(`Email: ${po.vendorEmail}`, 50, yPos); yPos += 15; }
      if (po.vendorPhone) { doc.text(`Phone: ${po.vendorPhone}`, 50, yPos); yPos += 15; }

      // Delivery address
      if (po.deliveryAddress) {
        doc.fontSize(12).fillColor('#2C3E50').text('SHIP TO:', 300, 185);
        doc.fontSize(10).fillColor('#7F8C8D').text(po.deliveryAddress, 300, 205, { width: 245 });
      }

      // Items Table Header
      yPos = 315;
      doc.fillColor('#FFFFFF').rect(50, yPos, 495, 25).fill('#34495E');
      doc.fillColor('#FFFFFF')
        .text('ITEM DETAILS', 60, yPos + 8)
        .text('QTY', 320, yPos + 8, { width: 40, align: 'center' })
        .text('RATE', 370, yPos + 8, { width: 60, align: 'right' })
        .text('DISCOUNT', 440, yPos + 8, { width: 50, align: 'right' })
        .text('AMOUNT', 500, yPos + 8, { width: 55, align: 'right' });

      yPos += 35;
      doc.fillColor('#34495E');

      po.items.forEach((item) => {
        if (yPos > 700) { doc.addPage(); yPos = 50; }

        doc.fontSize(10)
          .text(item.itemDetails, 60, yPos, { width: 240 })
          .text(item.quantity.toString(), 320, yPos, { width: 40, align: 'center' })
          .text(`Rs.${item.rate.toFixed(2)}`, 370, yPos, { width: 60, align: 'right' })
          .text(item.discount > 0 ? `${item.discount}${item.discountType === 'percentage' ? '%' : 'Rs.'}` : '-', 440, yPos, { width: 50, align: 'right' })
          .text(`Rs.${item.amount.toFixed(2)}`, 500, yPos, { width: 55, align: 'right' });

        yPos += 25;
        doc.moveTo(50, yPos).lineTo(545, yPos).strokeColor('#ECF0F1').stroke();
        yPos += 5;
      });

      // Summary
      yPos += 20;
      const sumX = 380;

      doc.fontSize(10).fillColor('#7F8C8D').text('Sub Total:', sumX, yPos);
      doc.fillColor('#34495E').text(`Rs.${po.subTotal.toFixed(2)}`, sumX + 100, yPos, { align: 'right' });
      yPos += 20;

      if (po.tdsAmount > 0) {
        doc.fillColor('#7F8C8D').text(`TDS (${po.tdsRate}%):`, sumX, yPos);
        doc.fillColor('#E74C3C').text(`- Rs.${po.tdsAmount.toFixed(2)}`, sumX + 100, yPos, { align: 'right' });
        yPos += 20;
      }
      if (po.tcsAmount > 0) {
        doc.fillColor('#7F8C8D').text(`TCS (${po.tcsRate}%):`, sumX, yPos);
        doc.fillColor('#34495E').text(`Rs.${po.tcsAmount.toFixed(2)}`, sumX + 100, yPos, { align: 'right' });
        yPos += 20;
      }
      if (po.cgst > 0) {
        doc.fillColor('#7F8C8D').text(`CGST (${(po.gstRate / 2).toFixed(1)}%):`, sumX, yPos);
        doc.fillColor('#34495E').text(`Rs.${po.cgst.toFixed(2)}`, sumX + 100, yPos, { align: 'right' });
        yPos += 15;
        doc.fillColor('#7F8C8D').text(`SGST (${(po.gstRate / 2).toFixed(1)}%):`, sumX, yPos);
        doc.fillColor('#34495E').text(`Rs.${po.sgst.toFixed(2)}`, sumX + 100, yPos, { align: 'right' });
        yPos += 20;
      }

      doc.moveTo(sumX, yPos).lineTo(545, yPos).strokeColor('#34495E').lineWidth(2).stroke();
      yPos += 15;

      doc.fontSize(14).fillColor('#2C3E50')
        .text('Total Amount:', sumX, yPos)
        .text(`Rs.${po.totalAmount.toFixed(2)}`, sumX + 100, yPos, { align: 'right' });

      // Notes
      if (po.vendorNotes || po.termsAndConditions) {
        yPos += 50;
        if (yPos > 650) { doc.addPage(); yPos = 50; }

        if (po.vendorNotes) {
          doc.fontSize(11).fillColor('#2C3E50').text('Notes:', 50, yPos);
          doc.fontSize(10).fillColor('#7F8C8D').text(po.vendorNotes, 50, yPos + 20, { width: 495 });
          yPos += 60;
        }
        if (po.termsAndConditions) {
          doc.fontSize(11).fillColor('#2C3E50').text('Terms & Conditions:', 50, yPos);
          doc.fontSize(9).fillColor('#7F8C8D').text(po.termsAndConditions, 50, yPos + 20, { width: 495 });
        }
      }

      // Footer
      doc.fontSize(9).fillColor('#95A5A6')
        .text('This is a computer-generated Purchase Order.', 50, 750, { align: 'center', width: 495 })
        .text('Abra Fleet Management | purchase@abrafleet.com', 50, 765, { align: 'center', width: 495 });

      doc.end();

      stream.on('finish', () => {
        resolve({ filename, filepath, relativePath: `/uploads/purchase-orders/${filename}` });
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

async function sendPurchaseOrderEmail(po, pdfPath) {
  const itemsHtml = po.items.map(item => `
    <tr>
      <td style="padding: 10px; border-bottom: 1px solid #ecf0f1;">${item.itemDetails}</td>
      <td style="padding: 10px; border-bottom: 1px solid #ecf0f1; text-align: center;">${item.quantity}</td>
      <td style="padding: 10px; border-bottom: 1px solid #ecf0f1; text-align: right;">₹${item.rate.toFixed(2)}</td>
      <td style="padding: 10px; border-bottom: 1px solid #ecf0f1; text-align: right;">₹${item.amount.toFixed(2)}</td>
    </tr>
  `).join('');

  const emailHtml = `
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 650px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #2C3E50 0%, #34495E 100%); color: white; padding: 30px; text-align: center; border-radius: 8px 8px 0 0; }
    .content { background: #f8f9fa; padding: 30px; border-radius: 0 0 8px 8px; }
    .po-box { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; border-left: 4px solid #3498DB; }
    .po-detail { display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #ecf0f1; }
    .label { font-weight: bold; color: #7f8c8d; }
    .value { color: #2c3e50; font-weight: 600; }
    .total-box { font-size: 22px; color: #27ae60; text-align: center; margin: 20px 0; padding: 15px; background: #e8f8f5; border-radius: 8px; }
    .items-table { width: 100%; border-collapse: collapse; margin: 20px 0; }
    .items-table th { background: #34495E; color: white; padding: 10px; text-align: left; }
    .info-box { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; border: 1px solid #e0e0e0; }
    .footer { text-align: center; color: #95a5a6; font-size: 12px; margin-top: 30px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🚗 ABRA FLEET</h1>
      <p style="margin:5px 0 0 0; opacity:0.9;">Fleet Management Solutions</p>
    </div>
    <div class="content">
      <h2 style="color:#2c3e50; margin-top:0;">Purchase Order from Abra Fleet</h2>

      <p>Dear <strong>${po.vendorName}</strong>,</p>
      <p>Please find below our purchase order. Kindly confirm the order and arrange delivery as per the expected delivery date.</p>

      <div class="po-box">
        <div class="po-detail">
          <span class="label">PO Number:</span>
          <span class="value">${po.purchaseOrderNumber}</span>
        </div>
        <div class="po-detail">
          <span class="label">PO Date:</span>
          <span class="value">${new Date(po.purchaseOrderDate).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}</span>
        </div>
        ${po.expectedDeliveryDate ? `
        <div class="po-detail">
          <span class="label">Expected Delivery:</span>
          <span class="value">${new Date(po.expectedDeliveryDate).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}</span>
        </div>` : ''}
        <div class="po-detail">
          <span class="label">Payment Terms:</span>
          <span class="value">${po.paymentTerms}</span>
        </div>
        ${po.referenceNumber ? `
        <div class="po-detail">
          <span class="label">Reference#:</span>
          <span class="value">${po.referenceNumber}</span>
        </div>` : ''}
      </div>

      <div class="total-box">
        <div style="font-size:14px; color:#7f8c8d; margin-bottom:5px;">Total Order Value</div>
        <strong>₹${po.totalAmount.toFixed(2)}</strong>
      </div>

      <!-- Items Table -->
      <table class="items-table">
        <thead>
          <tr>
            <th>Item Details</th>
            <th style="text-align:center;">Qty</th>
            <th style="text-align:right;">Rate</th>
            <th style="text-align:right;">Amount</th>
          </tr>
        </thead>
        <tbody>
          ${itemsHtml}
          <tr>
            <td colspan="3" style="padding:10px; text-align:right; font-weight:bold;">Sub Total:</td>
            <td style="padding:10px; text-align:right; font-weight:bold;">₹${po.subTotal.toFixed(2)}</td>
          </tr>
          ${po.cgst > 0 ? `
          <tr>
            <td colspan="3" style="padding:5px 10px; text-align:right; color:#666;">CGST (${(po.gstRate/2).toFixed(1)}%):</td>
            <td style="padding:5px 10px; text-align:right;">₹${po.cgst.toFixed(2)}</td>
          </tr>
          <tr>
            <td colspan="3" style="padding:5px 10px; text-align:right; color:#666;">SGST (${(po.gstRate/2).toFixed(1)}%):</td>
            <td style="padding:5px 10px; text-align:right;">₹${po.sgst.toFixed(2)}</td>
          </tr>` : ''}
          <tr style="background:#e8f8f5;">
            <td colspan="3" style="padding:12px 10px; text-align:right; font-weight:bold; font-size:16px;">Total:</td>
            <td style="padding:12px 10px; text-align:right; font-weight:bold; font-size:16px; color:#27ae60;">₹${po.totalAmount.toFixed(2)}</td>
          </tr>
        </tbody>
      </table>

      ${po.deliveryAddress ? `
      <div class="info-box">
        <h4 style="margin-top:0; color:#2c3e50;">📦 Delivery Address</h4>
        <p style="margin:0; color:#666;">${po.deliveryAddress}</p>
      </div>` : ''}

      ${po.vendorNotes ? `
      <div class="info-box">
        <h4 style="margin-top:0; color:#2c3e50;">📝 Notes</h4>
        <p style="margin:0; color:#666;">${po.vendorNotes}</p>
      </div>` : ''}

      <div class="info-box">
        <h4 style="margin-top:0; color:#2c3e50;">📞 Contact Us</h4>
        <p style="margin:0;">📧 Email: ${process.env.COMPANY_EMAIL || 'purchase@abrafleet.com'}<br>
        📞 Phone: ${process.env.COMPANY_PHONE || '+91-XXXXXXXXXX'}</p>
      </div>

      <p>The purchase order PDF is attached to this email for your reference.</p>
    </div>
    <div class="footer">
      <p><strong>Abra Fleet Management Solutions</strong></p>
      <p>This is a computer-generated purchase order.</p>
    </div>
  </div>
</body>
</html>`;

  return emailTransporter.sendMail({
    from: `"Abra Fleet Purchase" <${process.env.SMTP_USER}>`,
    to: po.vendorEmail,
    subject: `Purchase Order ${po.purchaseOrderNumber} from Abra Fleet - ₹${po.totalAmount.toFixed(2)}`,
    html: emailHtml,
    attachments: [{
      filename: `PO-${po.purchaseOrderNumber}.pdf`,
      path: pdfPath
    }]
  });
}

// ============================================================================
// VENDOR ROUTES
// ============================================================================

// GET /api/vendors - Get all vendors
router.get('/vendors', async (req, res) => {
  try {
    const { search, page = 1, limit = 50 } = req.query;
    const query = { isActive: true };

    if (search) {
      query.$or = [
        { vendorName: { $regex: search, $options: 'i' } },
        { vendorEmail: { $regex: search, $options: 'i' } },
        { companyName: { $regex: search, $options: 'i' } }
      ];
    }

    const skip = (parseInt(page) - 1) * parseInt(limit);
    const vendors = await Vendor.find(query).sort({ vendorName: 1 }).skip(skip).limit(parseInt(limit));
    const total = await Vendor.countDocuments(query);

    res.json({
      success: true,
      data: {
        vendors,
        pagination: {
          total,
          page: parseInt(page),
          limit: parseInt(limit),
          pages: Math.ceil(total / parseInt(limit))
        }
      }
    });
  } catch (error) {
    console.error('Error fetching vendors:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/vendors - Create vendor
router.post('/vendors', async (req, res) => {
  try {
    const data = req.body;

    if (!data.vendorName || !data.vendorEmail || !data.vendorPhone) {
      return res.status(400).json({
        success: false,
        error: 'Vendor name, email, and phone are required'
      });
    }

    const existing = await Vendor.findOne({
      vendorEmail: data.vendorEmail.toLowerCase(),
      isActive: true
    });
    if (existing) {
      return res.status(400).json({
        success: false,
        error: 'Vendor with this email already exists'
      });
    }

    data.createdBy = getCreator(req);
    const vendor = new Vendor(data);
    await vendor.save();

    console.log(`✅ Vendor created: ${vendor.vendorName}`);
    res.status(201).json({ success: true, message: 'Vendor created', data: vendor });
  } catch (error) {
    console.error('Error creating vendor:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// PURCHASE ORDER ROUTES
// ============================================================================

// GET /api/purchase-orders/stats
router.get('/stats', async (req, res) => {
  try {
    const [
      total,
      draft,
      issued,
      received,
      billed,
      totalValueResult
    ] = await Promise.all([
      PurchaseOrder.countDocuments(),
      PurchaseOrder.countDocuments({ status: 'DRAFT' }),
      PurchaseOrder.countDocuments({ status: 'ISSUED' }),
      PurchaseOrder.countDocuments({ status: { $in: ['RECEIVED', 'PARTIALLY_RECEIVED'] } }),
      PurchaseOrder.countDocuments({ status: { $in: ['BILLED', 'CLOSED'] } }),
      PurchaseOrder.aggregate([{ $group: { _id: null, total: { $sum: '$totalAmount' } } }])
    ]);

    res.json({
      success: true,
      data: {
        totalPurchaseOrders: total,
        draftPurchaseOrders: draft,
        issuedPurchaseOrders: issued,
        receivedPurchaseOrders: received,
        billedPurchaseOrders: billed,
        totalValue: totalValueResult[0]?.total || 0
      }
    });
  } catch (error) {
    console.error('Error fetching PO stats:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/purchase-orders - List all
router.get('/', async (req, res) => {
  try {
    const { status, fromDate, toDate, page = 1, limit = 20, search } = req.query;

    const query = {};
    if (status) query.status = status;
    if (fromDate || toDate) {
      query.purchaseOrderDate = {};
      if (fromDate) query.purchaseOrderDate.$gte = new Date(fromDate);
      if (toDate) query.purchaseOrderDate.$lte = new Date(toDate);
    }
    if (search) {
      query.$or = [
        { purchaseOrderNumber: { $regex: search, $options: 'i' } },
        { vendorName: { $regex: search, $options: 'i' } },
        { referenceNumber: { $regex: search, $options: 'i' } }
      ];
    }

    const skip = (parseInt(page) - 1) * parseInt(limit);
    const pos = await PurchaseOrder.find(query)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .select('-__v');

    const total = await PurchaseOrder.countDocuments(query);

    res.json({
      success: true,
      data: pos,
      pagination: {
        total,
        page: parseInt(page),
        limit: parseInt(limit),
        pages: Math.ceil(total / parseInt(limit))
      }
    });
  } catch (error) {
    console.error('Error fetching purchase orders:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/purchase-orders/:id - Get single PO
router.get('/:id', async (req, res) => {
  try {
    const po = await PurchaseOrder.findById(req.params.id);
    if (!po) return res.status(404).json({ success: false, error: 'Purchase order not found' });
    res.json({ success: true, data: po });
  } catch (error) {
    console.error('Error fetching PO:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/purchase-orders - Create new PO
router.post('/', async (req, res) => {
  try {
    const data = { ...req.body };

    // Handle vendorId
    if (data.vendorId) {
      if (typeof data.vendorId === 'string') {
        if (mongoose.Types.ObjectId.isValid(data.vendorId)) {
          data.vendorId = new mongoose.Types.ObjectId(data.vendorId);
        } else {
          data.vendorId = new mongoose.Types.ObjectId();
        }
      }
    } else {
      data.vendorId = new mongoose.Types.ObjectId();
    }

    // Generate PO number
    if (!data.purchaseOrderNumber) {
      data.purchaseOrderNumber = await generatePONumber();
    }

    // Calculate item amounts
    if (data.items) {
      data.items = data.items.map(item => ({
        ...item,
        amount: calcItemAmount(item)
      }));
    }

    data.createdBy = getCreator(req);
    const po = new PurchaseOrder(data);
    await po.save();
// ✅ COA: Debit Expense + Credit Accounts Payable + TDS + TCS
try {
  const [expenseId, apId, taxId, tdsPayableId, tdsReceivableId] = await Promise.all([
    getSystemAccountId('Cost of Goods Sold'),
    getSystemAccountId('Accounts Payable'),
    getSystemAccountId('Tax Payable'),
    getSystemAccountId('TDS Payable'),
    getSystemAccountId('TDS Receivable'),
  ]);
  const txnDate = new Date(po.purchaseOrderDate);

  if (expenseId) await postTransactionToCOA({
    accountId: expenseId, date: txnDate,
    description: `PO ${po.purchaseOrderNumber} - ${po.vendorName}`,
    referenceType: 'Bill', referenceId: po._id,
    referenceNumber: po.purchaseOrderNumber,
    debit: po.subTotal, credit: 0
  });

  if (apId) await postTransactionToCOA({
    accountId: apId, date: txnDate,
    description: `PO ${po.purchaseOrderNumber} - ${po.vendorName}`,
    referenceType: 'Bill', referenceId: po._id,
    referenceNumber: po.purchaseOrderNumber,
    debit: 0, credit: po.totalAmount
  });

  if (taxId && (po.cgst + po.sgst) > 0) await postTransactionToCOA({
    accountId: taxId, date: txnDate,
    description: `GST on PO ${po.purchaseOrderNumber}`,
    referenceType: 'Bill', referenceId: po._id,
    referenceNumber: po.purchaseOrderNumber,
    debit: po.cgst + po.sgst, credit: 0
  });

  if (tdsPayableId && po.tdsAmount > 0) await postTransactionToCOA({
    accountId: tdsPayableId, date: txnDate,
    description: `TDS on PO ${po.purchaseOrderNumber}`,
    referenceType: 'Bill', referenceId: po._id,
    referenceNumber: po.purchaseOrderNumber,
    debit: 0, credit: po.tdsAmount
  });

  if (tdsReceivableId && po.tcsAmount > 0) await postTransactionToCOA({
    accountId: tdsReceivableId, date: txnDate,
    description: `TCS on PO ${po.purchaseOrderNumber}`,
    referenceType: 'Bill', referenceId: po._id,
    referenceNumber: po.purchaseOrderNumber,
    debit: po.tcsAmount, credit: 0
  });

  console.log(`✅ COA posted for PO: ${po.purchaseOrderNumber}`);
} catch (coaErr) {
  console.error('⚠️ COA post error (PO create):', coaErr.message);
}

    console.log(`✅ Purchase order created: ${po.purchaseOrderNumber}`);
    res.status(201).json({ success: true, message: 'Purchase order created', data: po });
  } catch (error) {
    console.error('Error creating PO:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/purchase-orders/:id - Update PO
router.put('/:id', async (req, res) => {
  try {
    const po = await PurchaseOrder.findById(req.params.id);
    if (!po) return res.status(404).json({ success: false, error: 'Purchase order not found' });

    if (['BILLED', 'CLOSED', 'CANCELLED'].includes(po.status)) {
      return res.status(400).json({
        success: false,
        error: `Cannot edit a purchase order with status: ${po.status}`
      });
    }

    const updates = { ...req.body };

    if (updates.items) {
      updates.items = updates.items.map(item => ({
        ...item,
        amount: calcItemAmount(item)
      }));
    }

    updates.updatedBy = getCreator(req);
    Object.assign(po, updates);
    await po.save();

    console.log(`✅ Purchase order updated: ${po.purchaseOrderNumber}`);
    res.json({ success: true, message: 'Purchase order updated', data: po });
  } catch (error) {
    console.error('Error updating PO:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/purchase-orders/:id/issue - Issue PO (DRAFT → ISSUED)
router.post('/:id/issue', async (req, res) => {
  try {
    const po = await PurchaseOrder.findById(req.params.id);
    if (!po) return res.status(404).json({ success: false, error: 'Purchase order not found' });

    if (po.status !== 'DRAFT') {
      return res.status(400).json({
        success: false,
        error: `Only DRAFT purchase orders can be issued. Current status: ${po.status}`
      });
    }

    po.status = 'ISSUED';
    po.updatedBy = getCreator(req);
    await po.save();

    console.log(`✅ Purchase order issued: ${po.purchaseOrderNumber}`);
    res.json({ success: true, message: 'Purchase order issued', data: po });
  } catch (error) {
    console.error('Error issuing PO:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/purchase-orders/:id/send - Send PO via email
router.post('/:id/send', async (req, res) => {
  try {
    const po = await PurchaseOrder.findById(req.params.id);
    if (!po) return res.status(404).json({ success: false, error: 'Purchase order not found' });

    if (!po.vendorEmail) {
      return res.status(400).json({
        success: false,
        error: 'Vendor email is required to send purchase order'
      });
    }

    // Generate PDF if not exists
    if (!po.pdfPath || !fs.existsSync(po.pdfPath)) {
      const pdfInfo = await generatePurchaseOrderPDF(po);
      po.pdfPath = pdfInfo.filepath;
      po.pdfGeneratedAt = new Date();
    }

    // Send email
    await sendPurchaseOrderEmail(po, po.pdfPath);

    // Update status to ISSUED if still DRAFT
    if (po.status === 'DRAFT') {
      po.status = 'ISSUED';
    }

    po.emailsSent.push({
      sentTo: po.vendorEmail,
      sentAt: new Date(),
      emailType: 'purchase_order'
    });

    po.updatedBy = getCreator(req);
    await po.save();

    console.log(`✅ Purchase order sent: ${po.purchaseOrderNumber} to ${po.vendorEmail}`);
    res.json({ success: true, message: 'Purchase order sent successfully', data: po });
  } catch (error) {
    console.error('Error sending PO:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/purchase-orders/:id/receive - Record purchase receive
router.post('/:id/receive', async (req, res) => {
  try {
    const po = await PurchaseOrder.findById(req.params.id);
    if (!po) return res.status(404).json({ success: false, error: 'Purchase order not found' });

    if (!['ISSUED', 'PARTIALLY_RECEIVED'].includes(po.status)) {
      return res.status(400).json({
        success: false,
        error: 'Only ISSUED or PARTIALLY_RECEIVED purchase orders can record a receive'
      });
    }

    const { receiveDate, items, notes } = req.body;

    if (!items || items.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'At least one item is required for receive'
      });
    }

    // Add receive record
    po.receives.push({
      receiveDate: receiveDate ? new Date(receiveDate) : new Date(),
      items,
      notes,
      recordedBy: getCreator(req),
      recordedAt: new Date()
    });

    // Calculate total received vs ordered
    const orderedQtyMap = {};
    po.items.forEach(item => {
      orderedQtyMap[item.itemDetails] = item.quantity;
    });

    const receivedQtyMap = {};
    po.receives.forEach(receive => {
      receive.items.forEach(rItem => {
        receivedQtyMap[rItem.itemDetails] =
          (receivedQtyMap[rItem.itemDetails] || 0) + (rItem.quantityReceived || 0);
      });
    });

    // Determine receive status
    let allReceived = true;
    let anyReceived = false;

    po.items.forEach(item => {
      const ordered = orderedQtyMap[item.itemDetails] || 0;
      const received = receivedQtyMap[item.itemDetails] || 0;
      if (received > 0) anyReceived = true;
      if (received < ordered) allReceived = false;
    });

    if (allReceived) {
      po.receiveStatus = 'RECEIVED';
      po.status = 'RECEIVED';
    } else if (anyReceived) {
      po.receiveStatus = 'PARTIALLY_RECEIVED';
      po.status = 'PARTIALLY_RECEIVED';
    }

    po.updatedBy = getCreator(req);
    await po.save();

    console.log(`✅ Purchase receive recorded for: ${po.purchaseOrderNumber}`);
    res.json({ success: true, message: 'Purchase receive recorded', data: po });
  } catch (error) {
    console.error('Error recording receive:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/purchase-orders/:id/convert-to-bill - Convert PO to Bill
router.post('/:id/convert-to-bill', async (req, res) => {
  try {
    const po = await PurchaseOrder.findById(req.params.id);
    if (!po) return res.status(404).json({ success: false, error: 'Purchase order not found' });

    if (!['RECEIVED', 'PARTIALLY_RECEIVED', 'PARTIALLY_BILLED'].includes(po.status)) {
      return res.status(400).json({
        success: false,
        error: 'Only RECEIVED or PARTIALLY_RECEIVED purchase orders can be converted to bill'
      });
    }

    // Build bill data from PO
    const Bill = mongoose.model('Bill') || null;

    // If Bill model is not loaded, create a placeholder response
    // (The actual Bill model should be in bills.js)
    const billData = {
      purchaseOrderId: po._id,
      purchaseOrderNumber: po.purchaseOrderNumber,
      vendorId: po.vendorId,
      vendorName: po.vendorName,
      vendorEmail: po.vendorEmail,
      vendorPhone: po.vendorPhone,
      billDate: new Date(),
      dueDate: calculateBillDueDate(new Date(), po.paymentTerms),
      paymentTerms: po.paymentTerms,
      items: po.items,
      vendorNotes: po.vendorNotes,
      termsAndConditions: po.termsAndConditions,
      subTotal: po.subTotal,
      tdsRate: po.tdsRate,
      tdsAmount: po.tdsAmount,
      tcsRate: po.tcsRate,
      tcsAmount: po.tcsAmount,
      gstRate: po.gstRate,
      cgst: po.cgst,
      sgst: po.sgst,
      igst: po.igst,
      totalAmount: po.totalAmount,
      status: 'OPEN',
      createdBy: getCreator(req)
    };

    // Try to create bill via Bill model if available
    let savedBill = null;
    try {
      const BillModel = require('./bill').BillModel;
      savedBill = new BillModel(billData);
      await savedBill.save();
    } catch (billModelError) {
      // Bill model may not be available — create a raw document
      const dynamicBillSchema = new mongoose.Schema({}, { strict: false, timestamps: true });
      let DynamicBill;
      try {
        DynamicBill = mongoose.model('Bill');
      } catch (_) {
        DynamicBill = mongoose.model('Bill', dynamicBillSchema, 'bills');
      }
      savedBill = new DynamicBill({ ...billData, billNumber: await generateBillNumber() });
      await savedBill.save();
    }

    // Update PO billing status
    po.billingStatus = 'BILLED';
    po.status = 'BILLED';

    if (savedBill) {
      po.linkedBills.push({
        billId: savedBill._id,
        billNumber: savedBill.billNumber || 'BILL-AUTO',
        createdAt: new Date()
      });
    }

    po.updatedBy = getCreator(req);
    await po.save();

    console.log(`✅ Purchase order converted to bill: ${po.purchaseOrderNumber}`);
    res.json({
      success: true,
      message: 'Purchase order converted to bill successfully',
      data: { purchaseOrder: po, bill: savedBill }
    });
  } catch (error) {
    console.error('Error converting PO to bill:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

async function generateBillNumber() {
  const date = new Date();
  const year = date.getFullYear().toString().slice(-2);
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  return `BILL-${year}${month}-${Date.now().toString().slice(-4)}`;
}

function calculateBillDueDate(date, terms) {
  const d = new Date(date);
  switch (terms) {
    case 'Net 15': d.setDate(d.getDate() + 15); break;
    case 'Net 30': d.setDate(d.getDate() + 30); break;
    case 'Net 45': d.setDate(d.getDate() + 45); break;
    case 'Net 60': d.setDate(d.getDate() + 60); break;
    default: break;
  }
  return d;
}

// POST /api/purchase-orders/:id/cancel - Cancel PO
router.post('/:id/cancel', async (req, res) => {
  try {
    const po = await PurchaseOrder.findById(req.params.id);
    if (!po) return res.status(404).json({ success: false, error: 'Purchase order not found' });

    if (['CANCELLED', 'BILLED', 'CLOSED'].includes(po.status)) {
      return res.status(400).json({
        success: false,
        error: `Cannot cancel a purchase order with status: ${po.status}`
      });
    }

    po.status = 'CANCELLED';
    po.updatedBy = getCreator(req);
    await po.save();

    console.log(`✅ Purchase order cancelled: ${po.purchaseOrderNumber}`);
    res.json({ success: true, message: 'Purchase order cancelled', data: po });
  } catch (error) {
    console.error('Error cancelling PO:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/purchase-orders/:id/close - Close PO manually
router.post('/:id/close', async (req, res) => {
  try {
    const po = await PurchaseOrder.findById(req.params.id);
    if (!po) return res.status(404).json({ success: false, error: 'Purchase order not found' });

    if (['CANCELLED', 'CLOSED'].includes(po.status)) {
      return res.status(400).json({
        success: false,
        error: `Purchase order is already ${po.status}`
      });
    }

    po.status = 'CLOSED';
    po.updatedBy = getCreator(req);
    await po.save();

    console.log(`✅ Purchase order closed: ${po.purchaseOrderNumber}`);
    res.json({ success: true, message: 'Purchase order closed', data: po });
  } catch (error) {
    console.error('Error closing PO:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/purchase-orders/:id/pdf - Download PDF
router.get('/:id/pdf', async (req, res) => {
  try {
    const po = await PurchaseOrder.findById(req.params.id);
    if (!po) return res.status(404).json({ success: false, error: 'Purchase order not found' });

    if (!po.pdfPath || !fs.existsSync(po.pdfPath)) {
      const pdfInfo = await generatePurchaseOrderPDF(po);
      po.pdfPath = pdfInfo.filepath;
      po.pdfGeneratedAt = new Date();
      await po.save();
    }

    res.download(po.pdfPath, `PO-${po.purchaseOrderNumber}.pdf`);
  } catch (error) {
    console.error('Error downloading PDF:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/purchase-orders/:id - Delete (only DRAFT)
router.delete('/:id', async (req, res) => {
  try {
    const po = await PurchaseOrder.findById(req.params.id);
    if (!po) return res.status(404).json({ success: false, error: 'Purchase order not found' });

    if (po.status !== 'DRAFT') {
      return res.status(400).json({
        success: false,
        error: 'Only DRAFT purchase orders can be deleted'
      });
    }

    await po.deleteOne();
    console.log(`✅ Purchase order deleted: ${po.purchaseOrderNumber}`);
    res.json({ success: true, message: 'Purchase order deleted' });
  } catch (error) {
    console.error('Error deleting PO:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/purchase-orders/bulk-import - Bulk Import
router.post('/bulk-import', async (req, res) => {
  try {
    const { purchaseOrders } = req.body;

    if (!purchaseOrders || !Array.isArray(purchaseOrders) || purchaseOrders.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'purchaseOrders array is required'
      });
    }

    const creator = getCreator(req);
    let successCount = 0;
    let failedCount = 0;
    const errors = [];

    for (let i = 0; i < purchaseOrders.length; i++) {
      try {
        const poData = { ...purchaseOrders[i] };

        // Generate PO number if not provided
        if (!poData.purchaseOrderNumber) {
          poData.purchaseOrderNumber = await generatePONumber();
        }

        // Handle vendorId
        poData.vendorId = new mongoose.Types.ObjectId();

        // Set creator
        poData.createdBy = creator;

        // Build basic items if not provided
        if (!poData.items || poData.items.length === 0) {
          poData.items = [{
            itemDetails: 'Imported Item',
            quantity: 1,
            rate: poData.subTotal || 0,
            discount: 0,
            discountType: 'percentage',
            amount: poData.subTotal || 0
          }];
        }

        const po = new PurchaseOrder(poData);
        await po.save();
        successCount++;
      } catch (e) {
        failedCount++;
        errors.push(`Row ${i + 1}: ${e.message}`);
      }
    }

    console.log(`✅ Bulk import: ${successCount} success, ${failedCount} failed`);

    res.json({
      success: true,
      message: `Imported ${successCount} purchase orders`,
      data: {
        successCount,
        failedCount,
        totalProcessed: purchaseOrders.length,
        errors
      }
    });
  } catch (error) {
    console.error('Error bulk importing:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

module.exports = router;