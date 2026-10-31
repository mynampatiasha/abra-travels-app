const { MongoClient } = require('mongodb');
require('dotenv').config();
MongoClient.connect(process.env.MONGODB_URI).then(async client => {
  const db = client.db('abra_fleet');
  
  const upsertResult = await db.collection('trip_otps').findOneAndUpdate(
    {
      tripGroupId: '694a7beec1882931f34d490a-pickup-2026-02-11',
      stopId: '69804b4055d83112afcc3474',
      passengerId: '69804b4055d83112afcc3474',
      type: 'step_in',
    },
    {
      $set: {
        updatedAt: new Date(),
      },
    },
    { upsert: true, returnDocument: 'after', includeResultMetadata: true }
  );

  console.log('upsertResult keys:', Object.keys(upsertResult));
  console.log('upsertResult.value defined?', !!upsertResult.value);
  console.log('upsertResult.verified:', upsertResult.verified);
  if (upsertResult.value) {
    console.log('upsertResult.value.verified:', upsertResult.value.verified);
  }

  client.close();
});
