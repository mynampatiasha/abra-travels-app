// ============================================================================
// PAYMENTS MADE - COMPLETE BACKEND (UPDATED)
// ============================================================================
// File: backend/routes/payment_made.js
//
// NEW in this version:
// ✅ GET /vendor-bills/:vendorId  → returns OPEN + OVERDUE + PARTIALLY_PAID
//    bills for that vendor (used by Flutter to show outstanding bills)
// ✅ POST / (create) → after saving payment, calls POST /api/bills/:id/payment
//    for each bill in billsApplied array → marks bills as paid/partially paid
// ✅ COA posting via postTransactionToCOA for payment_made record
// ✅ Balance deduction from paidFromAccount (existing, kept)
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const PDFDocument = require('pdfkit');
const nodemailer = require('nodemailer');
const fs = require('fs');
const path = require('path');
const multer = require('multer');

// ✅ COA Helper — same pattern as bill.js
const { postTransactionToCOA, ChartOfAccount } = require('./chart_of_accounts');

async function getSystemAccountId(name) {
  try {
    const acc = await ChartOfAccount.findOne({
      accountName: name,
      isSystemAccount: true,
    }).select('_id').lean();
    return acc ? acc._id : null;
  } catch (e) {
    console.error(`COA lookup error for "${name}":`, e.message);
    return null;
  }
}

// ============================================================================
// MONGOOSE SCHEMA
// ============================================================================

const paymentMadeSchema = new mongoose.Schema(
  {
    paymentNumber: { type: String, required: true, unique: true, index: true },

    vendorId: { type: mongoose.Schema.Types.ObjectId, ref: 'Vendor', required: true },
    vendorName: { type: String, required: true },
    vendorEmail: { type: String },

    paymentDate: { type: Date, required: true, default: Date.now },
    paymentMode: {
      type: String,
      enum: ['Cash', 'Cheque', 'Bank Transfer', 'UPI', 'Card', 'Online', 'NEFT', 'RTGS', 'IMPS'],
      required: true,
    },
    referenceNumber: { type: String },
    paidFromAccountId: { type: mongoose.Schema.Types.ObjectId, ref: 'Account', default: null },
    paidFromAccountName: { type: String, default: null },
    amount: { type: Number, required: true, min: 0 },
    notes: { type: String },

    paymentType: {
      type: String,
      enum: ['PAYMENT', 'ADVANCE', 'EXCESS'],
      default: 'PAYMENT',
    },

    status: {
      type: String,
      enum: ['DRAFT', 'RECORDED', 'APPLIED', 'PARTIALLY_APPLIED', 'REFUNDED', 'VOIDED'],
      default: 'RECORDED',
      index: true,
    },

    billsApplied: [
      {
        billId: mongoose.Schema.Types.ObjectId,
        billNumber: String,
        amountApplied: Number,
        appliedDate: Date,
      },
    ],

    amountApplied: { type: Number, default: 0 },
    amountUnused: { type: Number, default: 0 },

    items: [
      {
        itemDetails: { type: String, required: true },
        itemType: { type: String, enum: ['FETCHED', 'MANUAL'], default: 'MANUAL' },
        itemId: { type: mongoose.Schema.Types.ObjectId },
        account: { type: String },
        quantity: { type: Number, default: 1 },
        rate: { type: Number, default: 0 },
        discount: { type: Number, default: 0 },
        discountType: { type: String, enum: ['percentage', 'amount'], default: 'percentage' },
        amount: { type: Number, default: 0 },
      },
    ],

    subTotal: { type: Number, default: 0 },
    tdsRate: { type: Number, default: 0 },
    tdsAmount: { type: Number, default: 0 },
    tcsRate: { type: Number, default: 0 },
    tcsAmount: { type: Number, default: 0 },
    gstRate: { type: Number, default: 18 },
    cgst: { type: Number, default: 0 },
    sgst: { type: Number, default: 0 },
    igst: { type: Number, default: 0 },
    totalAmount: { type: Number, default: 0 },

    refunds: [
      {
        refundId: mongoose.Schema.Types.ObjectId,
        amount: Number,
        refundDate: Date,
        refundMode: String,
        referenceNumber: String,
        notes: String,
        refundedBy: String,
        refundedAt: Date,
      },
    ],
    totalRefunded: { type: Number, default: 0 },

    pdfPath: String,
    pdfGeneratedAt: Date,

    createdBy: { type: String, required: true },
    updatedBy: String,
  },
  { timestamps: true }
);

