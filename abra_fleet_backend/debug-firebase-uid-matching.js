// Debug Firebase UID matching
const { MongoClient } = require('mongodb');
require('dotenv').config({ path: './.env' });

async function debugFirebaseUidMatching() {
  console.log('🔍 Debugging Firebase UID Matching...\n');
  
  let client;
  try {
    // Connect to MongoDB
    client = new MongoClient(process.env.MONGODB_URI);
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    
    // Get unique customerIds from trips
    const uniqueCustomerIds = await db.collection('trips').distinct('customerId');
    console.log('Unique customerIds in trips:', uniqueCustomerIds);
    
    // Check if any of these match firebaseUid in users
    console.log('\n🔍 Checking Firebase UID matches...');
    for (const customerId of uniqueCustomerIds) {
      const user = await db.collection('users').findOne({ firebaseUid: customerId });
      if (user) {
        console.log(`✅ CustomerId "${customerId}" matches user:`, {
          name: user.name,
          email: user.email,
          companyName: user.companyName,
          role: user.role
        });
        
        // Count trips for this user
        const tripCount = await db.collection('trips').countDocuments({ customerId: customerId });
        console.log(`   → ${tripCount} trips found for this user`);
      } else {
        console.log(`❌ CustomerId "${customerId}" - no matching firebaseUid found`);
      }
    }
    
    // Let's also check all users with firebaseUid
    console.log('\n👥 All users with firebaseUid:');
    const usersWithFirebaseUid = await db.collection('users').find({ 
      firebaseUid: { $exists: true, $ne: null },
      role: 'customer'
    }).toArray();
    
    usersWithFirebaseUid.forEach((user, index) => {
      console.log(`User ${index + 1}:`);
      console.log('  firebaseUid:', user.firebaseUid);
      console.log('  name:', user.name);
      console.log('  email:', user.email);
      console.log('  companyName:', user.companyName);
    });
    
    // Test the corrected pipeline using firebaseUid
    console.log('\n🔄 Testing corrected pipeline with firebaseUid...');
    
    const now = new Date();
    const startDate = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000); // Last 30 days
    const endDate = now;
    
    const pipeline = [
      {
        $match: {
          role: 'customer',
          firebaseUid: { $exists: true, $ne: null }
        }
      },
      {
        $group: {
          _id: '$companyName',
          totalEmployees: { $sum: 1 },
          employees: {
            $push: {
              employeeId: '$employeeId',
              name: '$name',
              email: '$email',
              department: '$department',
              firebaseUid: '$firebaseUid' // Use firebaseUid instead of customerId
            }
          }
        }
      },
      {
        $lookup: {
          from: 'trips',
          let: { 
            employeeFirebaseUids: '$employees.firebaseUid' // Get all employee firebaseUids
          },
          pipeline: [
            {
              $match: {
                $expr: { 
                  $in: ['$customerId', '$$employeeFirebaseUids'] // Match trips by customerId = firebaseUid
                },
                // Use multiple date fields with OR condition
                $or: [
                  { createdAt: { $gte: startDate, $lte: endDate } },
                  { tripDate: { $gte: startDate, $lte: endDate } },
                  { completedAt: { $gte: startDate, $lte: endDate } }
                ]
              }
            }
          ],
          as: 'allTrips'
        }
      },
      {
        $addFields: {
          completedTrips: {
            $size: {
              $filter: {
                input: '$allTrips',
                cond: { $eq: ['$$this.status', 'completed'] }
              }
            }
          },
          cancelledTrips: {
            $size: {
              $filter: {
                input: '$allTrips',
                cond: { $eq: ['$$this.status', 'cancelled'] }
              }
            }
          },
          revenue: {
            $sum: {
              $map: {
                input: {
                  $filter: {
                    input: '$allTrips',
                    cond: { $eq: ['$$this.status', 'completed'] }
                  }
                },
                as: 'trip',
                in: { $ifNull: ['$$trip.fare', 0] }
              }
            }
          },
          // Employee-wise trip breakdown using firebaseUid
          employeeTrips: {
            $map: {
              input: '$employees',
              as: 'employee',
              in: {
                employeeId: '$$employee.employeeId',
                name: '$$employee.name',
                email: '$$employee.email',
                department: '$$employee.department',
                completedTrips: {
                  $size: {
                    $filter: {
                      input: '$allTrips',
                      cond: {
                        $and: [
                          { $eq: ['$$this.customerId', '$$employee.firebaseUid'] },
                          { $eq: ['$$this.status', 'completed'] }
                        ]
                      }
                    }
                  }
                },
                cancelledTrips: {
                  $size: {
                    $filter: {
                      input: '$allTrips',
                      cond: {
                        $and: [
                          { $eq: ['$$this.customerId', '$$employee.firebaseUid'] },
                          { $eq: ['$$this.status', 'cancelled'] }
                        ]
                      }
                    }
                  }
                },
                totalTrips: {
                  $size: {
                    $filter: {
                      input: '$allTrips',
                      cond: { $eq: ['$$this.customerId', '$$employee.firebaseUid'] }
                    }
                  }
                },
                revenue: {
                  $sum: {
                    $map: {
                      input: {
                        $filter: {
                          input: '$allTrips',
                          cond: {
                            $and: [
                              { $eq: ['$$this.customerId', '$$employee.firebaseUid'] },
                              { $eq: ['$$this.status', 'completed'] }
                            ]
                          }
                        }
                      },
                      as: 'trip',
                      in: { $ifNull: ['$$trip.fare', 0] }
                    }
                  }
                }
              }
            }
          }
        }
      },
      {
        $sort: { revenue: -1, completedTrips: -1, totalEmployees: -1 }
      }
    ];

    const companies = await db.collection('users').aggregate(pipeline).toArray();
    
    console.log('📊 Results with firebaseUid matching:');
    console.log('Total companies found:', companies.length);
    
    if (companies.length > 0) {
      companies.forEach((company, index) => {
        console.log(`\n🏢 Company ${index + 1}: ${company._id}`);
        console.log('  Employees:', company.totalEmployees);
        console.log('  Completed Trips:', company.completedTrips);
        console.log('  Cancelled Trips:', company.cancelledTrips);
        console.log('  Revenue: ₹', company.revenue.toFixed(2));
        
        const activeEmployees = (company.employeeTrips || []).filter(emp => emp.totalTrips > 0);
        if (activeEmployees.length > 0) {
          console.log('  👥 Active Employees:');
          activeEmployees.forEach((emp, empIndex) => {
            console.log(`    ${empIndex + 1}. ${emp.name} - ${emp.completedTrips} completed, ${emp.cancelledTrips} cancelled, ₹${emp.revenue.toFixed(2)}`);
          });
        } else {
          console.log('  ⚠️  No active employees in this period');
        }
      });
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    if (client) {
      await client.close();
      console.log('\n✅ MongoDB connection closed');
    }
  }
}

// Run the debug
debugFirebaseUidMatching();