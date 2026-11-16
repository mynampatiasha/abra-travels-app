const fs = require('fs');

const targetPath = 'routes/driver_trip_router.js';
let content = fs.readFileSync(targetPath, 'utf8');

const splitMarker = '// STEP 4: Send completion notifications';
const splitMarker2 = 'TRIP COMPLETED SUCCESSFULLY';

const startIdx = content.indexOf(splitMarker);
const endIdxRaw = content.indexOf(splitMarker2);

if (startIdx !== -1 && endIdxRaw !== -1) {
  // Find the exact console.log that prints the marker
  const endIdx = content.lastIndexOf('console.log(', endIdxRaw);
  // Find the start of the console.log line above it
  const finalEndIdx = content.lastIndexOf('console.log(', endIdx - 1);

  const newLogic = \`// STEP 4: Send completion notifications and request feedback
    // ========================================================================
    console.log(\`\\n📲 Sending completion & feedback notifications...\`);
    
    // Extract unique customers from all stops across all completed trips
    const uniqueCustomers = new Map();
    for (const trip of trips) {
      for (const stop of trip.stops || []) {
        if (stop.customer && stop.customer.email) {
          uniqueCustomers.set(stop.customer.email, {
            customerInfo: stop.customer,
            tripId: trip._id.toString(),
            tripNumber: trip.tripNumber || tripGroupId.substring(0, 8),
            stopId: stop.stopId
          });
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
            body: \`Thank you for riding with us. Distance: \${actualDistance} km\`,
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
            body: \`Please rate your experience with \${driver.personalInfo?.name || driver.name || 'your driver'}\`,
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
        
        console.log(\`   ✅ Completion & Feedback sent to \${customer.name || email}\`);
      }
    }
    
    \`;

  content = content.substring(0, startIdx) + newLogic + content.substring(finalEndIdx);
  fs.writeFileSync(targetPath, content, 'utf8');
  console.log('Successfully updated feedback and completion notifications for /end');
} else {
  console.log('Failed to find split markers', { startIdx, endIdxRaw });
}
