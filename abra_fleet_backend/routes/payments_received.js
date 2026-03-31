// ============================================================================
// PAYMENTS RECEIVED ROUTES - ZOHO BOOKS EXACT WORKFLOW
// ============================================================================
// File: backend/routes/payments-received.js
// Workflow: Record Payment with Proofs → Update Invoice Status → Send Email with Proofs
// Email is sent ONLY when payment is recorded with proofs (not on "Mark as Paid")
// ============================================================================


const express = require('express');
const router = express.Router();
const { MongoClient, ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');
const { uploadPaymentProofs } = require('../middleware/upload');
const path = require('path');
const fs = require('fs');


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
// Import nodemailer - use dynamic import or check if it's properly installed
let nodemailer;
try {
  nodemailer = require('nodemailer');
  if (!nodemailer || !nodemailer.createTransport) {
    console.warn('⚠️ Nodemailer not properly loaded, email features will be disabled');
    nodemailer = null;
  }
} catch (error) {
  console.warn('⚠️ Nodemailer not available, email features will be disabled:', error.message);
  nodemailer = null;
}

// MongoDB connection
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';
let db;

MongoClient.connect(MONGODB_URI)
  .then(client => {
    console.log('✅ Connected to MongoDB for Payments Received');
    db = client.db();
  })
  .catch(error => console.error('❌ MongoDB connection error:', error));

// ============================================================================
// EMAIL SERVICE FOR PAYMENT RECEIPTS
// ============================================================================

let emailTransporter = null;
if (nodemailer) {
  try {
    emailTransporter = nodemailer.createTransporter({
      host: process.env.SMTP_HOST || 'smtp.gmail.com',
      port: process.env.SMTP_PORT || 587,
      secure: false,
      auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASSWORD
      }
    });
    console.log('✅ Email transporter configured for payment receipts');
  } catch (error) {
    console.warn('⚠️ Failed to configure email transporter:', error.message);
  }
}

