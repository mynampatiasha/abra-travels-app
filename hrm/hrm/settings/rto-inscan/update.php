<?php
    error_reporting(E_ALL);
    ini_set('display_errors', 1);

    session_start();
    require_once('../../database.php');
    require_once('../../database-settings.php');

    header('Content-Type: application/json'); // Set response to JSON

    if ($_POST['action'] === 'update') {
        $id = $_POST['id']; // ID of the record to update

        // Define the fields to update
        $fields = [
                'tracking_no', 'order_id', 'customer_name', 'rto_initiation_date', 'rto_received_date', 
                'carrier_name', 'original_tracking_no', 'rto_tracking_no', 'product_id', 'product_name',
                'ordered_qty', 'returned_qty', 'missing_qty', 'product_condition', 'inspection_status', 
                'stock_status', 'refund_status', 'refund_amount', 'remarks'
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
            $update_query = "UPDATE rto_inscan SET " . implode(', ', $updates) . " WHERE id = '$id'";

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
