// ============================================================================
// SALES ORDERS BACKEND API - Complete Implementation
// ============================================================================
// File: backend/routes/sales-order.js
// Features: CRUD, Convert from Quote, Bulk Import, PDF, Email, Invoice Conversion
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const { body, param, validationResult } = require('express-validator');
const PDFDocument = require('pdfkit');
const nodemailer = require('nodemailer');
const fs = require('fs');
const path = require('path');

// ============================================================================
// LOGO PATH RESOLVER
// ============================================================================

let CACHED_LOGO_PATH = null;

function findLogoPath() {
  const possiblePaths = [
    path.join(__dirname, '..', 'assets', 'abra.jpeg'),
    path.join(__dirname, '..', 'assets', 'abra.jpg'),
    path.join(__dirname, '..', 'assets', 'abra.png'),
    path.join(__dirname, '..', '..', 'assets', 'abra.jpeg'),
    path.join(__dirname, '..', '..', 'assets', 'abra.jpg'),
    path.join(__dirname, '..', '..', 'assets', 'abra.png'),
    path.join(process.cwd(), 'assets', 'abra.jpeg'),
    path.join(process.cwd(), 'assets', 'abra.jpg'),
    path.join(process.cwd(), 'assets', 'abra.png'),
    path.join(process.cwd(), 'abra_fleet_backend', 'assets', 'abra.jpeg'),
    path.join(process.cwd(), 'abra_fleet_backend', 'assets', 'abra.jpg'),
    path.join(process.cwd(), 'abra_fleet_backend', 'assets', 'abra.png'),
    path.join(process.cwd(), 'backend', 'assets', 'abra.jpeg'),
    path.join(process.cwd(), 'backend', 'assets', 'abra.jpg'),
    path.join(process.cwd(), 'backend', 'assets', 'abra.png'),
  ];
  
  for (const testPath of possiblePaths) {
    try {
      if (fs.existsSync(testPath)) {
        const stats = fs.statSync(testPath);
        if (stats.isFile() && stats.size > 0) {
          console.log('✅ LOGO FOUND:', testPath);
          return testPath;
        }
      }
    } catch (err) {
      // Continue searching
    }
  }
  
  console.error('❌ LOGO NOT FOUND!');
  return null;
}

function getLogoPath() {
  if (!CACHED_LOGO_PATH) {
    CACHED_LOGO_PATH = findLogoPath();
  }
  return CACHED_LOGO_PATH;
}

// ============================================================================
// MONGOOSE MODEL DEFINITION
// ============================================================================

const salesOrderItemSchema = new mongoose.Schema({
  itemDetails: {
    type: String,
    required: true,
    trim: true,
  },
  quantity: {
    type: Number,
    required: true,
    min: 0,
  },
  rate: {
    type: Number,
    required: true,
    min: 0,
  },
  discount: {
    type: Number,
    default: 0,
    min: 0,
  },
  discountType: {
    type: String,
    enum: ['percentage', 'amount'],
    default: 'percentage',
  },
  amount: {
    type: Number,
    required: true,
    min: 0,
  },
  // Stock tracking
  quantityPacked: {
    type: Number,
    default: 0,
    min: 0,
  },
  quantityShipped: {
    type: Number,
    default: 0,
    min: 0,
  },
  quantityInvoiced: {
    type: Number,
    default: 0,
    min: 0,
  },
}, { _id: false });

const salesOrderSchema = new mongoose.Schema({
  organizationId: {
    type: String,
    required: false,
    index: true,
  },
  salesOrderNumber: {
    type: String,
    required: true,
    unique: true,
    trim: true,
  },
  referenceNumber: {
    type: String,
    trim: true,
  },
  customerId: {
    type: String,
    required: true,
    index: true,
  },
  customerName: {
    type: String,
    required: true,
    trim: true,
  },
  customerEmail: {
    type: String,
    trim: true,
    lowercase: true,
  },
  customerPhone: {
    type: String,
    trim: true,
  },
  
  // Dates
  salesOrderDate: {
    type: Date,
    required: true,
    default: Date.now,
  },
  expectedShipmentDate: {
    type: Date,
  },
  paymentTerms: {
    type: String,
    enum: ['Due on Receipt', 'Net 15', 'Net 30', 'Net 45', 'Net 60'],
    default: 'Net 30',
  },
  deliveryMethod: {
    type: String,
    trim: true,
  },
  
  // Additional Info
  salesperson: {
    type: String,
    trim: true,
  },
  subject: {
    type: String,
    trim: true,
  },
  
  // Items
  items: {
    type: [salesOrderItemSchema],
    required: true,
    validate: {
      validator: function(items) {
        return items && items.length > 0;
      },
      message: 'At least one item is required',
    },
  },
  
  // Financial Calculations
  subTotal: {
    type: Number,
    required: true,
    default: 0,
  },
  tdsRate: {
    type: Number,
    default: 0,
    min: 0,
    max: 100,
  },
  tdsAmount: {
    type: Number,
    default: 0,
    min: 0,
  },
  tcsRate: {
    type: Number,
    default: 0,
    min: 0,
    max: 100,
  },
  tcsAmount: {
    type: Number,
    default: 0,
    min: 0,
  },
  gstRate: {
    type: Number,
    default: 18,
    min: 0,
    max: 100,
  },
  cgst: {
    type: Number,
    default: 0,
    min: 0,
  },
  sgst: {
    type: Number,
    default: 0,
    min: 0,
  },
  igst: {
    type: Number,
    default: 0,
    min: 0,
  },
  totalAmount: {
    type: Number,
    required: true,
    default: 0,
  },
  
  // Notes
  customerNotes: {
    type: String,
    trim: true,
  },
  termsAndConditions: {
    type: String,
    trim: true,
  },
  
  // Status Management
  status: {
    type: String,
    enum: ['DRAFT', 'OPEN', 'CONFIRMED', 'PACKED', 'SHIPPED', 'INVOICED', 'CLOSED', 'CANCELLED', 'VOID'],
    default: 'DRAFT',
    index: true,
  },
  
  // Approval Workflow
  approvalStatus: {
    type: String,
    enum: ['PENDING', 'APPROVED', 'REJECTED', 'NOT_REQUIRED'],
    default: 'NOT_REQUIRED',
  },
  approvedBy: {
    type: String,
  },
  approvedAt: {
    type: Date,
  },
  
  // Conversion tracking
  convertedFromQuoteId: {
    type: String,
  },
  convertedFromQuoteNumber: {
    type: String,
  },
  convertedToInvoice: {
    type: Boolean,
    default: false,
  },
  convertedToInvoiceId: {
    type: String,
  },
  convertedToInvoiceNumber: {
    type: String,
  },
  convertedDate: {
    type: Date,
  },
  
  // Email tracking
  emailsSent: [{
    sentTo: String,
    sentAt: Date,
    emailType: {
      type: String,
      enum: ['sales_order', 'shipment_update', 'invoice']
    }
  }],
  
  // PDF Generation
  pdfPath: String,
  pdfGeneratedAt: Date,
  
  // Audit Trail
  createdBy: {
    type: String,
    required: true,
  },
  updatedBy: String,
}, {
  timestamps: true,
});

