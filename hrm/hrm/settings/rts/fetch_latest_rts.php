<?php
session_start();
require_once('../../database.php'); // Include your database connection

$query = "SELECT return_tracking_no FROM rts ORDER BY id DESC LIMIT 1";
$result = mysqli_query($dbConn, $query);
$row = mysqli_fetch_assoc($result);

if ($row) {
    $latestNumber = $row['return_tracking_no'];
    preg_match('/(\d+)$/', $latestNumber, $matches);
    $nextNumber = isset($matches[1]) ? (int)$matches[1] + 1 : 1000001; // Default if none found
} else {
    $nextNumber = 1000001; // Start from this if no record exists
}

echo json_encode(["next_return_tracking_no" => "ALRTS-" . $nextNumber]);

// Close the database connection
mysqli_close($dbConn);
?>