// Send payment receipt email with proofs attached
async function sendPaymentReceiptEmail(payment, invoice, proofPaths) {
  if (!emailTransporter) {
    console.warn('⚠️ Email transporter not available, skipping email send');
    return false;
  }
  
  try {
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
    .payment-box { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; border-left: 4px solid #27ae60; }
    .payment-detail { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid #ecf0f1; }
    .footer { text-align: center; color: #95a5a6; font-size: 12px; margin-top: 30px; }
    .proof-notice { background: #fff3cd; padding: 15px; border-radius: 8px; margin: 20px 0; border-left: 4px solid #ffc107; }
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
        <p style="margin: 10px 0 0 0;">We have received your payment of ₹${payment.amountReceived.toFixed(2)}</p>
      </div>
      
      <div class="payment-box">
        <h3 style="margin-top: 0; color: #2c3e50;">Payment Details:</h3>
        <div class="payment-detail">
          <span style="color: #7f8c8d;">Payment Number:</span>
          <span style="font-weight: bold;">${payment.paymentNumber}</span>
        </div>
        ${invoice ? `
        <div class="payment-detail">
          <span style="color: #7f8c8d;">Invoice Number:</span>
          <span style="font-weight: bold;">${invoice.invoiceNumber}</span>
        </div>
        ` : ''}
        <div class="payment-detail">
          <span style="color: #7f8c8d;">Amount Paid:</span>
          <span style="font-weight: bold; color: #27ae60;">₹${payment.amountReceived.toFixed(2)}</span>
        </div>
        <div class="payment-detail">
          <span style="color: #7f8c8d;">Payment Date:</span>
          <span>${payment.paymentDate}</span>
        </div>
        <div class="payment-detail">
          <span style="color: #7f8c8d;">Payment Mode:</span>
          <span>${payment.paymentMode}</span>
        </div>
        ${payment.reference ? `
        <div class="payment-detail">
          <span style="color: #7f8c8d;">Reference Number:</span>
          <span>${payment.reference}</span>
        </div>
        ` : ''}
        ${payment.bankCharges > 0 ? `
        <div class="payment-detail">
          <span style="color: #7f8c8d;">Bank Charges:</span>
          <span style="color: #e74c3c;">₹${payment.bankCharges.toFixed(2)}</span>
        </div>
        ` : ''}
        ${invoice ? `
        <div class="payment-detail" style="border: none; font-weight: bold; font-size: 16px; margin-top: 15px; padding-top: 15px; border-top: 2px solid #27ae60;">
          <span style="color: #2c3e50;">Remaining Balance:</span>
          <span style="color: ${invoice.amountDue > 0 ? '#e74c3c' : '#27ae60'};">₹${invoice.amountDue.toFixed(2)}</span>
        </div>
        ` : ''}
      </div>
      
      ${proofPaths && proofPaths.length > 0 ? `
      <div class="proof-notice">
        <strong>📎 Payment Proofs Attached:</strong><br>
        We have attached ${proofPaths.length} payment proof document(s) to this email for your records.
      </div>
      ` : ''}
      
      ${payment.notes ? `
      <div style="background: white; padding: 15px; border-radius: 8px; margin: 20px 0;">
        <strong style="color: #2c3e50;">Notes:</strong><br>
        <p style="margin: 10px 0 0 0; color: #7f8c8d;">${payment.notes}</p>
      </div>
      ` : ''}
      
      <div style="background: white; padding: 20px; border-radius: 8px; margin-top: 20px;">
        <h3 style="color: #2c3e50; margin-top: 0;">📞 Need Help?</h3>
        <p>If you have any questions about this payment, please contact us:</p>
        <ul style="list-style: none; padding: 0;">
          <li style="padding: 5px 0;">📧 Email: billing@abrafleet.com</li>
          <li style="padding: 5px 0;">📞 Phone: +91-XXXXXXXXXX</li>
          <li style="padding: 5px 0;">🕐 Business Hours: Mon-Fri, 9 AM - 6 PM IST</li>
        </ul>
      </div>
    </div>
    
    <div class="footer">
      <p><strong>Abra Fleet Management Solutions</strong></p>
      <p>This is an automated email. Please do not reply to this message.</p>
    </div>
  </div>
</body>
</html>
    `;

    const attachments = [];
    
    // Attach payment proof files
    if (proofPaths && proofPaths.length > 0) {
      proofPaths.forEach((proofPath, index) => {
        if (fs.existsSync(proofPath)) {
          attachments.push({
            filename: `Payment-Proof-${index + 1}${path.extname(proofPath)}`,
            path: proofPath
          });
        }
      });
    }

    const mailOptions = {
      from: `"Abra Fleet Billing" <${process.env.SMTP_USER}>`,
      to: payment.customerEmail || invoice?.customerEmail,
      subject: `Payment Receipt - ${payment.paymentNumber} - ₹${payment.amountReceived.toFixed(2)}`,
      html: emailHtml,
      attachments: attachments
    };

    await emailTransporter.sendMail(mailOptions);
    console.log(`📧 Payment receipt email sent to ${payment.customerEmail || invoice?.customerEmail}`);
    return true;
  } catch (error) {
    console.error('❌ Failed to send payment receipt email:', error);
    throw error;
  }
}

// ============================================================================
// GET ALL PAYMENTS
// ============================================================================

router.get('/', verifyToken, async (req, res) => {
  try {
    const { filter, sortBy, sortOrder = 'desc' } = req.query;
    
    let query = {};
    
    // Apply filters
    if (filter && filter !== 'All Payments') {
      switch (filter) {
        case 'Draft':
          query.status = 'draft';
          break;
        case 'Paid':
          query.status = 'paid';
          break;
        case 'Void':
          query.status = 'void';
          break;
      }
    }

    // Build sort object
    let sort = { createdAt: -1 }; // Default sort by creation date
    if (sortBy) {
      sort = {};
      sort[sortBy] = sortOrder === 'asc' ? 1 : -1;
    }

    const payments = await db.collection('payments_received')
      .find(query)
      .sort(sort)
      .toArray();

    // Format payments for frontend
    const formattedPayments = payments.map(payment => ({
      id: payment._id,
      date: payment.paymentDate,
      paymentNumber: payment.paymentNumber,
      referenceNumber: payment.reference || '',
      customerName: payment.customerName,
      invoiceNumber: payment.invoiceNumber || '',
      mode: payment.paymentMode,
      amount: payment.amountReceived,
      status: payment.status || 'paid',
      hasProofs: payment.paymentProofs && payment.paymentProofs.length > 0,
      proofsCount: payment.paymentProofs ? payment.paymentProofs.length : 0,
      createdAt: payment.createdAt,
      updatedAt: payment.updatedAt
    }));

    res.json({
      success: true,
      data: formattedPayments,
      total: formattedPayments.length
    });

  } catch (error) {
    console.error('❌ Error fetching payments:', error);
    res.status(500).json({
      success: false,
      message: 'Error fetching payments',
      error: error.message
    });
  }
});

// ============================================================================
// GET PAYMENT BY ID
// ============================================================================

router.get('/:id', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid payment ID'
      });
    }

    const payment = await db.collection('payments_received')
      .findOne({ _id: new ObjectId(id) });

    if (!payment) {
      return res.status(404).json({
        success: false,
        message: 'Payment not found'
      });
    }

    res.json({
      success: true,
      data: payment
    });

  } catch (error) {
    console.error('❌ Error fetching payment:', error);
    res.status(500).json({
      success: false,
      message: 'Error fetching payment',
      error: error.message
    });
  }
});

// ============================================================================
// CREATE NEW PAYMENT WITH PROOFS - ZOHO BOOKS WORKFLOW
// ============================================================================

router.post('/', verifyToken, uploadPaymentProofs, async (req, res) => {
  try {
    console.log('\n' + '💰'.repeat(50));
    console.log('ZOHO BOOKS WORKFLOW: RECORD PAYMENT WITH PROOFS');
    console.log('💰'.repeat(50));
    
    // Parse payment data from form field
    let paymentData;
    try {
      paymentData = JSON.parse(req.body.paymentData);
    } catch (e) {
      return res.status(400).json({
        success: false,
        message: 'Invalid payment data format'
      });
    }

    const {
      customerId,
      customerName,
      customerEmail,
      amountReceived,
      bankCharges = 0,
      paymentDate,
      paymentNumber,
      paymentMode = 'Cash',
      depositTo,
      reference = '',
      taxDeduction = 'No Tax deducted',
      notes = '',
      sendThankYouNote = false,
      invoicePayments = {},
      status = 'paid'
    } = paymentData;

    console.log('📋 Payment Details:');
    console.log('   Customer:', customerName);
    console.log('   Amount:', amountReceived);
    console.log('   Payment #:', paymentNumber);
    console.log('   Files uploaded:', req.files ? req.files.length : 0);
    console.log('   Invoices to update:', Object.keys(invoicePayments).length);

    // Validation
    if (!customerName || !amountReceived || !paymentDate || !paymentNumber || !depositTo) {
      return res.status(400).json({
        success: false,
        message: 'Missing required fields: customerName, amountReceived, paymentDate, paymentNumber, depositTo'
      });
    }

    // Check if payment number already exists
    const existingPayment = await db.collection('payments_received')
      .findOne({ paymentNumber: paymentNumber });

    if (existingPayment) {
      return res.status(400).json({
        success: false,
        message: 'Payment number already exists'
      });
    }

    // Process uploaded files
    const paymentProofs = [];
    const proofPaths = [];
    if (req.files && req.files.length > 0) {
      console.log('📎 Processing uploaded files...');
      for (const file of req.files) {
        paymentProofs.push({
          filename: file.filename,
          originalName: file.originalname,
          filepath: file.path,
          fileType: file.mimetype,
          fileSize: file.size,
          uploadedAt: new Date()
        });
        proofPaths.push(file.path);
        console.log(`   ✅ ${file.originalname} (${(file.size / 1024).toFixed(1)} KB)`);
      }
    }

    // Calculate amounts
    const totalInvoicePayments = Object.values(invoicePayments).reduce((sum, amt) => sum + parseFloat(amt), 0);
    const netAmount = parseFloat(amountReceived) - parseFloat(bankCharges);

    // Create payment record
    const paymentRecord = {
      customerId,
      customerName,
      customerEmail,
      amountReceived: parseFloat(amountReceived),
      bankCharges: parseFloat(bankCharges),
      paymentDate,
      paymentNumber,
      paymentMode,
      depositTo,
      reference,
      taxDeduction,
      notes,
      sendThankYouNote,
      status,
      
      // Invoice payments
      invoicePayments,
      
      // Calculated fields
      netAmount,
      amountUsedForPayments: totalInvoicePayments,
      amountRefunded: 0,
      amountInExcess: netAmount - totalInvoicePayments,
      
      // Payment proofs
      paymentProofs,
      
      // Metadata
      createdAt: new Date(),
      updatedAt: new Date(),
      createdBy: req.user?.email || req.user?.uid || 'system',
      emailSent: false
    };

    // Insert payment
    const result = await db.collection('payments_received').insertOne(paymentRecord);
    console.log('✅ Payment created:', result.insertedId);

    // ============================================================================
    // UPDATE LINKED INVOICES - ZOHO BOOKS WORKFLOW
    // ============================================================================
    let updatedInvoices = [];
    if (Object.keys(invoicePayments).length > 0) {
      console.log('🔗 Updating linked invoices...');
      
      for (const [invoiceId, amount] of Object.entries(invoicePayments)) {
        if (parseFloat(amount) > 0) {
          try {
            // Convert invoiceId to ObjectId if needed
            const invoiceObjectId = ObjectId.isValid(invoiceId) ? new ObjectId(invoiceId) : invoiceId;
            
            // Find invoice
            const invoice = await db.collection('invoices').findOne({ _id: invoiceObjectId });
            
            if (invoice) {
              // Prepare payment record for invoice
              const paymentRecord = {
                paymentId: result.insertedId.toString(),
                amount: parseFloat(amount),
                paymentDate: new Date(paymentDate),
                paymentMethod: paymentMode,
                referenceNumber: reference,
                notes: `Payment #${paymentNumber}`,
                recordedBy: req.user?.email || req.user?.uid || 'system',
                recordedAt: new Date()
              };
              
              // Calculate new amounts
              const newAmountPaid = (invoice.amountPaid || 0) + parseFloat(amount);
              const newAmountDue = invoice.totalAmount - newAmountPaid;
              
              // Determine new status
              let newStatus = invoice.status;
              if (newAmountDue <= 0) {
                newStatus = 'PAID';
              } else if (newAmountPaid > 0 && newAmountDue > 0) {
                newStatus = 'PARTIALLY_PAID';
              }
              
              // Update invoice
              await db.collection('invoices').updateOne(
                { _id: invoiceObjectId },
                {
                  $push: { payments: paymentRecord },
                  $set: {
                    amountPaid: newAmountPaid,
                    amountDue: newAmountDue,
                    status: newStatus,
                    updatedAt: new Date()
                  }
                }
              );
              
              // Get updated invoice for response
              const updatedInvoice = await db.collection('invoices').findOne({ _id: invoiceObjectId });
              updatedInvoices.push(updatedInvoice);
              
              console.log(`   ✅ Updated invoice ${invoice.invoiceNumber} (+₹${amount}) - Status: ${newStatus}`);
            } else {
              console.log(`   ⚠️  Invoice ${invoiceId} not found`);
            }
          } catch (err) {
            console.error(`   ⚠️  Failed to update invoice ${invoiceId}:`, err.message);
          }
        }
      }
    }

