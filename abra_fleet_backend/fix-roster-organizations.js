// Fix roster organizations in database
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function fixRosterOrganizations() {
  console.log('🔗 Connecting to MongoDB...');
  const client = new MongoClient(MONGODB_URI);
  await client.connect();
  console.log('✅ Connected to MongoDB');
  
  const db = client.db();
  
  try {
    console.log('\n🔧 Fixing roster organizations...');
    console.log('='.repeat(60));
    
    // Find rosters that need fixing
    const rostersToFix = await db.collection('rosters').find({
      status: 'pending_assignment',
      $or: [
        { organization: { $exists: false } },
        { organization: null },
        { organization: '' },
        { 'employeeDetails.organization': { $exists: false } },
        { 'employeeDetails.organization': null },
        { 'employeeDetails.organization': '' }
      ]
    }).toArray();
    
    console.log(`Found ${rostersToFix.length} rosters to fix`);
    
    let fixedCount = 0;
    
    for (const roster of rostersToFix) {
      const email = roster.customerEmail || roster.employeeDetails?.email;
      let organization = null;
      
      if (email) {
        // Extract domain from email
        const domain = email.split('@')[1];
        
        // Map domain to organization
        switch (domain) {
          case 'techcorp.com':
            organization = 'TechCorp Solutions';
            break;
          case 'innovate.com':
            organization = 'Innovate Labs';
            break;
          case 'abrafleet.com':
            organization = 'Abra Fleet Demo';
            break;
          case 'gmail.com':
            organization = 'Individual Customer';
            break;
          default:
            // Use domain as organization name (capitalize first letter)
            organization = domain.split('.')[0].charAt(0).toUpperCase() + domain.split('.')[0].slice(1) + ' Corp';
            break;
        }
      }
      
      if (organization) {
        await db.collection('rosters').updateOne(
          { _id: roster._id },
          {
            $set: {
              organization: organization,
              'employeeDetails.organization': organization,
              'employeeDetails.companyName': organization,
              'employeeData.organization': organization,
              'employeeData.companyName': organization,
              updatedAt: new Date()
            }
          }
        );
        
        console.log(`✅ Fixed ${roster.customerName || roster.employeeDetails?.name} (${email}) → ${organization}`);
        fixedCount++;
      }
    }
    
    console.log(`\n📊 Fixed ${fixedCount} rosters`);
    
    // Verify the fix
    console.log('\n🔍 Verifying fix...');
    const techCorpRosters = await db.collection('rosters').find({
      organization: 'TechCorp Solutions',
      status: 'pending_assignment'
    }).toArray();
    
    const innovateRosters = await db.collection('rosters').find({
      organization: 'Innovate Labs', 
      status: 'pending_assignment'
    }).toArray();
    
    console.log(`✅ TechCorp Solutions: ${techCorpRosters.length} rosters`);
    console.log(`✅ Innovate Labs: ${innovateRosters.length} rosters`);
    
    techCorpRosters.forEach(roster => {
      console.log(`   - ${roster.customerName || roster.employeeDetails?.name}`);
    });
    
    innovateRosters.forEach(roster => {
      console.log(`   - ${roster.customerName || roster.employeeDetails?.name}`);
    });
    
    console.log('\n🎉 Organizations fixed! Ready for testing.');
    
  } catch (error) {
    console.error('❌ Error fixing organizations:', error);
  } finally {
    await client.close();
    console.log('✅ Disconnected from MongoDB');
  }
}

// Run the fix
fixRosterOrganizations();