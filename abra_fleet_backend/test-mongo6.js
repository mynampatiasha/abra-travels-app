const { MongoClient } = require('mongodb');
require('dotenv').config();
MongoClient.connect(process.env.MONGODB_URI).then(client => {
  const db = client.db('test');
  db.collection('trip_otps').find({}).sort({ createdAt: -1 }).limit(3).toArray().then(docs => {
    console.log(JSON.stringify(docs, null, 2));
    client.close();
  });
});
