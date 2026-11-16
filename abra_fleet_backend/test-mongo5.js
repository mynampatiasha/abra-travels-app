const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();
MongoClient.connect(process.env.MONGODB_URI).then(client => {
  const db = client.db('test');
  db.collection('trip_otps').find({
    $or: [
      { passengerId: '69804b4055d83112afcc3474' },
      { passengerId: new ObjectId('69804b4055d83112afcc3474') }
    ]
  }).toArray().then(docs => {
    console.log(JSON.stringify(docs, null, 2));
    client.close();
  });
});
