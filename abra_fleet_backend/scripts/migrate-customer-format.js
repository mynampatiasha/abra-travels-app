// scripts/migrate-customer-format.js
// Migration script to convert nested format customers to flat format

const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function migrateCustomerFormat() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    console.log('\n🔄 CUSTOMER FORMAT MIGRATION STARTED');
    console.log('═'.repeat(80));
    
    await client.connect();
    const db = client.db();
    const customersCollection = db.collection('customers');
    
    // Find all customers with nested format
    const nestedFormatCustomers = await customersCollection.find({
      $or: [
        { 'name.firstName': { $exists: true } },
        { 'contactInfo.email': { $exists: true } },
        { 'company.name': { $exists: true } }
      ]
    }).toArray();
    
    console.log(`\n📊 Found ${nestedFormatCustomers.length} customers with nested format`);
    
    if (nestedFormatCustomers.length === 0) {
      console.log('✅ No customers need migration. All customers are already in flat format.');
      return;
    }
    
    console.log('\n🔧 Starting migration...\n');
    
    let successCount = 0;
    let errorCount = 0;
    
    for (const customer of nestedFormatCustomers) {
      try {
        // Build the flat format update
        const flatFormat = {
          $set: {}
        };
        
        // Migrate name field
        if (customer.name && typeof customer.name === 'object') {
          const firstName = customer.name.firstName || '';
          const lastName = customer.name.lastName || '';
          flatFormat.$set.name = `${firstName} ${lastName}`.trim();
          
          // If companyName was in name object, move it to root
          if (customer.name.companyName && !customer.companyName) {
            flatFormat.$set.companyName = customer.name.companyName;
          }
        }
        
        // Migrate contactInfo fields
        if (customer.contactInfo && typeof customer.contactInfo === 'object') {
          if (customer.contactInfo.email && !customer.email) {
            flatFormat.$set.email = customer.contactInfo.email;
          }
          if (customer.contactInfo.phone && !customer.phone) {
            flatFormat.$set.phone = customer.contactInfo.phone;
          }
        }
        
        // Migrate company field
        if (customer.company && typeof customer.company === 'object') {
          if (customer.company.name && !customer.companyName) {
            flatFormat.$set.companyName = customer.company.name;
          }
        }
        
        // Ensure required fields have defaults
        if (!flatFormat.$set.name && !customer.name) {
          flatFormat.$set.name = customer.email || 'Unknown';
        }
        if (!flatFormat.$set.email && !customer.email) {
          flatFormat.$set.email = '';
        }
        if (!flatFormat.$set.phone && !customer.phone) {
          flatFormat.$set.phone = '';
        }
        if (!flatFormat.$set.companyName && !customer.companyName) {
          flatFormat.$set.companyName = '';
        }
        
        // Ensure other required fields exist
        if (!customer.department) {
          flatFormat.$set.department = '';
        }
        if (!customer.branch) {
          flatFormat.$set.branch = '';
        }
        if (!customer.employeeId) {
          flatFormat.$set.employeeId = customer.customerId || '';
        }
        if (!customer.status) {
          flatFormat.$set.status = 'active';
        }
        if (!customer.role) {
          flatFormat.$set.role = 'customer';
        }
        
        // Update timestamp
        flatFormat.$set.updatedAt = new Date();
        flatFormat.$set.migratedAt = new Date();
        flatFormat.$set.migrationNote = 'Converted from nested to flat format';
        
        // Remove nested fields
        const unsetFields = {
          $unset: {}
        };
        
        if (customer.name && typeof customer.name === 'object') {
          unsetFields.$unset['name.firstName'] = '';
          unsetFields.$unset['name.lastName'] = '';
          unsetFields.$unset['name.companyName'] = '';
        }
        if (customer.contactInfo) {
          unsetFields.$unset.contactInfo = '';
        }
        if (customer.company) {
          unsetFields.$unset.company = '';
        }
        if (customer.billingAddress) {
          unsetFields.$unset.billingAddress = '';
        }
        if (customer.shippingAddress) {
          unsetFields.$unset.shippingAddress = '';
        }
        if (customer.notes) {
          unsetFields.$unset.notes = '';
        }
        
        // Perform the update
        const updateOperations = { ...flatFormat };
        if (Object.keys(unsetFields.$unset).length > 0) {
          updateOperations.$unset = unsetFields.$unset;
        }
        
        await customersCollection.updateOne(
          { _id: customer._id },
          updateOperations
        );
        
        successCount++;
        console.log(`✅ [${successCount}/${nestedFormatCustomers.length}] Migrated: ${customer.email || customer.contactInfo?.email || customer._id}`);
        
      } catch (error) {
        errorCount++;
        console.error(`❌ Error migrating customer ${customer._id}:`, error.message);
      }
    }
    
    console.log('\n' + '═'.repeat(80));
    console.log('📊 MIGRATION SUMMARY');
    console.log('═'.repeat(80));
    console.log(`✅ Successfully migrated: ${successCount}`);
    console.log(`❌ Failed: ${errorCount}`);
    console.log(`📊 Total processed: ${nestedFormatCustomers.length}`);
    
    // Verify migration
    console.log('\n🔍 Verifying migration...');
    const remainingNestedCustomers = await customersCollection.countDocuments({
      $or: [
        { 'name.firstName': { $exists: true } },
        { 'contactInfo.email': { $exists: true } },
        { 'company.name': { $exists: true } }
      ]
    });
    
    if (remainingNestedCustomers === 0) {
      console.log('✅ Migration verified! All customers are now in flat format.');
    } else {
      console.log(`⚠️ Warning: ${remainingNestedCustomers} customers still have nested format.`);
    }
    
    // Show sample of migrated customers
    console.log('\n📋 Sample of migrated customers:');
    const sampleCustomers = await customersCollection.find({
      migratedAt: { $exists: true }
    }).limit(3).toArray();
    
    sampleCustomers.forEach((customer, index) => {
      console.log(`\n${index + 1}. ${customer.name} (${customer.email})`);
      console.log(`   - Customer ID: ${customer.customerId}`);
      console.log(`   - Company: ${customer.companyName || 'N/A'}`);
      console.log(`   - Department: ${customer.department || 'N/A'}`);
      console.log(`   - Branch: ${customer.branch || 'N/A'}`);
      console.log(`   - Status: ${customer.status}`);
    });
    
    console.log('\n✅ MIGRATION COMPLETED SUCCESSFULLY');
    
  } catch (error) {
    console.error('\n❌ Migration failed:', error);
    throw error;
  } finally {
    await client.close();
  }
}

// Run migration
if (require.main === module) {
  migrateCustomerFormat()
    .then(() => {
      console.log('\n👋 Migration script finished');
      process.exit(0);
    })
    .catch((error) => {
      console.error('\n💥 Migration script failed:', error);
      process.exit(1);
    });
}

module.exports = { migrateCustomerFormat };
