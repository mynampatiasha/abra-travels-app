// Test the fixed company analytics directly
const { MongoClient } = require('mongodb');
require('dotenv').config({ path: './.env' });

async function testFixedAnalytics() {
  console.log('🔍 Testing FIXED Company Analytics...\n');
  
  let client;
  try {
    // Connect to MongoDB
    client = new MongoClient(process.env.MONGODB_URI);
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    
    // Test with week filter (last 7 days) - same as backend
    const now = new Date();
    const startDate = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const endDate = now;
    
    console.log('📅 Date range (Week):', { startDate, endDate });
    
    // FIXED pipeline matching the corrected backend version
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
              department: '$department',
              customerId: { $toString: '$_id' } // Convert ObjectId to string for trip lookup
            }
          }
        }
      },
      {
        $lookup: {
          from: 'trips',
          let: { 
            employeeIds: '$employees.customerId' // Get all employee _ids as strings
          },
          pipeline: [
            {
              $match: {
                $expr: { 
                  $in: ['$customerId', '$$employeeIds'] // Match trips by customerId
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
          // Employee-wise trip breakdown using customerId
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
                          { $eq: ['$$this.customerId', '$$employee.customerId'] },
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
                          { $eq: ['$$this.customerId', '$$employee.customerId'] },
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
                      cond: { $eq: ['$$this.customerId', '$$employee.customerId'] }
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
                              { $eq: ['$$this.customerId', '$$employee.customerId'] },
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

    console.log('🔄 Running FIXED aggregation pipeline...');
    const companies = await db.collection('users').aggregate(pipeline).toArray();
    
    console.log('📊 FIXED Results:');
    console.log('Total companies found:', companies.length);
    
    if (companies.length > 0) {
      // Format the response with detailed employee information
      const mostActive = companies.map(company => ({
        name: company._id || 'Unknown Company',
        totalEmployees: company.totalEmployees || 0,
        completedTrips: company.completedTrips || 0,
        cancelledTrips: company.cancelledTrips || 0,
        ongoingTrips: company.ongoingTrips || 0,
        revenue: company.revenue || 0,
        averageTripsPerEmployee: company.totalEmployees > 0 
          ? Math.round((company.completedTrips || 0) / company.totalEmployees * 100) / 100 
          : 0,
        averageRevenuePerEmployee: company.totalEmployees > 0 
          ? Math.round((company.revenue || 0) / company.totalEmployees * 100) / 100 
          : 0,
        employeeBreakdown: (company.employeeTrips || [])
          .filter(emp => emp.totalTrips > 0) // Only show employees with trips
          .sort((a, b) => (b.completedTrips || 0) - (a.completedTrips || 0)) // Sort by completed trips
          .slice(0, 5) // Top 5 most active employees
      }));

      console.log('\n🏢 Company Results:');
      mostActive.forEach((company, index) => {
        console.log(`\nCompany ${index + 1}: ${company.name}`);
        console.log('  Employees:', company.totalEmployees);
        console.log('  Completed Trips:', company.completedTrips);
        console.log('  Cancelled Trips:', company.cancelledTrips);
        console.log('  Revenue: ₹', company.revenue.toFixed(2));
        
        if (company.employeeBreakdown && company.employeeBreakdown.length > 0) {
          console.log('  👥 Employee Breakdown:');
          company.employeeBreakdown.forEach((emp, empIndex) => {
            console.log(`    ${empIndex + 1}. ${emp.name} - ${emp.completedTrips} trips, ₹${emp.revenue.toFixed(2)}`);
          });
        } else {
          console.log('  ⚠️  No employee trip data for this period');
        }
      });
      
      console.log('\n📈 Sample Response for Frontend:');
      console.log(JSON.stringify(mostActive[0], null, 2));
    } else {
      console.log('❌ No companies found with the fixed pipeline');
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
testFixedAnalytics();