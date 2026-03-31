// routes/feedback_router.js
const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const axios = require('axios'); // 🆕 ADD THIS: npm install axios

// ============================================================================
// 🆕 CRM INTEGRATION CONFIGURATION
// ============================================================================
const CRM_CONFIG = {
    apiUrl: 'https://crm.abra-logistic.com/api/create-ticket.php',
    apiKey: 'ABRA_FLEET_KEERTI_HR_2025_SECRET_KEY_XYZ123',
    hrAdminId: 44, // Keerti Patil (HR)
    enabled: true  
};

// ============================================================================
// 🆕 FUNCTION: Sync ticket to CRM
// ============================================================================
async function syncTicketToCRM(ticketData) {
    if (!CRM_CONFIG.enabled) {
        console.log('⚠️  CRM integration disabled');
        return { success: false, reason: 'disabled' };
    }
    
    try {
        console.log('\n🔄 SYNCING TICKET TO CRM');
        console.log('─'.repeat(80));
        console.log('   Ticket Number:', ticketData.ticket_number);
        console.log('   CRM URL:', CRM_CONFIG.apiUrl);
        
        const response = await axios.post(
            CRM_CONFIG.apiUrl,
            {
                ticket_number: ticketData.ticket_number,
                name: ticketData.name,
                subject: ticketData.subject,
                message: ticketData.message,
                description: ticketData.description || ticketData.message,
                status: ticketData.status || 'Open',
                priority: ticketData.priority || 'medium',
                assigned_to: CRM_CONFIG.hrAdminId,
                source: 'fleet_feedback'
            },
            {
                headers: {
                    'Content-Type': 'application/json',
                    'X-API-Key': CRM_CONFIG.apiKey
                },
                timeout: 10000
            }
        );
        
        if (response.data.success) {
            console.log('   ✅ Ticket synced to CRM successfully');
            console.log('   CRM Ticket ID:', response.data.data?.ticket_id);
            console.log('   Assigned to:', response.data.data?.assigned_to_name);
            console.log('   View at:', response.data.data?.crm_url);
            console.log('✅ CRM SYNC COMPLETE');
            console.log('─'.repeat(80) + '\n');
            
            return {
                success: true,
                crmTicketId: response.data.data?.ticket_id,
                crmTicketNumber: response.data.data?.ticket_number
            };
        } else {
            console.log('   ⚠️  CRM sync failed:', response.data.message);
            return { success: false, reason: response.data.message };
        }
        
    } catch (error) {
        console.error('❌ ERROR SYNCING TO CRM');
        
        if (error.response) {
            console.error('   Status:', error.response.status);
            console.error('   Message:', error.response.data?.message || error.message);
        } else if (error.request) {
            console.error('   No response from CRM API');
        } else {
            console.error('   Error:', error.message);
        }
        
        console.error('─'.repeat(80) + '\n');
        return { success: false, error: error.message };
    }
}

