const mongoose = require('mongoose');
require('dotenv').config();

// MongoDB Connection
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet_billing';

mongoose.connect(MONGODB_URI, {
  useNewUrlParser: true,
  useUnifiedTopology: true,
})
.then(() => console.log('✅ MongoDB connected for testing'))
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

async function testItemsDatabase() {
  console.log('🧪 Testing Items Database Operations\n');

  try {
    // Test 1: Check existing items
    console.log('1️⃣ Checking existing items in database');
    const existingItems = await Item.find({ isActive: true });
    console.log(`📊 Found ${existingItems.length} existing items`);
    
    if (existingItems.length > 0) {
      console.log('📝 Sample items:');
      existingItems.slice(0, 3).forEach((item, index) => {
        console.log(`   ${index + 1}. ${item.name} (${item.type}) - Created: ${item.createdAt.toDateString()}`);
      });
    }
    console.log('');

    // Test 2: Create sample items if none exist
    if (existingItems.length === 0) {
      console.log('2️⃣ Creating sample items for testing');
      
      const sampleItems = [
        {
          name: 'Vehicle Service',
          type: 'Service',
          unit: 'hour',
          isSellable: true,
          isPurchasable: true,
          sellingPrice: 2500.00,
          costPrice: 2000.00,
          salesAccount: 'Service Revenue',
          purchaseAccount: 'Direct Expenses',
          salesDescription: 'Complete vehicle maintenance service',
          purchaseDescription: 'Cost for vehicle service materials and labor'
        },
        {
          name: 'Fuel Charges',
          type: 'Service',
          unit: 'liter',
          isSellable: true,
          isPurchasable: true,
          sellingPrice: 100.00,
          costPrice: 95.00,
          salesAccount: 'Sales',
          purchaseAccount: 'Cost of Goods Sold',
          salesDescription: 'Fuel charges for transportation',
          purchaseDescription: 'Fuel purchase cost'
        },
        {
          name: 'Driver Allowance',
          type: 'Service',
          unit: 'day',
          isSellable: true,
          isPurchasable: false,
          sellingPrice: 500.00,
          salesAccount: 'Service Revenue',
          salesDescription: 'Daily driver allowance'
        },
        {
          name: 'Vehicle Insurance',
          type: 'Service',
          unit: 'year',
          isSellable: true,
          isPurchasable: true,
          sellingPrice: 15000.00,
          costPrice: 14000.00,
          salesAccount: 'Service Revenue',
          purchaseAccount: 'Direct Expenses',
          salesDescription: 'Annual vehicle insurance coverage',
          purchaseDescription: 'Insurance premium cost'
        },
        {
          name: 'Maintenance Kit',
          type: 'Goods',
          unit: 'kit',
          isSellable: true,
          isPurchasable: true,
          sellingPrice: 1200.00,
          costPrice: 800.00,
          salesAccount: 'Sales',
          purchaseAccount: 'Cost of Goods Sold',
          salesDescription: 'Complete vehicle maintenance kit',
          purchaseDescription: 'Maintenance kit purchase cost'
        }
      ];

      for (const itemData of sampleItems) {
        const item = new Item(itemData);
        await item.save();
        console.log(`✅ Created: ${item.name}`);
      }
      console.log('');
    }

    // Test 3: Test search functionality
    console.log('3️⃣ Testing search functionality');
    const searchResults = await Item.find({
      isActive: true,
      $or: [
        { name: { $regex: 'vehicle', $options: 'i' } },
        { salesDescription: { $regex: 'vehicle', $options: 'i' } },
        { purchaseDescription: { $regex: 'vehicle', $options: 'i' } }
      ]
    });
    console.log(`🔍 Search for "vehicle": ${searchResults.length} results`);
    searchResults.forEach(item => {
      console.log(`   - ${item.name} (${item.type})`);
    });
    console.log('');

    // Test 4: Test type filtering
    console.log('4️⃣ Testing type filtering');
    const serviceItems = await Item.find({ isActive: true, type: 'Service' });
    const goodsItems = await Item.find({ isActive: true, type: 'Goods' });
    console.log(`📦 Services: ${serviceItems.length} items`);
    console.log(`📦 Goods: ${goodsItems.length} items`);
    console.log('');

    // Test 5: Test date filtering
    console.log('5️⃣ Testing date filtering');
    const today = new Date();
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    
    const recentItems = await Item.find({
      isActive: true,
      createdAt: {
        $gte: thirtyDaysAgo,
        $lt: today
      }
    });
    console.log(`📅 Items created in last 30 days: ${recentItems.length}`);
    console.log('');

    // Test 6: Test pagination
    console.log('6️⃣ Testing pagination');
    const page1 = await Item.find({ isActive: true })
      .sort({ createdAt: -1 })
      .limit(3)
      .skip(0);
    console.log(`📄 Page 1 (3 items): ${page1.length} results`);
    page1.forEach((item, index) => {
      console.log(`   ${index + 1}. ${item.name} - ₹${item.sellingPrice || 0}`);
    });
    console.log('');

    // Test 7: Test combined filters
    console.log('7️⃣ Testing combined filters');
    const combinedResults = await Item.find({
      isActive: true,
      type: 'Service',
      $or: [
        { name: { $regex: 'service', $options: 'i' } },
        { salesDescription: { $regex: 'service', $options: 'i' } }
      ]
    });
    console.log(`🔍 Service items with "service" in name/description: ${combinedResults.length}`);
    combinedResults.forEach(item => {
      console.log(`   - ${item.name}: ₹${item.sellingPrice || 0}`);
    });
    console.log('');

    console.log('🎉 All database tests completed successfully!');
    console.log(`📊 Total items in database: ${await Item.countDocuments({ isActive: true })}`);

  } catch (error) {
    console.error('❌ Test failed:', error.message);
    console.error(error);
  } finally {
    mongoose.connection.close();
  }
}

// Run the tests
testItemsDatabase();