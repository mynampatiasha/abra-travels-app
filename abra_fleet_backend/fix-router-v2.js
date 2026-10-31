const fs = require('fs');

const targetPath = 'routes/driver_trip_router.js';
let content = fs.readFileSync(targetPath, 'utf8');

// Replace standard try-catch blocks around await notificationService.send
const fcmRegex = /try\s*\{\s*await\s+notificationService\.send\(([\s\S]*?)\);\s*(.*?fcmSuccessCount\+\+;\s*[\s\S]*?)\}\s*catch\s*\((.*?)\)\s*\{\s*([\s\S]*?)\}/g;

content = content.replace(fcmRegex, (match, options, successBlock, errorVar, errorBlock) => {
  return `// Optimized: Fire-and-forget FCM notification
            notificationService.send(${options}).then(() => {
              ${successBlock}
            }).catch(${errorVar} => {
              ${errorBlock}
            });`;
});

// There is one occurrence without try/catch:
const fcmRegex2 = /try\s*\{\s*await\s+notificationService\.send\(([\s\S]*?)\);\s*\}\s*catch\s*\((.*?)\)\s*\{\s*([\s\S]*?)\}/g;
content = content.replace(fcmRegex2, (match, options, errorVar, errorBlock) => {
  return `notificationService.send(${options}).catch(${errorVar} => {
              ${errorBlock}
            });`;
});

fs.writeFileSync(targetPath, content, 'utf8');
console.log('Done transforming driver_trip_router.js');