// Pre-save: recalculate amounts
paymentMadeSchema.pre('save', function (next) {
  if (this.items && this.items.length > 0) {
    this.subTotal = this.items.reduce((sum, item) => sum + (item.amount || 0), 0);
    this.tdsAmount = (this.subTotal * this.tdsRate) / 100;
    this.tcsAmount = (this.subTotal * this.tcsRate) / 100;
    const gstBase = this.subTotal - this.tdsAmount + this.tcsAmount;
    const gstAmount = (gstBase * this.gstRate) / 100;
    this.cgst = gstAmount / 2;
    this.sgst = gstAmount / 2;
    this.igst = 0;
    this.totalAmount = this.subTotal - this.tdsAmount + this.tcsAmount + gstAmount;
  } else {
    this.totalAmount = this.amount || 0;
    this.subTotal = this.amount || 0;
  }

  this.amountApplied = (this.billsApplied || []).reduce(
    (s, b) => s + (b.amountApplied || 0), 0
  );
  this.amountUnused = Math.max(
    0,
    this.totalAmount - this.amountApplied - (this.totalRefunded || 0)
  );

  if (this.amountApplied >= this.totalAmount && this.totalAmount > 0)
    this.status = 'APPLIED';
  else if (this.amountApplied > 0)
    this.status = 'PARTIALLY_APPLIED';
  else if (!['DRAFT', 'VOIDED', 'REFUNDED'].includes(this.status))
    this.status = 'RECORDED';

  next();
});

paymentMadeSchema.index({ vendorId: 1, paymentDate: -1 });
paymentMadeSchema.index({ status: 1 });
paymentMadeSchema.index({ createdAt: -1 });

const PaymentMade = mongoose.model('PaymentMade', paymentMadeSchema);

// ============================================================================
// HELPERS
// ============================================================================

async function generatePaymentNumber() {
  const date = new Date();
  const yr = date.getFullYear().toString().slice(-2);
  const mo = (date.getMonth() + 1).toString().padStart(2, '0');
  const last = await PaymentMade.findOne({
    paymentNumber: new RegExp(`^PMT-${yr}${mo}`),
  }).sort({ paymentNumber: -1 });
  let seq = 1;
  if (last) seq = parseInt(last.paymentNumber.split('-')[2]) + 1;
  return `PMT-${yr}${mo}-${seq.toString().padStart(4, '0')}`;
}

function calcItemAmount(item) {
  let amt = (item.quantity || 1) * (item.rate || 0);
  if (item.discount > 0) {
    if (item.discountType === 'percentage') amt -= amt * (item.discount / 100);
    else amt -= item.discount;
  }
  return Math.max(0, Math.round(amt * 100) / 100);
}

// ============================================================================
// PDF GENERATION (unchanged)
// ============================================================================

function findLogoPath() {
  const candidates = [
    path.join(__dirname, '..', 'assets', 'abra.jpeg'),
    path.join(__dirname, '..', 'assets', 'abra.jpg'),
    path.join(__dirname, '..', 'assets', 'abra.png'),
    path.join(process.cwd(), 'assets', 'abra.jpeg'),
    path.join(process.cwd(), 'backend', 'assets', 'abra.jpeg'),
  ];
  for (const p of candidates) {
    try { if (fs.existsSync(p) && fs.statSync(p).size > 0) return p; } catch (_) {}
  }
  return null;
}

