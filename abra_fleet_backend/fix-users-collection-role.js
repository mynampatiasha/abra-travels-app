// Fix users collection to have super_admin role for admin@abrafleet.com
require('dotenv').config();
const mongoose = require('mongoose');

async function fixUsersCollectionRole() {
  try {
    console.log('\n🔧 Fixing users collection role...');
    console.log('─'.repeat(80));
    
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected to MongoDB');
    
    // Update users collection to use super_admin for admin@abrafleet.com
    const result = await mongoose.connection.db.collection('users').updateMany(
      { email: 'admin@abrafleet.com' },
      { $set: { role: 'super_admin' } }
    );
    
    console.log(`✅ Updated ${result.modifiedCount} users records`);
    
    // Verify the changes
    const user = await mongoose.connection.db.collection('users').findOne({ 
      email: 'admin@abrafleet.com' 
    });
    
    if (user) {
      console.log(`✅ Verified users collection role: ${user.role}`);
    }
    
    console.log('\n─'.repeat(80) + '\n');
    
    await mongoose.disconnect();
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    process.exit(1);
  }
}

fixUsersCollectionRole();