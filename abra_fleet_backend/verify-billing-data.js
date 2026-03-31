const { MongoClient } = require('mongodb');
require('dotenv').config();

async function verifyBillingData() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('abra_fleet');
    
    // Check contracts
    console.log('📝 CONTRACTS:');
    console.log('='.repeat(60));
    const contracts = await db.collection('contracts').find({}).toArray();
    console.log(`Total Contracts: ${contracts.length}\n`);
    
    contracts.forEach((contract, index) => {
      console.log(`${index + 1}. ${contract.contractId}`);
      console.log(`   Organization: ${contract.organizationName}`);
      console.log(`   Status: ${contract.status}`);
      console.log(`   Period: ${contract.startDate.toISOString().split('T')[0]} to ${contract.endDate.toISOString().split('T')[0]}`);
      console.log(`   Billing Cycle: ${contract.paymentTerms.billingCycle}`);
      console.log(`   Min/Max: ₹${contract.paymentTerms.monthlyMinimum} / ₹${contract.paymentTerms.monthlyMaximum}`);
      console.log(`   Vehicle Types: ${Object.keys(contract.vehiclePricing).join(', ')}`);
      console.log('');
    });
    
    // Check invoices
    console.log('\n💰 INVOICES:');
    console.log('='.repeat(60));
    const invoices = await db.collection('invoices').find({}).sort({ date: -1 }).toArray();
    console.log(`Total Invoices: ${invoices.length}\n`);
    
    invoices.forEach((invoice, index) => {
      console.log(`${index + 1}. ${invoice.id}`);
      console.log(`   Organization: ${invoice.organizationName}`);
      console.log(`   Contract: ${invoice.contractId}`);
      console.log(`   Status: ${invoice.status}`);
      console.log(`   Amount: ₹${invoice.totalAmount.toFixed(2)}`);
      console.log(`   Paid: ₹${invoice.amountPaid.toFixed(2)}`);
      console.log(`   Due: ₹${(invoice.totalAmount - invoice.amountPaid).toFixed(2)}`);
      console.log(`   Trips: ${invoice.trips}`);
      console.log(`   Date: ${invoice.date.toISOString().split('T')[0]}`);
      console.log(`   Due Date: ${invoice.dueDate.toISOString().split('T')[0]}`);
      console.log('');
    });
    
    // Check audit logs
    console.log('\n📋 AUDIT LOGS:');
    console.log('='.repeat(60));
    const auditLogs = await db.collection('audit_logs')
      .find({ entityType: { $in: ['contract', 'invoice'] } })
      .sort({ timestamp: -1 })
      .limit(10)
      .toArray();
    console.log(`Total Audit Logs: ${auditLogs.length} (showing last 10)\n`);
    
    auditLogs.forEach((log, index) => {
      console.log(`${index + 1}. ${log.action.toUpperCase()} ${log.entityType}`);
      console.log(`   Entity ID: ${log.entityId}`);
      console.log(`   By: ${log.userName}`);
      console.log(`   Time: ${log.timestamp.toISOString()}`);
      console.log(`   Remarks: ${log.remarks || 'N/A'}`);
      console.log('');
    });
    
    // Statistics
    console.log('\n📊 STATISTICS:');
    console.log('='.repeat(60));
    
    const totalRevenue = invoices.reduce((sum, inv) => sum + inv.totalAmount, 0);
    const totalPaid = invoices.reduce((sum, inv) => sum + inv.amountPaid, 0);
    const totalPending = totalRevenue - totalPaid;
    const totalTrips = invoices.reduce((sum, inv) => sum + inv.trips, 0);
    
    const statusCounts = invoices.reduce((acc, inv) => {
      acc[inv.status] = (acc[inv.status] || 0) + 1;
      return acc;
    }, {});
    
    console.log(`Total Revenue: ₹${totalRevenue.toFixed(2)}`);
    console.log(`Total Paid: ₹${totalPaid.toFixed(2)}`);
    console.log(`Total Pending: ₹${totalPending.toFixed(2)}`);
    console.log(`Total Trips: ${totalTrips}`);
    console.log(`\nInvoice Status Breakdown:`);
    Object.entries(statusCounts).forEach(([status, count]) => {
      console.log(`   ${status}: ${count}`);
    });
    
    console.log('\n' + '='.repeat(60));
    console.log('✅ VERIFICATION COMPLETE!');
    console.log('='.repeat(60));
    console.log('\n🚀 Ready to test! Start your backend server:');
    console.log('   cd abra_fleet_backend');
    console.log('   node index.js');
    console.log('\n');
    
  } catch (error) {
    console.error('❌ Error verifying billing data:', error);
  } finally {
    await client.close();
  }
}

// Run verification
verifyBillingData();