// ============================================================================
// AUTO-TICKET GENERATION FUNCTION FOR FEEDBACK (🆕 MODIFIED - Added CRM sync)
// ============================================================================
async function createTicketFromFeedback(db, feedbackData, source) {
    const hr_admin_id = '44'; // Keerti Patil - HR Admin
    
    // Generate unique ticket number
    const ticket_number = `${source.toUpperCase()}-FB-${new Date().toISOString().slice(0, 10).replace(/-/g, '')}-${Math.floor(1000 + Math.random() * 9000)}`;
    
    // Set priority based on feedback type
    let priority = 'medium';
    if (feedbackData.type.toLowerCase() === 'complaint') {
        priority = 'high';
    } else if (feedbackData.type.toLowerCase() === 'appreciation') {
        priority = 'low';
    }
    
    // Prepare ticket message
    const ticketMessage = `${source.charAt(0).toUpperCase() + source.slice(1)} Feedback Submission

From: ${feedbackData.name}
Type: ${feedbackData.type}
Rating: ${feedbackData.rating}/5

Message:
${feedbackData.message}`;
    
    // Prepare ticket data
    const ticket = {
        ticket_number,
        name: feedbackData.name,
        subject: `[${source.toUpperCase()}-${feedbackData.type.toUpperCase()}] ${feedbackData.subject}`,
        message: ticketMessage,
        description: feedbackData.message,
        status: 'Open',
        priority,
        assigned_to: hr_admin_id,
        source: `${source}_feedback`,
        created_at: new Date(),
        updated_at: new Date()
    };
    
    try {
        // Step 1: Save to MongoDB
        const result = await db.collection('tickets').insertOne(ticket);
        const mongoTicketId = result.insertedId;
        
        console.log('   ✅ Ticket saved to MongoDB:', mongoTicketId);
        
        // 🆕 Step 2: Sync to CRM
        const crmResult = await syncTicketToCRM(ticket);
        
        // 🆕 Return both MongoDB and CRM results
        return {
            mongoTicketId,
            crmSynced: crmResult.success,
            crmTicketId: crmResult.crmTicketId || null,
            ticket_number
        };
        
    } catch (error) {
        console.error('Error creating ticket from feedback:', error);
        return null;
    }
}

// ============================================================================
// SUBMIT CUSTOMER FEEDBACK (🆕 MODIFIED - Enhanced success message)
// ============================================================================
router.post('/customer/submit', async (req, res) => {
    console.log('\n📝 SUBMITTING CUSTOMER FEEDBACK');
    console.log('─'.repeat(80));
    
    try {
        const { customer_name, feedback_type, subject, message, rating } = req.body;
        const customer_email = req.user.email; // From auth middleware
        
        console.log('   Customer:', customer_name);
        console.log('   Type:', feedback_type);
        console.log('   Subject:', subject);
        console.log('   Rating:', rating);
        
        // Validate required fields
        if (!customer_name || !feedback_type || !subject || !message || !rating) {
            return res.status(400).json({
                success: false,
                error: 'Missing required fields',
                message: 'Please fill in all required fields'
            });
        }
        
        // Check for recent duplicate (within 1 minute)
        const oneMinuteAgo = new Date(Date.now() - 60000);
        const duplicate = await req.db.collection('customer_feedback').findOne({
            customer_email,
            subject,
            date_submitted: { $gt: oneMinuteAgo }
        });
        
        if (duplicate) {
            console.log('   ⚠️  Duplicate submission detected');
            return res.json({
                success: true,
                message: 'Feedback already submitted.'
            });
        }
        
        // Create feedback document
        const feedback = {
            customer_email,
            customer_name,
            feedback_type,
            subject,
            message,
            rating: parseInt(rating),
            date_submitted: new Date(),
            status: 'pending',
            admin_response: null,
            response_date: null,
            parent_feedback_id: null
        };
        
        // Insert feedback
        const result = await req.db.collection('customer_feedback').insertOne(feedback);
        const feedback_id = result.insertedId;
        
        console.log('   ✅ Feedback inserted:', feedback_id);
        
        // Auto-create ticket
        const ticketData = {
            name: customer_name,
            subject,
            message,
            type: feedback_type,
            rating
        };
        
        const ticketResult = await createTicketFromFeedback(req.db, ticketData, 'customer');
        
        // 🆕 ENHANCED SUCCESS MESSAGE
        let successMessage = 'Thank you! Your feedback has been submitted successfully.';
        if (ticketResult) {
            if (ticketResult.crmSynced) {
                successMessage += ` A support ticket (${ticketResult.ticket_number}) has been created and sent to Keerti Patil (HR) in our CRM system.`;
            } else {
                successMessage += ` A support ticket (${ticketResult.ticket_number}) has been created and our team will review it shortly.`;
            }
            console.log('   ✅ Ticket created:', ticketResult.ticket_number);
            console.log('   MongoDB ID:', ticketResult.mongoTicketId);
            console.log('   CRM Synced:', ticketResult.crmSynced ? 'Yes ✅' : 'No ⚠️');
            if (ticketResult.crmTicketId) {
                console.log('   CRM Ticket ID:', ticketResult.crmTicketId);
            }
        }
        
        console.log('✅ CUSTOMER FEEDBACK SUBMITTED');
        console.log('─'.repeat(80) + '\n');
        
        res.json({
            success: true,
            message: successMessage,
            data: {
                feedback_id,
                ticket_number: ticketResult?.ticket_number,
                mongo_ticket_id: ticketResult?.mongoTicketId,
                crm_ticket_id: ticketResult?.crmTicketId,
                crm_synced: ticketResult?.crmSynced || false
            }
        });
        
    } catch (error) {
        console.error('❌ ERROR SUBMITTING CUSTOMER FEEDBACK');
        console.error('   Error:', error.message);
        console.error('─'.repeat(80) + '\n');
        
        res.status(500).json({
            success: false,
            error: 'Failed to submit feedback',
            message: error.message
        });
    }
});