// Indexes for better query performance
salesOrderSchema.index({ organizationId: 1, salesOrderNumber: 1 });
salesOrderSchema.index({ organizationId: 1, customerId: 1 });
salesOrderSchema.index({ organizationId: 1, status: 1 });
salesOrderSchema.index({ organizationId: 1, salesOrderDate: -1 });
salesOrderSchema.index({ organizationId: 1, createdAt: -1 });

// Methods
salesOrderSchema.methods.canEdit = function() {
  return !['INVOICED', 'CLOSED', 'CANCELLED', 'VOID'].includes(this.status);
};

salesOrderSchema.methods.canDelete = function() {
  return this.status === 'DRAFT';
};

salesOrderSchema.methods.canConvert = function() {
  return ['CONFIRMED', 'OPEN', 'PACKED', 'SHIPPED'].includes(this.status);
};

// Create the SalesOrder model
const SalesOrder = mongoose.model('SalesOrder', salesOrderSchema);

// ============================================================================
// MIDDLEWARE
// ============================================================================

const validateRequest = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ 
      success: false, 
      message: 'Validation failed', 
      errors: errors.array() 
    });
  }
  next();
};

// ============================================================================
// VALIDATION RULES
// ============================================================================

const salesOrderValidationRules = [
  body('customerId').notEmpty().withMessage('Customer ID is required'),
  body('customerName').notEmpty().withMessage('Customer name is required'),
  body('salesOrderDate').isISO8601().withMessage('Valid sales order date is required'),
  body('items').isArray({ min: 1 }).withMessage('At least one item is required'),
  body('items.*.itemDetails').notEmpty().withMessage('Item details are required'),
  body('items.*.quantity').isFloat({ min: 0.01 }).withMessage('Quantity must be greater than 0'),
  body('items.*.rate').isFloat({ min: 0 }).withMessage('Rate must be non-negative'),
  body('status').isIn(['DRAFT', 'OPEN', 'CONFIRMED', 'PACKED', 'SHIPPED', 'INVOICED', 'CLOSED', 'CANCELLED', 'VOID'])
    .withMessage('Invalid status'),
];

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

// Generate unique sales order number
const generateSalesOrderNumber = async (organizationId) => {
  try {
    const year = new Date().getFullYear();
    const prefix = `SO-${year}`;
    
    const latestSalesOrder = await SalesOrder.findOne({
      organizationId,
      salesOrderNumber: new RegExp(`^${prefix}`)
    }).sort({ createdAt: -1 });
    
    let sequence = 1;
    if (latestSalesOrder) {
      const parts = latestSalesOrder.salesOrderNumber.split('-');
      sequence = parseInt(parts[parts.length - 1]) + 1;
    }
    
    return `${prefix}-${sequence.toString().padStart(4, '0')}`;
  } catch (error) {
    console.error('Error generating sales order number:', error);
    throw new Error('Failed to generate sales order number');
  }
};

// Calculate sales order totals
const calculateSalesOrderTotals = (items, tdsRate = 0, tcsRate = 0, gstRate = 18) => {
  let subTotal = 0;
  
  items.forEach(item => {
    let itemAmount = item.quantity * item.rate;
    
    if (item.discount > 0) {
      if (item.discountType === 'percentage') {
        itemAmount = itemAmount - (itemAmount * item.discount / 100);
      } else {
        itemAmount = itemAmount - item.discount;
      }
    }
    
    item.amount = parseFloat(itemAmount.toFixed(2));
    subTotal += item.amount;
  });
  
  subTotal = parseFloat(subTotal.toFixed(2));
  
  const tdsAmount = parseFloat((subTotal * tdsRate / 100).toFixed(2));
  const tcsAmount = parseFloat((subTotal * tcsRate / 100).toFixed(2));
  const gstBase = subTotal - tdsAmount + tcsAmount;
  const totalGst = parseFloat((gstBase * gstRate / 100).toFixed(2));
  const cgst = parseFloat((totalGst / 2).toFixed(2));
  const sgst = parseFloat((totalGst / 2).toFixed(2));
  const totalAmount = parseFloat((subTotal - tdsAmount + tcsAmount + totalGst).toFixed(2));
  
  return {
    subTotal,
    tdsAmount,
    tcsAmount,
    cgst,
    sgst,
    igst: 0,
    totalAmount,
    tdsRate,
    tcsRate,
    gstRate
  };
};

