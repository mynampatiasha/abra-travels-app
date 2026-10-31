<?php
session_start();
require_once('../../database.php'); // Include your database connection

// Fetch office names
$query = "SELECT off_name FROM offices";
$result = mysqli_query($dbConn, $query);

$locations = [];
if ($result) {
    if (mysqli_num_rows($result) > 0) {
        while ($row = mysqli_fetch_assoc($result)) {
            $locations[] = $row['off_name'];
        }
    }
} else {
    echo json_encode([
        'success' => false,
        'message' => 'Failed to fetch data: ' . mysqli_error($dbConn)
    ]);
    exit;
}

// Return the list of office names as JSON
echo json_encode(['locations' => $locations]);

// Close the database connection
mysqli_close($dbConn);
?>
