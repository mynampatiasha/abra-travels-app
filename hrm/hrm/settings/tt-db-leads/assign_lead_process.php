<?php
session_start();
ob_start();
require_once('../../database-settings.php');
require_once('../../database.php');
require_once('../../library.php');
require_once('../../funciones.php');
require '../../requirelanguage.php';
require '../../requirelanguage_image.php';
$con = conexion();

$lead_id = $_POST['lead_id'];
$status = $_POST['status'];
$comments = $_POST['comments'];
$assigned_to = $_POST['assigned_to'];
$followup_time = $_POST['followup_time'];
$action_by = $_SESSION['user_name']; // Assuming logged-in user ID
$current_time = date('Y-m-d H:i:s');

// Fetch the assigned follow-up time
$result = $con->query("SELECT assigned_followup_time FROM tt_lead_followups WHERE lead_id = $lead_id ORDER BY action_timestamp DESC LIMIT 1");
$row = $result->fetch_assoc();
$assigned_followup_time = $row['assigned_followup_time'];

// Calculate delay (if any)
$delay = 0;
if ($assigned_followup_time) {
    $delay = (strtotime($current_time) - strtotime($assigned_followup_time)) / 60; // Minutes
}

// Log action in tt_lead_followups
$stmt = $con->prepare("
    INSERT INTO tt_lead_followups (lead_id, action_by, action_description, assigned_to, assigned_followup_time, delay_in_minutes, comments)
    VALUES (?, ?, ?, ?, ?, ?, ?)
");
$stmt->bind_param("issssis", $lead_id, $action_by, $status, $assigned_to, $followup_time, $delay, $comments);
$stmt->execute();

// Update lead status in main table (optional)
$con->query("UPDATE tt_db_leads SET status = '$status' WHERE id = $lead_id");

$business_fetch = mysqli_query($dbConn, "SELECT business FROM tt_db_leads WHERE id = $lead_id");
while($row = mysqli_fetch_array($business_fetch)){
	$business = $row['business'];
}

if($business == "Abra Travels"){
	header("Location: ../../tt-sale-leads.php?b=at");
}
elseif($business == "Abra Designbuild"){
	header("Location: ../../tt-sale-leads.php?b=db");
}
elseif($business == "Abra Logistics"){
	header("Location: ../../tt-sale-leads.php?b=al");
}
else{
	header("Location: ../../index.php");
}

?>
