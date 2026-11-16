<?php
    error_reporting(E_ALL);
    ini_set('display_errors', 1);

    session_start();
    require_once('../../database.php');
    require_once('../../database-settings.php');

    header('Content-Type: application/json'); // Set response to JSON

    if ($_POST['action'] === 'update') {
        $order_id = $_POST['id']; // ID of the record to update

        // Define the fields to update
        $fields = [
            'tracking_no', 'dispatched_from', 'origin', 'destination', 
            'company_name', 'customer_code', 'customer_name', 'booking_datetime', 
            'booking_status', 'inscan_datetime', 'inscan_status', 'outscan_datetime', 
            'outscan_status', 'current_status', 'current_status_datetime', 'remarks'
        ];

        $updates = [];

        // Prepare the updates dynamically
        foreach ($fields as $field) {
            if (isset($_POST[$field])) {
                $value = mysqli_real_escape_string($dbConn, $_POST[$field]);
                $updates[] = "$field = '$value'";
            }
        }

        if (!empty($updates)) {
            // Construct the update query
            $update_query = "UPDATE single_order SET " . implode(', ', $updates) . " WHERE id = '$order_id'";

            // Execute the query
            if (mysqli_query($dbConn, $update_query)) {
                echo json_encode(['success' => true, 'message' => 'Record updated successfully.']);
            } else {
                echo json_encode(['success' => false, 'message' => 'Database error: ' . mysqli_error($dbConn)]);
            }
        } else {
            echo json_encode(['success' => false, 'message' => 'No fields to update.']);
        }
    } else {
        echo json_encode(['success' => false, 'message' => 'Invalid action.']);
    }
?>

