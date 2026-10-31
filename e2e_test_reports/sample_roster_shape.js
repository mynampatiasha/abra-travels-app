require('dotenv').config({ path: 'D:/Fleet_Management/Fleet_Management/Fleet Management/abra_fleet_backend/.env' });
const { MongoClient } = require('D:/Fleet_Management/Fleet_Management/Fleet Management/abra_fleet_backend/node_modules/mongodb');
(async () => {
  const c = new MongoClient(process.env.MONGODB_URI); await c.connect();
  const r = await c.db().collection('rosters').findOne({ rosterType: 'both' }) || await c.db().collection('rosters').findOne({});
  const pick = ['rosterType','weekdays','fromDate','toDate','startDate','endDate','fromTime','toTime','startTime','endTime','officeLocation','shift','status','priority'];
  console.log(JSON.stringify(Object.fromEntries(pick.filter((k) => r[k] !== undefined).map((k) => [k, r[k]]))));
  console.log('location keys:', JSON.stringify({ loginPickupLocation: r.loginPickupLocation && Object.keys(r.loginPickupLocation), logoutDropLocation: r.logoutDropLocation && Object.keys(r.logoutDropLocation), locations: r.locations && Object.keys(r.locations), officeLocationCoordinates: r.officeLocationCoordinates && Object.keys(r.officeLocationCoordinates) }));
  await c.close();
})();
