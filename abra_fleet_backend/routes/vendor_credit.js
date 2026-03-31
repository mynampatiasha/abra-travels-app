// ============================================================================
// VENDOR CREDIT BACKEND
// ============================================================================
// File: routes/vendor_credit.js
// Full Express routes + Mongoose model + controller logic
// Register in app.js: app.use('/api/vendor-credits', require('./routes/vendor_credit'))
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');

// ============================================================================
// MONGOOSE SCHEMA
// ============================================================================

const VendorCreditItemSchema = new mongoose.Schema({
  itemDetails: { type: String, required: true },
  account: { type: String, default: '' },
  quantity: { type: Number, required: true, min: 0 },
  rate: { type: Number, required: true, min: 0 },
  discount: { type: Number, default: 0 },
  discountType: { type: String, enum: ['percentage', 'amount'], default: 'percentage' },
  amount: { type: Number, required: true, min: 0 },
}, { _id: false });

const CreditApplicationSchema = new mongoose.Schema({
  billId: { type: String, default: '' },
  billNumber: { type: String, required: true },
  amount: { type: Number, required: true, min: 0.01 },
  appliedDate: { type: Date, default: Date.now },
});

const CreditRefundSchema = new mongoose.Schema({
  amount: { type: Number, required: true, min: 0.01 },
  refundDate: { type: Date, default: Date.now },
  paymentMode: {
    type: String,
    enum: ['Cash', 'Cheque', 'Bank Transfer', 'UPI', 'NEFT', 'RTGS', 'IMPS', 'Online'],
    default: 'Bank Transfer'
  },
  referenceNumber: { type: String, default: '' },
  notes: { type: String, default: '' },
});

const VendorCreditSchema = new mongoose.Schema({
  creditNumber: { type: String, unique: true, sparse: true },
  vendorId: { type: String, required: true },
  vendorName: { type: String, required: true },
  vendorEmail: { type: String, default: '' },
  vendorGSTIN: { type: String, default: '' },
  creditDate: { type: Date, required: true, default: Date.now },
  billId: { type: String, default: null },
  billNumber: { type: String, default: null },
  reason: { type: String, required: true },
  status: {
    type: String,
    enum: ['OPEN', 'PARTIALLY_APPLIED', 'CLOSED', 'VOID'],
    default: 'OPEN'
  },
  items: [VendorCreditItemSchema],
  subTotal: { type: Number, default: 0 },
  gstRate: { type: Number, default: 0 },
  cgst: { type: Number, default: 0 },
  sgst: { type: Number, default: 0 },
  tdsAmount: { type: Number, default: 0 },
  tcsAmount: { type: Number, default: 0 },
  totalAmount: { type: Number, required: true, min: 0 },
  appliedAmount: { type: Number, default: 0 },
  balanceAmount: { type: Number, default: 0 },
  applications: [CreditApplicationSchema],
  refunds: [CreditRefundSchema],
  notes: { type: String, default: '' },
  isImported: { type: Boolean, default: false },
}, {
  timestamps: true,
  toJSON: { virtuals: true },
  toObject: { virtuals: true }
});

// Auto-generate credit number
VendorCreditSchema.pre('save', async function (next) {
  if (!this.creditNumber) {
    const date = new Date();
    const year = date.getFullYear().toString().slice(-2);
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const count = await mongoose.model('VendorCredit').countDocuments();
    this.creditNumber = `VC-${year}${month}-${String(count + 1).padStart(4, '0')}`;
  }
  next();
});

const VendorCredit = mongoose.models.VendorCredit ||
  mongoose.model('VendorCredit', VendorCreditSchema);

// ============================================================================
// HELPER
// ============================================================================

function successResponse(res, data, message = 'Success', statusCode = 200) {
  return res.status(statusCode).json({ success: true, message, data });
}

function errorResponse(res, message = 'Error', statusCode = 500, error = null) {
  console.error(`[VendorCredit] ${message}`, error || '');
  return res.status(statusCode).json({ success: false, message, error: error?.message });
}

