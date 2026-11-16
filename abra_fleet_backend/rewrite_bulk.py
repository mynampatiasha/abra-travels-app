import re

with open('routes/admin-drivers.js', 'r', encoding='utf-8') as f:
    content = f.read()

start_marker = "router.post('/bulk-import', async (req, res) => {"
end_marker = "// @route   POST /api/admin/drivers"

start_idx = content.find(start_marker)
end_idx = content.find(end_marker, start_idx + len(start_marker))
if end_idx == -1:
    end_idx = len(content)
else:
    end_idx = content.rfind('\n// =================================', start_idx, end_idx)

new_route = '''router.post('/bulk-import', async (req, res) => {
  console.log('\\n?? ========== BULK DRIVER IMPORT STARTED ==========');
  
  try {
    const { drivers } = req.body;
    
    if (!drivers || !Array.isArray(drivers) || drivers.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'No driver data provided'
      });
    }
    
    console.log(`?? Processing ${drivers.length} drivers for bulk import`);
    
    const results = {
      successful: [],
      failed: [],
      skipped: []
    };
    
    for (let i = 0; i < drivers.length; i++) {
      const driverData = drivers[i];
      const pInfo = driverData.personalInfo || {};
      const license = driverData.license || {};
      
      console.log(`\\n?? Processing driver ${i + 1}/${drivers.length}: ${pInfo.firstName} ${pInfo.lastName}`);
      
      try {
        const driverCount = await req.db.collection('drivers').countDocuments();
        const driverId = driverData.driverId || `DRV-${String(driverCount + 100001).padStart(6, '0')}`;
        
        const existingDriver = await req.db.collection('drivers').findOne({
          $or: [
            { 'personalInfo.phone': pInfo.phone },
            { 'personalInfo.email': pInfo.email },
            { 'license.licenseNumber': license.licenseNumber }
          ]
        });
        
        if (existingDriver) {
          console.log(`??  Driver already exists: ${pInfo.email}`);
          results.skipped.push({
            data: driverData,
            reason: 'Driver with same phone, email, or license already exists'
          });
          continue;
        }
        
        const parseDate = (d) => {
            if (!d) return null;
            const pd = new Date(d);
            return isNaN(pd.getTime()) ? null : pd;
        };
        
        const newDriver = {
          driverId,
          name: `${pInfo.firstName || ''} ${pInfo.lastName || ''}`.trim(),
          email: pInfo.email,
          phone: pInfo.phone,
          personalInfo: {
            firstName: pInfo.firstName,
            lastName: pInfo.lastName,
            phone: pInfo.phone,
            email: pInfo.email,
            dateOfBirth: parseDate(pInfo.dateOfBirth),
            bloodGroup: pInfo.bloodGroup,
            gender: pInfo.gender
          },
          license: {
            licenseNumber: license.licenseNumber,
            type: license.licenseType,
            issueDate: parseDate(license.issueDate),
            expiryDate: parseDate(license.expiryDate),
            issuingAuthority: license.issuingAuthority
          },
          emergencyContact: driverData.emergencyContact || null,
          address: driverData.address || null,
          employment: driverData.employment || null,
          bankDetails: driverData.bankDetails || null,
          status: driverData.status || 'active',
          assignedVehicle: null,
          vehicleNumber: null,
          documents: [],
          feedbackStats: {
            totalFeedback: 0,
            averageRating: 0,
            rating5Stars: 0,
            rating4Stars: 0,
            rating3Stars: 0,
            rating2Stars: 0,
            rating1Stars: 0
          },
          joinedDate: new Date(),
          createdAt: new Date(),
          updatedAt: new Date()
        };
        
        const result = await req.db.collection('drivers').insertOne(newDriver);
        console.log(`? Driver inserted: ${result.insertedId}`);
        
        results.successful.push({
          data: driverData,
          driverId: driverId,
          _id: result.insertedId
        });
        
      } catch (error) {
        console.log(`? Error processing driver ${i + 1}:`, error.message);
        results.failed.push({
          data: driverData,
          error: error.message
        });
      }
    }
    
    console.log(`?? Bulk import complete. Success: ${results.successful.length}, Failed: ${results.failed.length}, Skipped: ${results.skipped.length}`);
    
    res.json({
      success: true,
      message: `Successfully imported ${results.successful.length} drivers`,
      successCount: results.successful.length,
      failedCount: results.failed.length,
      skippedCount: results.skipped.length,
      results
    });
    
  } catch (error) {
    console.error('? Error in bulk driver import:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to process bulk import',
      error: error.message
    });
  }
});
'''

final_content = content[:start_idx] + new_route + content[end_idx:]

with open('routes/admin-drivers.js', 'w', encoding='utf-8') as f:
    f.write(final_content)

print('Success')
