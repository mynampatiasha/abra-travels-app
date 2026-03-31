// Fix Asha's rosters to include customer name and email fields
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

async function fixAshaRosterCustomerFields() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    // Get Asha's rosters
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);
    
    const rosters = await db.collection('rosters').find({
      driverId: 'AMATisPyRgQc39FXypD4iu7unVs1',
      scheduledDate: { $gte: today, $lt: tomorrow }
    }).toArray();
    
    console.log(`\n📋 Found ${rosters.length} rosters to fix`);
    
    let fixed = 0;
    for (const roster of rosters) {
      // Get customer details
      const customer = await db.collection('customers').findOne({
        _id: new ObjectId(roster.customerId)
      });
      
      if (customer) {
        // Update roster with customer details
        await db.collection('rosters').updateOne(
          { _id: roster._id },
          {
            $set: {
              customerName: customer.name,
              customerEmail: customer.email,
              customerPhone: customer.phone
            }
          }
        );
        
        console.log(`✅ Fixed roster ${roster._id} - Added ${customer.name}`);
        fixed++;
      } else {
        console.log(`❌ Customer not found for roster ${roster._id}`);
      }
    }
    
    console.log(`\n🎉 Fixed ${fixed} rosters!`);
    console.log('✅ Customer names and details will now show in the driver app');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

fixAshaRosterCustomerFields();