// ============================================================================
// ROUTES
// ============================================================================

// GET /api/vendor-credits/stats
router.get('/stats', async (req, res) => {
  try {
    const [totalCredits, statusBreakdown, amounts] = await Promise.all([
      VendorCredit.countDocuments(),
      VendorCredit.aggregate([
        { $group: { _id: '$status', count: { $sum: 1 } } }
      ]),
      VendorCredit.aggregate([
        {
          $group: {
            _id: null,
            totalCreditAmount: { $sum: '$totalAmount' },
            totalApplied: { $sum: '$appliedAmount' },
            totalBalance: { $sum: '$balanceAmount' },
          }
        }
      ])
    ]);

    const statusMap = {};
    statusBreakdown.forEach(s => { statusMap[s._id] = s.count; });
    const amts = amounts[0] || {};

    return successResponse(res, {
      totalCredits,
      totalCreditAmount: amts.totalCreditAmount || 0,
      totalApplied: amts.totalApplied || 0,
      totalBalance: amts.totalBalance || 0,
      openCredits: statusMap['OPEN'] || 0,
      partiallyApplied: statusMap['PARTIALLY_APPLIED'] || 0,
      closedCredits: statusMap['CLOSED'] || 0,
    }, 'Stats loaded');
  } catch (err) {
    return errorResponse(res, 'Failed to load stats', 500, err);
  }
});

// GET /api/vendor-credits
router.get('/', async (req, res) => {
  try {
    const {
      page = 1, limit = 20, status, search,
      fromDate, toDate, vendorId
    } = req.query;

    const pageNum = Math.max(1, parseInt(page));
    const limitNum = Math.min(100, Math.max(1, parseInt(limit)));
    const skip = (pageNum - 1) * limitNum;

    const filter = {};

    if (status) filter.status = status;
    if (vendorId) filter.vendorId = vendorId;

    if (fromDate || toDate) {
      filter.creditDate = {};
      if (fromDate) filter.creditDate.$gte = new Date(fromDate);
      if (toDate) {
        const to = new Date(toDate);
        to.setHours(23, 59, 59, 999);
        filter.creditDate.$lte = to;
      }
    }

    if (search) {
      const regex = new RegExp(search, 'i');
      filter.$or = [
        { creditNumber: regex },
        { vendorName: regex },
        { vendorEmail: regex },
        { billNumber: regex },
        { reason: regex },
      ];
    }

    const [credits, total] = await Promise.all([
      VendorCredit.find(filter)
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limitNum)
        .lean(),
      VendorCredit.countDocuments(filter),
    ]);

    return successResponse(res, {
      credits,
      pagination: {
        total,
        pages: Math.ceil(total / limitNum),
        page: pageNum,
        limit: limitNum,
      },
    });
  } catch (err) {
    return errorResponse(res, 'Failed to fetch vendor credits', 500, err);
  }
});

// GET /api/vendor-credits/:id
router.get('/:id', async (req, res) => {
  try {
    const credit = await VendorCredit.findById(req.params.id).lean();
    if (!credit) return errorResponse(res, 'Vendor credit not found', 404);
    return successResponse(res, credit);
  } catch (err) {
    return errorResponse(res, 'Failed to fetch vendor credit', 500, err);
  }
});

// POST /api/vendor-credits
router.post('/', async (req, res) => {
  try {
    const body = req.body;

    if (!body.vendorId) return errorResponse(res, 'Vendor ID is required', 400);
    if (!body.vendorName) return errorResponse(res, 'Vendor Name is required', 400);
    if (!body.reason) return errorResponse(res, 'Reason is required', 400);
    if (!body.items || body.items.length === 0) return errorResponse(res, 'At least one item is required', 400);

    // Validate items
    for (const item of body.items) {
      if (!item.itemDetails) return errorResponse(res, 'Item details required', 400);
      if (!item.quantity || item.quantity <= 0) return errorResponse(res, 'Item quantity must be > 0', 400);
      if (!item.rate || item.rate <= 0) return errorResponse(res, 'Item rate must be > 0', 400);
    }

    const credit = new VendorCredit({
      ...body,
      balanceAmount: body.totalAmount || 0,
      appliedAmount: 0,
      applications: [],
      refunds: [],
    });

    await credit.save();
    return successResponse(res, credit, 'Vendor credit created', 201);
  } catch (err) {
    if (err.code === 11000) {
      return errorResponse(res, 'Credit number already exists', 400, err);
    }
    return errorResponse(res, 'Failed to create vendor credit', 500, err);
  }
});

