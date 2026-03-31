// Test company analytics directly with MongoDB
const { MongoClient } = require('mongodb');
require('dotenv').config({ path: './.env' });

async function testCompanyAnalyticsDirectly() {
  console.log('🔍 Testing Company Analytics Directly with MongoDB...\n');
  
  let client;
  try {
    // Connect to MongoDB
    client = new MongoClient(process.env.MONGODB_URI);
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    
    // Test the same pipeline as in the backend
    const now = new Date();
    const startDate = new Date(now.getFullYear(), now.getMonth(), now.getDate()); // Today
    const endDate = now;
    
    console.log('📅 Date range:', { startDate, endDate });
    
    // Enhanced pipeline to get detailed company analytics with employee trip details
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
                $expr: { $eq: ['$customer.companyName', '$$companyName'] },
                createdAt: { $gte: startDate, $lte: endDate }
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

    console.log('🔄 Running aggregation pipeline...');
    const companies = await db.collection('users').aggregate(pipeline).toArray();
    
    console.log('📊 Results:');
    console.log('Total companies found:', companies.length);
    
    if (companies.length > 0) {
      console.log('\n🏢 Sample Company Data:');
      const sampleCompany = companies[0];
      console.log('Company Name:', sampleCompany._id);
      console.log('Total Employees:', sampleCompany.totalEmployees);
      console.log('Completed Trips:', sampleCompany.completedTrips);
      console.log('Cancelled Trips:', sampleCompany.cancelledTrips);
      console.log('Revenue:', sampleCompany.revenue);
      
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

      console.log('\n👥 Employee Breakdown:');
      if (mostActive[0].employeeBreakdown && mostActive[0].employeeBreakdown.length > 0) {
        console.log('Number of active employees:', mostActive[0].employeeBreakdown.length);
        console.log('Sample employee data:');
        console.log(JSON.stringify(mostActive[0].employeeBreakdown[0], null, 2));
      } else {
        console.log('No employee breakdown data available');
      }
      
      console.log('\n📈 Formatted Response Sample:');
      console.log(JSON.stringify(mostActive[0], null, 2));
    } else {
      console.log('❌ No companies found');
      
      // Let's check what data we have
      console.log('\n🔍 Checking available data...');
      const userCount = await db.collection('users').countDocuments();
      const customerCount = await db.collection('users').countDocuments({ role: 'customer' });
      const tripCount = await db.collection('trips').countDocuments();
      
      console.log('Total users:', userCount);
      console.log('Total customers:', customerCount);
      console.log('Total trips:', tripCount);
      
      if (customerCount > 0) {
        console.log('\n📋 Sample customer data:');
        const sampleCustomers = await db.collection('users').find({ role: 'customer' }).limit(3).toArray();
        sampleCustomers.forEach((customer, index) => {
          console.log(`Customer ${index + 1}:`, {
            name: customer.name,
            email: customer.email,
            companyName: customer.companyName,
            employeeId: customer.employeeId
          });
        });
      }
      
      if (tripCount > 0) {
        console.log('\n🚗 Sample trip data:');
        const sampleTrips = await db.collection('trips').find({}).limit(3).toArray();
        sampleTrips.forEach((trip, index) => {
          console.log(`Trip ${index + 1}:`, {
            status: trip.status,
            customerEmail: trip.customer?.email,
            companyName: trip.customer?.companyName,
            fare: trip.fare,
            createdAt: trip.createdAt
          });
        });
      }
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
testCompanyAnalyticsDirectly();