// ============================================================================
// SUBMIT EMPLOYEE FEEDBACK (🆕 MODIFIED - Enhanced success message)
// ============================================================================
router.post('/employee/submit', async (req, res) => {
    console.log('\n📝 SUBMITTING EMPLOYEE FEEDBACK');
    console.log('─'.repeat(80));
    
    try {
        const { employee_name, feedback_type, subject, message, rating } = req.body;
        const employee_email = req.user.email;
        
        console.log('   Employee:', employee_name);
        console.log('   Type:', feedback_type);
        console.log('   Subject:', subject);
        console.log('   Rating:', rating);
        
        // Validate required fields
        if (!employee_name || !feedback_type || !subject || !message || !rating) {
            return res.status(400).json({
                success: false,
                error: 'Missing required fields',
                message: 'Please fill in all required fields'
            });
        }
        
        // Check for recent duplicate
        const oneMinuteAgo = new Date(Date.now() - 60000);
        const duplicate = await req.db.collection('employee_feedback').findOne({
            employee_email,
            subject,
            date_submitted: { $gt: oneMinuteAgo }
        });
        
        if (duplicate) {
            console.log('   ⚠️  Duplicate submission detected');
            return res.json({
                success: true,
                message: 'Feedback already submitted.'
            });
        }
        
        // Create feedback document
        const feedback = {
            employee_email,
            employee_name,
            feedback_type,
            subject,
            message,
            rating: parseInt(rating),
            date_submitted: new Date(),
            status: 'pending',
            admin_response: null,
            response_date: null,
            parent_feedback_id: null
        };
        
        // Insert feedback
        const result = await req.db.collection('employee_feedback').insertOne(feedback);
        const feedback_id = result.insertedId;
        
        console.log('   ✅ Feedback inserted:', feedback_id);
        
        // Auto-create ticket
        const ticketData = {
            name: employee_name,
            subject,
            message,
            type: feedback_type,
            rating
        };
        
        const ticketResult = await createTicketFromFeedback(req.db, ticketData, 'employee');
        
        // 🆕 ENHANCED SUCCESS MESSAGE
        let successMessage = 'Thank you! Your feedback has been submitted successfully.';
        if (ticketResult) {
            if (ticketResult.crmSynced) {
                successMessage += ` A support ticket (${ticketResult.ticket_number}) has been created and sent to Keerti Patil (HR).`;
            } else {
                successMessage += ` A support ticket (${ticketResult.ticket_number}) has been created.`;
            }
            console.log('   ✅ Ticket created:', ticketResult.ticket_number);
            console.log('   MongoDB ID:', ticketResult.mongoTicketId);
            console.log('   CRM Synced:', ticketResult.crmSynced ? 'Yes ✅' : 'No ⚠️');
            if (ticketResult.crmTicketId) {
                console.log('   CRM Ticket ID:', ticketResult.crmTicketId);
            }
        }
        
        console.log('✅ EMPLOYEE FEEDBACK SUBMITTED');
        console.log('─'.repeat(80) + '\n');
        
        res.json({
            success: true,
            message: successMessage,
            data: {
                feedback_id,
                ticket_number: ticketResult?.ticket_number,
                mongo_ticket_id: ticketResult?.mongoTicketId,
                crm_ticket_id: ticketResult?.crmTicketId,
                crm_synced: ticketResult?.crmSynced || false
            }
        });
        
    } catch (error) {
        console.error('❌ ERROR SUBMITTING EMPLOYEE FEEDBACK');
        console.error('   Error:', error.message);
        console.error('─'.repeat(80) + '\n');
        
        res.status(500).json({
            success: false,
            error: 'Failed to submit feedback',
            message: error.message
        });
    }
});

