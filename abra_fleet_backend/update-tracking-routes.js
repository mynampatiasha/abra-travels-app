// File: update-tracking-routes.js
// Script to update tracking routes with backward compatibility for trip IDs

const fs = require('fs');
const path = require('path');

function updateTrackingRoutes() {
  const filePath = path.join(__dirname, 'routes', 'tracking.js');
  
  try {
    console.log('📝 Updating tracking routes for trip ID backward compatibility...');
    
    let content = fs.readFileSync(filePath, 'utf8');
    
    // Replace all occurrences of the trip finding pattern
    const oldPattern = /\{\s*\$or:\s*\[\s*\{\s*_id:\s*new\s+ObjectId\(tripId\)\s*\},\s*\{\s*tripId:\s*tripId\s*\}\s*\]\s*\}/g;
    const newPattern = `{
        $or: [
          { _id: new ObjectId(tripId) },
          { tripId: tripId },
          { tripNumber: tripId } // Backward compatibility
        ]
      }`;
    
    const updatedContent = content.replace(oldPattern, newPattern);
    
    // Count replacements
    const matches = content.match(oldPattern);
    const replacementCount = matches ? matches.length : 0;
    
    if (replacementCount > 0) {
      fs.writeFileSync(filePath, updatedContent, 'utf8');
      console.log(`✅ Updated ${replacementCount} trip finding patterns in tracking routes`);
    } else {
      console.log('ℹ️ No patterns found to update in tracking routes');
    }
    
  } catch (error) {
    console.error('❌ Error updating tracking routes:', error);
    throw error;
  }
}

// Run if called directly
if (require.main === module) {
  updateTrackingRoutes();
  console.log('✅ Tracking routes update completed!');
}

module.exports = { updateTrackingRoutes };