// Generate PDF for sales order
const generateSalesOrderPDF = async (salesOrder) => {
  return new Promise((resolve, reject) => {
    try {
      const uploadsDir = path.join(__dirname, '..', 'uploads', 'sales-orders');
      if (!fs.existsSync(uploadsDir)) {
        fs.mkdirSync(uploadsDir, { recursive: true });
      }
      
      const filename = `sales-order-${salesOrder.salesOrderNumber}.pdf`;
      const filepath = path.join(uploadsDir, filename);
      
      const doc = new PDFDocument({ size: 'A4', margin: 50 });
      const stream = fs.createWriteStream(filepath);
      
      doc.pipe(stream);
      
      // ========================================================================
      // LOGO LOADING
      // ========================================================================
      
      const logoPath = getLogoPath();
      let logoLoaded = false;
      
      if (logoPath) {
        try {
          doc.image(logoPath, 40, 35, { 
            width: 120,
            height: 60,
            fit: [120, 60]
          });
          logoLoaded = true;
          console.log('   ✅ Logo embedded in PDF');
        } catch (logoError) {
          console.error('   ❌ Logo loading failed:', logoError.message);
        }
      }
      
      if (!logoLoaded) {
        // Fallback to text if logo not found
        doc.fontSize(22)
           .fillColor('#0066CC')
           .font('Helvetica-Bold')
           .text('ABRA Travels', 40, 40);
        
        doc.fontSize(9)
           .fillColor('#666666')
           .font('Helvetica')
           .text('YOUR JOURNEY, OUR COMMITMENT', 40, 67);
      }
      
      // Sales Order Title
      doc.fontSize(28)
         .fillColor('#2C3E50')
         .text('SALES ORDER', 400, 50, { align: 'right' });
      
      // Sales Order Details
      doc.fontSize(10)
         .fillColor('#34495E')
         .text(`SO #: ${salesOrder.salesOrderNumber}`, 400, 90, { align: 'right' })
         .text(`Date: ${new Date(salesOrder.salesOrderDate).toLocaleDateString('en-IN')}`, 400, 105, { align: 'right' });
      
      if (salesOrder.referenceNumber) {
        doc.text(`Reference: ${salesOrder.referenceNumber}`, 400, 120, { align: 'right' });
      }
      
      // Line separator
      doc.moveTo(50, 150)
         .lineTo(545, 150)
         .strokeColor('#BDC3C7')
         .stroke();
      
      // Customer Section
      doc.fontSize(12)
         .fillColor('#2C3E50')
         .text('CUSTOMER:', 50, 170);
      
      doc.fontSize(11)
         .fillColor('#34495E')
         .text(salesOrder.customerName, 50, 190)
         .fontSize(10)
         .fillColor('#7F8C8D');
      
      let yPos = 205;
      if (salesOrder.customerEmail) {
        doc.text(`Email: ${salesOrder.customerEmail}`, 50, yPos);
        yPos += 15;
      }
      if (salesOrder.customerPhone) {
        doc.text(`Phone: ${salesOrder.customerPhone}`, 50, yPos);
      }
      
      // Shipment Info
      if (salesOrder.expectedShipmentDate) {
        doc.fontSize(12)
           .fillColor('#2C3E50')
           .text('SHIPMENT INFO:', 350, 170);
        
        doc.fontSize(10)
           .fillColor('#7F8C8D')
           .text(`Expected: ${new Date(salesOrder.expectedShipmentDate).toLocaleDateString('en-IN')}`, 350, 190);
        
        if (salesOrder.deliveryMethod) {
          doc.text(`Method: ${salesOrder.deliveryMethod}`, 350, 205);
        }
      }
      
      // Items Table
      yPos = 280;
      doc.fontSize(10)
         .fillColor('#FFFFFF')
         .rect(50, yPos, 495, 25)
         .fill('#34495E');
      
      doc.fillColor('#FFFFFF')
         .text('ITEM DETAILS', 60, yPos + 8)
         .text('QTY', 320, yPos + 8, { width: 40, align: 'center' })
         .text('RATE', 370, yPos + 8, { width: 60, align: 'right' })
         .text('AMOUNT', 500, yPos + 8, { width: 55, align: 'right' });
      
      yPos += 35;
      doc.fillColor('#34495E');
      
      salesOrder.items.forEach((item) => {
        if (yPos > 700) {
          doc.addPage();
          yPos = 50;
        }
        
        doc.fontSize(10)
           .text(item.itemDetails, 60, yPos, { width: 240 })
           .text(item.quantity.toString(), 320, yPos, { width: 40, align: 'center' })
           .text(`Rs.${item.rate.toFixed(2)}`, 370, yPos, { width: 60, align: 'right' })
           .text(`Rs.${item.amount.toFixed(2)}`, 500, yPos, { width: 55, align: 'right' });
        
        yPos += 25;
        
        doc.moveTo(50, yPos)
           .lineTo(545, yPos)
           .strokeColor('#ECF0F1')
           .stroke();
        
        yPos += 5;
      });
      
      // Summary
      yPos += 20;
      const summaryX = 380;
      
      doc.fontSize(10)
         .fillColor('#7F8C8D')
         .text('Sub Total:', summaryX, yPos, { align: 'left' })
         .fillColor('#34495E')
         .text(`Rs.${salesOrder.subTotal.toFixed(2)}`, summaryX + 100, yPos, { align: 'right' });
      
      yPos += 20;
      
      if (salesOrder.tdsAmount > 0) {
        doc.fillColor('#7F8C8D')
           .text(`TDS (${salesOrder.tdsRate}%):`, summaryX, yPos, { align: 'left' })
           .fillColor('#E74C3C')
           .text(`- Rs.${salesOrder.tdsAmount.toFixed(2)}`, summaryX + 100, yPos, { align: 'right' });
        yPos += 20;
      }
      
      if (salesOrder.tcsAmount > 0) {
        doc.fillColor('#7F8C8D')
           .text(`TCS (${salesOrder.tcsRate}%):`, summaryX, yPos, { align: 'left' })
           .fillColor('#34495E')
           .text(`Rs.${salesOrder.tcsAmount.toFixed(2)}`, summaryX + 100, yPos, { align: 'right' });
        yPos += 20;
      }
      
      if (salesOrder.cgst > 0) {
        doc.fillColor('#7F8C8D')
           .text(`CGST (${(salesOrder.gstRate / 2).toFixed(1)}%):`, summaryX, yPos, { align: 'left' })
           .fillColor('#34495E')
           .text(`Rs.${salesOrder.cgst.toFixed(2)}`, summaryX + 100, yPos, { align: 'right' });
        yPos += 15;
        
        doc.fillColor('#7F8C8D')
           .text(`SGST (${(salesOrder.gstRate / 2).toFixed(1)}%):`, summaryX, yPos, { align: 'left' })
           .fillColor('#34495E')
           .text(`Rs.${salesOrder.sgst.toFixed(2)}`, summaryX + 100, yPos, { align: 'right' });
        yPos += 20;
      }
      
      doc.moveTo(summaryX, yPos)
         .lineTo(545, yPos)
         .strokeColor('#34495E')
         .lineWidth(2)
         .stroke();
      
      yPos += 15;
      
      doc.fontSize(14)
         .fillColor('#2C3E50')
         .text('Total Amount:', summaryX, yPos, { align: 'left' })
         .text(`Rs.${salesOrder.totalAmount.toFixed(2)}`, summaryX + 100, yPos, { align: 'right' });
      
      // Status Badge
      yPos += 30;
      let statusColor;
      
      switch (salesOrder.status) {
        case 'CONFIRMED':
        case 'OPEN':
          statusColor = '#27AE60';
          break;
        case 'PACKED':
          statusColor = '#3498DB';
          break;
        case 'SHIPPED':
          statusColor = '#9B59B6';
          break;
        case 'INVOICED':
        case 'CLOSED':
          statusColor = '#16A085';
          break;
        default:
          statusColor = '#95A5A6';
      }
      
      doc.rect(summaryX, yPos, 165, 25)
         .fill(statusColor);
      
      doc.fontSize(12)
         .fillColor('#FFFFFF')
         .text(salesOrder.status, summaryX, yPos + 7, { width: 165, align: 'center' });
      
      // Notes
      if (salesOrder.customerNotes || salesOrder.termsAndConditions) {
        yPos += 50;
        
        if (yPos > 650) {
          doc.addPage();
          yPos = 50;
        }
        
        if (salesOrder.customerNotes) {
          doc.fontSize(11)
             .fillColor('#2C3E50')
             .text('Notes:', 50, yPos);
          
          doc.fontSize(10)
             .fillColor('#7F8C8D')
             .text(salesOrder.customerNotes, 50, yPos + 20, { width: 495 });
          
          yPos += 60;
        }
        
        if (salesOrder.termsAndConditions) {
          doc.fontSize(11)
             .fillColor('#2C3E50')
             .text('Terms & Conditions:', 50, yPos);
          
          doc.fontSize(9)
             .fillColor('#7F8C8D')
             .text(salesOrder.termsAndConditions, 50, yPos + 20, { width: 495 });
        }
      }
      
      // Footer
      doc.fontSize(9)
         .fillColor('#95A5A6')
         .text('Thank you for your business!', 50, 750, { align: 'center', width: 495 })
         .text('For queries, contact: sales@abrafleet.com | +91-XXXXXXXXXX', 50, 765, { align: 'center', width: 495 });
      
      doc.end();
      
      stream.on('finish', () => {
        resolve({
          filename: filename,
          filepath: filepath,
          relativePath: `/uploads/sales-orders/${filename}`
        });
      });
      
      stream.on('error', reject);
      
    } catch (error) {
      reject(error);
    }
  });
};

