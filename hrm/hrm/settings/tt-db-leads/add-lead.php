<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database.php');

	if ($_SERVER['REQUEST_METHOD'] == 'POST') {
		$customer_name = htmlspecialchars($_POST['customer_name']);
		$email = htmlspecialchars($_POST['email']);
		$phone = htmlspecialchars($_POST['phone']);
		$status = htmlspecialchars($_POST['status']);
		$business = htmlspecialchars($_POST['business']);
		$created_by = $_SESSION['user_name'];

		$query = "INSERT INTO tt_db_leads (customer_name, email, phone, status, business, created_by) 
				  VALUES (?, ?, ?, ?, ?, ?)";
		$stmt = mysqli_prepare($dbConn, $query);
		mysqli_stmt_bind_param($stmt, "ssssss", $customer_name, $email, $phone, $status, $business, $created_by);
		mysqli_stmt_execute($stmt);

		if (mysqli_stmt_affected_rows($stmt) > 0) {
			echo "<script type=\"text/javascript\">
						alert(\"New lead created successfully.\");";
				if($business == "Abra Travels"){
					echo "window.location = \"../../tt-sale-leads.php?b=at\"";
				}
				elseif($business == "Abra Designbuild"){
					echo "window.location = \"../../tt-sale-leads.php?b=db\"";
				}
				elseif($business == "Abra Logistics"){
					echo "window.location = \"../../tt-sale-leads.php?b=al\"";
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
	
	mysqli_stmt_close($stmt);
    
?>