async function generatePaymentPDF(payment) {
  return new Promise((resolve, reject) => {
    try {
      const uploadsDir = path.join(__dirname, '..', 'uploads', 'payments');
      if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });
      const filename = `payment-${payment.paymentNumber}.pdf`;
      const filepath = path.join(uploadsDir, filename);
      const doc = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
      const stream = fs.createWriteStream(filepath);
      doc.pipe(stream);

      const logoPath = findLogoPath();
      let logoLoaded = false;
      if (logoPath) {
        try {
          doc.image(logoPath, 40, 35, { width: 120, height: 60, fit: [120, 60] });
          logoLoaded = true;
        } catch (_) {}
      }
      if (!logoLoaded) {
        doc.fontSize(22).fillColor('#0066CC').font('Helvetica-Bold').text('ABRA Travels', 40, 40);
      }

      const cy = logoLoaded ? 105 : 85;
      doc.fontSize(8).fillColor('#555555').font('Helvetica')
        .text('Bangalore, Karnataka, India', 40, cy)
        .text('GST: 29AABCT1332L1ZM', 40, cy + 11)
        .text('Contact: +91 88672 88076', 40, cy + 22)
        .text('Email: info@abratravels.com', 40, cy + 33);

      doc.fontSize(32).fillColor('#2C3E50').font('Helvetica-Bold').text('PAYMENT', 350, 40, { align: 'right' });
      doc.fontSize(10).fillColor('#27AE60').font('Helvetica-Bold').text('MADE', 350, 80, { align: 'right' });

      const boxY = 155;
      doc.rect(40, boxY, 515, 60).fillAndStroke('#F8F9FA', '#DDDDDD');
      doc.rect(40, boxY, 515, 2).fillAndStroke('#0066CC', '#0066CC');
      doc.fontSize(8).fillColor('#2C3E50').font('Helvetica-Bold');
      ['Payment Number:', 'Payment Date:', 'Payment Mode:'].forEach((lbl, i) =>
        doc.text(lbl, 50, boxY + 12 + i * 15));
      doc.fillColor('#000000').font('Helvetica');
      doc.text(payment.paymentNumber, 160, boxY + 12);
      doc.text(new Date(payment.paymentDate).toLocaleDateString('en-IN', {
        day: '2-digit', month: 'short', year: 'numeric'
      }), 160, boxY + 27);
      doc.text(payment.paymentMode, 160, boxY + 42);
      doc.fillColor('#2C3E50').font('Helvetica-Bold');
      ['Reference #:', 'Status:', 'Type:'].forEach((lbl, i) =>
        doc.text(lbl, 305, boxY + 12 + i * 15));
      doc.fillColor('#000000').font('Helvetica');
      doc.text(payment.referenceNumber || 'N/A', 395, boxY + 12);
      doc.text(payment.status, 395, boxY + 27);
      doc.text(payment.paymentType, 395, boxY + 42);

      const vY = boxY + 72;
      doc.fontSize(11).fillColor('#0066CC').font('Helvetica-Bold').text('PAID TO:', 40, vY);
      doc.fontSize(10).fillColor('#000000').font('Helvetica-Bold').text(payment.vendorName, 40, vY + 18);
      if (payment.vendorEmail) {
        doc.fontSize(8).fillColor('#555555').font('Helvetica')
          .text(`Email: ${payment.vendorEmail}`, 40, vY + 32);
      }

      // Bills applied section
      if (payment.billsApplied && payment.billsApplied.length > 0) {
        const billsY = vY + 55;
        doc.fontSize(11).fillColor('#0066CC').font('Helvetica-Bold').text('BILLS PAID:', 40, billsY);
        let bY = billsY + 18;
        doc.rect(40, bY, 515, 20).fillAndStroke('#8E44AD', '#8E44AD');
        doc.fontSize(8).fillColor('#FFFFFF').font('Helvetica-Bold');
        doc.text('Bill #', 50, bY + 6);
        doc.text('Amount Applied', 400, bY + 6, { width: 145, align: 'right' });
        bY += 20;
        payment.billsApplied.forEach((b, idx) => {
          const rc = idx % 2 === 0 ? '#FFFFFF' : '#F8F9FA';
          doc.rect(40, bY, 515, 20).fillAndStroke(rc, '#E8E8E8');
          doc.fontSize(8).fillColor('#000000').font('Helvetica');
          doc.text(b.billNumber || '-', 50, bY + 6);
          doc.text(`₹${(b.amountApplied || 0).toFixed(2)}`, 400, bY + 6, { width: 145, align: 'right' });
          bY += 20;
        });
      }

      const tableTop = 370;
      doc.rect(40, tableTop, 515, 22).fillAndStroke('#2C3E50', '#2C3E50');
      doc.fontSize(8).fillColor('#FFFFFF').font('Helvetica-Bold');
      doc.text('ITEM DETAILS', 50, tableTop + 8);
      doc.text('QTY', 330, tableTop + 8, { width: 40, align: 'center' });
      doc.text('RATE', 380, tableTop + 8, { width: 60, align: 'right' });
      doc.text('AMOUNT', 455, tableTop + 8, { width: 90, align: 'right' });

      let yPos = tableTop + 22;
      (payment.items || []).forEach((item, idx) => {
        const rc = idx % 2 === 0 ? '#FFFFFF' : '#F8F9FA';
        doc.rect(40, yPos, 515, 26).fillAndStroke(rc, '#E8E8E8');
        doc.fontSize(8).fillColor('#000000').font('Helvetica');
        doc.text(item.itemDetails || 'N/A', 50, yPos + 9, { width: 260, ellipsis: true });
        doc.text((item.quantity || 0).toString(), 330, yPos + 9, { width: 40, align: 'center' });
        doc.text(`₹${(item.rate || 0).toFixed(2)}`, 380, yPos + 9, { width: 60, align: 'right' });
        doc.text(`₹${(item.amount || 0).toFixed(2)}`, 455, yPos + 9, { width: 90, align: 'right' });
        yPos += 26;
      });

      const stY = yPos + 20;
      let curY = stY;
      const lX = 370, vX = 485;
      doc.fontSize(8).fillColor('#2C3E50').font('Helvetica-Bold').text('Subtotal:', lX, curY);
      doc.fillColor('#000000').font('Helvetica')
        .text(`₹ ${(payment.subTotal || 0).toFixed(2)}`, vX, curY, { width: 70, align: 'right' });
      curY += 14;
      if ((payment.cgst || 0) > 0) {
        doc.fillColor('#2C3E50').font('Helvetica-Bold').text('CGST:', lX, curY);
        doc.fillColor('#000000').font('Helvetica')
          .text(`₹ ${payment.cgst.toFixed(2)}`, vX, curY, { width: 70, align: 'right' });
        curY += 14;
      }
      if ((payment.sgst || 0) > 0) {
        doc.fillColor('#2C3E50').font('Helvetica-Bold').text('SGST:', lX, curY);
        doc.fillColor('#000000').font('Helvetica')
          .text(`₹ ${payment.sgst.toFixed(2)}`, vX, curY, { width: 70, align: 'right' });
        curY += 14;
      }
      doc.moveTo(370, curY + 3).lineTo(555, curY + 3).strokeColor('#2C3E50').lineWidth(1).stroke();
      curY += 10;
      doc.rect(370, curY, 185, 22).strokeColor('#2C3E50').lineWidth(2).stroke();
      doc.fontSize(10).fillColor('#2C3E50').font('Helvetica-Bold').text('Total Payment:', lX + 5, curY + 6);
      doc.fontSize(12).fillColor('#27AE60').font('Helvetica-Bold')
        .text(`₹ ${(payment.totalAmount || 0).toFixed(2)}`, vX, curY + 5, { width: 65, align: 'right' });

      const footerY = 730;
      doc.moveTo(40, footerY).lineTo(555, footerY).lineWidth(1.5).strokeColor('#0066CC').stroke();
      doc.fontSize(8).fillColor('#2C3E50').font('Helvetica-Bold')
        .text('Thank you — ABRA Travels', 40, footerY + 8, { align: 'center', width: 515 });
      doc.fontSize(6).fillColor('#888888').font('Helvetica')
        .text('ABRA Travels | YOUR JOURNEY, OUR COMMITMENT', 40, footerY + 20, { align: 'center', width: 515 });
      doc.fontSize(6).fillColor('#AAAAAA')
        .text('www.abratravels.com | info@abratravels.com | +91 88672 88076', 40, footerY + 30, { align: 'center', width: 515 });

      doc.end();
      stream.on('finish', () => resolve({ filename, filepath, relativePath: `/uploads/payments/${filename}` }));
      stream.on('error', reject);
    } catch (err) { reject(err); }
  });
}

