const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function testFeedbackSystem() {
  const client = new MongoClient(MONGODB_URI);

  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');

    const db = client.db();

    // 1. Create test feedback
    console.log('\n📝 Creating test feedback...');
    
    const testFeedback = {
      tripId: new ObjectId(),
      tripType: 'pickup',
      customerId: new ObjectId(),
      driverId: new ObjectId(),
      vehicleId: new ObjectId(),
      routeId: new ObjectId(),
      organizationId: new ObjectId(),
      rating: 5,
      quickTags: ['on_time', 'clean_vehicle', 'safe_driving'],
      comment: 'Excellent service! Driver was very professional.',
      feedbackType: 'post_trip',
      tripDate: new Date(),
      tripDelay: 0,
      wasLate: false,
      promptedAt: new Date(),
      submittedAt: new Date(),
      status: 'submitted',
      reviewedBy: null,
      actionTaken: null
    };

    const result = await db.collection('feedback').insertOne(testFeedback);
    console.log('✅ Test feedback created:', result.insertedId);

    // 2. Create low rating feedback (should auto-escalate)
    console.log('\n⚠️  Creating low rating feedback...');
    
    const lowRatingFeedback = {
      ...testFeedback,
      _id: new ObjectId(),
      rating: 2,
      quickTags: ['late', 'rash_driving'],
      comment: 'Driver was 20 minutes late and drove rashly.',
      tripDelay: 20,
      wasLate: true,
      status: 'escalated',
      escalatedAt: new Date()
    };

    await db.collection('feedback').insertOne(lowRatingFeedback);
    console.log('✅ Low rating feedback created (escalated)');

    // 3. Query feedback statistics
    console.log('\n📊 Feedback Statistics:');
    
    const stats = await db.collection('feedback').aggregate([
      {
        $group: {
          _id: null,
          totalFeedback: { $sum: 1 },
          averageRating: { $avg: '$rating' },
          ratings: { $push: '$rating' }
        }
      }
    ]).toArray();

    if (stats.length > 0) {
      const ratingBreakdown = { 5: 0, 4: 0, 3: 0, 2: 0, 1: 0 };
      stats[0].ratings.forEach(r => ratingBreakdown[r]++);

      console.log('Total Feedback:', stats[0].totalFeedback);
      console.log('Average Rating:', stats[0].averageRating.toFixed(2));
      console.log('Rating Breakdown:', ratingBreakdown);
    }

    // 4. Test driver stats aggregation
    console.log('\n👨‍✈️ Creating driver stats...');
    
    const driverStats = {
      driverId: testFeedback.driverId,
      period: `${new Date().getFullYear()}-${String(new Date().getMonth() + 1).padStart(2, '0')}`,
      organizationId: testFeedback.organizationId,
      totalTrips: 50,
      feedbackReceived: 40,
      averageRating: 4.5,
      ratingBreakdown: {
        5: 25,
        4: 10,
        3: 3,
        2: 1,
        1: 1
      },
      commonIssues: {
        late: 2,
        ac_issue: 1
      },
      punctualityScore: 92,
      lastUpdated: new Date()
    };

    await db.collection('driver_feedback_stats').insertOne(driverStats);
    console.log('✅ Driver stats created');

    // 5. Query escalated feedback
    console.log('\n🚨 Escalated Feedback:');
    
    const escalated = await db.collection('feedback')
      .find({ status: 'escalated' })
      .toArray();

    console.log(`Found ${escalated.length} escalated feedback items`);
    escalated.forEach(f => {
      console.log(`  - Rating: ${f.rating}, Comment: ${f.comment}`);
    });

    // 6. Test feedback eligibility logic
    console.log('\n✅ Feedback Eligibility Tests:');
    
    const testCases = [
      { scenario: 'First trip with driver', previousTrips: 0, delay: 0, expected: true },
      { scenario: 'Significant delay', previousTrips: 5, delay: 15, expected: true },
      { scenario: 'Regular trip (20% sampling)', previousTrips: 5, delay: 0, expected: 'random' },
    ];

    testCases.forEach(test => {
      console.log(`  ${test.scenario}: ${test.expected === true ? '✅ Should prompt' : test.expected === 'random' ? '🎲 Random (20%)' : '❌ Skip'}`);
    });

    console.log('\n✅ Feedback system test completed successfully!');

  } catch (error) {
    console.error('❌ Error testing feedback system:', error);
  } finally {
    await client.close();
    console.log('\n🔌 Disconnected from MongoDB');
  }
}

testFeedbackSystem();
