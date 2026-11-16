<?php
    error_reporting(E_ALL);
    ini_set('display_errors', 1);

    session_start();
    require_once('../../database.php');
    require_once('../../database-settings.php');

    if ($_POST['action'] === 'update') {
        $fields = [
            'storage_id', 'company_name', 'customer_code', 'customer_name', 'item_code',
            'item_name', 'location', 'rack', 'bin', 'initial_qty',
            'current_qty', 'capacity', 'temp_range', 'batch_no',
            'expiry_date', 'responsible_person', 'category', 'unit_price', 'total_value', 'warehouse_id'
        ];

        $values = [];
        foreach ($fields as $field) {
            $value = isset($_POST[$field]) ? mysqli_real_escape_string($dbConn, $_POST[$field]) : '';
            $values[] = "'$value'";
        }

        $insert_query = "INSERT INTO storage (" . implode(', ', $fields) . ") VALUES (" . implode(', ', $values) . ")";
        $result = mysqli_query($dbConn, $insert_query);

        // Check if product_id and initial_qty are set, and update the `oc_product` table
        if (isset($_POST['product_id'], $_POST['initial_qty'])) {
            $product_id = mysqli_real_escape_string($dbConnZylo, $_POST['product_id']);
            $initial_qty = mysqli_real_escape_string($dbConnZylo, $_POST['initial_qty']);

            // Update the `oc_product` table
            $product_update_query = "UPDATE oc_product SET quantity = '$initial_qty' WHERE product_id = '$product_id'";
            mysqli_query($dbConnZylo, $product_update_query); // Execute the query
        }

        if ($result) {
            // Output JavaScript directly for browser execution
            echo "<script type=\"text/javascript\">
                    alert(\"Record updated successfully.\");
                    window.location = \"../../storage-az-product-mapping.php\";
                </script>";
        } else {
            // Output error in JSON format
            header('Content-Type: application/json');
            echo json_encode(['success' => false, 'message' => 'Database error: ' . mysqli_error($dbConn)]);
        }
    } else {
        header('Content-Type: application/json');
        echo json_encode(['success' => false, 'message' => 'No fields to update.']);
    }
?>