// PUT /api/vendor-credits/:id
router.put('/:id', async (req, res) => {
  try {
    const credit = await VendorCredit.findById(req.params.id);
    if (!credit) return errorResponse(res, 'Vendor credit not found', 404);

    if (credit.status === 'CLOSED' || credit.status === 'VOID') {
      return errorResponse(res, 'Cannot edit a closed or voided credit', 400);
    }

    const forbidden = ['creditNumber', 'applications', 'refunds', 'appliedAmount', '_id'];
    const updates = Object.fromEntries(
      Object.entries(req.body).filter(([k]) => !forbidden.includes(k))
    );

    Object.assign(credit, updates);

    // Recalculate balance
    const applied = credit.applications.reduce((s, a) => s + a.amount, 0);
    const refunded = credit.refunds.reduce((s, r) => s + r.amount, 0);
    credit.appliedAmount = applied + refunded;
    credit.balanceAmount = credit.totalAmount - credit.appliedAmount;

    await credit.save();
    return successResponse(res, credit, 'Vendor credit updated');
  } catch (err) {
    return errorResponse(res, 'Failed to update vendor credit', 500, err);
  }
});

// PUT /api/vendor-credits/:id/void
router.put('/:id/void', async (req, res) => {
  try {
    const credit = await VendorCredit.findById(req.params.id);
    if (!credit) return errorResponse(res, 'Vendor credit not found', 404);
    if (credit.status === 'CLOSED') return errorResponse(res, 'Cannot void a closed credit', 400);

    credit.status = 'VOID';
    await credit.save();
    return successResponse(res, credit, 'Vendor credit voided');
  } catch (err) {
    return errorResponse(res, 'Failed to void vendor credit', 500, err);
  }
});

// POST /api/vendor-credits/:id/apply
router.post('/:id/apply', async (req, res) => {
  try {
    const credit = await VendorCredit.findById(req.params.id);
    if (!credit) return errorResponse(res, 'Vendor credit not found', 404);

    if (credit.status === 'VOID') return errorResponse(res, 'Cannot apply a voided credit', 400);
    if (credit.status === 'CLOSED') return errorResponse(res, 'Credit is fully closed', 400);

    const { billId, billNumber, amount, appliedDate } = req.body;

    if (!billNumber) return errorResponse(res, 'Bill number is required', 400);
    if (!amount || amount <= 0) return errorResponse(res, 'Amount must be greater than 0', 400);
    if (amount > credit.balanceAmount + 0.01) {
      return errorResponse(res, `Amount exceeds available balance (₹${credit.balanceAmount.toFixed(2)})`, 400);
    }

    // Add application
    credit.applications.push({
      billId: billId || '',
      billNumber,
      amount: parseFloat(amount),
      appliedDate: appliedDate ? new Date(appliedDate) : new Date(),
    });

    // Update amounts
    const totalApplied = credit.applications.reduce((s, a) => s + a.amount, 0)
      + credit.refunds.reduce((s, r) => s + r.amount, 0);
    credit.appliedAmount = totalApplied;
    credit.balanceAmount = credit.totalAmount - totalApplied;

    // Update status
    if (credit.balanceAmount <= 0.01) {
      credit.status = 'CLOSED';
      credit.balanceAmount = 0;
    } else {
      credit.status = 'PARTIALLY_APPLIED';
    }

    await credit.save();

    // Optionally: update the bill's amount paid (if bill model is available)
    // await Bill.findByIdAndUpdate(billId, { $inc: { amountPaid: amount, amountDue: -amount } });

    return successResponse(res, credit, `Credit applied to bill ${billNumber}`);
  } catch (err) {
    return errorResponse(res, 'Failed to apply credit', 500, err);
  }
});

