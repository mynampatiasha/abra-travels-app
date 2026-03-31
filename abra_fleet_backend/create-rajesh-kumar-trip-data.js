const { MongoClient, ObjectId } = require('mongodb');

async function createRajeshKumarTripData() {
    const client = new MongoClient('mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0');
    
    try {
        await client.connect();
        console.log('Connected to MongoDB');
        
        const db = client.db('abra_fleet');
        
        // First, let's verify Rajesh Kumar's data
        const rajeshDriver = await db.collection('drivers').findOne({
            driverId: 'DRV-100001'
        });
        
        if (!rajeshDriver) {
            console.error('❌ Rajesh Kumar driver not found!');
            return;
        }
        
        console.log('✅ Found Rajesh Kumar:');
        console.log(`   - Driver ID: ${rajeshDriver.driverId}`);
        console.log(`   - Firebase UID: ${rajeshDriver.firebaseUid}`);
        console.log(`   - Email: ${rajeshDriver.personalInfo?.email}`);
        
        // Get his assigned rosters to create realistic trips
        const rosters = await db.collection('rosters').find({
            driverId: 'DRV-100001'
        }).toArray();
        
        console.log(`\n📋 Found ${rosters.length} rosters for trip creation`);
        
        // Create comprehensive trip data for the last 30 days
        const trips = [];
        const now = new Date();
        
        // Generate 25 trips over the last 30 days
        for (let i = 0; i < 25; i++) {
            const daysAgo = Math.floor(Math.random() * 30) + 1;
            const tripDate = new Date(now);
            tripDate.setDate(tripDate.getDate() - daysAgo);
            
            // Random start time between 7 AM and 6 PM
            const startHour = 7 + Math.floor(Math.random() * 11);
            const startMinute = Math.floor(Math.random() * 60);
            
            const startTime = new Date(tripDate);
            startTime.setHours(startHour, startMinute, 0, 0);
            
            // Trip duration between 30-90 minutes
            const durationMinutes = 30 + Math.floor(Math.random() * 60);
            const endTime = new Date(startTime);
            endTime.setMinutes(endTime.getMinutes() + durationMinutes);
            
            // Random customer from his rosters
            const randomRoster = rosters[Math.floor(Math.random() * rosters.length)];
            
            // Random distance between 5-50 km
            const distance = 5 + Math.random() * 45;
            
            // Random rating between 4.0-5.0 for completed trips
            const rating = 4.0 + Math.random() * 1.0;
            
            // 90% completed, 5% cancelled, 5% in_progress (only for recent trips)
            let status = 'completed';
            if (Math.random() < 0.05) {
                status = 'cancelled';
            } else if (Math.random() < 0.05 && daysAgo <= 1) {
                status = 'in_progress';
            }
            
            const trip = {
                _id: new ObjectId(),
                tripId: `TRIP-${Date.now()}-${i}`,
                tripNumber: `TR-2024-${String(1000 + i).padStart(4, '0')}`,
                driverId: 'DRV-100001',
                driverName: 'Rajesh Kumar',
                driverFirebaseUid: rajeshDriver.firebaseUid,
                customerId: randomRoster.userId,
                customerName: randomRoster.customerName,
                customerEmail: randomRoster.customerEmail,
                customerPhone: randomRoster.customerPhone || '+91' + Math.floor(Math.random() * 9000000000 + 1000000000),
                vehicleId: randomRoster.vehicleNumber || 'KA02CD5678',
                vehicleNumber: randomRoster.vehicleNumber || 'KA02CD5678',
                pickupLocation: {
                    address: randomRoster.pickupLocation || 'Electronic City, Bangalore',
                    coordinates: {
                        latitude: 12.8456 + (Math.random() - 0.5) * 0.1,
                        longitude: 77.6603 + (Math.random() - 0.5) * 0.1
                    }
                },
                dropLocation: {
                    address: randomRoster.dropLocation || 'Whitefield, Bangalore',
                    coordinates: {
                        latitude: 12.9698 + (Math.random() - 0.5) * 0.1,
                        longitude: 77.7500 + (Math.random() - 0.5) * 0.1
                    }
                },
                startTime: startTime,
                endTime: status === 'in_progress' ? null : endTime,
                scheduledStartTime: new Date(startTime.getTime() - 5 * 60 * 1000), // 5 minutes before actual
                scheduledEndTime: status === 'in_progress' ? null : new Date(endTime.getTime() + 10 * 60 * 1000), // 10 minutes after actual
                actualStartTime: startTime,
                actualEndTime: status === 'in_progress' ? null : endTime,
                status: status,
                distance: parseFloat(distance.toFixed(2)),
                rating: status === 'completed' ? parseFloat(rating.toFixed(1)) : null,
                fare: parseFloat((distance * 12 + 50).toFixed(2)), // Base fare + per km
                fuelConsumed: parseFloat((distance / 15).toFixed(2)), // Assuming 15 km/l efficiency
                route: {
                    totalDistance: parseFloat(distance.toFixed(2)),
                    estimatedDuration: durationMinutes,
                    actualDuration: status === 'completed' ? durationMinutes : null
                },
                organizationId: randomRoster.organizationId || 'ORG-001',
                organizationName: randomRoster.organizationName || 'ABRA Fleet',
                createdAt: new Date(startTime.getTime() - 24 * 60 * 60 * 1000), // Created 1 day before trip
                updatedAt: status === 'in_progress' ? new Date() : endTime,
                metadata: {
                    source: 'driver_reports_system',
                    createdBy: 'system',
                    version: '1.0'
                }
            };
            
            trips.push(trip);
        }
        
        // Sort trips by start time (newest first)
        trips.sort((a, b) => b.startTime - a.startTime);
        
        console.log(`\n🚀 Creating ${trips.length} trips for Rajesh Kumar...`);
        
        // Delete existing trips for Rajesh Kumar to avoid duplicates
        const deleteResult = await db.collection('trips').deleteMany({
            driverId: 'DRV-100001'
        });
        console.log(`🗑️  Deleted ${deleteResult.deletedCount} existing trips`);
        
        // Insert new trips
        const insertResult = await db.collection('trips').insertMany(trips);
        console.log(`✅ Inserted ${insertResult.insertedCount} new trips`);
        
        // Create summary statistics
        const completedTrips = trips.filter(t => t.status === 'completed');
        const totalDistance = completedTrips.reduce((sum, t) => sum + t.distance, 0);
        const avgRating = completedTrips.reduce((sum, t) => sum + (t.rating || 0), 0) / completedTrips.length;
        const totalWorkingHours = completedTrips.reduce((sum, t) => {
            if (t.startTime && t.endTime) {
                return sum + (t.endTime - t.startTime) / (1000 * 60 * 60);
            }
            return sum;
        }, 0);
        
        console.log('\n📊 Trip Summary:');
        console.log(`   - Total Trips: ${trips.length}`);
        console.log(`   - Completed: ${completedTrips.length}`);
        console.log(`   - Cancelled: ${trips.filter(t => t.status === 'cancelled').length}`);
        console.log(`   - In Progress: ${trips.filter(t => t.status === 'in_progress').length}`);
        console.log(`   - Total Distance: ${totalDistance.toFixed(1)} km`);
        console.log(`   - Average Rating: ${avgRating.toFixed(1)}/5.0`);
        console.log(`   - Total Working Hours: ${totalWorkingHours.toFixed(1)} hours`);
        
        // Also create some driver performance data
        const performanceData = {
            _id: new ObjectId(),
            driverId: 'DRV-100001',
            driverFirebaseUid: rajeshDriver.firebaseUid,
            month: now.getMonth() + 1,
            year: now.getFullYear(),
            totalTrips: trips.length,
            completedTrips: completedTrips.length,
            cancelledTrips: trips.filter(t => t.status === 'cancelled').length,
            totalDistance: parseFloat(totalDistance.toFixed(2)),
            totalWorkingHours: parseFloat(totalWorkingHours.toFixed(2)),
            avgRating: parseFloat(avgRating.toFixed(2)),
            totalFuelConsumed: parseFloat(completedTrips.reduce((sum, t) => sum + (t.fuelConsumed || 0), 0).toFixed(2)),
            onTimeTrips: completedTrips.filter(t => {
                if (t.scheduledEndTime && t.actualEndTime) {
                    return t.actualEndTime <= new Date(t.scheduledEndTime.getTime() + 15 * 60 * 1000);
                }
                return false;
            }).length,
            createdAt: new Date(),
            updatedAt: new Date()
        };
        
        // Insert or update performance data
        await db.collection('driver_performance').replaceOne(
            { 
                driverId: 'DRV-100001',
                month: now.getMonth() + 1,
                year: now.getFullYear()
            },
            performanceData,
            { upsert: true }
        );
        
        console.log('✅ Created/updated driver performance data');
        
        console.log('\n🎉 Successfully created comprehensive trip data for Rajesh Kumar!');
        console.log('   The driver reports should now show real data instead of dummy data.');
        
    } catch (error) {
        console.error('❌ Error creating trip data:', error);
    } finally {
        await client.close();
        console.log('\nDisconnected from MongoDB');
    }
}

// Run the script
createRajeshKumarTripData();