// ============================================================================
// EMAIL (unchanged)
// ============================================================================

const emailTransporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'smtp.gmail.com',
  port: parseInt(process.env.SMTP_PORT || '587'),
  secure: false,
  auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASSWORD },
});

async function sendPaymentEmail(payment) {
  if (!payment.vendorEmail) return;
  const html = `<!DOCTYPE html><html><body style="font-family:Arial,sans-serif;background:#f4f4f4;padding:20px;">
  <table width="600" style="background:#fff;border-radius:10px;overflow:hidden;margin:0 auto;">
    <tr><td style="background:linear-gradient(135deg,#27AE60,#229954);padding:30px;color:#fff;text-align:center;">
      <h1 style="margin:0;">✅ Payment Confirmation</h1><p style="margin:8px 0 0;">${payment.paymentNumber}</p>
    </td></tr>
    <tr><td style="padding:30px;">
      <p>Dear <strong>${payment.vendorName}</strong>,</p>
      <p>Payment recorded successfully:</p>
      <table width="100%" style="border-collapse:collapse;margin:20px 0;">
        <tr style="background:#f8f9fa;"><td style="padding:10px;font-weight:bold;">Payment #</td><td style="padding:10px;">${payment.paymentNumber}</td></tr>
        <tr><td style="padding:10px;font-weight:bold;">Date</td><td style="padding:10px;">${new Date(payment.paymentDate).toLocaleDateString('en-IN')}</td></tr>
        <tr style="background:#f8f9fa;"><td style="padding:10px;font-weight:bold;">Amount</td><td style="padding:10px;color:#27AE60;font-weight:bold;">₹${(payment.totalAmount || payment.amount || 0).toFixed(2)}</td></tr>
        <tr><td style="padding:10px;font-weight:bold;">Mode</td><td style="padding:10px;">${payment.paymentMode}</td></tr>
        ${payment.referenceNumber ? `<tr style="background:#f8f9fa;"><td style="padding:10px;font-weight:bold;">Reference</td><td style="padding:10px;">${payment.referenceNumber}</td></tr>` : ''}
      </table>
    </td></tr>
    <tr><td style="background:#2C3E50;color:#95A5A6;padding:20px;text-align:center;font-size:12px;">ABRA Travels | info@abratravels.com | +91 88672 88076</td></tr>
  </table></body></html>`;
  return emailTransporter.sendMail({
    from: `"ABRA Travels" <${process.env.SMTP_USER}>`,
    to: payment.vendorEmail,
    subject: `✅ Payment Confirmation - ${payment.paymentNumber}`,
    html,
  });
}