// ============================================================================
    // UPDATE ACCOUNT BALANCE - CREDIT RECEIVED AMOUNT
    // ============================================================================
    try {
      const PaymentAccount = db.collection('paymentaccounts');
      const depositAccountId = depositTo;
      let balanceCredited = false;
      const creditAmount = parseFloat(amountReceived);

      // Try as ObjectId first
// Try as ObjectId first
      if (ObjectId.isValid(depositAccountId)) {
        const updateResult = await PaymentAccount.findOneAndUpdate(
          { _id: new ObjectId(depositAccountId) },
          {
            $inc: { currentBalance: creditAmount },
            $set: { updatedAt: new Date() }
          },
          { returnDocument: 'after' }
        );
 if (updateResult) {
          balanceCredited = true;
          const newBal = updateResult.currentBalance ?? updateResult.value?.currentBalance ?? 'updated';
          console.log(`✅ Balance credited to account ID ${depositAccountId}: +₹${creditAmount} → new balance: ₹${newBal}`);
        }
      }

      // If ObjectId lookup failed, try by account name
      if (!balanceCredited) {
        const updateResult = await PaymentAccount.findOneAndUpdate(
          { accountName: depositAccountId },
          {
            $inc: { currentBalance: creditAmount },
            $set: { updatedAt: new Date() }
          },
          { returnDocument: 'after' }
        );
        if (updateResult) {
          balanceCredited = true;
          console.log(`✅ Balance credited to account name "${depositAccountId}": +₹${creditAmount}`);
        }
      }

      if (!balanceCredited) {
        console.warn(`⚠️ BALANCE WARNING: Could not find deposit account "${depositAccountId}" to credit ₹${creditAmount}. Payment saved but balance NOT updated.`);
      }
    } catch (balanceErr) {
      console.error(`⚠️ BALANCE ERROR: Failed to credit balance for payment ${result.insertedId}:`, balanceErr.message);
    }