// ============================================================================
// SUBMIT DRIVER FEEDBACK (🆕 MODIFIED - Enhanced success message)
// ============================================================================
router.post('/driver/submit', async (req, res) => {
    console.log('\n📝 SUBMITTING DRIVER FEEDBACK');
    console.log('─'.repeat(80));
    
    try {
        const { driver_name, feedback_type, subject, message, rating } = req.body;
        const driver_email = req.user.email;
        
        console.log('   Driver:', driver_name);
        console.log('   Type:', feedback_type);
        console.log('   Subject:', subject);
        console.log('   Rating:', rating);
        
        // Validate required fields
        if (!driver_name || !feedback_type || !subject || !message || !rating) {
            return res.status(400).json({
                success: false,
                error: 'Missing required fields',
                message: 'Please fill in all required fields'
            });
        }
        
        // Check for recent duplicate
        const oneMinuteAgo = new Date(Date.now() - 60000);
        const duplicate = await req.db.collection('driver_feedback').findOne({
            driver_email,
            subject,
            date_submitted: { $gt: oneMinuteAgo }
        });
        
        if (duplicate) {
            console.log('   ⚠️  Duplicate submission detected');
            return res.json({
                success: true,
                message: 'Feedback already submitted.'
            });
        }
        
        // Create feedback document
        const feedback = {
            driver_email,
            driver_name,
            feedback_type,
            subject,
            message,
            rating: parseInt(rating),
            date_submitted: new Date(),
            status: 'pending',
            admin_response: null,
            response_date: null,
            parent_feedback_id: null
        };
        
        // Insert feedback
        const result = await req.db.collection('driver_feedback').insertOne(feedback);
        const feedback_id = result.insertedId;
        
        console.log('   ✅ Feedback inserted:', feedback_id);
        
        // Auto-create ticket
        const ticketData = {
            name: driver_name,
            subject,
            message,
            type: feedback_type,
            rating
        };
        
        const ticketResult = await createTicketFromFeedback(req.db, ticketData, 'driver');
        
        // 🆕 ENHANCED SUCCESS MESSAGE
        let successMessage = 'Thank you! Your feedback has been submitted successfully.';
        if (ticketResult) {
            if (ticketResult.crmSynced) {
                successMessage += ` A support ticket (${ticketResult.ticket_number}) has been created and sent to HR.`;
            } else {
                successMessage += ` A support ticket (${ticketResult.ticket_number}) has been created.`;
            }
            console.log('   ✅ Ticket created:', ticketResult.ticket_number);
            console.log('   MongoDB ID:', ticketResult.mongoTicketId);
            console.log('   CRM Synced:', ticketResult.crmSynced ? 'Yes ✅' : 'No ⚠️');
            if (ticketResult.crmTicketId) {
                console.log('   CRM Ticket ID:', ticketResult.crmTicketId);
            }
        }
        
        console.log('✅ DRIVER FEEDBACK SUBMITTED');
        console.log('─'.repeat(80) + '\n');
        
        res.json({
            success: true,
            message: successMessage,
            data: {
                feedback_id,
                ticket_number: ticketResult?.ticket_number,
                mongo_ticket_id: ticketResult?.mongoTicketId,
                crm_ticket_id: ticketResult?.crmTicketId,
                crm_synced: ticketResult?.crmSynced || false
            }
        });
        
    } catch (error) {
        console.error('❌ ERROR SUBMITTING DRIVER FEEDBACK');
        console.error('   Error:', error.message);
        console.error('─'.repeat(80) + '\n');
        
        res.status(500).json({
            success: false,
            error: 'Failed to submit feedback',
            message: error.message
        });
    }
});