// Email transporter
const getEmailTransporter = () => {
  return nodemailer.createTransport({
    host: process.env.SMTP_HOST || 'smtp.gmail.com',
    port: process.env.SMTP_PORT || 587,
    secure: false,
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASSWORD,
    },
  });
};

// Send sales order email
const sendSalesOrderEmail = async (salesOrder, pdfBuffer) => {
  try {
    if (!process.env.SMTP_USER || !process.env.SMTP_PASSWORD) {
      console.log('⚠️  SMTP not configured - skipping email send');
      return;
    }
    
    const transporter = getEmailTransporter();
    
    const mailOptions = {
      from: process.env.SMTP_FROM || process.env.SMTP_USER,
      to: salesOrder.customerEmail,
      subject: `Sales Order ${salesOrder.salesOrderNumber} from ${process.env.COMPANY_NAME || 'Abra Fleet'}`,
      html: `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
          <h2>Sales Order ${salesOrder.salesOrderNumber}</h2>
          <p>Dear ${salesOrder.customerName},</p>
          <p>Please find attached sales order ${salesOrder.salesOrderNumber} for your records.</p>
          
          <div style="background-color: #f5f5f5; padding: 15px; margin: 20px 0; border-radius: 5px;">
            <p><strong>Sales Order Summary:</strong></p>
            <p>SO Number: ${salesOrder.salesOrderNumber}</p>
            <p>Date: ${new Date(salesOrder.salesOrderDate).toLocaleDateString()}</p>
            ${salesOrder.expectedShipmentDate ? `<p>Expected Shipment: ${new Date(salesOrder.expectedShipmentDate).toLocaleDateString()}</p>` : ''}
            <p>Total Amount: ₹${salesOrder.totalAmount.toFixed(2)}</p>
            <p>Status: ${salesOrder.status}</p>
          </div>
          
          ${salesOrder.customerNotes ? `<p><strong>Notes:</strong><br>${salesOrder.customerNotes}</p>` : ''}
          
          <p>If you have any questions, please don't hesitate to contact us.</p>
          
          <p>Best regards,<br>${process.env.COMPANY_NAME || 'Abra Fleet'}</p>
        </div>
      `,
      attachments: [
        {
          filename: `${salesOrder.salesOrderNumber}.pdf`,
          content: pdfBuffer,
        },
      ],
    };
    
    await transporter.sendMail(mailOptions);
    console.log(`✅ Sales order email sent to ${salesOrder.customerEmail}`);
  } catch (error) {
    console.error('⚠️  Error sending sales order email:', error.message);
  }
};