// POST /api/vendor-credits/:id/refund
router.post('/:id/refund', async (req, res) => {
  try {
    const credit = await VendorCredit.findById(req.params.id);
    if (!credit) return errorResponse(res, 'Vendor credit not found', 404);

    if (credit.status === 'VOID') return errorResponse(res, 'Cannot refund a voided credit', 400);
    if (credit.status === 'CLOSED') return errorResponse(res, 'Credit is fully closed', 400);

    const { amount, refundDate, paymentMode, referenceNumber, notes } = req.body;

    if (!amount || amount <= 0) return errorResponse(res, 'Amount must be greater than 0', 400);
    if (amount > credit.balanceAmount + 0.01) {
      return errorResponse(res, `Amount exceeds available balance (₹${credit.balanceAmount.toFixed(2)})`, 400);
    }

    // Add refund
    credit.refunds.push({
      amount: parseFloat(amount),
      refundDate: refundDate ? new Date(refundDate) : new Date(),
      paymentMode: paymentMode || 'Bank Transfer',
      referenceNumber: referenceNumber || '',
      notes: notes || '',
    });

    // Update amounts
    const totalUsed = credit.applications.reduce((s, a) => s + a.amount, 0)
      + credit.refunds.reduce((s, r) => s + r.amount, 0);
    credit.appliedAmount = totalUsed;
    credit.balanceAmount = credit.totalAmount - totalUsed;

    if (credit.balanceAmount <= 0.01) {
      credit.status = 'CLOSED';
      credit.balanceAmount = 0;
    } else {
      credit.status = 'PARTIALLY_APPLIED';
    }

    await credit.save();
    return successResponse(res, credit, 'Refund recorded successfully');
  } catch (err) {
    return errorResponse(res, 'Failed to record refund', 500, err);
  }
});

// DELETE /api/vendor-credits/:id
router.delete('/:id', async (req, res) => {
  try {
    const credit = await VendorCredit.findById(req.params.id);
    if (!credit) return errorResponse(res, 'Vendor credit not found', 404);

    if (credit.status === 'CLOSED') {
      return errorResponse(res, 'Cannot delete a closed credit', 400);
    }

    await VendorCredit.findByIdAndDelete(req.params.id);
    return successResponse(res, null, 'Vendor credit deleted');
  } catch (err) {
    return errorResponse(res, 'Failed to delete vendor credit', 500, err);
  }
});

// POST /api/vendor-credits/bulk-import
router.post('/bulk-import', async (req, res) => {
  try {
    const { credits } = req.body;

    if (!credits || !Array.isArray(credits) || credits.length === 0) {
      return errorResponse(res, 'No credits data provided', 400);
    }

    let successCount = 0;
    let failedCount = 0;
    const errors = [];
    const created = [];

    for (let i = 0; i < credits.length; i++) {
      try {
        const data = credits[i];

        if (!data.vendorName) throw new Error('Vendor Name is required');
        if (!data.reason) throw new Error('Reason is required');
        if (!data.totalAmount || data.totalAmount <= 0) throw new Error('Total Amount must be > 0');
        if (!data.items || data.items.length === 0) throw new Error('At least one item required');

        const credit = new VendorCredit({
          ...data,
          isImported: true,
          appliedAmount: 0,
          balanceAmount: data.totalAmount,
          applications: [],
          refunds: [],
        });

        await credit.save();
        created.push(credit);
        successCount++;
      } catch (e) {
        failedCount++;
        errors.push(`Row ${i + 1}: ${e.message}`);
      }
    }

    return successResponse(res, {
      totalProcessed: credits.length,
      successCount,
      failedCount,
      errors,
      created: created.map(c => c.creditNumber),
    }, `Import complete: ${successCount} succeeded, ${failedCount} failed`);
  } catch (err) {
    return errorResponse(res, 'Bulk import failed', 500, err);
  }
});

module.exports = router;