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
            'tracking_no', 'order_id', 'customer_name', 'order_date', 'return_request_date', 
            'return_status', 'return_reason', 'product_id', 'product_name', 'ordered_qty', 
            'returned_qty', 'remaining_qty', 'condition_of_product', 'return_tracking_no', 
            'return_carrier', 'return_shipping_date', 'return_received_date', 
            'warehouse_received_by', 'return_inspection_status', 'refund_status', 'refund_amount', 
            'payment_method', 'invoice_no', 'original_order_value', 'remarks'
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
            $update_query = "UPDATE rts SET " . implode(', ', $updates) . " WHERE id = '$id'";

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
