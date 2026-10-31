<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database.php');

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // Initialize conditions array
    $conditions = [];

    // Filter by month and year
    if (!empty($_POST['month']) && !empty($_POST['year'])) {
        $month = $_POST['month'];
        $year = $_POST['year'];
        $start_date = "$year-$month-01";
        $end_date = date("Y-m-t", strtotime($start_date));
        $conditions[] = "enquiry_date BETWEEN '$start_date' AND '$end_date'";
        $conditions[] = "book_date BETWEEN '$start_date' AND '$end_date'";
    }

    // Filter by specific date ranges
    if (!empty($_POST['enquiry_start_date']) && !empty($_POST['enquiry_end_date'])) {
        $conditions[] = "enquiry_date BETWEEN '{$_POST['enquiry_start_date']}' AND '{$_POST['enquiry_end_date']}'";
    }
    if (!empty($_POST['book_start_date']) && !empty($_POST['book_end_date'])) {
        $conditions[] = "book_date BETWEEN '{$_POST['book_start_date']}' AND '{$_POST['book_end_date']}'";
    }

    // Build the WHERE clause
    $where_clause = !empty($conditions) ? "WHERE " . implode(" AND ", $conditions) : "";

    // SQL query
    $sql = "
        SELECT * 
        FROM courier
        $where_clause
        ORDER BY enquiry_date, book_date
    ";

    $result = mysqli_query($dbConn, $sql);

    if (!$result) {
        die("Query failed: " . mysqli_error($dbConn));
    }

    // Set headers for Excel file download
    header("Content-Type: application/vnd.ms-excel");
    header("Content-Disposition: attachment; filename=Courier_Report.xls");
    header("Pragma: no-cache");
    header("Expires: 0");

    // Start outputting the table as HTML
    echo "<table border='1'>";
    echo "<tr>";
    echo "<th>CID</th><th>Tracking</th><th>Enquiry Number</th><th>Cons No</th><th>Letra</th>";
    echo "<th>Ship Name</th><th>Phone</th><th>Sender Address</th><th>CC</th><th>Locker</th>";
    echo "<th>Correo</th><th>Receiver Name</th><th>Receiver Phone</th><th>Telefono1</th><th>Receiver Address</th>";
    echo "<th>CC Receiver</th><th>Email</th><th>Type</th><th>Weight</th><th>Variable</th>";
    echo "<th>Kilo Adicional</th><th>Shipping Subtotal</th><th>Altura</th><th>Ancho</th><th>Longitud</th>";
    echo "<th>Total Peso</th><th>Invoice No</th><th>Quantity</th><th>Book Mode</th><th>Shipping Method</th>";
    echo "<th>Declarate</th><th>Declarado</th><th>Freight</th><th>Mode</th><th>Pick Date</th>";
    echo "<th>Schedule</th><th>Pick Time</th><th>ISO</th><th>State</th><th>City</th>";
    echo "<th>Zipcode</th><th>Pais Destino</th><th>ISO1</th><th>State1</th><th>City1</th>";
    echo "<th>Zipcode1</th><th>Status</th><th>Dom/International</th><th>Comments</th>";
    echo "<th>Book Date</th><th>Enquiry Date</th><th>Payment</th><th>Pay Mode</th><th>Status Delivered</th>";
    echo "<th>Office Name</th><th>User</th><th>Amount</th>";
    echo "</tr>";

    // Output rows
    if (mysqli_num_rows($result) > 0) {
        while ($row = mysqli_fetch_assoc($result)) {
            echo "<tr>";
            foreach ($row as $value) {
                echo "<td>" . htmlspecialchars($value) . "</td>";
            }
            echo "</tr>";
        }
    } else {
        echo "<tr><td colspan='60'>No records found.</td></tr>";
    }

    echo "</table>";
    exit(); // End script execution after output
}
?>
