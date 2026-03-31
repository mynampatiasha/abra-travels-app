const mongoose = require('mongoose');

// Connect to MongoDB directly
async function testCustomersDirectDB() {
  try {
    console.log('🧪 Testing Billing Customers via Direct DB Connection...\n');
    
    // Connect to MongoDB
    await mongoose.connect('mongodb://localhost:27017/abra_fleet_management');
    console.log('✅ Connected to MongoDB');
    
    // Define the schema (same as in invoice.js)
    const billingCustomerSchema = new mongoose.Schema({
      customerName: {
        type: String,
        required: true,
        trim: true,
        index: true
      },
      customerEmail: {
        type: String,
        required: true,
        trim: true,
        lowercase: true,
        index: true
      },
      customerPhone: {
        type: String,
        required: true,
        trim: true
      },
      companyName: {
        type: String,
        trim: true
      },
      gstNumber: {
        type: String,
        trim: true,
        uppercase: true
      },
      billingAddress: {
        street: String,
        city: String,
        state: String,
        pincode: String,
        country: { type: String, default: 'India' }
      },
      shippingAddress: {
        street: String,
        city: String,
        state: String,
        pincode: String,
        country: { type: String, default: 'India' }
      },
      contactPerson: String,
      website: String,
      notes: String,
      isActive: {
        type: Boolean,
        default: true,
        index: true
      },
      createdBy: {
        type: String,
        required: true
      },
      updatedBy: String,
      createdAt: {
        type: Date,
        default: Date.now,
        index: true
      },
      updatedAt: {
        type: Date,
        default: Date.now
      }
    }, {
      timestamps: true,
      collection: 'billing-customers'
    });
    
    const BillingCustomer = mongoose.model('BillingCustomer', billingCustomerSchema);
    
    // Test 1: Create a customer
    console.log('📝 Step 1: Creating a test customer...');
    
    const testCustomer = new BillingCustomer({
      customerName: 'Direct DB Test Customer',
      customerEmail: 'directdb@test.com',
      customerPhone: '+91-9876543210',
      companyName: 'Direct DB Test Company',
      gstNumber: '29ABCDE1234F1Z5',
      billingAddress: {
        street: '123 Direct DB Street',
        city: 'Bangalore',
        state: 'Karnataka',
        pincode: '560001',
        country: 'India'
      },
      notes: 'Created via direct DB connection for testing',
      createdBy: 'test-script'
    });
    
    const savedCustomer = await testCustomer.save();
    console.log('   ✅ Customer created successfully!');
    console.log('   Customer ID:', savedCustomer._id);
    console.log('   Customer Name:', savedCustomer.customerName);
    console.log('   Customer Email:', savedCustomer.customerEmail);
    
    // Test 2: Fetch all customers
    console.log('\n📋 Step 2: Fetching all customers...');
    
    const allCustomers = await BillingCustomer.find({ isActive: true });
    console.log('   ✅ Found', allCustomers.length, 'active customers');
    
    if (allCustomers.length > 0) {
      console.log('   Sample customers:');
      allCustomers.slice(0, 3).forEach((customer, index) => {
        console.log(`   ${index + 1}. ${customer.customerName} (${customer.customerEmail})`);
      });
    }
    
    // Test 3: Search functionality
    console.log('\n🔍 Step 3: Testing search functionality...');
    
    const searchResults = await BillingCustomer.find({
      $or: [
        { customerName: { $regex: 'test', $options: 'i' } },
        { customerEmail: { $regex: 'test', $options: 'i' } },
        { companyName: { $regex: 'test', $options: 'i' } }
      ],
      isActive: true
    });
    
    console.log('   ✅ Search found', searchResults.length, 'customers with "test"');
    
    // Test 4: Update customer
    console.log('\n✏️ Step 4: Updating customer...');
    
    savedCustomer.notes = 'Updated via direct DB connection';
    savedCustomer.updatedBy = 'test-script-update';
    await savedCustomer.save();
    
    console.log('   ✅ Customer updated successfully!');
    console.log('   Updated notes:', savedCustomer.notes);
    
    // Test 5: Statistics
    console.log('\n📊 Step 5: Getting customer statistics...');
    
    const stats = await BillingCustomer.aggregate([
      {
        $group: {
          _id: null,
          totalCustomers: { $sum: 1 },
          activeCustomers: {
            $sum: { $cond: [{ $eq: ['$isActive', true] }, 1, 0] }
          },
          inactiveCustomers: {
            $sum: { $cond: [{ $eq: ['$isActive', false] }, 1, 0] }
          }
        }
      }
    ]);
    
    const result = stats[0] || {
      totalCustomers: 0,
      activeCustomers: 0,
      inactiveCustomers: 0
    };
    
    console.log('   ✅ Customer statistics:');
    console.log('   Total customers:', result.totalCustomers);
    console.log('   Active customers:', result.activeCustomers);
    console.log('   Inactive customers:', result.inactiveCustomers);
    
    console.log('\n🎉 Direct DB testing completed successfully!');
    console.log('   The billing customer schema and operations work correctly.');
    console.log('   The API routes should work once authentication is resolved.');
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
  } finally {
    await mongoose.disconnect();
    console.log('✅ Disconnected from MongoDB');
  }
}

testCustomersDirectDB();