// ============================================================================
// API ROUTES
// ============================================================================

// GET /api/sales-orders - Get all sales orders
router.get('/', async (req, res) => {
  try {
    const { 
      status, 
      page = 1, 
      limit = 20,
      search,
      fromDate,
      toDate
    } = req.query;
    
    const organizationId = req.user.organizationId || 'default_org';
    
    const query = { organizationId };
    
    if (status && status !== 'All') {
      query.status = status;
    }
    
    if (search) {
      query.$or = [
        { salesOrderNumber: { $regex: search, $options: 'i' } },
        { customerName: { $regex: search, $options: 'i' } },
        { referenceNumber: { $regex: search, $options: 'i' } },
      ];
    }
    
    if (fromDate || toDate) {
      query.salesOrderDate = {};
      if (fromDate) {
        query.salesOrderDate.$gte = new Date(fromDate);
      }
      if (toDate) {
        query.salesOrderDate.$lte = new Date(toDate);
      }
    }
    
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    const [salesOrders, total] = await Promise.all([
      SalesOrder.find(query)
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(parseInt(limit))
        .select('-__v'),
      SalesOrder.countDocuments(query),
    ]);
    
    res.json({
      success: true,
      data: {
        salesOrders,
        pagination: {
          page: parseInt(page),
          limit: parseInt(limit),
          total,
          pages: Math.ceil(total / parseInt(limit)),
        },
      },
    });
  } catch (error) {
    console.error('Error fetching sales orders:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch sales orders', 
      error: error.message 
    });
  }
});

// GET /api/sales-orders/stats - Get statistics
router.get('/stats', async (req, res) => {
  try {
    const organizationId = req.user.organizationId || 'default_org';
    
    const [
      totalSalesOrders,
      draftSalesOrders,
      openSalesOrders,
      confirmedSalesOrders,
      shippedSalesOrders,
      invoicedSalesOrders,
      totalValue,
    ] = await Promise.all([
      SalesOrder.countDocuments({ organizationId }),
      SalesOrder.countDocuments({ organizationId, status: 'DRAFT' }),
      SalesOrder.countDocuments({ organizationId, status: 'OPEN' }),
      SalesOrder.countDocuments({ organizationId, status: 'CONFIRMED' }),
      SalesOrder.countDocuments({ organizationId, status: 'SHIPPED' }),
      SalesOrder.countDocuments({ organizationId, status: 'INVOICED' }),
      SalesOrder.aggregate([
        { $match: { organizationId } },
        { $group: { _id: null, total: { $sum: '$totalAmount' } } },
      ]),
    ]);
    
    res.json({
      success: true,
      data: {
        totalSalesOrders,
        draftSalesOrders,
        openSalesOrders,
        confirmedSalesOrders,
        shippedSalesOrders,
        invoicedSalesOrders,
        totalValue: totalValue[0]?.total || 0,
      },
    });
  } catch (error) {
    console.error('Error fetching sales order stats:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch sales order statistics', 
      error: error.message 
    });
  }
});

