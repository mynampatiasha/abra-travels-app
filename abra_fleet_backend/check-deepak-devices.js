const { MongoClient } = require('mongodb');
require('dotenv').config({ path: '.env' });

async function checkDevices() {
  const client = await MongoClient.connect(process.env.MONGODB_URI);
  const db = client.db('abra_fleet');
  
  const collections = await db.listCollections().toArray();
  console.log('All collections:', collections.map(c => c.name).join(', '));
  
  // Check device_tokens collection
  try {
    const deviceTokens = await db.collection('device_tokens').find({ 
      $or: [
        { userId: '6958bb76aa7823cfd6ff72d0' },
        { email: 'deepak.joshi@abrafleet.com' }
      ]
    }).toArray();
    console.log('\nDevice tokens for Deepak:', JSON.stringify(deviceTokens, null, 2));
  } catch(e) {
    console.log('device_tokens collection error:', e.message);
  }

  // Also check notifications already stored for this user
  try {
    const notifs = await db.collection('notifications').find({ 
      $or: [
        { userId: '6958bb76aa7823cfd6ff72d0' },
        { userEmail: 'deepak.joshi@abrafleet.com' }
      ]
    }).sort({ createdAt: -1 }).limit(3).toArray();
    console.log('\nRecent notifications:', JSON.stringify(notifs.map(n => ({
      id: n._id, title: n.title, userId: n.userId, userEmail: n.userEmail, createdAt: n.createdAt
    })), null, 2));
  } catch(e) {
    console.log('notifications error:', e.message);
  }

  await client.close();
}
checkDevices().catch(console.error);
