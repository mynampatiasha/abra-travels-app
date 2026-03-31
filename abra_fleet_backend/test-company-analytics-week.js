// Test company analytics with week filter
const { MongoClient } = require('mongodb');
require('dotenv').config({ path: './.env' });

async function testCompanyAnalyticsWeek() {
  console.log('🔍 Testing Company Analytics with Week Filter...\n');
  
  let client;
  try {
    // Connect to MongoDB
    client = new MongoClient(process.env.MONGODB_URI);
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    
    // Test with week filter (last 7 days)
    const now = new Date();
    const startDate = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const endDate = now;
    
    console.log('📅 Date range (Week):', { startDate, endDate });
    
    // First, let's check what trips exist
    console.log('\n🔍 Checking available trip data...');
    const totalTrips = await db.collection('trips').countDocuments();
    console.log('Total trips in database:', totalTrips);
    
    if (totalTrips > 0) {
      const sampleTrips = await db.collection('trips').find({}).limit(5).toArray();
      console.log('\n📋 Sample trips:');
      sampleTrips.forEach((trip, index) => {
        console.log(`Trip ${index + 1}:`, {
          status: trip.status,
          customerEmail: trip.customer?.email,
          companyName: trip.customer?.companyName,
          fare: trip.fare,
          createdAt: trip.createdAt
        });
      });
      
      // Check trips in date range
      const tripsInRange = await db.collection('trips').countDocuments({
        createdAt: { $gte: startDate, $lte: endDate }
      });
      console.log('\nTrips in last 7 days:', tripsInRange);
      
      // Check all trips regardless of date
      console.log('\n🔄 Running analytics with all trips (no date filter)...');
      const pipeline = [
        {
          $match: {
            role: 'customer'
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
                department: '$department'
              }
            }
          }
        },
        {
          $lookup: {
            from: 'trips',
            let: { companyName: '$_id' },
            pipeline: [
              {
                $match: {
                  $expr: { $eq: ['$customer.companyName', '$$companyName'] }
                  // Removed date filter to get all trips
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
            ongoingTrips: {
              $size: {
                $filter: {
                  input: '$allTrips',
                  cond: { $in: ['$$this.status', ['scheduled', 'in_progress', 'ongoing']] }
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
            // Employee-wise trip breakdown
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
                            { $eq: ['$$this.customer.email', '$$employee.email'] },
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
                            { $eq: ['$$this.customer.email', '$$employee.email'] },
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
                        cond: { $eq: ['$$this.customer.email', '$$employee.email'] }
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
                                { $eq: ['$$this.customer.email', '$$employee.email'] },
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
        },
        {
          $limit: 10
        }
      ];

      const companies = await db.collection('users').aggregate(pipeline).toArray();
      
      console.log('📊 Results (All Time):');
      console.log('Total companies found:', companies.length);
      
      if (companies.length > 0) {
        companies.forEach((company, index) => {
          console.log(`\n🏢 Company ${index + 1}:`);
          console.log('Name:', company._id);
          console.log('Employees:', company.totalEmployees);
          console.log('Completed Trips:', company.completedTrips);
          console.log('Cancelled Trips:', company.cancelledTrips);
          console.log('Revenue:', company.revenue);
          
          // Format the response with detailed employee information
          const employeeBreakdown = (company.employeeTrips || [])
            .filter(emp => emp.totalTrips > 0) // Only show employees with trips
            .sort((a, b) => (b.completedTrips || 0) - (a.completedTrips || 0)) // Sort by completed trips
            .slice(0, 5); // Top 5 most active employees
          
          if (employeeBreakdown.length > 0) {
            console.log('Active Employees:', employeeBreakdown.length);
            console.log('Top Employee:', employeeBreakdown[0].name, 'with', employeeBreakdown[0].completedTrips, 'completed trips');
          } else {
            console.log('No active employees found');
          }
        });
      }
    } else {
      console.log('❌ No trips found in database');
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

// Run the test
testCompanyAnalyticsWeek();