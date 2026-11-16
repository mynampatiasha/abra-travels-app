<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database.php');

	if($_SERVER["REQUEST_METHOD"] == "POST") {
		$title = mysqli_real_escape_string($dbConn, $_POST['title']);
		$description = mysqli_real_escape_string($dbConn, $_POST['description']);
		$created_at = date('Y-m-d H:i:s');

		$sql = "INSERT INTO hr_notices (title, description, created_at) VALUES ('$title', '$description', '$created_at')";

		if (mysqli_query($dbConn, $sql)) {
			echo "<script>alert('Notice added successfully!'); window.location.href='../../hr-notices.php';</script>";
		} else {
			echo "Error: " . $sql . "<br>" . mysqli_error($dbConn);
		}
	}
    
?>