// GET /api/sales-orders/:id - Get single sales order
router.get('/:id', [
  param('id').isMongoId().withMessage('Invalid sales order ID'),
  validateRequest,
], async (req, res) => {
  try {
    const salesOrder = await SalesOrder.findOne({
      _id: req.params.id,
      organizationId: req.user.organizationId || 'default_org',
    });
    
    if (!salesOrder) {
      return res.status(404).json({ 
        success: false, 
        message: 'Sales order not found' 
      });
    }
    
    res.json({
      success: true,
      data: salesOrder,
    });
  } catch (error) {
    console.error('Error fetching sales order:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch sales order', 
      error: error.message 
    });
  }
});

// POST /api/sales-orders - Create new sales order
router.post('/', salesOrderValidationRules, validateRequest, async (req, res) => {
  try {
    const organizationId = req.user.organizationId || 'default_org';
    
    console.log('✅ Creating sales order with organizationId:', organizationId);
    
    const salesOrderNumber = await generateSalesOrderNumber(organizationId);
    const totals = calculateSalesOrderTotals(
      req.body.items,
      req.body.tdsRate || 0,
      req.body.tcsRate || 0,
      req.body.gstRate || 18
    );
    
    const salesOrder = new SalesOrder({
      ...req.body,
      salesOrderNumber,
      organizationId,
      createdBy: req.user.userId,
      ...totals,
    });
    
    await salesOrder.save();
    
    console.log('✅ Sales order created successfully:', salesOrder.salesOrderNumber);
    
    res.status(201).json({
      success: true,
      message: 'Sales order created successfully',
      data: salesOrder,
    });
  } catch (error) {
    console.error('❌ Error creating sales order:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to create sales order', 
      error: error.message 
    });
  }
});

// POST /api/sales-orders/bulk-import - Bulk import sales orders
router.post('/bulk-import', [
  body('salesOrders').isArray({ min: 1 }).withMessage('Sales orders array is required'),
  validateRequest,
], async (req, res) => {
  try {
    const organizationId = req.user.organizationId || 'default_org';
    const userId = req.user.userId;
    const salesOrdersData = req.body.salesOrders;
    
    console.log(`\n📦 Starting bulk import for ${salesOrdersData.length} sales orders...`);
    
    const results = {
      successCount: 0,
      failedCount: 0,
      totalProcessed: salesOrdersData.length,
      errors: [],
    };
    
    for (let i = 0; i < salesOrdersData.length; i++) {
      const soData = salesOrdersData[i];
      
      try {
        // Validate required fields
        if (!soData.customerName) throw new Error('Customer name is required');
        if (!soData.customerEmail) throw new Error('Customer email is required');
        if (!soData.salesOrderDate) throw new Error('Sales order date is required');
        if (!soData.subTotal || soData.subTotal <= 0) throw new Error('Sub total must be greater than 0');
        if (!soData.totalAmount || soData.totalAmount <= 0) throw new Error('Total amount must be greater than 0');
        
        // Validate status
        const validStatuses = ['DRAFT', 'OPEN', 'CONFIRMED', 'PACKED', 'SHIPPED', 'INVOICED', 'CLOSED', 'CANCELLED'];
        if (!validStatuses.includes(soData.status)) {
          throw new Error(`Invalid status. Must be one of: ${validStatuses.join(', ')}`);
        }
        
        // Generate sales order number
        let salesOrderNumber = soData.salesOrderNumber;
        if (!salesOrderNumber) {
          salesOrderNumber = await generateSalesOrderNumber(organizationId);
        } else {
          const existingSO = await SalesOrder.findOne({ organizationId, salesOrderNumber });
          if (existingSO) {
            salesOrderNumber = await generateSalesOrderNumber(organizationId);
            console.log(`   ⚠️  SO number ${soData.salesOrderNumber} exists, generated new: ${salesOrderNumber}`);
          }
        }
        
        // Create dummy item if no items provided
        let items = [];
        if (!soData.items || soData.items.length === 0) {
          items = [{
            itemDetails: soData.subject || 'Service',
            quantity: 1,
            rate: soData.subTotal || 0,
            discount: 0,
            discountType: 'percentage',
            amount: soData.subTotal || 0,
          }];
        } else {
          items = soData.items;
        }
        
        const customerId = soData.customerId || `CUST-${Date.now()}-${i}`;
        
        const salesOrder = new SalesOrder({
          organizationId,
          salesOrderNumber,
          referenceNumber: soData.referenceNumber || '',
          customerId,
          customerName: soData.customerName,
          customerEmail: soData.customerEmail,
          customerPhone: soData.customerPhone || '',
          salesOrderDate: new Date(soData.salesOrderDate),
          expectedShipmentDate: soData.expectedShipmentDate ? new Date(soData.expectedShipmentDate) : null,
          paymentTerms: soData.paymentTerms || 'Net 30',
          deliveryMethod: soData.deliveryMethod || '',
          salesperson: soData.salesperson || '',
          subject: soData.subject || '',
          items,
          subTotal: soData.subTotal,
          tdsRate: soData.tdsRate || 0,
          tdsAmount: soData.tdsAmount || 0,
          tcsRate: soData.tcsRate || 0,
          tcsAmount: soData.tcsAmount || 0,
          gstRate: soData.gstRate || 18,
          cgst: soData.cgst || 0,
          sgst: soData.sgst || 0,
          igst: soData.igst || 0,
          totalAmount: soData.totalAmount,
          customerNotes: soData.customerNotes || '',
          termsAndConditions: soData.termsConditions || '',
          status: soData.status,
          createdBy: userId,
        });
        
        await salesOrder.save();
        
        results.successCount++;
        console.log(`   ✅ Successfully imported sales order: ${salesOrderNumber}`);
        
      } catch (error) {
        results.failedCount++;
        const errorMsg = `SO ${i + 1} (${soData.salesOrderNumber || 'N/A'}): ${error.message}`;
        results.errors.push(errorMsg);
        console.log(`   ❌ Failed to import: ${errorMsg}`);
      }
    }
    
    console.log(`\n📊 Bulk import completed:`);
    console.log(`   ✅ Success: ${results.successCount}`);
    console.log(`   ❌ Failed: ${results.failedCount}`);
    
    res.status(200).json({
      success: true,
      message: `Bulk import completed. ${results.successCount} sales orders imported, ${results.failedCount} failed.`,
      data: results,
    });
    
  } catch (error) {
    console.error('❌ Error in bulk import:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to process bulk import',
      error: error.message,
    });
  }
});

