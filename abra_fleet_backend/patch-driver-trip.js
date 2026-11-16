const fs = require('fs');

let content = fs.readFileSync('routes/driver_trip_router.js', 'utf8');

const oldLogic = `    // STEP 4: Send completion notifications
    // ========================================================================
    console.log(\`\\n📲 Sending completion notifications...\`);
    
    for (const trip of trips) {
      // ✅ FIXED: Find customer in CUSTOMERS collection
      const customer = await req.db.collection('customers').findOne({
        email: trip.customerEmail
      });
      
      if (customer) {
        // Get all customer devices
        const devices = await req.db.collection('user_devices').find({
          $or: [
            { userEmail: trip.customerEmail },
            { userId: customer._id.toString() }
          ],
          isActive: true
        }).toArray();
        
        for (const device of devices) {
          try {
            notificationService.send({
              deviceToken: device.deviceToken,
              deviceType: device.deviceType || 'android',
              title: '✅ Trip completed!',
              body: \`Thank you for riding with us. Distance: \${actualDistance} km\`,
              data: {
                type: 'trip_completed',
                tripId: trip._id.toString(),
                actualDistance: actualDistance
              }
            });
            
            console.log(\`   ✅ Completion notification sent to \${trip.customerName}\`);
          } catch (notifError) {
            console.log(\`   ⚠️ Failed to notify \${trip.customerName}\`);
          }
        }
      }
    }`;

const newLogic = `    // STEP 4: Send completion notifications and request feedback
    // ========================================================================
    console.log(\`\\n📲 Sending completion & feedback notifications...\`);
    
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
    }`;

if (content.includes(oldLogic)) {
  content = content.replace(oldLogic, newLogic);
  fs.writeFileSync('routes/driver_trip_router.js', content, 'utf8');
  console.log('Successfully patched driver_trip_router.js');
} else {
  console.log('Could not find old logic in driver_trip_router.js');
}
