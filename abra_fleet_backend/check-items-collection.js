const mongoose = require('mongoose');

// Load environment variables
require('dotenv').config();

// MongoDB Connection
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet_billing';

mongoose.connect(MONGODB_URI, {
  useNewUrlParser: true,
  useUnifiedTopology: true,
})
.then(() => console.log('✅ MongoDB connected for checking items collection'))
.catch(err => console.error('❌ MongoDB connection error:', err));

// Item Schema (same as in new_item_billing.js)
const itemSchema = new mongoose.Schema({
  name: {
    type: String,
    required: true,
    trim: true,
    index: true,
  },
  type: {
    type: String,
    enum: ['Goods', 'Service'],
    required: true,
  },
  unit: {
    type: String,
    trim: true,
  },
  isSellable: {
    type: Boolean,
    default: true,
  },
  isPurchasable: {
    type: Boolean,
    default: true,
  },
  // Sales Information
  sellingPrice: {
    type: Number,
    min: 0,
  },
  salesAccount: {
    type: String,
    trim: true,
  },
  salesDescription: {
    type: String,
    trim: true,
  },
  // Purchase Information
  costPrice: {
    type: Number,
    min: 0,
  },
  purchaseAccount: {
    type: String,
    trim: true,
  },
  purchaseDescription: {
    type: String,
    trim: true,
  },
  preferredVendor: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Vendor',
  },
  // Metadata
  createdAt: {
    type: Date,
    default: Date.now,
  },
  updatedAt: {
    type: Date,
    default: Date.now,
  },
  isActive: {
    type: Boolean,
    default: true,
  },
});

const Item = mongoose.model('Item', itemSchema);

async function checkItemsCollection() {
  try {
    console.log('\n🔍 Checking items collection...\n');
    
    // Count total items
    const totalItems = await Item.countDocuments();
    console.log(`📊 Total items in collection: ${totalItems}`);
    
    // Count active items
    const activeItems = await Item.countDocuments({ isActive: true });
    console.log(`✅ Active items: ${activeItems}`);
    
    // Count inactive items
    const inactiveItems = await Item.countDocuments({ isActive: false });
    console.log(`❌ Inactive items: ${inactiveItems}`);
    
    if (totalItems > 0) {
      console.log('\n📋 Sample items:');
      console.log('================');
      
      // Get first 5 items
      const sampleItems = await Item.find({ isActive: true })
        .limit(5)
        .sort({ createdAt: -1 });
      
      sampleItems.forEach((item, index) => {
        console.log(`\n${index + 1}. ${item.name}`);
        console.log(`   Type: ${item.type}`);
        console.log(`   Unit: ${item.unit || 'N/A'}`);
        console.log(`   Selling Price: ₹${item.sellingPrice || 'N/A'}`);
        console.log(`   Cost Price: ₹${item.costPrice || 'N/A'}`);
        console.log(`   Sales Account: ${item.salesAccount || 'N/A'}`);
        console.log(`   Purchase Account: ${item.purchaseAccount || 'N/A'}`);
        console.log(`   Created: ${item.createdAt.toLocaleDateString()}`);
      });
      
      // Count by type
      const goodsCount = await Item.countDocuments({ type: 'Goods', isActive: true });
      const servicesCount = await Item.countDocuments({ type: 'Service', isActive: true });
      
      console.log('\n📈 Items by type:');
      console.log(`   Goods: ${goodsCount}`);
      console.log(`   Services: ${servicesCount}`);
      
    } else {
      console.log('\n📭 No items found in the collection.');
      console.log('\n💡 To create sample items, you can:');
      console.log('   1. Use the frontend billing interface');
      console.log('   2. Create items via API calls');
      console.log('   3. Run a script to create sample data');
    }
    
  } catch (error) {
    console.error('❌ Error checking items collection:', error);
  } finally {
    mongoose.connection.close();
    console.log('\n🔌 Database connection closed.');
  }
}

// Run the check
checkItemsCollection();