// ✅ COA: Debit Undeposited Funds + Credit Accounts Receivable
// ✅ COA: Debit selected deposit account + Credit Accounts Receivable
try {
  // Dynamically find COA account matching the selected deposit account
  const cleanDepositName = depositTo
    ? depositTo.replace(/\s*\([^)]*\)\s*$/, '').trim()
    : 'Undeposited Funds';

  console.log(`💰 COA lookup for deposit account: "${cleanDepositName}"`);

  const [cashId, arId] = await Promise.all([
    ChartOfAccount.findOne({
      accountName: { $regex: new RegExp(`^${cleanDepositName}$`, 'i') }
    }).select('_id').lean().then(acc => {
      if (acc) {
        console.log(`✅ Found COA: ${cleanDepositName}`);
        return acc._id;
      }
      console.log(`⚠️ Not found: "${cleanDepositName}", fallback to Undeposited Funds`);
      return getSystemAccountId('Undeposited Funds');
    }),
    getSystemAccountId('Accounts Receivable'),
  ]);
let txnDate;
if (paymentDate && paymentDate.includes('/')) {
  const [day, month, year] = paymentDate.split('/');
  txnDate = new Date(`${year}-${month}-${day}`);
} else {
  txnDate = new Date(paymentDate);
}
if (isNaN(txnDate)) txnDate = new Date();
  const paymentAmount = parseFloat(amountReceived);

  if (cashId) await postTransactionToCOA({
    accountId: cashId, date: txnDate,
    description: `Payment received - ${paymentNumber} - ${customerName}`,
    referenceType: 'Payment',
    referenceId: result.insertedId,
    referenceNumber: paymentNumber,
    debit: paymentAmount, credit: 0
  });

  if (arId) await postTransactionToCOA({
    accountId: arId, date: txnDate,
    description: `Payment received - ${paymentNumber} - ${customerName}`,
    referenceType: 'Payment',
    referenceId: result.insertedId,
    referenceNumber: paymentNumber,
    debit: 0, credit: paymentAmount
  });

  console.log(`✅ COA posted for payment: ${paymentNumber}`);
} catch (coaErr) {
  console.error('⚠️ COA post error (payment received):', coaErr.message);
}

    // ============================================================================
    // SEND PAYMENT RECEIPT EMAIL WITH PROOFS - ZOHO BOOKS WORKFLOW
    // ============================================================================
    let emailSent = false;
    if (sendThankYouNote && (customerEmail || updatedInvoices[0]?.customerEmail)) {
      try {
        console.log('📧 Sending payment receipt email with proofs...');
        await sendPaymentReceiptEmail(
          paymentRecord,
          updatedInvoices[0], // Primary invoice
          proofPaths
        );
        
        // Update payment record
        await db.collection('payments_received').updateOne(
          { _id: result.insertedId },
          { $set: { emailSent: true, emailSentAt: new Date() } }
        );
        
        emailSent = true;
        console.log('✅ Payment receipt email sent successfully');
      } catch (emailError) {
        console.error('⚠️  Failed to send email (non-critical):', emailError.message);
      }
    }

    console.log('✅ PAYMENT RECORDING COMPLETE');
    console.log('💰'.repeat(50) + '\n');

    res.status(201).json({
      success: true,
      message: 'Payment recorded successfully',
      data: {
        id: result.insertedId,
        paymentNumber,
        proofsUploaded: paymentProofs.length,
        invoicesUpdated: updatedInvoices.length,
        emailSent,
        ...paymentRecord
      }
    });

  } catch (error) {
    console.error('❌ Error creating payment:', error);
    
    // Clean up uploaded files on error
    if (req.files && req.files.length > 0) {
      req.files.forEach(file => {
        try {
          fs.unlinkSync(file.path);
        } catch (err) {
          console.error('Failed to delete file:', err);
        }
      });
    }
    
    res.status(500).json({
      success: false,
      message: 'Error creating payment',
      error: error.message
    });
  }
});

