// routes/vehicle_checklist_router.js
// ============================================================================
// VEHICLE CHECKLIST BACKEND ROUTE
// ============================================================================
// ADD TO index.js (2 lines):
//
//   const vehicleChecklistRoutes = require('./routes/vehicle_checklist_router');
//   app.use('/api/vehicle-checklist', verifyJWT, vehicleChecklistRoutes);
//
// That's it. Fits your existing pattern exactly.
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');

// ============================================================================
// MONGOOSE SCHEMA
// ============================================================================

const checklistItemSchema = new mongoose.Schema({
  id:       { type: String, required: true },
  category: { type: String, required: true },
  title:    { type: String, required: true },
  checked:  { type: Boolean, default: false },
  note:     { type: String, default: '' },
}, { _id: false });

const vehicleChecklistSchema = new mongoose.Schema({
  driverId:      { type: String, required: true },
  driverEmail:   { type: String, default: '' },
  vehicleNumber: { type: String, required: true },
  date:          { type: String, required: true },        // 'yyyy-MM-dd'
  submittedAt:   { type: Date,   default: Date.now },
  totalItems:    { type: Number, default: 0 },
  checkedItems:  { type: Number, default: 0 },
  allPassed:     { type: Boolean, default: false },
  items:         [checklistItemSchema],
  failedItems:   { type: Array,  default: [] },
}, {
  timestamps: true,
  collection: 'vehicle_checklists',
});

// Compound unique index: one submission per driver per vehicle per day
vehicleChecklistSchema.index(
  { driverId: 1, vehicleNumber: 1, date: 1 },
  { unique: true }
);

// Model (use existing model if already compiled to avoid OverwriteModelError)
const VehicleChecklist =
  mongoose.models.VehicleChecklist ||
  mongoose.model('VehicleChecklist', vehicleChecklistSchema);

// ============================================================================
// POST /api/vehicle-checklist/submit
// Submit today's checklist → saves to MongoDB
// ============================================================================

router.post('/submit', async (req, res) => {
  console.log('\n📋 VEHICLE CHECKLIST SUBMIT');
  console.log('─'.repeat(60));

  try {
    const {
      driverId,
      driverEmail,
      vehicleNumber,
      date,
      submittedAt,
      totalItems,
      checkedItems,
      allPassed,
      items,
      failedItems,
    } = req.body;

    // ── Validate required fields ──────────────────────────────────────
    if (!driverId || typeof driverId !== 'string' || driverId.trim() === '') {
      return res.status(400).json({
        success: false,
        message: 'driverId is required',
      });
    }

    if (!vehicleNumber || typeof vehicleNumber !== 'string' || vehicleNumber.trim() === '') {
      return res.status(400).json({
        success: false,
        message: 'vehicleNumber is required',
      });
    }

    if (!date || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      return res.status(400).json({
        success: false,
        message: 'date is required in yyyy-MM-dd format',
      });
    }

    if (!Array.isArray(items) || items.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'items array is required and must not be empty',
      });
    }

    console.log(`   Driver ID:     ${driverId}`);
    console.log(`   Driver Email:  ${driverEmail || 'N/A'}`);
    console.log(`   Vehicle:       ${vehicleNumber}`);
    console.log(`   Date:          ${date}`);
    console.log(`   Checked:       ${checkedItems} / ${totalItems}`);
    console.log(`   All Passed:    ${allPassed}`);

    // ── Check if already submitted today ─────────────────────────────
    const existing = await VehicleChecklist.findOne({
      driverId: driverId.trim(),
      vehicleNumber: vehicleNumber.trim(),
      date,
    });

    if (existing) {
      console.log('⚠️  Checklist already submitted today — returning existing');
      return res.status(200).json({
        success: true,
        message: 'Checklist already submitted for today',
        data: {
          checklistId: existing._id,
          alreadySubmitted: true,
          date: existing.date,
          checkedItems: existing.checkedItems,
          totalItems: existing.totalItems,
        },
      });
    }

    // ── Save to MongoDB ───────────────────────────────────────────────
    const checklist = new VehicleChecklist({
      driverId:      driverId.trim(),
      driverEmail:   (driverEmail || '').trim(),
      vehicleNumber: vehicleNumber.trim(),
      date,
      submittedAt:   submittedAt ? new Date(submittedAt) : new Date(),
      totalItems:    Number(totalItems) || items.length,
      checkedItems:  Number(checkedItems) || 0,
      allPassed:     Boolean(allPassed),
      items:         items.map((item) => ({
        id:       String(item.id || ''),
        category: String(item.category || ''),
        title:    String(item.title || ''),
        checked:  Boolean(item.checked),
        note:     String(item.note || ''),
      })),
      failedItems: Array.isArray(failedItems) ? failedItems : [],
    });

    const saved = await checklist.save();

    console.log(`✅ Checklist saved — ID: ${saved._id}`);
    console.log('─'.repeat(60) + '\n');

    return res.status(201).json({
      success: true,
      message: 'Vehicle checklist submitted successfully',
      data: {
        checklistId:  saved._id,
        driverId:     saved.driverId,
        vehicleNumber: saved.vehicleNumber,
        date:         saved.date,
        checkedItems: saved.checkedItems,
        totalItems:   saved.totalItems,
        allPassed:    saved.allPassed,
        submittedAt:  saved.submittedAt,
      },
    });

  } catch (error) {
    // Duplicate key: already submitted (race condition)
    if (error.code === 11000) {
      console.log('⚠️  Duplicate key — checklist already exists');
      return res.status(200).json({
        success: true,
        message: 'Checklist already submitted for today',
        data: { alreadySubmitted: true },
      });
    }

    console.error('❌ Checklist submit error:', error.message);
    console.error('   Stack:', error.stack);
    return res.status(500).json({
      success: false,
      message: 'Failed to save checklist. Please try again.',
      error: process.env.NODE_ENV === 'development' ? error.message : undefined,
    });
  }
});

