const { MongoClient, ObjectId } = require('mongodb');

async function fixRajeshKumarPerformanceData() {
    const client = new MongoClient('mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0');
    
    try {
        await client.connect();
        console.log('Connected to MongoDB');
        
        const db = client.db('abra_fleet');
        
        // Get Rajesh Kumar's trips to calculate performance
        const trips = await db.collection('trips').find({
            driverId: 'DRV-100001'
        }).toArray();
        
        if (trips.length === 0) {
            console.log('❌ No trips found for Rajesh Kumar');
            return;
        }
        
        console.log(`✅ Found ${trips.length} trips for Rajesh Kumar`);
        
        const completedTrips = trips.filter(t => t.status === 'completed');
        const now = new Date();
        
        // Calculate performance metrics
        const totalDistance = completedTrips.reduce((sum, t) => sum + (t.distance || 0), 0);
        const avgRating = completedTrips.length > 0 
            ? completedTrips.reduce((sum, t) => sum + (t.rating || 0), 0) / completedTrips.length
            : 0;
        
        const totalWorkingHours = completedTrips.reduce((sum, t) => {
            if (t.startTime && t.endTime) {
                return sum + (new Date(t.endTime) - new Date(t.startTime)) / (1000 * 60 * 60);
            }
            return sum;
        }, 0);
        
        const onTimeTrips = completedTrips.filter(t => {
            if (t.scheduledEndTime && t.actualEndTime) {
                return new Date(t.actualEndTime) <= new Date(new Date(t.scheduledEndTime).getTime() + 15 * 60 * 1000);
            }
            return false;
        });
        
        // Create performance data without _id in the document
        const performanceData = {
            driverId: 'DRV-100001',
            driverFirebaseUid: 'aVIF9Ahluig993fCNyZRrIDC3KO2',
            month: now.getMonth() + 1,
            year: now.getFullYear(),
            totalTrips: trips.length,
            completedTrips: completedTrips.length,
            cancelledTrips: trips.filter(t => t.status === 'cancelled').length,
            totalDistance: parseFloat(totalDistance.toFixed(2)),
            totalWorkingHours: parseFloat(totalWorkingHours.toFixed(2)),
            avgRating: parseFloat(avgRating.toFixed(2)),
            totalFuelConsumed: parseFloat(completedTrips.reduce((sum, t) => sum + (t.fuelConsumed || 0), 0).toFixed(2)),
            onTimeTrips: onTimeTrips.length,
            onTimePercentage: completedTrips.length > 0 
                ? parseFloat(((onTimeTrips.length / completedTrips.length) * 100).toFixed(2))
                : 0,
            createdAt: new Date(),
            updatedAt: new Date()
        };
        
        // Delete existing performance data first
        await db.collection('driver_performance').deleteMany({
            driverId: 'DRV-100001'
        });
        
        // Insert new performance data
        const result = await db.collection('driver_performance').insertOne(performanceData);
        
        console.log('✅ Created driver performance data:', result.insertedId);
        
        console.log('\n📊 Performance Summary:');
        console.log(`   - Total Trips: ${performanceData.totalTrips}`);
        console.log(`   - Completed: ${performanceData.completedTrips}`);
        console.log(`   - Cancelled: ${performanceData.cancelledTrips}`);
        console.log(`   - Total Distance: ${performanceData.totalDistance} km`);
        console.log(`   - Average Rating: ${performanceData.avgRating}/5.0`);
        console.log(`   - Total Working Hours: ${performanceData.totalWorkingHours} hours`);
        console.log(`   - On-Time Percentage: ${performanceData.onTimePercentage}%`);
        
        console.log('\n🎉 Successfully fixed performance data for Rajesh Kumar!');
        
    } catch (error) {
        console.error('❌ Error fixing performance data:', error);
    } finally {
        await client.close();
        console.log('\nDisconnected from MongoDB');
    }
}

// Run the script
fixRajeshKumarPerformanceData();