// ============================================================================
// UPDATE PAYMENT
// ============================================================================

router.put('/:id', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid payment ID'
      });
    }

    const updateData = {
      ...req.body,
      updatedAt: new Date(),
      updatedBy: req.user?.email || req.user?.uid || 'system'
    };

    // Remove fields that shouldn't be updated
    delete updateData._id;
    delete updateData.createdAt;
    delete updateData.createdBy;
    delete updateData.paymentProofs; // Proofs managed separately

    const result = await db.collection('payments_received')
      .updateOne(
        { _id: new ObjectId(id) },
        { $set: updateData }
      );

    if (result.matchedCount === 0) {
      return res.status(404).json({
        success: false,
        message: 'Payment not found'
      });
    }

    res.json({
      success: true,
      message: 'Payment updated successfully'
    });

  } catch (error) {
    console.error('❌ Error updating payment:', error);
    res.status(500).json({
      success: false,
      message: 'Error updating payment',
      error: error.message
    });
  }
});

// ============================================================================
// DELETE PAYMENT
// ============================================================================

router.delete('/:id', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid payment ID'
      });
    }

    // Get payment before deleting — we need depositTo and amountReceived for balance reversal
    const payment = await db.collection('payments_received')
      .findOne({ _id: new ObjectId(id) });

    if (!payment) {
      return res.status(404).json({
        success: false,
        message: 'Payment not found'
      });
    }

    // Delete associated proof files
    if (payment.paymentProofs && payment.paymentProofs.length > 0) {
      payment.paymentProofs.forEach(proof => {
        try {
          if (fs.existsSync(proof.filepath)) {
            fs.unlinkSync(proof.filepath);
            console.log(`🗑️  Deleted proof file: ${proof.filename}`);
          }
        } catch (err) {
          console.error(`Failed to delete file ${proof.filename}:`, err);
        }
      });
    }

    // Delete payment record
    const result = await db.collection('payments_received')
      .deleteOne({ _id: new ObjectId(id) });

    if (result.deletedCount === 0) {
      return res.status(404).json({
        success: false,
        message: 'Payment not found'
      });
    }

    // ── BALANCE REVERSE ON DELETE ────────────────────────────────────────────
    // When a payment is deleted, reverse the credit — deduct the amount back from the account
    try {
      const depositAccountId = payment.depositTo;
      const deductAmount = parseFloat(payment.amountReceived);
      let balanceReversed = false;

      if (depositAccountId && deductAmount > 0) {
        const PaymentAccountCol = db.collection('paymentaccounts');

        if (ObjectId.isValid(depositAccountId)) {
          const r = await PaymentAccountCol.findOneAndUpdate(
            { _id: new ObjectId(depositAccountId) },
            { $inc: { currentBalance: -deductAmount }, $set: { updatedAt: new Date() } },
            { returnDocument: 'after' }
          );
          if (r) {
            balanceReversed = true;
            console.log(`✅ Balance reversed on payment delete: -₹${deductAmount} from account ID ${depositAccountId}`);
          }
        }

        if (!balanceReversed) {
          const r = await PaymentAccountCol.findOneAndUpdate(
            { accountName: depositAccountId },
            { $inc: { currentBalance: -deductAmount }, $set: { updatedAt: new Date() } },
            { returnDocument: 'after' }
          );
          if (r) {
            balanceReversed = true;
            console.log(`✅ Balance reversed on payment delete: -₹${deductAmount} from account name "${depositAccountId}"`);
          }
        }

        if (!balanceReversed) {
          console.warn(`⚠️ BALANCE WARNING: Could not reverse balance. Account "${depositAccountId}" not found. Payment deleted but balance NOT updated.`);
        }
      }
    } catch (balanceErr) {
      console.error(`⚠️ BALANCE ERROR: Failed to reverse balance on payment delete:`, balanceErr.message);
    }
    // ── END BALANCE REVERSE ──────────────────────────────────────────────────

    res.json({
      success: true,
      message: 'Payment deleted successfully'
    });

  } catch (error) {
    console.error('❌ Error deleting payment:', error);
    res.status(500).json({
      success: false,
      message: 'Error deleting payment',
      error: error.message
    });
  }
});