// ============================================================================
// GET USER'S FEEDBACK (Customer, Employee, or Driver)
// ============================================================================
router.get('/my-feedback/:source', async (req, res) => {
    console.log('\n📋 FETCHING USER FEEDBACK');
    console.log('─'.repeat(80));
    
    try {
        const { source } = req.params; // 'customer', 'employee', or 'driver'
        const user_email = req.user.email;
        
        console.log('   User:', user_email);
        console.log('   Source:', source);
        
        if (!['customer', 'employee', 'driver'].includes(source)) {
            return res.status(400).json({
                success: false,
                error: 'Invalid source',
                message: 'Source must be "customer", "employee", or "driver"'
            });
        }
        
        const collection = source === 'customer' ? 'customer_feedback' : 
                          source === 'employee' ? 'employee_feedback' : 'driver_feedback';
        const emailField = source === 'customer' ? 'customer_email' : 
                          source === 'employee' ? 'employee_email' : 'driver_email';
        
        // Fetch all feedback for this user
        const feedback = await req.db.collection(collection)
            .find({ [emailField]: user_email })
            .sort({ date_submitted: -1 })
            .toArray();
        
        console.log('   ✅ Found', feedback.length, 'feedback entries');
        console.log('✅ FEEDBACK FETCHED');
        console.log('─'.repeat(80) + '\n');
        
        res.json({
            success: true,
            data: feedback
        });
        
    } catch (error) {
        console.error('❌ ERROR FETCHING FEEDBACK');
        console.error('   Error:', error.message);
        console.error('─'.repeat(80) + '\n');
        
        res.status(500).json({
            success: false,
            error: 'Failed to fetch feedback',
            message: error.message
        });
    }
});

// ============================================================================
// SUBMIT USER REPLY TO ADMIN RESPONSE
// ============================================================================
router.post('/reply/:source', async (req, res) => {
    console.log('\n💬 SUBMITTING USER REPLY');
    console.log('─'.repeat(80));
    
    try {
        const { source } = req.params;
        const { original_feedback_id, user_name, original_subject, reply_message } = req.body;
        const user_email = req.user.email;
        
        console.log('   Source:', source);
        console.log('   Original Feedback ID:', original_feedback_id);
        console.log('   Reply to:', original_subject);
        
        if (!['customer', 'employee', 'driver'].includes(source)) {
            return res.status(400).json({
                success: false,
                error: 'Invalid source'
            });
        }
        
        const collection = source === 'customer' ? 'customer_feedback' : 
                          source === 'employee' ? 'employee_feedback' : 'driver_feedback';
        const emailField = source === 'customer' ? 'customer_email' : 
                          source === 'employee' ? 'employee_email' : 'driver_email';
        const nameField = source === 'customer' ? 'customer_name' : 
                         source === 'employee' ? 'employee_name' : 'driver_name';
        
        // Create reply as new feedback entry
        const reply = {
            [emailField]: user_email,
            [nameField]: user_name,
            feedback_type: 'general',
            subject: `Re: ${original_subject}`,
            message: reply_message,
            rating: 5, // Default rating for replies
            date_submitted: new Date(),
            status: 'pending',
            admin_response: null,
            response_date: null,
            parent_feedback_id: new ObjectId(original_feedback_id)
        };
        
        const result = await req.db.collection(collection).insertOne(reply);
        
        console.log('   ✅ Reply submitted:', result.insertedId);
        console.log('✅ USER REPLY SUBMITTED');
        console.log('─'.repeat(80) + '\n');
        
        res.json({
            success: true,
            message: 'Your reply has been sent successfully!',
            data: {
                reply_id: result.insertedId
            }
        });
        
    } catch (error) {
        console.error('❌ ERROR SUBMITTING REPLY');
        console.error('   Error:', error.message);
        console.error('─'.repeat(80) + '\n');
        
        res.status(500).json({
            success: false,
            error: 'Failed to submit reply',
            message: error.message
        });
    }
});