// ============================================================================
// MULTER FOR IMPORT
// ============================================================================

const importUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (/\.(xlsx|xls|csv)$/i.test(file.originalname)) cb(null, true);
    else cb(new Error('Only Excel/CSV files allowed'));
  },
});

// ============================================================================
// ROUTES
// ============================================================================

// ── NEW: GET /vendor-bills/:vendorId ─────────────────────────────────────────
// Returns all OPEN + OVERDUE + PARTIALLY_PAID bills for a vendor
// Used by Flutter Payment Made screen to show outstanding bills
router.get('/vendor-bills/:vendorId', async (req, res) => {
  try {
    const { vendorId } = req.params;

    if (!mongoose.Types.ObjectId.isValid(vendorId)) {
      return res.status(400).json({ success: false, error: 'Invalid vendor ID' });
    }

    // Dynamically get the Bill model (registered in bill.js)
    const Bill = mongoose.models.Bill ||
      mongoose.model('Bill', new mongoose.Schema({}, { strict: false }));

    const bills = await Bill.find({
      vendorId: new mongoose.Types.ObjectId(vendorId),
      status: { $in: ['OPEN', 'OVERDUE', 'PARTIALLY_PAID'] },
    })
      .select('billNumber billDate dueDate totalAmount amountDue amountPaid status')
      .sort({ billDate: 1 }) // oldest first for auto-allocation
      .lean();

    res.json({
      success: true,
      count: bills.length,
      data: bills,
    });
  } catch (err) {
    console.error('Error fetching vendor bills:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET all
router.get('/', async (req, res) => {
  try {
    const {
      status, vendorId, fromDate, toDate, paymentMode,
      paymentType, page = 1, limit = 20, search,
    } = req.query;
    const query = {};
    if (status) query.status = status;
    if (vendorId) query.vendorId = vendorId;
    if (paymentMode) query.paymentMode = paymentMode;
    if (paymentType) query.paymentType = paymentType;
    if (fromDate || toDate) {
      query.paymentDate = {};
      if (fromDate) query.paymentDate.$gte = new Date(fromDate);
      if (toDate) query.paymentDate.$lte = new Date(toDate);
    }
    if (search) {
      query.$or = [
        { paymentNumber: new RegExp(search, 'i') },
        { vendorName: new RegExp(search, 'i') },
        { referenceNumber: new RegExp(search, 'i') },
      ];
    }
    const skip = (parseInt(page) - 1) * parseInt(limit);
    const [payments, total] = await Promise.all([
      PaymentMade.find(query).sort({ createdAt: -1 }).skip(skip).limit(parseInt(limit)).select('-__v'),
      PaymentMade.countDocuments(query),
    ]);
    res.json({
      success: true,
      data: payments,
      pagination: {
        total, page: parseInt(page), limit: parseInt(limit),
        pages: Math.ceil(total / parseInt(limit)),
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET stats
router.get('/stats', async (req, res) => {
  try {
    const stats = await PaymentMade.aggregate([
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 },
          totalAmount: { $sum: '$totalAmount' },
          totalApplied: { $sum: '$amountApplied' },
          totalUnused: { $sum: '$amountUnused' },
        },
      },
    ]);
    const overall = { totalPayments: 0, totalAmount: 0, totalApplied: 0, totalUnused: 0, byStatus: {} };
    stats.forEach((s) => {
      overall.totalPayments += s.count;
      overall.totalAmount += s.totalAmount;
      overall.totalApplied += s.totalApplied;
      overall.totalUnused += s.totalUnused;
      overall.byStatus[s._id] = { count: s.count, amount: s.totalAmount };
    });
    res.json({ success: true, data: overall });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET single
router.get('/:id', async (req, res) => {
  try {
    const payment = await PaymentMade.findById(req.params.id);
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    res.json({ success: true, data: payment });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── POST / — Create payment ───────────────────────────────────────────────────
router.post('/', async (req, res) => {
  try {
    const data = { ...req.body };
    if (!data.paymentNumber) data.paymentNumber = await generatePaymentNumber();
    if (!data.vendorId) return res.status(400).json({ success: false, error: 'Vendor is required' });

    if (typeof data.vendorId === 'string' && mongoose.Types.ObjectId.isValid(data.vendorId)) {
      data.vendorId = new mongoose.Types.ObjectId(data.vendorId);
    }
    if (data.items) {
      data.items = data.items.map((item) => ({ ...item, amount: calcItemAmount(item) }));
    }
    data.createdBy = req.user?.email || req.user?.uid || 'system';

    const payment = new PaymentMade(data);
    await payment.save();

    // ── STEP 1: Deduct balance from paidFromAccount ───────────────────────────
    if (data.paidFromAccountId) {
      try {
        const PaymentAccount = mongoose.models.PaymentAccount ||
          mongoose.model('PaymentAccount', new mongoose.Schema(
            { currentBalance: { type: Number, default: 0 } },
            { strict: false }
          ));
        const deductAmount = payment.totalAmount || payment.amount || 0;
        const updatedAccount = await PaymentAccount.findByIdAndUpdate(
          data.paidFromAccountId,
          { $inc: { currentBalance: -deductAmount }, $set: { updatedAt: new Date() } },
          { new: true }
        );
        if (updatedAccount) {
          console.log(`✅ Balance deducted from "${updatedAccount.accountName}": -₹${deductAmount} → ₹${updatedAccount.currentBalance}`);
        } else {
          console.warn(`⚠️ Account ${data.paidFromAccountId} not found — balance NOT updated`);
        }
      } catch (balErr) {
        console.error(`⚠️ Balance deduction error:`, balErr.message);
      }
    }

    // ── STEP 2: Apply payment to each bill via bill.js payment route ──────────
    // This marks each bill as PAID / PARTIALLY_PAID and posts bill-level COA
    const billsApplied = data.billsApplied || [];
    for (const ba of billsApplied) {
      if (!ba.billId || !ba.amountApplied || ba.amountApplied <= 0) continue;
      try {
        const Bill = mongoose.models.Bill;
        if (!Bill) { console.warn('Bill model not loaded — skipping bill payment update'); continue; }

        const bill = await Bill.findById(ba.billId);
        if (!bill) { console.warn(`Bill ${ba.billId} not found`); continue; }

        const billPayment = {
          paymentId: payment._id,
          amount: ba.amountApplied,
          paymentDate: payment.paymentDate,
          paymentMode: payment.paymentMode,
          referenceNumber: payment.paymentNumber,
          notes: `Payment Made: ${payment.paymentNumber}`,
          recordedBy: data.createdBy,
          recordedAt: new Date(),
        };

        bill.payments = bill.payments || [];
        bill.payments.push(billPayment);
        bill.amountPaid = (bill.amountPaid || 0) + ba.amountApplied;
        await bill.save();

        // ── COA for bill payment: Debit AP + Credit Bank/Cash ───────────────
        try {
          const [apId, bankId] = await Promise.all([
            getSystemAccountId('Accounts Payable'),
            getSystemAccountId('Undeposited Funds'),
          ]);
          const txnDate = new Date(payment.paymentDate);
          if (apId) {
            await postTransactionToCOA({
              accountId: apId,
              date: txnDate,
              description: `Payment ${payment.paymentNumber} - ${bill.billNumber}`,
              referenceType: 'Payment',
              referenceId: payment._id,
              referenceNumber: payment.paymentNumber,
              debit: ba.amountApplied,
              credit: 0,
            });
          }
          if (bankId) {
            await postTransactionToCOA({
              accountId: bankId,
              date: txnDate,
              description: `Payment ${payment.paymentNumber} - ${bill.billNumber}`,
              referenceType: 'Payment',
              referenceId: payment._id,
              referenceNumber: payment.paymentNumber,
              debit: 0,
              credit: ba.amountApplied,
            });
          }
          console.log(`✅ COA posted for bill payment: ${bill.billNumber} ← ₹${ba.amountApplied}`);
        } catch (coaErr) {
          console.error(`⚠️ COA post error for bill ${ba.billId}:`, coaErr.message);
        }

        console.log(`✅ Bill ${bill.billNumber} updated: paid ₹${ba.amountApplied}, status: ${bill.status}`);
      } catch (billErr) {
        console.error(`⚠️ Bill payment update error for ${ba.billId}:`, billErr.message);
      }
    }

    // ── STEP 3: COA for payment_made record (items-based portion) ─────────────
    // Only posts if there are line items (advance / extra payment)
    if (payment.items && payment.items.length > 0 && payment.subTotal > 0) {
      try {
        const [expenseId, apId] = await Promise.all([
          getSystemAccountId('Cost of Goods Sold'),
          getSystemAccountId('Accounts Payable'),
        ]);
        const txnDate = new Date(payment.paymentDate);
        if (expenseId) {
          await postTransactionToCOA({
            accountId: expenseId,
            date: txnDate,
            description: `Payment Made ${payment.paymentNumber} - ${payment.vendorName} (items)`,
            referenceType: 'PaymentMade',
            referenceId: payment._id,
            referenceNumber: payment.paymentNumber,
            debit: payment.subTotal,
            credit: 0,
          });
        }
        if (apId) {
          await postTransactionToCOA({
            accountId: apId,
            date: txnDate,
            description: `Payment Made ${payment.paymentNumber} - ${payment.vendorName} (items)`,
            referenceType: 'PaymentMade',
            referenceId: payment._id,
            referenceNumber: payment.paymentNumber,
            debit: 0,
            credit: payment.subTotal,
          });
        }
        console.log(`✅ COA posted for payment_made items: ${payment.paymentNumber}`);
      } catch (coaErr) {
        console.error(`⚠️ COA post error (payment items):`, coaErr.message);
      }
    }

    try { await sendPaymentEmail(payment); } catch (_) {}

    console.log(`✅ Payment Made created: ${payment.paymentNumber}`);
    res.status(201).json({ success: true, message: 'Payment recorded', data: payment });
  } catch (err) {
    console.error('Error creating payment:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// PUT update
router.put('/:id', async (req, res) => {
  try {
    const payment = await PaymentMade.findById(req.params.id);
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    if (payment.status === 'APPLIED')
      return res.status(400).json({ success: false, error: 'Cannot edit fully applied payments' });
    const updates = { ...req.body };
    if (updates.items) updates.items = updates.items.map((item) => ({ ...item, amount: calcItemAmount(item) }));
    updates.updatedBy = req.user?.email || 'system';
    Object.assign(payment, updates);
    await payment.save();
    res.json({ success: true, message: 'Payment updated', data: payment });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST apply to bills
router.post('/:id/apply', async (req, res) => {
  try {
    const payment = await PaymentMade.findById(req.params.id);
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    const { bills } = req.body;
    if (!Array.isArray(bills)) return res.status(400).json({ success: false, error: 'Bills array required' });
    for (const b of bills) {
      payment.billsApplied.push({
        billId: b.billId, billNumber: b.billNumber,
        amountApplied: b.amountApplied, appliedDate: new Date(),
      });
    }
    await payment.save();
    res.json({ success: true, message: 'Payment applied to bills', data: payment });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST refund
router.post('/:id/refund', async (req, res) => {
  try {
    const payment = await PaymentMade.findById(req.params.id);
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    const { amount, refundMode, referenceNumber, notes } = req.body;
    if (!amount || amount <= 0) return res.status(400).json({ success: false, error: 'Invalid refund amount' });
    if (amount > (payment.amountUnused || 0))
      return res.status(400).json({ success: false, error: 'Refund exceeds unused amount' });
    payment.refunds.push({
      refundId: new mongoose.Types.ObjectId(), amount, refundDate: new Date(),
      refundMode, referenceNumber, notes,
      refundedBy: req.user?.email || 'system', refundedAt: new Date(),
    });
    payment.totalRefunded = (payment.totalRefunded || 0) + amount;
    if (payment.totalRefunded >= payment.totalAmount) payment.status = 'REFUNDED';
    await payment.save();
    res.json({ success: true, message: 'Refund recorded', data: payment });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// DELETE
router.delete('/:id', async (req, res) => {
  try {
    const payment = await PaymentMade.findById(req.params.id);
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    if (!['DRAFT', 'RECORDED'].includes(payment.status)) {
      return res.status(400).json({ success: false, error: 'Only Draft or Recorded payments can be deleted' });
    }
    await payment.deleteOne();

    // Restore balance on delete
    if (payment.paidFromAccountId) {
      try {
        const PaymentAccount = mongoose.models.PaymentAccount ||
          mongoose.model('PaymentAccount', new mongoose.Schema(
            { currentBalance: { type: Number, default: 0 } }, { strict: false }
          ));
        const restoreAmount = payment.totalAmount || payment.amount || 0;
        const restoredAccount = await PaymentAccount.findByIdAndUpdate(
          payment.paidFromAccountId,
          { $inc: { currentBalance: restoreAmount }, $set: { updatedAt: new Date() } },
          { new: true }
        );
        if (restoredAccount) {
          console.log(`✅ Balance restored: +₹${restoreAmount} → "${restoredAccount.accountName}" ₹${restoredAccount.currentBalance}`);
        }
      } catch (balErr) {
        console.error(`⚠️ Balance restore error:`, balErr.message);
      }
    }

    res.json({ success: true, message: 'Payment deleted' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET PDF
router.get('/:id/pdf', async (req, res) => {
  try {
    const payment = await PaymentMade.findById(req.params.id);
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    if (!payment.pdfPath || !fs.existsSync(payment.pdfPath)) {
      const info = await generatePaymentPDF(payment);
      payment.pdfPath = info.filepath;
      payment.pdfGeneratedAt = new Date();
      await payment.save();
    }
    res.download(payment.pdfPath, `Payment-${payment.paymentNumber}.pdf`);
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET download URL
router.get('/:id/download-url', async (req, res) => {
  try {
    const payment = await PaymentMade.findById(req.params.id);
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    if (!payment.pdfPath || !fs.existsSync(payment.pdfPath)) {
      const info = await generatePaymentPDF(payment);
      payment.pdfPath = info.filepath;
      payment.pdfGeneratedAt = new Date();
      await payment.save();
    }
    const baseUrl = process.env.BASE_URL || `${req.protocol}://${req.get('host')}`;
    res.json({
      success: true,
      downloadUrl: `${baseUrl}/uploads/payments/${path.basename(payment.pdfPath)}`,
      filename: `Payment-${payment.paymentNumber}.pdf`,
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST bulk import
router.post('/bulk-import', importUpload.single('file'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ success: false, error: 'No file uploaded' });
    const paymentsData = JSON.parse(req.body.paymentsData || '[]');
    if (!paymentsData.length) return res.status(400).json({ success: false, error: 'No payment data' });
    const results = { totalProcessed: paymentsData.length, successCount: 0, failedCount: 0, errors: [] };
    for (const [i, pd] of paymentsData.entries()) {
      try {
        pd.paymentNumber = await generatePaymentNumber();
        pd.createdBy = req.user?.email || 'import';
        if (!pd.vendorId) pd.vendorId = new mongoose.Types.ObjectId();
        const p = new PaymentMade(pd);
        await p.save();
        results.successCount++;
      } catch (e) {
        results.failedCount++;
        results.errors.push(`Row ${i + 2}: ${e.message}`);
      }
    }
    res.json({ success: true, message: 'Import completed', data: results });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;