// ============================================================================
// GET PAYMENT PROOFS
// ============================================================================

router.get('/:id/proofs', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid payment ID'
      });
    }

    const payment = await db.collection('payments_received')
      .findOne({ _id: new ObjectId(id) });

    if (!payment) {
      return res.status(404).json({
        success: false,
        message: 'Payment not found'
      });
    }

    res.json({
      success: true,
      data: payment.paymentProofs || []
    });

  } catch (error) {
    console.error('❌ Error fetching payment proofs:', error);
    res.status(500).json({
      success: false,
      message: 'Error fetching payment proofs',
      error: error.message
    });
  }
});

// ============================================================================
// DOWNLOAD PAYMENT PROOF
// ============================================================================

router.get('/:id/proofs/:proofIndex/download', verifyToken, async (req, res) => {
  try {
    const { id, proofIndex } = req.params;
    
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid payment ID'
      });
    }

    const payment = await db.collection('payments_received')
      .findOne({ _id: new ObjectId(id) });

    if (!payment) {
      return res.status(404).json({
        success: false,
        message: 'Payment not found'
      });
    }

    const index = parseInt(proofIndex);
    if (!payment.paymentProofs || index >= payment.paymentProofs.length) {
      return res.status(404).json({
        success: false,
        message: 'Proof not found'
      });
    }

    const proof = payment.paymentProofs[index];
    
    if (!fs.existsSync(proof.filepath)) {
      return res.status(404).json({
        success: false,
        message: 'Proof file not found on server'
      });
    }

    res.download(proof.filepath, proof.originalName);

  } catch (error) {
    console.error('❌ Error downloading payment proof:', error);
    res.status(500).json({
      success: false,
      message: 'Error downloading payment proof',
      error: error.message
    });
  }
});

