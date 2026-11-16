const fs = require('fs');
const targetPath = 'routes/driver_trip_router.js';
let content = fs.readFileSync(targetPath, 'utf8');
const lines = content.split('\\n');

let newLines = [];
let skip = false;

for (let i = 0; i < lines.length; i++) {
  if (lines[i].includes('// STEP 4: Send completion notifications') && lines[i+2].includes('Sending completion')) {
    skip = true;
    
    // Inject new logic
    newLines.push(
\`    // ========================================================================
    // STEP 4: Send completion notifications and request feedback
    // ========================================================================
    console.log(\\\`\\\\n📲 Sending completion & feedback notifications...\\\`);
    
    // Extract unique customers from all stops across all completed trips
    const uniqueCustomers = new Map();
    for (const trip of trips) {
      for (const stop of trip.stops || []) {
        if (stop.customer && stop.customer.email) {
          // Only send to customers who actually boarded
          if (stop.status === 'completed' || stop.status === 'boarded') {
            uniqueCustomers.set(stop.customer.email, {
              customerInfo: stop.customer,
              tripId: trip._id.toString(),
              tripNumber: trip.tripNumber || tripGroupId.substring(0, 8),
              stopId: stop.stopId
            });
          }
        }
      }
    }
    
    for (const [email, data] of uniqueCustomers.entries()) {
      const customer = await req.db.collection('customers').findOne({ email });
      if (customer) {
        const devices = await req.db.collection('user_devices').find({
          $or: [
            { userEmail: email },
            { userId: customer._id.toString() }
          ],
          isActive: true
        }).toArray();
        
        for (const device of devices) {
          // 1. Send Completion Notification
          notificationService.send({
            deviceToken: device.deviceToken,
            deviceType: device.deviceType || 'android',
            title: '✅ Trip completed!',
            body: \\\`Thank you for riding with us. Distance: \${actualDistance} km\\\`,
            data: {
              type: 'trip_completed',
              tripId: data.tripId,
              actualDistance: actualDistance
            }
          }).catch(e => console.log('Completion notif failed:', e.message));
          
          // 2. Send Feedback Request Notification
          notificationService.send({
            deviceToken: device.deviceToken,
            deviceType: device.deviceType || 'android',
            title: '⭐ How was your ride?',
            body: \\\`Please rate your experience with \${driver.personalInfo?.name || driver.name || 'your driver'}\\\`,
            data: {
              type: 'feedback_request',
              tripId: data.tripId,
              stopId: data.stopId,
              tripNumber: data.tripNumber,
              action: 'open_feedback'
            },
            priority: 'high',
            category: 'feedback'
          }).catch(e => console.log('Feedback notif failed:', e.message));
        }
        
        // Save feedback request to database
        const feedbackRequestDoc = {
          tripId: new ObjectId(data.tripId),
          tripGroupId: tripGroupId,
          stopId: data.stopId,
          customerId: customer._id,
          customerEmail: customer.email,
          customerName: customer.name,
          driverId: driverMongoId,
          feedbackGiven: false,
          requestedAt: new Date(),
          expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000) // 24 hours
        };
        await req.db.collection('feedback_requests').insertOne(feedbackRequestDoc);
        
        console.log(\\\`   ✅ Completion & Feedback sent to \${customer.name || email}\\\`);
      }
    }\`
    );
  }
  
  if (skip && lines[i].includes('TRIP COMPLETED SUCCESSFULLY')) {
    skip = false;
    // We skipped up to the log line before it, so let's push the boundary lines
    newLines.push("    console.log('='.repeat(80));");
    newLines.push(lines[i]);
    continue;
  }
  
  if (!skip) {
    newLines.push(lines[i]);
  }
}

fs.writeFileSync(targetPath, newLines.join('\\n'), 'utf8');
console.log('Successfully updated feedback and completion notifications for /end using safe lines split');