// PUT /api/sales-orders/:id - Update sales order
router.put('/:id', [
  param('id').isMongoId().withMessage('Invalid sales order ID'),
  ...salesOrderValidationRules,
  validateRequest,
], async (req, res) => {
  try {
    const salesOrder = await SalesOrder.findOne({
      _id: req.params.id,
      organizationId: req.user.organizationId || 'default_org',
    });
    
    if (!salesOrder) {
      return res.status(404).json({ 
        success: false, 
        message: 'Sales order not found' 
      });
    }
    
    if (!salesOrder.canEdit()) {
      return res.status(400).json({ 
        success: false, 
        message: 'Cannot edit invoiced, closed, cancelled, or void sales orders' 
      });
    }
    
    const totals = calculateSalesOrderTotals(
      req.body.items,
      req.body.tdsRate || 0,
      req.body.tcsRate || 0,
      req.body.gstRate || 18
    );
    
    Object.assign(salesOrder, req.body, totals);
    salesOrder.updatedBy = req.user.userId;
    
    await salesOrder.save();
    
    res.json({
      success: true,
      message: 'Sales order updated successfully',
      data: salesOrder,
    });
  } catch (error) {
    console.error('Error updating sales order:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to update sales order', 
      error: error.message 
    });
  }
});

// DELETE /api/sales-orders/:id - Delete sales order
router.delete('/:id', [
  param('id').isMongoId().withMessage('Invalid sales order ID'),
  validateRequest,
], async (req, res) => {
  try {
    const salesOrder = await SalesOrder.findOne({
      _id: req.params.id,
      organizationId: req.user.organizationId || 'default_org',
    });
    
    if (!salesOrder) {
      return res.status(404).json({ 
        success: false, 
        message: 'Sales order not found' 
      });
    }
    
    await salesOrder.deleteOne();
    
    res.json({
      success: true,
      message: 'Sales order deleted successfully',
    });
  } catch (error) {
    console.error('Error deleting sales order:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to delete sales order', 
      error: error.message 
    });
  }
});

// POST /api/sales-orders/:id/send - Send sales order via email
router.post('/:id/send', [
  param('id').isMongoId().withMessage('Invalid sales order ID'),
  validateRequest,
], async (req, res) => {
  try {
    const organizationId = req.user.organizationId || 'default_org';
    
    const salesOrder = await SalesOrder.findOne({
      _id: req.params.id,
      organizationId: organizationId,
    });
    
    if (!salesOrder) {
      return res.status(404).json({ 
        success: false, 
        message: 'Sales order not found' 
      });
    }
    
    if (!salesOrder.customerEmail) {
      return res.status(400).json({ 
        success: false, 
        message: 'Customer email is required to send sales order' 
      });
    }
    
    // Generate PDF
    const pdfInfo = await generateSalesOrderPDF(salesOrder);
    const pdfBuffer = fs.readFileSync(pdfInfo.filepath);
    
    // Send email
    await sendSalesOrderEmail(salesOrder, pdfBuffer);
    
    // Update status
    if (salesOrder.status === 'DRAFT') {
      salesOrder.status = 'OPEN';
    }
    
    salesOrder.emailsSent.push({
      sentTo: salesOrder.customerEmail,
      sentAt: new Date(),
      emailType: 'sales_order',
    });
    
    salesOrder.pdfPath = pdfInfo.filepath;
    salesOrder.pdfGeneratedAt = new Date();
    
    await salesOrder.save();
    
    res.json({
      success: true,
      message: 'Sales order sent successfully',
      data: salesOrder,
    });
  } catch (error) {
    console.error('Error sending sales order:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to send sales order', 
      error: error.message 
    });
  }
});

// GET /api/sales-orders/:id/download - Download PDF
router.get('/:id/download', [
  param('id').isMongoId().withMessage('Invalid sales order ID'),
  validateRequest,
], async (req, res) => {
  try {
    const salesOrder = await SalesOrder.findOne({
      _id: req.params.id,
      organizationId: req.user.organizationId || 'default_org',
    });
    
    if (!salesOrder) {
      return res.status(404).json({ 
        success: false, 
        message: 'Sales order not found' 
      });
    }
    
    // Generate PDF
    if (!salesOrder.pdfPath || !fs.existsSync(salesOrder.pdfPath)) {
      const pdfInfo = await generateSalesOrderPDF(salesOrder);
      salesOrder.pdfPath = pdfInfo.filepath;
      salesOrder.pdfGeneratedAt = new Date();
      await salesOrder.save();
    }
    
    res.download(salesOrder.pdfPath, `${salesOrder.salesOrderNumber}.pdf`);
  } catch (error) {
    console.error('Error downloading PDF:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to download PDF', 
      error: error.message 
    });
  }
});