// ============================================================================
// GET UNPAID INVOICES FOR CUSTOMER
// ============================================================================

// GET UNPAID INVOICES FOR CUSTOMER - FIXED TO HANDLE OBJECTID
router.get('/customer/:customerId/unpaid-invoices', verifyToken, async (req, res) => {
  try {
    const { customerId } = req.params;
    const { startDate, endDate } = req.query;

    console.log(`🔍 Fetching unpaid invoices for customer: ${customerId}`);

    // Convert customerId to ObjectId if it's a valid ObjectId string
    let customerIdQuery;
    if (ObjectId.isValid(customerId)) {
      customerIdQuery = new ObjectId(customerId);
      console.log(`   Using ObjectId: ${customerIdQuery}`);
    } else {
      customerIdQuery = customerId;
      console.log(`   Using string: ${customerIdQuery}`);
    }

    // Build query - try both ObjectId and string match
    let query = {
      $or: [
        { customerId: customerIdQuery },  // ObjectId match
        { customerId: customerId }  // String match (fallback)
      ],
      status: { $in: ['SENT', 'UNPAID', 'OVERDUE', 'PARTIALLY_PAID'] },
      amountDue: { $gt: 0 }
    };

    // Apply date filter if provided
    if (startDate && endDate) {
      query.invoiceDate = {
        $gte: new Date(startDate),
        $lte: new Date(endDate)
      };
    }

    console.log('📋 Query:', JSON.stringify(query, null, 2));

    // Query MongoDB directly
    const unpaidInvoices = await db.collection('invoices')
      .find(query)
      .sort({ invoiceDate: -1 })
      .toArray();
    
    console.log(`✅ Found ${unpaidInvoices.length} unpaid invoices`);

    // Log each invoice found
    unpaidInvoices.forEach((inv, index) => {
      console.log(`   ${index + 1}. ${inv.invoiceNumber} - Status: ${inv.status} - Due: ₹${inv.amountDue}`);
    });

    res.json({
      success: true,
      data: unpaidInvoices,
      total: unpaidInvoices.length
    });

  } catch (error) {
    console.error('❌ Error fetching unpaid invoices:', error);
    res.status(500).json({
      success: false,
      message: 'Error fetching unpaid invoices',
      error: error.message
    });
  }
});

























// ============================================================================
// GET PAYMENT STATISTICS
// ============================================================================