// ============================================================================
// GET /api/vehicle-checklist/status?date=yyyy-MM-dd&vehicleNumber=KA01AB1234
// Check if today's checklist was already submitted
// ============================================================================

router.get('/status', async (req, res) => {
  try {
    const { date, vehicleNumber } = req.query;

    // driverId comes from the JWT token (set by verifyJWT middleware)
    const driverId = req.user?.userId || req.user?.id;

    if (!driverId) {
      return res.status(401).json({
        success: false,
        message: 'Driver not authenticated',
      });
    }

    if (!date || !vehicleNumber) {
      return res.status(400).json({
        success: false,
        message: 'date and vehicleNumber query params are required',
      });
    }

    const checklist = await VehicleChecklist.findOne({
      driverId: String(driverId),
      vehicleNumber: String(vehicleNumber),
      date: String(date),
    }).select('_id date checkedItems totalItems allPassed submittedAt');

    return res.status(200).json({
      success: true,
      data: {
        submitted:    !!checklist,
        checklistId:  checklist?._id || null,
        date:         date,
        checkedItems: checklist?.checkedItems ?? 0,
        totalItems:   checklist?.totalItems ?? 0,
        allPassed:    checklist?.allPassed ?? false,
        submittedAt:  checklist?.submittedAt ?? null,
      },
    });

  } catch (error) {
    console.error('❌ Checklist status error:', error.message);
    return res.status(500).json({
      success: false,
      message: 'Failed to check checklist status',
    });
  }
});

// ============================================================================
// GET /api/vehicle-checklist/history?vehicleNumber=KA01AB1234&limit=30
// Get submission history for a vehicle (admin use)
// ============================================================================

router.get('/history', async (req, res) => {
  try {
    const { vehicleNumber, driverId, limit = 30 } = req.query;

    const filter = {};
    if (vehicleNumber) filter.vehicleNumber = String(vehicleNumber);
    if (driverId) filter.driverId = String(driverId);

    const history = await VehicleChecklist
      .find(filter)
      .sort({ submittedAt: -1 })
      .limit(Math.min(Number(limit), 100))
      .select('-items'); // Exclude full items array for list view

    return res.status(200).json({
      success: true,
      data: {
        total: history.length,
        checklists: history,
      },
    });

  } catch (error) {
    console.error('❌ Checklist history error:', error.message);
    return res.status(500).json({
      success: false,
      message: 'Failed to fetch checklist history',
    });
  }
});

// ============================================================================
// GET /api/vehicle-checklist/:id
// Get a single checklist with all items (admin use)
// ============================================================================

router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;

    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid checklist ID',
      });
    }

    const checklist = await VehicleChecklist.findById(id);

    if (!checklist) {
      return res.status(404).json({
        success: false,
        message: 'Checklist not found',
      });
    }

    return res.status(200).json({
      success: true,
      data: checklist,
    });

  } catch (error) {
    console.error('❌ Checklist fetch error:', error.message);
    return res.status(500).json({
      success: false,
      message: 'Failed to fetch checklist',
    });
  }
});

module.exports = router;