// POST /api/sales-orders/:id/confirm - Confirm sales order
router.post('/:id/confirm', [
  param('id').isMongoId().withMessage('Invalid sales order ID'),
  validateRequest,
], async (req, res) => {
  try {
    const salesOrder = await SalesOrder.findOne({
      _id: req.params.id,
      organizationId: req.user.organizationId || 'default_org',
    });
    
    if (!salesOrder) {
      return res.status(404).json({ 
        success: false, 
        message: 'Sales order not found' 
      });
    }
    
    salesOrder.status = 'CONFIRMED';
    await salesOrder.save();
    
    res.json({
      success: true,
      message: 'Sales order confirmed successfully',
      data: salesOrder,
    });
  } catch (error) {
    console.error('Error confirming sales order:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to confirm sales order', 
      error: error.message 
    });
  }
});

// POST /api/sales-orders/:id/convert-to-invoice - Convert to invoice
router.post('/:id/convert-to-invoice', [
  param('id').isMongoId().withMessage('Invalid sales order ID'),
  validateRequest,
], async (req, res) => {
  try {
    const salesOrder = await SalesOrder.findOne({
      _id: req.params.id,
      organizationId: req.user.organizationId || 'default_org',
    });
    
    if (!salesOrder) {
      return res.status(404).json({ 
        success: false, 
        message: 'Sales order not found' 
      });
    }
    
    if (!salesOrder.canConvert()) {
      return res.status(400).json({ 
        success: false, 
        message: 'Only confirmed, open, packed, or shipped sales orders can be converted to invoices' 
      });
    }
    
    // Import Invoice model
    const Invoice = mongoose.model('Invoice');
    
    // Generate invoice number
    const date = new Date();
    const year = date.getFullYear().toString().slice(-2);
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    
    const lastInvoice = await Invoice.findOne({
      invoiceNumber: new RegExp(`^INV-${year}${month}`)
    }).sort({ invoiceNumber: -1 });
    
    let sequence = 1;
    if (lastInvoice) {
      const lastSequence = parseInt(lastInvoice.invoiceNumber.split('-')[2]);
      sequence = lastSequence + 1;
    }
    
    const invoiceNumber = `INV-${year}${month}-${sequence.toString().padStart(4, '0')}`;
    
    const invoiceDate = new Date();
    const dueDate = new Date(invoiceDate);
    
    // Calculate due date based on payment terms
    switch (salesOrder.paymentTerms) {
      case 'Due on Receipt':
        break;
      case 'Net 15':
        dueDate.setDate(dueDate.getDate() + 15);
        break;
      case 'Net 30':
        dueDate.setDate(dueDate.getDate() + 30);
        break;
      case 'Net 45':
        dueDate.setDate(dueDate.getDate() + 45);
        break;
      case 'Net 60':
        dueDate.setDate(dueDate.getDate() + 60);
        break;
      default:
        dueDate.setDate(dueDate.getDate() + 30);
    }
    
    const organizationId = req.user.organizationId || 'default_org';
    
    // Create invoice from sales order
    const invoice = new Invoice({
      organizationId: organizationId,
      invoiceNumber: invoiceNumber,
      customerId: salesOrder.customerId,
      customerName: salesOrder.customerName,
      customerEmail: salesOrder.customerEmail,
      customerPhone: salesOrder.customerPhone,
      orderNumber: salesOrder.salesOrderNumber,
      invoiceDate: invoiceDate,
      terms: salesOrder.paymentTerms,
      dueDate: dueDate,
      salesperson: salesOrder.salesperson,
      subject: salesOrder.subject,
      items: salesOrder.items.map(item => ({
        itemDetails: item.itemDetails,
        quantity: item.quantity,
        rate: item.rate,
        discount: item.discount || 0,
        discountType: item.discountType || 'percentage',
        amount: item.amount
      })),
      customerNotes: salesOrder.customerNotes,
      termsAndConditions: salesOrder.termsAndConditions,
      subTotal: salesOrder.subTotal,
      tdsRate: salesOrder.tdsRate || 0,
      tdsAmount: salesOrder.tdsAmount || 0,
      tcsRate: salesOrder.tcsRate || 0,
      tcsAmount: salesOrder.tcsAmount || 0,
      gstRate: salesOrder.gstRate || 18,
      cgst: salesOrder.cgst || 0,
      sgst: salesOrder.sgst || 0,
      igst: salesOrder.igst || 0,
      totalAmount: salesOrder.totalAmount,
      status: 'DRAFT',
      amountPaid: 0,
      amountDue: salesOrder.totalAmount,
      createdBy: req.user.userId,
    });
    
    await invoice.save();
    
    // Update sales order
    salesOrder.status = 'INVOICED';
    salesOrder.convertedToInvoice = true;
    salesOrder.convertedToInvoiceId = invoice._id.toString();
    salesOrder.convertedToInvoiceNumber = invoiceNumber;
    salesOrder.convertedDate = new Date();
    await salesOrder.save();
    
    console.log(`✅ Sales order ${salesOrder.salesOrderNumber} converted to invoice ${invoiceNumber}`);
    
    res.json({
      success: true,
      message: 'Sales order converted to invoice successfully',
      data: {
        salesOrder: salesOrder,
        invoice: invoice
      },
    });
  } catch (error) {
    console.error('❌ Error converting sales order to invoice:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to convert sales order to invoice', 
      error: error.message 
    });
  }
});

module.exports = router;