router.get('/stats/summary', verifyToken, async (req, res) => {
  try {
    const { startDate, endDate, customerName } = req.query;

    let matchQuery = {};
    
    if (startDate && endDate) {
      matchQuery.paymentDate = {
        $gte: startDate,
        $lte: endDate
      };
    }

    if (customerName) {
      matchQuery.customerName = customerName;
    }

    const stats = await db.collection('payments_received').aggregate([
      { $match: matchQuery },
      {
        $group: {
          _id: null,
          totalPayments: { $sum: 1 },
          totalAmount: { $sum: '$amountReceived' },
          totalBankCharges: { $sum: '$bankCharges' },
          totalNetAmount: { $sum: '$netAmount' },
          avgPaymentAmount: { $avg: '$amountReceived' },
        }
      }
    ]).toArray();

    const paymentModeStats = await db.collection('payments_received').aggregate([
      { $match: matchQuery },
      {
        $group: {
          _id: '$paymentMode',
          count: { $sum: 1 },
          totalAmount: { $sum: '$amountReceived' }
        }
      }
    ]).toArray();

    res.json({
      success: true,
      data: {
        summary: stats[0] || {
          totalPayments: 0,
          totalAmount: 0,
          totalBankCharges: 0,
          totalNetAmount: 0,
          avgPaymentAmount: 0
        },
        paymentModeBreakdown: paymentModeStats
      }
    });

  } catch (error) {
    console.error('❌ Error fetching payment statistics:', error);
    res.status(500).json({
      success: false,
      message: 'Error fetching payment statistics',
      error: error.message
    });
  }
});

// ============================================================================
// EXPORT PAYMENTS TO CSV
// ============================================================================

router.get('/export/csv', verifyToken, async (req, res) => {
  try {
    const { filter, startDate, endDate } = req.query;
    
    let query = {};
    
    if (filter && filter !== 'All Payments') {
      switch (filter) {
        case 'Draft':
          query.status = 'draft';
          break;
        case 'Paid':
          query.status = 'paid';
          break;
        case 'Void':
          query.status = 'void';
          break;
      }
    }

    if (startDate && endDate) {
      query.paymentDate = {
        $gte: startDate,
        $lte: endDate
      };
    }

    const payments = await db.collection('payments_received')
      .find(query)
      .sort({ paymentDate: -1 })
      .toArray();

    // Generate CSV content
    const csvHeaders = [
      'Payment Date',
      'Payment Number',
      'Customer Name',
      'Amount Received',
      'Bank Charges',
      'Net Amount',
      'Payment Mode',
      'Deposit To',
      'Reference',
      'Tax Deduction',
      'Status',
      'Has Proofs',
      'Notes'
    ].join(',');

    const csvRows = payments.map(payment => [
      payment.paymentDate,
      payment.paymentNumber,
      payment.customerName,
      payment.amountReceived,
      payment.bankCharges || 0,
      payment.netAmount,
      payment.paymentMode,
      payment.depositTo,
      payment.reference || '',
      payment.taxDeduction,
      payment.status,
      payment.paymentProofs && payment.paymentProofs.length > 0 ? 'Yes' : 'No',
      (payment.notes || '').replace(/,/g, ';')
    ].join(','));

    const csvContent = [csvHeaders, ...csvRows].join('\n');

    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', 'attachment; filename=payments_received.csv');
    res.send(csvContent);

  } catch (error) {
    console.error('❌ Error exporting payments:', error);
    res.status(500).json({
      success: false,
      message: 'Error exporting payments',
      error: error.message
    });
  }
});

// ============================================================================
// GET NEXT PAYMENT NUMBER
// ============================================================================

router.get('/next-payment-number', verifyToken, async (req, res) => {
  try {
    const lastPayment = await db.collection('payments_received')
      .findOne({}, { sort: { paymentNumber: -1 } });
    
    const lastNumber = lastPayment ? parseInt(lastPayment.paymentNumber) : 0;
    const nextNumber = (lastNumber + 1).toString();

    res.json({
      success: true,
      data: {
        nextPaymentNumber: nextNumber
      }
    });

  } catch (error) {
    console.error('❌ Error getting next payment number:', error);
    res.status(500).json({
      success: false,
      message: 'Error getting next payment number',
      error: error.message
    });
  }
});

module.exports = router;
