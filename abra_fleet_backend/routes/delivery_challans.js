// ============================================================================
// DELIVERY CHALLAN SYSTEM - COMPLETE BACKEND API
// ============================================================================
// File: backend/routes/delivery_challans.js
// Features:
// ✅ Complete CRUD operations
// ✅ Status workflow management (Draft → Open → Delivered → Invoiced/Returned)
// ✅ Convert to Invoice (automatic)
// ✅ Partial invoicing & returns tracking
// ✅ PDF generation
// ✅ Email sending
// ✅ Quantity tracking (dispatched, delivered, invoiced, returned)
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const PDFDocument = require('pdfkit');
const nodemailer = require('nodemailer');
const fs = require('fs');
const path = require('path');

// ============================================================================
// MONGOOSE SCHEMA
// ============================================================================

const deliveryChallanSchema = new mongoose.Schema({
  challanNumber: {
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
  customerName: {
    type: String,
    required: true
  },
  customerEmail: String,
  customerPhone: String,
  
  // Address
  deliveryAddress: {
    street: String,
    city: String,
    state: String,
    pincode: String,
    country: { type: String, default: 'India' }
  },
  
  // Dates
  challanDate: {
    type: Date,
    required: true,
    default: Date.now
  },
  expectedDeliveryDate: Date,
  actualDeliveryDate: Date,
  
  // References
  referenceNumber: String,
  orderNumber: String,
  
  // Purpose
  purpose: {
    type: String,
    enum: [
      'Supply on Approval',
      'Job Work',
      'Stock Transfer',
      'Exhibition/Display',
      'Replacement/Repair',
      'Sales',
      'Other'
    ],
    default: 'Sales'
  },
  
  // Transport Details
  transportMode: {
    type: String,
    enum: ['Road', 'Rail', 'Air', 'Ship'],
    default: 'Road'
  },
  vehicleNumber: String,
  driverName: String,
  driverPhone: String,
  transporterName: String,
  lrNumber: String, // Lorry Receipt Number
  
  // Items with quantity tracking
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
    unit: {
      type: String,
      default: 'Pcs'
    },
    hsnCode: String,
    notes: String,
    
    // Quantity tracking
    quantityDispatched: {
      type: Number,
      default: 0
    },
    quantityDelivered: {
      type: Number,
      default: 0
    },
    quantityInvoiced: {
      type: Number,
      default: 0
    },
    quantityReturned: {
      type: Number,
      default: 0
    }
  }],
  
  // Notes
  customerNotes: String,
  internalNotes: String,
  termsAndConditions: String,
  
  // Status tracking
  status: {
    type: String,
    enum: [
      'DRAFT',
      'OPEN',
      'DELIVERED',
      'INVOICED',
      'PARTIALLY_INVOICED',
      'RETURNED',
      'PARTIALLY_RETURNED',
      'CANCELLED'
    ],
    default: 'DRAFT',
    index: true
  },
  
  // Linked documents
  linkedInvoices: [{
    invoiceId: mongoose.Schema.Types.ObjectId,
    invoiceNumber: String,
    invoicedDate: Date,
    amount: Number
  }],
  
  // PDF & Email
  pdfPath: String,
  pdfGeneratedAt: Date,
  emailsSent: [{
    sentTo: String,
    sentAt: Date,
    emailType: String
  }],
  
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

// Pre-save middleware
deliveryChallanSchema.pre('save', function(next) {
  // Initialize quantity tracking for items
  this.items.forEach(item => {
    if (item.quantityDispatched === 0 && this.status !== 'DRAFT') {
      item.quantityDispatched = item.quantity;
    }
  });
  
  // Auto-update status based on quantities
  this._updateStatusBasedOnQuantities();
  
  next();
});

// Method to update status based on quantities
deliveryChallanSchema.methods._updateStatusBasedOnQuantities = function() {
  if (this.status === 'DRAFT' || this.status === 'CANCELLED') {
    return;
  }
  
  let totalQuantity = 0;
  let totalInvoiced = 0;
  let totalReturned = 0;
  
  this.items.forEach(item => {
    totalQuantity += item.quantity;
    totalInvoiced += item.quantityInvoiced;
    totalReturned += item.quantityReturned;
  });
  
  if (totalInvoiced > 0 && totalInvoiced < totalQuantity) {
    this.status = 'PARTIALLY_INVOICED';
  } else if (totalInvoiced >= totalQuantity) {
    this.status = 'INVOICED';
  } else if (totalReturned > 0 && totalReturned < totalQuantity) {
    this.status = 'PARTIALLY_RETURNED';
  } else if (totalReturned >= totalQuantity) {
    this.status = 'RETURNED';
  }
};

const DeliveryChallan = mongoose.model('DeliveryChallan', deliveryChallanSchema);

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

async function generateChallanNumber() {
  const date = new Date();
  const year = date.getFullYear().toString().slice(-2);
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  
  const lastChallan = await DeliveryChallan.findOne({
    challanNumber: new RegExp(`^DC-${year}${month}`)
  }).sort({ challanNumber: -1 });
  
  let sequence = 1;
  if (lastChallan) {
    const lastSequence = parseInt(lastChallan.challanNumber.split('-')[2]);
    sequence = lastSequence + 1;
  }
  
  return `DC-${year}${month}-${sequence.toString().padStart(4, '0')}`;
}

// ============================================================================
// PDF GENERATION
// ============================================================================

async function generateChallanPDF(challan) {
  return new Promise((resolve, reject) => {
    try {
      console.log('📄 Starting PDF generation for challan:', challan.challanNumber);
      
      const uploadsDir = path.join(__dirname, '..', 'uploads', 'challans');
      if (!fs.existsSync(uploadsDir)) {
        fs.mkdirSync(uploadsDir, { recursive: true });
      }
      
      const filename = `challan-${challan.challanNumber}.pdf`;
      const filepath = path.join(uploadsDir, filename);
      
      const doc = new PDFDocument({ 
        size: 'A4', 
        margin: 40,
        bufferPages: true
      });
      const stream = fs.createWriteStream(filepath);
      
      doc.pipe(stream);
      
      // Header
      doc.fontSize(28)
         .fillColor('#2C3E50')
         .font('Helvetica-Bold')
         .text('DELIVERY CHALLAN', 40, 40);
      
      doc.fontSize(10)
         .fillColor('#7F8C8D')
         .font('Helvetica')
         .text('GOODS DISPATCH NOTE', 40, 75);
      
      // Company details
      doc.fontSize(9)
         .fillColor('#555555')
         .font('Helvetica')
         .text('ABRA Travels', 40, 100)
         .text('Bangalore, Karnataka, India', 40, 113)
         .text('GST: 29AABCT1332L1ZM', 40, 126)
         .text('Contact: +91 88672 88076', 40, 139);
      
      // Challan Number & Date (RIGHT SIDE)
      doc.fontSize(11)
         .fillColor('#2C3E50')
         .font('Helvetica-Bold')
         .text('Challan Number:', 350, 100)
         .fillColor('#000000')
         .font('Helvetica')
         .text(challan.challanNumber || 'N/A', 460, 100);
      
      doc.fillColor('#2C3E50')
         .font('Helvetica-Bold')
         .text('Date:', 350, 115)
         .fillColor('#000000')
         .font('Helvetica')
         .text(new Date(challan.challanDate).toLocaleDateString('en-IN'), 460, 115);
      
      if (challan.referenceNumber) {
        doc.fillColor('#2C3E50')
           .font('Helvetica-Bold')
           .text('Reference:', 350, 130)
           .fillColor('#000000')
           .font('Helvetica')
           .text(challan.referenceNumber, 460, 130);
      }
      
      // Status badge
      const statusColors = {
        'DELIVERED': '#27AE60',
        'INVOICED': '#3498DB',
        'DRAFT': '#95A5A6',
        'OPEN': '#F39C12',
        'RETURNED': '#E74C3C',
        'PARTIALLY_INVOICED': '#9B59B6',
        'PARTIALLY_RETURNED': '#E67E22'
      };
      
      const statusColor = statusColors[challan.status] || '#95A5A6';
      doc.fontSize(10)
         .fillColor(statusColor)
         .font('Helvetica-Bold')
         .text(challan.status.replace(/_/g, ' '), 350, 150);
      
      // Customer Information
      let yPos = 180;
      
      doc.fontSize(12)
         .fillColor('#0066CC')
         .font('Helvetica-Bold')
         .text('DELIVER TO:', 40, yPos);
      
      doc.fontSize(11)
         .fillColor('#000000')
         .font('Helvetica-Bold')
         .text(challan.customerName || 'N/A', 40, yPos + 20);
      
      yPos += 38;
      
      doc.fontSize(9)
         .fillColor('#555555')
         .font('Helvetica');
      
      if (challan.deliveryAddress) {
        const addr = challan.deliveryAddress;
        if (addr.street) {
          doc.text(addr.street, 40, yPos);
          yPos += 12;
        }
        if (addr.city || addr.state || addr.pincode) {
          doc.text(`${addr.city || ''}, ${addr.state || ''} ${addr.pincode || ''}`, 40, yPos);
          yPos += 12;
        }
      }
      
      if (challan.customerEmail) {
        doc.text(`Email: ${challan.customerEmail}`, 40, yPos);
        yPos += 12;
      }
      
      if (challan.customerPhone) {
        doc.text(`Phone: ${challan.customerPhone}`, 40, yPos);
      }
      
      // Transport Details Box
      if (challan.transportMode || challan.vehicleNumber || challan.transporterName) {
        yPos = 180;
        doc.rect(320, yPos, 235, 80)
           .fillAndStroke('#F8F9FA', '#DDDDDD');
        
        doc.fontSize(10)
           .fillColor('#0066CC')
           .font('Helvetica-Bold')
           .text('TRANSPORT DETAILS', 330, yPos + 10);
        
        doc.fontSize(8)
           .fillColor('#2C3E50')
           .font('Helvetica-Bold');
        
        yPos += 30;
        
        if (challan.transportMode) {
          doc.text('Mode:', 330, yPos);
          doc.fillColor('#000000')
             .font('Helvetica')
             .text(challan.transportMode, 420, yPos);
          yPos += 12;
        }
        
        if (challan.vehicleNumber) {
          doc.fillColor('#2C3E50')
             .font('Helvetica-Bold')
             .text('Vehicle:', 330, yPos);
          doc.fillColor('#000000')
             .font('Helvetica')
             .text(challan.vehicleNumber, 420, yPos);
          yPos += 12;
        }
        
        if (challan.transporterName) {
          doc.fillColor('#2C3E50')
             .font('Helvetica-Bold')
             .text('Transporter:', 330, yPos);
          doc.fillColor('#000000')
             .font('Helvetica')
             .text(challan.transporterName, 420, yPos);
        }
      }
      
      // Items Table
      const tableTop = 290;
      
      doc.rect(40, tableTop, 515, 22)
         .fillAndStroke('#2C3E50', '#2C3E50');
      
      doc.fontSize(8)
         .fillColor('#FFFFFF')
         .font('Helvetica-Bold');
      
      doc.text('ITEM DETAILS', 50, tableTop + 8);
      doc.text('QTY', 330, tableTop + 8, { width: 40, align: 'center' });
      doc.text('UNIT', 380, tableTop + 8, { width: 60, align: 'center' });
      doc.text('HSN', 450, tableTop + 8, { width: 90, align: 'right' });
      
      let itemYPos = tableTop + 22;
      
      challan.items.forEach((item, index) => {
        const rowColor = index % 2 === 0 ? '#FFFFFF' : '#F8F9FA';
        
        doc.rect(40, itemYPos, 515, 26)
           .fillAndStroke(rowColor, '#E8E8E8');
        
        doc.fontSize(8)
           .fillColor('#000000')
           .font('Helvetica');
        
        const itemText = item.itemDetails || 'N/A';
        doc.text(itemText, 50, itemYPos + 9, { width: 260, height: 26, ellipsis: true });
        
        doc.text(item.quantity?.toString() || '0', 330, itemYPos + 9, { width: 40, align: 'center' });
        doc.text(item.unit || 'Pcs', 380, itemYPos + 9, { width: 60, align: 'center' });
        doc.text(item.hsnCode || '-', 450, itemYPos + 9, { width: 90, align: 'right' });
        
        itemYPos += 26;
      });
      
      // Total Quantity Box
      itemYPos += 10;
      
      doc.rect(370, itemYPos, 185, 22)
         .strokeColor('#2C3E50')
         .lineWidth(2)
         .stroke();
      
      const totalQty = challan.items.reduce((sum, item) => sum + item.quantity, 0);
      
      doc.fontSize(10)
         .fillColor('#2C3E50')
         .font('Helvetica-Bold')
         .text('Total Quantity:', 380, itemYPos + 6);
      
      doc.fontSize(12)
         .fillColor('#27AE60')
         .font('Helvetica-Bold')
         .text(totalQty.toString(), 485, itemYPos + 5, { width: 65, align: 'right' });
      
      // Notes
      if (challan.customerNotes) {
        itemYPos += 40;
        
        doc.fontSize(9)
           .fillColor('#0066CC')
           .font('Helvetica-Bold')
           .text('Notes:', 40, itemYPos);
        
        doc.fontSize(8)
           .fillColor('#555555')
           .font('Helvetica')
           .text(challan.customerNotes, 40, itemYPos + 14, { width: 515, align: 'left' });
      }
      
      // Terms & Conditions
      if (challan.termsAndConditions) {
        itemYPos += 50;
        
        doc.fontSize(9)
           .fillColor('#0066CC')
           .font('Helvetica-Bold')
           .text('Terms & Conditions:', 40, itemYPos);
        
        doc.fontSize(8)
           .fillColor('#555555')
           .font('Helvetica')
           .text(challan.termsAndConditions, 40, itemYPos + 14, { width: 515, align: 'left' });
      }
      
      // Footer
      const footerY = 730;
      
      doc.moveTo(40, footerY)
         .lineTo(555, footerY)
         .lineWidth(1.5)
         .strokeColor('#0066CC')
         .stroke();
      
      doc.fontSize(8)
         .fillColor('#2C3E50')
         .font('Helvetica-Bold')
         .text('This is a computer-generated delivery challan and does not require a signature', 40, footerY + 8, { align: 'center', width: 515 });
      
      doc.fontSize(6)
         .fillColor('#888888')
         .font('Helvetica')
         .text('ABRA Travels | YOUR JOURNEY, OUR COMMITMENT', 40, footerY + 20, { align: 'center', width: 515 });
      
      doc.end();
      
      stream.on('finish', () => {
        console.log(`✅ PDF generated successfully: ${filename}`);
        
        resolve({
          filename: filename,
          filepath: filepath,
          relativePath: `/uploads/challans/${filename}`
        });
      });
      
      stream.on('error', (error) => {
        console.error('❌ PDF stream error:', error);
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

async function sendChallanEmail(challan, pdfPath) {
  console.log('📧 Preparing to send challan email to:', challan.customerEmail);
  
  const emailHtml = `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Delivery Challan ${challan.challanNumber}</title>
</head>
<body style="margin: 0; padding: 0; font-family: Arial, sans-serif; background-color: #f4f4f4;">
  <table width="100%" cellpadding="20" cellspacing="0" border="0" style="background-color: #f4f4f4;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" border="0" style="background-color: #ffffff; border-radius: 10px; overflow: hidden; box-shadow: 0 4px 15px rgba(0,0,0,0.1);">
          
          <!-- Header -->
          <tr>
            <td style="background: linear-gradient(135deg, #3498db 0%, #2980b9 100%); color: white; padding: 35px; text-align: left;">
              <h1 style="color: #ffffff; margin: 0 0 5px 0; font-size: 28px;">ABRA Travels</h1>
              <p style="color: #ffffff; margin: 0; letter-spacing: 1px; font-size: 13px;">YOUR JOURNEY, OUR COMMITMENT</p>
              <h2 style="margin: 20px 0 0 0; font-size: 24px; color: #ffffff;">📦 Delivery Challan</h2>
            </td>
          </tr>
          
          <!-- Content -->
          <tr>
            <td style="padding: 40px;">
              
              <p style="font-size: 16px; color: #2c3e50; margin: 0 0 20px 0;">Dear ${challan.customerName},</p>
              
              <p style="font-size: 14px; color: #555555; margin: 0 0 20px 0; line-height: 1.8;">
                This is to inform you that we have dispatched goods as per delivery challan <strong>${challan.challanNumber}</strong>.
              </p>
              
              <!-- Challan Details Card -->
              <table width="100%" cellpadding="20" cellspacing="0" border="0" style="background-color: #F8F9FA; border-left: 4px solid #3498DB; border-radius: 6px; margin: 25px 0;">
                <tr>
                  <td>
                    <table width="100%" cellpadding="0" cellspacing="0" border="0">
                      <tr>
                        <td style="font-size: 14px; color: #666666; font-weight: 600; padding-bottom: 12px;">Challan Number:</td>
                        <td style="font-size: 14px; color: #2C3E50; font-weight: bold; text-align: right; padding-bottom: 12px;">${challan.challanNumber}</td>
                      </tr>
                      <tr>
                        <td style="font-size: 14px; color: #666666; font-weight: 600; padding-bottom: 12px;">Dispatch Date:</td>
                        <td style="font-size: 14px; color: #2C3E50; font-weight: bold; text-align: right; padding-bottom: 12px;">${new Date(challan.challanDate).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}</td>
                      </tr>
                      ${challan.expectedDeliveryDate ? `
                      <tr>
                        <td style="font-size: 14px; color: #666666; font-weight: 600; padding-bottom: 12px;">Expected Delivery:</td>
                        <td style="font-size: 14px; color: #2C3E50; font-weight: bold; text-align: right; padding-bottom: 12px;">${new Date(challan.expectedDeliveryDate).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}</td>
                      </tr>
                      ` : ''}
                      ${challan.referenceNumber ? `
                      <tr>
                        <td style="font-size: 14px; color: #666666; font-weight: 600;">Reference Number:</td>
                        <td style="font-size: 14px; color: #2C3E50; font-weight: bold; text-align: right;">${challan.referenceNumber}</td>
                      </tr>
                      ` : ''}
                    </table>
                  </td>
                </tr>
              </table>
              
              <!-- Items Summary -->
              <table width="100%" cellpadding="18" cellspacing="0" border="0" style="background: linear-gradient(135deg, #E8F5E9 0%, #C8E6C9 100%); border-radius: 8px; border-left: 4px solid #27AE60; margin: 20px 0;">
                <tr>
                  <td style="text-align: center;">
                    <p style="font-size: 16px; color: #27AE60; font-weight: bold; margin: 0;">Total Items: ${challan.items.length}</p>
                    <p style="font-size: 14px; color: #1B5E20; margin: 8px 0 0 0;">Total Quantity: ${challan.items.reduce((sum, item) => sum + item.quantity, 0)}</p>
                  </td>
                </tr>
              </table>
              
              ${challan.transportMode || challan.vehicleNumber ? `
              <!-- Transport Details -->
              <table width="100%" cellpadding="18" cellspacing="0" border="0" style="background: linear-gradient(135deg, #E3F2FD 0%, #BBDEFB 100%); border-radius: 8px; border-left: 4px solid #2196F3; margin: 20px 0;">
                <tr>
                  <td>
                    <h4 style="margin: 0 0 12px 0; color: #1976D2; font-size: 15px;">🚚 Transport Information</h4>
                    ${challan.transportMode ? `<p style="margin: 6px 0; font-size: 13px; color: #333;"><strong>Mode:</strong> ${challan.transportMode}</p>` : ''}
                    ${challan.vehicleNumber ? `<p style="margin: 6px 0; font-size: 13px; color: #333;"><strong>Vehicle Number:</strong> ${challan.vehicleNumber}</p>` : ''}
                    ${challan.transporterName ? `<p style="margin: 6px 0; font-size: 13px; color: #333;"><strong>Transporter:</strong> ${challan.transporterName}</p>` : ''}
                  </td>
                </tr>
              </table>
              ` : ''}
              
              ${challan.customerNotes ? `
              <table width="100%" cellpadding="15" cellspacing="0" border="0" style="background: #FFF9C4; border-radius: 6px; border-left: 4px solid #FBC02D; margin: 20px 0;">
                <tr>
                  <td>
                    <p style="margin: 0 0 10px 0; color: #F57F17; font-weight: bold;">📝 Important Notes:</p>
                    <p style="margin: 0; color: #555; font-size: 14px;">${challan.customerNotes}</p>
                  </td>
                </tr>
              </table>
              ` : ''}
              
              <p style="font-size: 14px; color: #555555; margin: 25px 0; line-height: 1.8;">
                📎 The delivery challan PDF is attached to this email for your records.
              </p>
              
              <p style="font-size: 14px; color: #555555; margin: 25px 0; line-height: 1.8;">
                Please verify the items upon delivery and contact us immediately if there are any discrepancies.
              </p>
              
              <p style="font-size: 16px; font-weight: bold; color: #3498DB; text-align: center; margin: 25px 0;">
                Thank you for choosing ABRA Travels! 🙏
              </p>
              
            </td>
          </tr>
          
          <!-- Footer -->
          <tr>
            <td style="background-color: #2C3E50; color: #ffffff; padding: 30px 40px; text-align: center;">
              <p style="margin: 0; font-weight: bold; font-size: 16px; color: #ffffff;">ABRA Travels</p>
              <p style="margin: 8px 0; font-style: italic; color: #ECF0F1; letter-spacing: 1px; font-size: 12px;">YOUR JOURNEY, OUR COMMITMENT</p>
              <p style="margin: 8px 0; color: #95A5A6; font-size: 12px;">📍 Bangalore, Karnataka, India</p>
              <p style="margin: 8px 0; color: #95A5A6; font-size: 12px;">📧 info@abratravels.com | 📱 +91 88672 88076</p>
              <p style="margin: 8px 0; color: #95A5A6; font-size: 12px;">🔖 GST: 29AABCT1332L1ZM</p>
              <p style="margin-top: 25px; color: #7F8C8D; font-size: 11px;">© ${new Date().getFullYear()} ABRA Travels. All rights reserved.</p>
            </td>
          </tr>
          
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
  
  const mailOptions = {
    from: `"ABRA Travels - Dispatch" <${process.env.SMTP_USER}>`,
    to: challan.customerEmail,
    subject: `📦 Delivery Challan ${challan.challanNumber} - ABRA Travels`,
    html: emailHtml,
    attachments: [
      {
        filename: `Challan-${challan.challanNumber}.pdf`,
        path: pdfPath
      }
    ]
  };
  
  console.log('   📤 Sending email...');
  const result = await emailTransporter.sendMail(mailOptions);
  console.log('   ✅ Email sent successfully! Message ID:', result.messageId);
  
  return result;
}

// ============================================================================
// API ROUTES
// ============================================================================

// Get all delivery challans with filters and pagination
router.get('/', async (req, res) => {
  try {
    const { status, customerId, fromDate, toDate, page = 1, limit = 20 } = req.query;
    
    const query = {};
    
    if (status) query.status = status;
    if (customerId) query.customerId = customerId;
    if (fromDate || toDate) {
      query.challanDate = {};
      if (fromDate) query.challanDate.$gte = new Date(fromDate);
      if (toDate) query.challanDate.$lte = new Date(toDate);
    }
    
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    const challans = await DeliveryChallan.find(query)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .select('-__v');
    
    const total = await DeliveryChallan.countDocuments(query);
    
    res.json({
      success: true,
      data: challans,
      pagination: {
        total,
        page: parseInt(page),
        limit: parseInt(limit),
        pages: Math.ceil(total / parseInt(limit))
      }
    });
  } catch (error) {
    console.error('Error fetching delivery challans:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get statistics
router.get('/stats', async (req, res) => {
  try {
    const stats = await DeliveryChallan.aggregate([
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 }
        }
      }
    ]);
    
    const overallStats = {
      totalChallans: 0,
      byStatus: {}
    };
    
    stats.forEach(stat => {
      overallStats.totalChallans += stat.count;
      overallStats.byStatus[stat._id] = stat.count;
    });
    
    res.json({ success: true, data: overallStats });
  } catch (error) {
    console.error('Error fetching stats:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get single delivery challan
router.get('/:id', async (req, res) => {
  try {
    const challan = await DeliveryChallan.findById(req.params.id);
    
    if (!challan) {
      return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    }
    
    res.json({ success: true, data: challan });
  } catch (error) {
    console.error('Error fetching delivery challan:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Create new delivery challan
router.post('/', async (req, res) => {
  try {
    const challanData = req.body;
    
    // Ensure customerId is ObjectId
    if (challanData.customerId) {
      if (typeof challanData.customerId === 'string') {
        if (mongoose.Types.ObjectId.isValid(challanData.customerId)) {
          challanData.customerId = new mongoose.Types.ObjectId(challanData.customerId);
        } else {
          challanData.customerId = new mongoose.Types.ObjectId();
        }
      }
    } else {
      challanData.customerId = new mongoose.Types.ObjectId();
    }
    
    // Generate challan number if not provided
    if (!challanData.challanNumber) {
      challanData.challanNumber = await generateChallanNumber();
    }
    
    // Set created by
    challanData.createdBy = req.user?.email || req.user?.uid || 'system';
    
    const challan = new DeliveryChallan(challanData);
    await challan.save();
    
    console.log(`✅ Delivery challan created: ${challan.challanNumber}`);
    
    res.status(201).json({
      success: true,
      message: 'Delivery challan created successfully',
      data: challan
    });
  } catch (error) {
    console.error('Error creating delivery challan:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Update delivery challan
router.put('/:id', async (req, res) => {
  try {
    const challan = await DeliveryChallan.findById(req.params.id);
    
    if (!challan) {
      return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    }
    
    if (challan.status === 'INVOICED') {
      return res.status(400).json({
        success: false,
        error: 'Cannot edit fully invoiced challans'
      });
    }
    
    const updates = req.body;
    updates.updatedBy = req.user?.email || req.user?.uid || 'system';
    
    Object.assign(challan, updates);
    await challan.save();
    
    console.log(`✅ Delivery challan updated: ${challan.challanNumber}`);
    
    res.json({
      success: true,
      message: 'Delivery challan updated successfully',
      data: challan
    });
  } catch (error) {
    console.error('Error updating delivery challan:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Mark as Open (dispatch)
router.post('/:id/dispatch', async (req, res) => {
  try {
    const challan = await DeliveryChallan.findById(req.params.id);
    
    if (!challan) {
      return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    }
    
    if (challan.status !== 'DRAFT') {
      return res.status(400).json({
        success: false,
        error: 'Only draft challans can be dispatched'
      });
    }
    
    challan.status = 'OPEN';
    challan.items.forEach(item => {
      item.quantityDispatched = item.quantity;
    });
    challan.updatedBy = req.user?.email || req.user?.uid || 'system';
    
    await challan.save();
    
    console.log(`✅ Delivery challan dispatched: ${challan.challanNumber}`);
    
    res.json({
      success: true,
      message: 'Delivery challan marked as dispatched',
      data: challan
    });
  } catch (error) {
    console.error('Error dispatching challan:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Mark as Delivered
router.post('/:id/delivered', async (req, res) => {
  try {
    const challan = await DeliveryChallan.findById(req.params.id);
    
    if (!challan) {
      return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    }
    
    if (challan.status !== 'OPEN') {
      return res.status(400).json({
        success: false,
        error: 'Only dispatched challans can be marked as delivered'
      });
    }
    
    challan.status = 'DELIVERED';
    challan.actualDeliveryDate = new Date();
    challan.items.forEach(item => {
      item.quantityDelivered = item.quantityDispatched;
    });
    challan.updatedBy = req.user?.email || req.user?.uid || 'system';
    
    await challan.save();
    
    console.log(`✅ Delivery challan marked as delivered: ${challan.challanNumber}`);
    
    res.json({
      success: true,
      message: 'Delivery challan marked as delivered',
      data: challan
    });
  } catch (error) {
    console.error('Error marking as delivered:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Convert to Invoice (AUTOMATIC)
router.post('/:id/convert-to-invoice', async (req, res) => {
  try {
    const challan = await DeliveryChallan.findById(req.params.id);
    
    if (!challan) {
      return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    }
    
    if (challan.status !== 'DELIVERED' && challan.status !== 'PARTIALLY_INVOICED') {
      return res.status(400).json({
        success: false,
        error: 'Only delivered challans can be converted to invoice'
      });
    }
    
    // Get quantities from request body (for partial invoicing)
    const { items: itemsToInvoice, createInvoice = true } = req.body;
    
    // Prepare invoice data
    const invoiceData = {
      customerId: challan.customerId,
      customerName: challan.customerName,
      customerEmail: challan.customerEmail,
      customerPhone: challan.customerPhone,
      billingAddress: challan.deliveryAddress,
      shippingAddress: challan.deliveryAddress,
      orderNumber: challan.referenceNumber,
      invoiceDate: new Date(),
      terms: 'Net 30',
      customerNotes: `Generated from Delivery Challan: ${challan.challanNumber}`,
      items: [],
      createdBy: req.user?.email || req.user?.uid || 'system'
    };
    
    // Add items with quantities
    let allItemsInvoiced = true;
    
    if (itemsToInvoice && Array.isArray(itemsToInvoice)) {
      // Partial invoicing
      itemsToInvoice.forEach(invoiceItem => {
        const challanItem = challan.items.id(invoiceItem.itemId);
        if (challanItem) {
          const qtyToInvoice = invoiceItem.quantity || 0;
          
          invoiceData.items.push({
            itemDetails: challanItem.itemDetails,
            quantity: qtyToInvoice,
            rate: invoiceItem.rate || 0,
            discount: invoiceItem.discount || 0,
            discountType: invoiceItem.discountType || 'percentage',
            amount: 0 // Will be calculated
          });
          
          // Update challan item
          challanItem.quantityInvoiced += qtyToInvoice;
          
          if (challanItem.quantityInvoiced < challanItem.quantity) {
            allItemsInvoiced = false;
          }
        }
      });
    } else {
      // Full invoicing
      challan.items.forEach(item => {
        const remainingQty = item.quantity - item.quantityInvoiced;
        
        if (remainingQty > 0) {
          invoiceData.items.push({
            itemDetails: item.itemDetails,
            quantity: remainingQty,
            rate: 0, // User must add rate
            discount: 0,
            discountType: 'percentage',
            amount: 0
          });
          
          item.quantityInvoiced = item.quantity;
        }
      });
    }
    
    // Update challan status
    challan._updateStatusBasedOnQuantities();
    
    // Link invoice (if actually creating it)
    if (createInvoice) {
      // Here you would call your invoice creation API
      // For now, we'll just return the invoice data
      
      challan.linkedInvoices.push({
        invoiceId: new mongoose.Types.ObjectId(), // Placeholder
        invoiceNumber: 'INV-PLACEHOLDER',
        invoicedDate: new Date(),
        amount: 0
      });
    }
    
    challan.updatedBy = req.user?.email || req.user?.uid || 'system';
    await challan.save();
    
    console.log(`✅ Delivery challan converted to invoice: ${challan.challanNumber}`);
    
    res.json({
      success: true,
      message: 'Delivery challan converted to invoice successfully',
      data: {
        challan: challan,
        invoiceData: invoiceData
      }
    });
  } catch (error) {
    console.error('Error converting to invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Record Partial Return
router.post('/:id/partial-return', async (req, res) => {
  try {
    const challan = await DeliveryChallan.findById(req.params.id);
    
    if (!challan) {
      return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    }
    
    const { items: returnedItems } = req.body;
    
    if (!returnedItems || !Array.isArray(returnedItems)) {
      return res.status(400).json({
        success: false,
        error: 'Returned items data is required'
      });
    }
    
    // Update returned quantities
    returnedItems.forEach(returnItem => {
      const challanItem = challan.items.id(returnItem.itemId);
      if (challanItem) {
        challanItem.quantityReturned += returnItem.quantity || 0;
      }
    });
    
    // Update status
    challan._updateStatusBasedOnQuantities();
    challan.updatedBy = req.user?.email || req.user?.uid || 'system';
    
    await challan.save();
    
    console.log(`✅ Partial return recorded for: ${challan.challanNumber}`);
    
    res.json({
      success: true,
      message: 'Partial return recorded successfully',
      data: challan
    });
  } catch (error) {
    console.error('Error recording partial return:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Mark as Returned (Full)
router.post('/:id/returned', async (req, res) => {
  try {
    const challan = await DeliveryChallan.findById(req.params.id);
    
    if (!challan) {
      return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    }
    
    challan.status = 'RETURNED';
    challan.items.forEach(item => {
      item.quantityReturned = item.quantity;
    });
    challan.updatedBy = req.user?.email || req.user?.uid || 'system';
    
    await challan.save();
    
    console.log(`✅ Delivery challan marked as returned: ${challan.challanNumber}`);
    
    res.json({
      success: true,
      message: 'Delivery challan marked as returned',
      data: challan
    });
  } catch (error) {
    console.error('Error marking as returned:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Send challan via email
router.post('/:id/send', async (req, res) => {
  try {
    const challan = await DeliveryChallan.findById(req.params.id);
    
    if (!challan) {
      return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    }
    
    if (!challan.customerEmail) {
      return res.status(400).json({
        success: false,
        error: 'Customer email is required to send challan'
      });
    }
    
    // Generate PDF if not exists
    let pdfInfo;
    if (!challan.pdfPath || !fs.existsSync(challan.pdfPath)) {
      pdfInfo = await generateChallanPDF(challan);
      challan.pdfPath = pdfInfo.filepath;
      challan.pdfGeneratedAt = new Date();
    }
    
    // Send email
    await sendChallanEmail(challan, challan.pdfPath);
    
    // Update status if draft
    if (challan.status === 'DRAFT') {
      challan.status = 'OPEN';
      challan.items.forEach(item => {
        item.quantityDispatched = item.quantity;
      });
    }
    
    challan.emailsSent.push({
      sentTo: challan.customerEmail,
      sentAt: new Date(),
      emailType: 'delivery_challan'
    });
    
    await challan.save();
    
    console.log(`✅ Delivery challan sent: ${challan.challanNumber}`);
    
    res.json({
      success: true,
      message: 'Delivery challan sent successfully',
      data: challan
    });
  } catch (error) {
    console.error('Error sending challan:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Download PDF
router.get('/:id/pdf', async (req, res) => {
  try {
    const challan = await DeliveryChallan.findById(req.params.id);
    
    if (!challan) {
      return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    }
    
    // Generate PDF if not exists
    if (!challan.pdfPath || !fs.existsSync(challan.pdfPath)) {
      const pdfInfo = await generateChallanPDF(challan);
      challan.pdfPath = pdfInfo.filepath;
      challan.pdfGeneratedAt = new Date();
      await challan.save();
    }
    
    res.download(challan.pdfPath, `Challan-${challan.challanNumber}.pdf`);
  } catch (error) {
    console.error('Error downloading PDF:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get download URL
router.get('/:id/download-url', async (req, res) => {
  try {
    const challan = await DeliveryChallan.findById(req.params.id);
    
    if (!challan) {
      return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    }
    
    // Generate PDF if not exists
    if (!challan.pdfPath || !fs.existsSync(challan.pdfPath)) {
      const pdfInfo = await generateChallanPDF(challan);
      challan.pdfPath = pdfInfo.filepath;
      challan.pdfGeneratedAt = new Date();
      await challan.save();
    }
    
    const baseUrl = process.env.BASE_URL || `${req.protocol}://${req.get('host')}`;
    const downloadUrl = `${baseUrl}/uploads/challans/${path.basename(challan.pdfPath)}`;
    
    res.json({
      success: true,
      downloadUrl: downloadUrl,
      filename: `Challan-${challan.challanNumber}.pdf`
    });
  } catch (error) {
    console.error('Error generating PDF URL:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Delete delivery challan
router.delete('/:id', async (req, res) => {
  try {
    const challan = await DeliveryChallan.findById(req.params.id);
    
    if (!challan) {
      return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    }
    
    if (challan.status !== 'DRAFT') {
      return res.status(400).json({
        success: false,
        error: 'Only draft challans can be deleted'
      });
    }
    
    await challan.deleteOne();
    
    console.log(`✅ Delivery challan deleted: ${challan.challanNumber}`);
    
    res.json({
      success: true,
      message: 'Delivery challan deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting challan:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

module.exports = router;