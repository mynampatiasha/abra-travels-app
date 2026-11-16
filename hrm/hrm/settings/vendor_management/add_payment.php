<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database.php');

	if ($_SERVER['REQUEST_METHOD'] == 'POST') {
		    $vendor_id = $_POST['vendor_id'];
			$payment_date = $_POST['payment_date'];
			$payment_amount = $_POST['payment_amount'];
			$payment_status = $_POST['payment_status'];
			$payment_method = $_POST['payment_method'];
			$remarks = $_POST['remarks'];
			$business = $_POST['business'];

		$sql = "INSERT INTO vendor_payments (vendor_id, payment_date, payment_amount, payment_status, payment_method, remarks)
            VALUES ('$vendor_id', '$payment_date', '$payment_amount', '$payment_status', '$payment_method', '$remarks')";
			
		if (mysqli_query($dbConn, $sql)) {
			echo "<script type=\"text/javascript\">
						alert(\"Payment entry successful.\");";
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
