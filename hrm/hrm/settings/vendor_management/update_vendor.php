<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database.php'); // Assuming the correct database connection file

if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    // Vendor ID to identify the record
    $vendor_id = mysqli_real_escape_string($dbConn, $_POST['vendor_id']);

    // Sanitize inputs
    $vendor_name = mysqli_real_escape_string($dbConn, $_POST['vendor_name']);
    $concerned_person = mysqli_real_escape_string($dbConn, $_POST['concerned_person']);
    $email = mysqli_real_escape_string($dbConn, $_POST['email']);
    $phone = mysqli_real_escape_string($dbConn, $_POST['phone']);
    $address = mysqli_real_escape_string($dbConn, $_POST['address']);
    $gst_details = mysqli_real_escape_string($dbConn, $_POST['gst_details']);
    $bank_account = mysqli_real_escape_string($dbConn, $_POST['bank_account']);
    $vendor_category = mysqli_real_escape_string($dbConn, $_POST['vendor_category']);
    $contract_number = mysqli_real_escape_string($dbConn, $_POST['contract_number']);
    $contract_start_date = mysqli_real_escape_string($dbConn, $_POST['contract_start_date']);
    $contract_end_date = mysqli_real_escape_string($dbConn, $_POST['contract_end_date']);
    $contract_renewal_date = mysqli_real_escape_string($dbConn, $_POST['contract_renewal_date']);
    $contract_status = mysqli_real_escape_string($dbConn, $_POST['contract_status']);
	$business = mysqli_real_escape_string($dbConn, $_POST['business']);

    // Handle multi-select dropdowns
    $services_offered = isset($_POST['services_offered']) ? implode(',', $_POST['services_offered']) : '';
    $subcategories = isset($_POST['subcategories']) ? implode(',', $_POST['subcategories']) : '';
    $subsubcategories = isset($_POST['subsubcategories']) ? implode(',', $_POST['subsubcategories']) : '';

    // Update query
    $sql = "UPDATE vendors SET 
                vendor_name = '$vendor_name',
                concerned_person = '$concerned_person',
                email = '$email',
                phone = '$phone',
                address = '$address',
                gst_details = '$gst_details',
                bank_account = '$bank_account',
                vendor_category = '$vendor_category',
                contract_number = '$contract_number',
                contract_start_date = '$contract_start_date',
                contract_end_date = '$contract_end_date',
                contract_renewal_date = '$contract_renewal_date',
                contract_status = '$contract_status',
                services_offered = '$services_offered',
                subcategories = '$subcategories',
                subsubcategories = '$subsubcategories'
            WHERE vendor_id = '$vendor_id'";

    if (mysqli_query($dbConn, $sql)) {
        echo "<script type=\"text/javascript\">
                alert(\"Vendor Info Updated Successfully!\");";
				if($business == "Abra Travels"){
					echo "window.location = \"../../vendors.php?b=at\"";
				}
				elseif($business == "Abra Designbuild"){
					echo "window.location = \"../../vendors.php?b=db\"";
				}
				elseif($business == "Abra Logistics"){
					echo "window.location = \"../../vendors.php?b=al\"";
				}
				else{
					echo "window.location = \"../../dashboard.php\"";
				}
              echo "
              </script>";
    } else {
        echo "Error: " . $sql . "<br>" . mysqli_error($dbConn);
    }
}
?>
