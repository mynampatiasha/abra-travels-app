// Test what's being exported from admin-clients-unified.js
const route = require('./routes/admin-clients-unified');
console.log('Type:', typeof route);
console.log('Constructor:', route.constructor.name);
console.log('Keys:', Object.keys(route));
console.log('Is function:', typeof route === 'function');
console.log('Has router methods:', typeof route.get === 'function', typeof route.post === 'function');