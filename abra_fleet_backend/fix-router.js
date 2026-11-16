const fs = require('fs');

const targetPath = 'routes/driver_trip_router.js';
let content = fs.readFileSync(targetPath, 'utf8');

// Fix 1: Feedback request on depart
// Change `if (stop.type === 'pickup' && stop.customer)` to `if (stop.type === 'drop' && stop.customer)`
// around line 1843 (request feedback for pickup stops)
content = content.replace(
  /\/\/ ⭐ REQUEST FEEDBACK FOR PICKUP STOPS\s+if \(stop\.type === 'pickup' && stop\.customer\)/,
  "// ⭐ REQUEST FEEDBACK FOR DROP STOPS\n    if (stop.type === 'drop' && stop.customer)"
);

// Fix 2: Remove await from notificationService.send in loops
const fcmRegex = /try\s*\{\s*await\s+notificationService\.send\(\{\s*([\s\S]*?)\}\);\s*([\s\S]*?)\}\s*catch\s*\(fcmEr(?:r|ror)\)\s*\{\s*([\s\S]*?)\}/g;

content = content.replace(fcmRegex, (match, options, successBlock, errorBlock) => {
  return `notificationService.send({\n${options}}).then(() => {\n${successBlock}}).catch(fcmError => {\n${errorBlock}});`;
});

// Fix 3: Remove await from notificationService.send without try/catch
const fcmRegex2 = /try\s*\{\s*await\s+notificationService\.send\(\{\s*([\s\S]*?)\}\);\s*\}\s*catch\s*\(fcmErr\)\s*\{\s*([\s\S]*?)\}/g;
content = content.replace(fcmRegex2, (match, options, errorBlock) => {
  return `notificationService.send({\n${options}}).catch(fcmErr => {\n${errorBlock}});`;
});


fs.writeFileSync(targetPath, content, 'utf8');
console.log('Done transforming driver_trip_router.js');
