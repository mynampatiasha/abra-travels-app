const fs = require('fs');

const targetPath = 'routes/driver_trip_router.js';
let content = fs.readFileSync(targetPath, 'utf8');

// Replace `await notificationService.send` with `notificationService.send`
// But we must also handle the `try {` block correctly. 
// A simpler way is just to remove `await `
content = content.replace(/await notificationService\.send\(/g, 'notificationService.send(');

// Now, we need to add a catch block to `notificationService.send({ ... })`
// We can find `priority: 'urgent'` or `priority: 'high'` followed by `}` and `)` and replace it.
content = content.replace(/priority:\s*'([^']+)'\s*\}\)/g, "priority: '$1'\n              }).catch(e => console.log('FCM Async Error: ' + e.message))");

fs.writeFileSync(targetPath, content, 'utf8');
console.log('Fixed async FCM notifications safely');
