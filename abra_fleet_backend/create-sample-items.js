const mongoose = require('mongoose');
require('dotenv').config();

// MongoDB Connection
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet_billing';

mongoose.connect(MONGODB_URI, {
  useNewUrlParser: true,
  useUnifiedTopology: true,
})
.then(() => console.log('✅ MongoDB connected for creating sample items'))
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

async function createSampleItems() {
  console.log('🧪 Creating Sample Items for Testing\n');

  try {
    // Clear existing items first (optional)
    console.log('🗑️ Clearing existing items...');
    await Item.deleteMany({});
    console.log('✅ Cleared existing items\n');

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
        salesDescription: 'Complete vehicle maintenance service including oil change, brake check, and general inspection',
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
        salesDescription: 'Fuel charges for transportation services',
        purchaseDescription: 'Fuel purchase cost from suppliers'
      },
      {
        name: 'Driver Allowance',
        type: 'Service',
        unit: 'day',
        isSellable: true,
        isPurchasable: false,
        sellingPrice: 500.00,
        salesAccount: 'Service Revenue',
        salesDescription: 'Daily driver allowance for transportation services'
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
        salesDescription: 'Annual vehicle insurance coverage for fleet vehicles',
        purchaseDescription: 'Insurance premium cost paid to insurance company'
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
        salesDescription: 'Complete vehicle maintenance kit with tools and supplies',
        purchaseDescription: 'Maintenance kit purchase cost from supplier'
      },
      {
        name: 'GPS Tracking Device',
        type: 'Goods',
        unit: 'piece',
        isSellable: true,
        isPurchasable: true,
        sellingPrice: 5000.00,
        costPrice: 3500.00,
        salesAccount: 'Sales',
        purchaseAccount: 'Cost of Goods Sold',
        salesDescription: 'Advanced GPS tracking device for vehicle monitoring',
        purchaseDescription: 'GPS device purchase from technology supplier'
      },
      {
        name: 'Fleet Management Software',
        type: 'Service',
        unit: 'month',
        isSellable: true,
        isPurchasable: true,
        sellingPrice: 2000.00,
        costPrice: 1500.00,
        salesAccount: 'Service Revenue',
        purchaseAccount: 'Direct Expenses',
        salesDescription: 'Monthly subscription for fleet management software',
        purchaseDescription: 'Software licensing cost'
      },
      {
        name: 'Vehicle Cleaning Service',
        type: 'Service',
        unit: 'service',
        isSellable: true,
        isPurchasable: true,
        sellingPrice: 300.00,
        costPrice: 200.00,
        salesAccount: 'Service Revenue',
        purchaseAccount: 'Direct Expenses',
        salesDescription: 'Professional vehicle cleaning and detailing service',
        purchaseDescription: 'Cost for cleaning supplies and labor'
      },
      {
        name: 'Emergency Roadside Assistance',
        type: 'Service',
        unit: 'call',
        isSellable: true,
        isPurchasable: true,
        sellingPrice: 1500.00,
        costPrice: 1200.00,
        salesAccount: 'Service Revenue',
        purchaseAccount: 'Direct Expenses',
        salesDescription: '24/7 emergency roadside assistance service',
        purchaseDescription: 'Cost for emergency service provider'
      },
      {
        name: 'Vehicle Spare Parts',
        type: 'Goods',
        unit: 'set',
        isSellable: true,
        isPurchasable: true,
        sellingPrice: 3500.00,
        costPrice: 2800.00,
        salesAccount: 'Sales',
        purchaseAccount: 'Cost of Goods Sold',
        salesDescription: 'Essential spare parts set for vehicle maintenance',
        purchaseDescription: 'Spare parts purchase from authorized dealer'
      }
    ];

    console.log('📦 Creating sample items...\n');
    
    for (const itemData of sampleItems) {
      const item = new Item(itemData);
      await item.save();
      console.log(`✅ Created: ${item.name} (${item.type}) - ₹${item.sellingPrice}`);
    }

    console.log('\n🎉 Sample items created successfully!');
    console.log(`📊 Total items created: ${sampleItems.length}`);

    // Test the search functionality
    console.log('\n🔍 Testing search functionality:');
    
    const vehicleSearch = await Item.find({
      isActive: true,
      $or: [
        { name: { $regex: 'vehicle', $options: 'i' } },
        { salesDescription: { $regex: 'vehicle', $options: 'i' } },
        { purchaseDescription: { $regex: 'vehicle', $options: 'i' } }
      ]
    });
    console.log(`   - "vehicle" search: ${vehicleSearch.length} results`);

    const serviceSearch = await Item.find({
      isActive: true,
      type: 'Service'
    });
    console.log(`   - Service items: ${serviceSearch.length} results`);

    const goodsSearch = await Item.find({
      isActive: true,
      type: 'Goods'
    });
    console.log(`   - Goods items: ${goodsSearch.length} results`);

  } catch (error) {
    console.error('❌ Error creating sample items:', error.message);
    console.error(error);
  } finally {
    mongoose.connection.close();
  }
}

// Run the creation
createSampleItems();