// ============================================================================
// ADMIN: GET ALL FEEDBACK (with filters)
// ============================================================================
router.get('/admin/all', async (req, res) => {
    console.log('\n👨‍💼 ADMIN: FETCHING ALL FEEDBACK');
    console.log('─'.repeat(80));
    
    try {
        const { 
            source,      // 'customer', 'employee', or 'all'
            name,        // Filter by name
            type,        // Filter by feedback type
            status,      // Filter by status
            date_from,   // Filter by date range
            date_to,
            page = 1,
            limit = 20
        } = req.query;
        
        console.log('   Source:', source || 'all');
        console.log('   Filters:', { name, type, status, date_from, date_to });
        
        // Build aggregation pipeline
        const sources = source === 'all' || !source 
            ? ['customer', 'employee', 'driver'] 
            : [source];
        
        let allFeedback = [];
        
        for (const src of sources) {
            const collection = src === 'customer' ? 'customer_feedback' : 
                              src === 'employee' ? 'employee_feedback' : 'driver_feedback';
            const emailField = src === 'customer' ? 'customer_email' : 
                              src === 'employee' ? 'employee_email' : 'driver_email';
            const nameField = src === 'customer' ? 'customer_name' : 
                             src === 'employee' ? 'employee_name' : 'driver_name';
            
            // Build query
            const query = {};
            
            if (name) {
                query[nameField] = { $regex: name, $options: 'i' };
            }
            
            if (type && type !== 'all') {
                query.feedback_type = type;
            }
            
            if (status && status !== 'all') {
                query.status = status;
            }
            
            if (date_from || date_to) {
                query.date_submitted = {};
                if (date_from) {
                    query.date_submitted.$gte = new Date(date_from);
                }
                if (date_to) {
                    const endDate = new Date(date_to);
                    endDate.setHours(23, 59, 59, 999);
                    query.date_submitted.$lte = endDate;
                }
            }
            
            const feedback = await req.db.collection(collection)
                .find(query)
                .sort({ date_submitted: -1 })
                .toArray();
            
            // Add source field to each feedback
            feedback.forEach(f => f.source = src);
            
            allFeedback = allFeedback.concat(feedback);
        }
        
        // Sort combined results by date
        allFeedback.sort((a, b) => b.date_submitted - a.date_submitted);
        
        // Pagination
        const startIndex = (page - 1) * limit;
        const endIndex = startIndex + parseInt(limit);
        const paginatedFeedback = allFeedback.slice(startIndex, endIndex);
        
        console.log('   ✅ Found', allFeedback.length, 'total feedback entries');
        console.log('   📄 Returning page', page, '(', paginatedFeedback.length, 'items)');
        console.log('✅ ADMIN FEEDBACK FETCHED');
        console.log('─'.repeat(80) + '\n');
        
        res.json({
            success: true,
            data: {
                feedback: paginatedFeedback,
                pagination: {
                    total: allFeedback.length,
                    page: parseInt(page),
                    limit: parseInt(limit),
                    totalPages: Math.ceil(allFeedback.length / limit)
                }
            }
        });
        
    } catch (error) {
        console.error('❌ ERROR FETCHING ADMIN FEEDBACK');
        console.error('   Error:', error.message);
        console.error('─'.repeat(80) + '\n');
        
        res.status(500).json({
            success: false,
            error: 'Failed to fetch feedback',
            message: error.message
        });
    }
});

