const webpush = require('web-push');

const vapidKeys = webpush.generateVAPIDKeys();

console.log('\n==========================================================');
console.log('🔑 VAPID KEYS GENERATED - ADD TO .env FILE:');
console.log('==========================================================');
console.log(`VAPID_PUBLIC_KEY=${vapidKeys.publicKey}`);
console.log(`VAPID_PRIVATE_KEY=${vapidKeys.privateKey}`);
console.log(`VAPID_SUBJECT=mailto:admin@abrafleet.com`);
console.log('==========================================================\n');
