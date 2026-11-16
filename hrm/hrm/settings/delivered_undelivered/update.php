<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

session_start();
require_once('../../database.php');
require_once('../../database-settings.php');

header('Content-Type: application/json'); // Set response to JSON

if ($_POST['action'] === 'update') {
    $tracking_no = $_POST['shipment_id']; // The tracking number
    $status = $_POST['status']; // Delivered or Undelivered
    $reason = isset($_POST['reason']) ? $_POST['reason'] : null; // Reason for undelivered

    // Current date and time for the submission
    $current_datetime = date('Y-m-d H:i:s');

    // Update the 'courier' table
    $courier_update = "";
    if ($status == "Delivered") {
        $courier_update = "UPDATE courier SET status_delivered = 'Delivered', comments = NULL, actual_delivery_date = '$current_datetime' WHERE tracking = '$tracking_no'";
    } else {
        $courier_update = "UPDATE courier SET status_delivered = 'Undelivered', comments = '$reason' WHERE tracking = '$tracking_no'";
    }

    // Update the 'fulfillment' table
    $fulfillment_update = "";
    if ($status == "Delivered") {
        $fulfillment_update = "UPDATE fulfillment SET order_status = 'fulfilled', reason = NULL, actual_fulfillment_date = '$current_datetime' WHERE tracking_no = '$tracking_no'";
    } else {
        $fulfillment_update = "UPDATE fulfillment SET order_status = 'unfulfilled', reason = '$reason' WHERE tracking_no = '$tracking_no'";
    }

    // Begin transaction
    mysqli_begin_transaction($dbConn);

    try {
        // Execute the courier update query
        if (!mysqli_query($dbConn, $courier_update)) {
            throw new Exception("Error updating courier table: " . mysqli_error($dbConn));
        }

        // Execute the fulfillment update query
        if (!mysqli_query($dbConn, $fulfillment_update)) {
            throw new Exception("Error updating fulfillment table: " . mysqli_error($dbConn));
        }

        // Commit transaction if both updates are successful
        mysqli_commit($dbConn);
        echo json_encode(['success' => true, 'message' => 'Record updated successfully.']);
    } catch (Exception $e) {
        // Rollback the transaction in case of error
        mysqli_roll_back($dbConn);
        echo json_encode(['success' => false, 'message' => $e->getMessage()]);
    }
} else {
    echo json_encode(['success' => false, 'message' => 'Invalid action.']);
}
?>