// ============================================================================
// ADMIN: REPLY TO FEEDBACK
// ============================================================================
router.post('/admin/reply', async (req, res) => {
    console.log('\n👨‍💼 ADMIN: REPLYING TO FEEDBACK');
    console.log('─'.repeat(80));
    
    try {
        const { feedback_id, feedback_source, response } = req.body;
        
        console.log('   Feedback ID:', feedback_id);
        console.log('   Source:', feedback_source);
        console.log('   Response length:', response?.length || 0);
        
        if (!feedback_id || !feedback_source || !response) {
            return res.status(400).json({
                success: false,
                error: 'Missing required fields'
            });
        }
        
        const collection = feedback_source === 'customer' 
            ? 'customer_feedback' 
            : feedback_source === 'employee' 
            ? 'employee_feedback' 
            : 'driver_feedback';
        
        // First, get the original feedback to extract user information
        const originalFeedback = await req.db.collection(collection).findOne({
            _id: new ObjectId(feedback_id)
        });
        
        if (!originalFeedback) {
            console.log('   ❌ Feedback not found');
            return res.status(404).json({
                success: false,
                error: 'Feedback not found'
            });
        }
        
        // Update feedback with admin response
        const result = await req.db.collection(collection).updateOne(
            { _id: new ObjectId(feedback_id) },
            {
                $set: {
                    admin_response: response,
                    response_date: new Date(),
                    status: 'responded'
                }
            }
        );
        
        if (result.matchedCount === 0) {
            console.log('   ❌ Failed to update feedback');
            return res.status(404).json({
                success: false,
                error: 'Failed to update feedback'
            });
        }
        
        console.log('   ✅ Admin response added');
        
        // ========== SEND NOTIFICATION TO USER ==========
        console.log('\n📱 SENDING NOTIFICATION TO USER');
        console.log('─'.repeat(50));
        
        try {
            // Import notification model
            const { createNotification } = require('../models/notification_model');
            
            // Determine user ID based on feedback source
            let userId = null;
            let userName = originalFeedback.customer_name || originalFeedback.name || 'User';
            
            if (feedback_source === 'customer') {
                // For customer feedback, try to get Firebase UID
                userId = originalFeedback.customer_email || originalFeedback.email;
                
                // Try to find user in users collection by email
                const user = await req.db.collection('users').findOne({
                    email: userId
                });
                
                if (user && user.firebaseUid) {
                    userId = user.firebaseUid;
                    console.log(`   ✅ Found Firebase UID for customer: ${userId}`);
                } else {
                    console.log(`   ⚠️  No Firebase UID found for email: ${userId}`);
                    // Still try to send notification with email as userId
                }
            } else if (feedback_source === 'driver') {
                // For driver feedback, try to get Firebase UID
                userId = originalFeedback.driver_email || originalFeedback.email;
                
                // Try to find driver in drivers collection
                const driver = await req.db.collection('drivers').findOne({
                    email: userId
                });
                
                if (driver && driver.firebaseUid) {
                    userId = driver.firebaseUid;
                    console.log(`   ✅ Found Firebase UID for driver: ${userId}`);
                } else {
                    console.log(`   ⚠️  No Firebase UID found for driver email: ${userId}`);
                }
            } else if (feedback_source === 'employee') {
                // For employee feedback, try to get Firebase UID
                userId = originalFeedback.employee_email || originalFeedback.email;
                
                // Try to find employee in users collection
                const employee = await req.db.collection('users').findOne({
                    email: userId
                });
                
                if (employee && employee.firebaseUid) {
                    userId = employee.firebaseUid;
                    console.log(`   ✅ Found Firebase UID for employee: ${userId}`);
                } else {
                    console.log(`   ⚠️  No Firebase UID found for employee email: ${userId}`);
                }
            }
            
            if (userId) {
                // Create notification
                const notificationData = {
                    userId: userId,
                    type: 'feedback_reply',
                    title: '💬 Admin Response to Your Feedback',
                    body: `We've responded to your feedback about "${originalFeedback.subject || 'your concern'}". Tap to view the response.`,
                    data: {
                        feedbackId: feedback_id,
                        feedbackSource: feedback_source,
                        originalSubject: originalFeedback.subject || 'Your Feedback',
                        responsePreview: response.length > 100 ? response.substring(0, 100) + '...' : response
                    },
                    metadata: {
                        feedbackId: feedback_id,
                        feedbackSource: feedback_source,
                        originalSubject: originalFeedback.subject,
                        adminResponseDate: new Date().toISOString()
                    },
                    priority: 'high',
                    category: 'feedback'
                };
                
                console.log(`   📤 Creating notification for user: ${userId}`);
                console.log(`   📝 Subject: ${originalFeedback.subject}`);
                console.log(`   👤 User: ${userName}`);
                
                const notification = await createNotification(req.db, notificationData);
                
                console.log('   ✅ Notification sent successfully!');
                console.log(`   📱 Notification ID: ${notification._id}`);
                
            } else {
                console.log('   ⚠️  Could not determine user ID - notification not sent');
            }
            
        } catch (notificationError) {
            console.error('   ❌ Error sending notification:', notificationError.message);
            // Don't fail the entire request if notification fails
        }
        
        console.log('✅ ADMIN REPLY SUBMITTED WITH NOTIFICATION');
        console.log('─'.repeat(80) + '\n');
        
        res.json({
            success: true,
            message: 'Response sent successfully! The user will be notified.'
        });
        
    } catch (error) {
        console.error('❌ ERROR SUBMITTING ADMIN REPLY');
        console.error('   Error:', error.message);
        console.error('─'.repeat(80) + '\n');
        
        res.status(500).json({
            success: false,
            error: 'Failed to send response',
            message: error.message
        });
    }
});

