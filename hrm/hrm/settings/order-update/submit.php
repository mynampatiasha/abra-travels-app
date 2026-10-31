<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

session_start();
require_once('../../database.php');
require_once('../../database-settings.php');

header('Content-Type: application/json'); // Set response to JSON

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $input = json_decode(file_get_contents('php://input'), true);

    if ($input['action'] === 'submit' && isset($input['data']) && is_array($input['data'])) {
        $data = $input['data'];
        $values = [];

        foreach ($data as $row) {
            $tracking_no = mysqli_real_escape_string($dbConn, $row['tracking_no']);
            $origin = mysqli_real_escape_string($dbConn, $row['origin']);
            $destination = mysqli_real_escape_string($dbConn, $row['destination']);
            $scanned_by = mysqli_real_escape_string($dbConn, $row['scanned_by']);
            $outscan_datetime = mysqli_real_escape_string($dbConn, $row['outscan_datetime']);
            $scan_location = mysqli_real_escape_string($dbConn, $row['scan_location']);
            $status = mysqli_real_escape_string($dbConn, $row['status']);
            $delivery_associate = mysqli_real_escape_string($dbConn, $row['delivery_associate']);

            // Prepare values for insertion into the inscan table
            $values[] = "('$tracking_no', '$origin', '$destination', '$scanned_by', '$outscan_datetime', '$scan_location', '$status', '$delivery_associate')";
        }

        $query = "INSERT INTO outscan (tracking_no, origin, destination, scanned_by, outscan_datetime, scan_location, status, delivery_associate) VALUES " . implode(", ", $values);

        mysqli_begin_transaction($dbConn); // Start a transaction
        try {
            // Insert records into the inscan table
            if (!mysqli_query($dbConn, $query)) {
                throw new Exception("Database error: " . mysqli_error($dbConn));
            }

            mysqli_commit($dbConn); // Commit the transaction
            echo json_encode(['success' => true, 'message' => 'Records inserted successfully.']);
        } catch (Exception $e) {
            mysqli_rollback($dbConn); // Rollback transaction in case of error
            echo json_encode(['success' => false, 'message' => $e->getMessage()]);
        }
    } else {
        echo json_encode(['success' => false, 'message' => 'Invalid data format.']);
    }
} else {
    echo json_encode(['success' => false, 'message' => 'Invalid request method.']);
}
?>