// ============================================================================
// GET FEEDBACK STATISTICS
// ============================================================================
router.get('/stats', async (req, res) => {
    console.log('\n📊 FETCHING FEEDBACK STATISTICS');
    console.log('─'.repeat(80));
    
    try {
        const { source = 'all' } = req.query;
        
        const sources = source === 'all' 
            ? ['customer', 'employee', 'driver'] 
            : [source];
        
        let stats = {
            total: 0,
            pending: 0,
            responded: 0,
            by_type: {},
            avg_rating: 0,
            recent_count: 0
        };
        
        const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
        let totalRating = 0;
        let ratingCount = 0;
        
        for (const src of sources) {
            const collection = src === 'customer' ? 'customer_feedback' : 
                              src === 'employee' ? 'employee_feedback' : 'driver_feedback';
            
            const feedback = await req.db.collection(collection).find({}).toArray();
            
            stats.total += feedback.length;
            
            feedback.forEach(f => {
                // Status counts
                if (f.status === 'pending') stats.pending++;
                if (f.status === 'responded') stats.responded++;
                
                // Type counts
                stats.by_type[f.feedback_type] = (stats.by_type[f.feedback_type] || 0) + 1;
                
                // Rating average
                totalRating += f.rating || 0;
                ratingCount++;
                
                // Recent count (last 30 days)
                if (f.date_submitted >= thirtyDaysAgo) {
                    stats.recent_count++;
                }
            });
        }
        
        stats.avg_rating = ratingCount > 0 ? (totalRating / ratingCount).toFixed(2) : 0;
        
        console.log('   ✅ Statistics calculated');
        console.log('   Total:', stats.total);
        console.log('   Avg Rating:', stats.avg_rating);
        console.log('✅ STATISTICS FETCHED');
        console.log('─'.repeat(80) + '\n');
        
        res.json({
            success: true,
            data: stats
        });
        
    } catch (error) {
        console.error('❌ ERROR FETCHING STATISTICS');
        console.error('   Error:', error.message);
        console.error('─'.repeat(80) + '\n');
        
        res.status(500).json({
            success: false,
            error: 'Failed to fetch statistics',
            message: error.message
        });
    }
});

module.exports = router;