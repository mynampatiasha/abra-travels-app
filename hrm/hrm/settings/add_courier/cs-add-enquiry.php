<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database.php');
require_once('../../database-settings.php');
require '../../requirelanguage.php';
require_once('../../funciones.php');
require '../../css/GUMP/gump.class.php';

// Validate and sanitize input data using GUMP
$validator = new GUMP();

// Sanitize the POST data
$_POST = $validator->sanitize($_POST);

// Validation and filter rules
$validator->validation_rules(array(
    'officename'       => 'required|alpha_space',
    'user'             => 'required|alpha_space',
    'Shippername'      => 'required|alpha_space',
    'Shipperphone'     => 'required|numeric',
    'Shipperaddress'   => 'required',
    'Shippercc'        => 'required',
    'Shipperemail'     => 'required|valid_email',
    'Receivername'     => 'required|alpha_space',
    'Receiverphone'    => 'required|numeric',
    'Receiveraddress'  => 'required',
    'Receiveremail'    => 'required|valid_email',
    'Qnty'             => 'required|integer',
    'Comments'         => 'required',
    'Shiptype'         => 'required|alpha',
    'Mode'             => 'required|alpha_space',
    'dom_internation'  => 'required|alpha',
    'shipping_subtotal'=> 'required|float',
    'pesoreal'         => 'required|float',
    'totalpeso'        => 'required|float',
    'altura'           => 'required|float',
    'ancho'            => 'required|float',
    'longitud'         => 'required|float',
    'schedule'         => 'required|date',
    'enquiry_date'         => 'required|date',
    'Pickuptime'       => 'required|alpha_space',
));

// Run validation
$validated_data = $validator->run($_POST);

// If validation fails, redirect with errors
if ($validated_data === false) {
    header("Location: ../../cs-create-enquiry.php?tipo=danger&mensaje=" . $validator->get_readable_errors(true));
    exit;
}

// Assign sanitized values to variables
$officename = $_POST['officename'];
$user = $_POST['user'];
$Shippername = $_POST['Shippername'];
$Shipperphone = $_POST['Shipperphone'];
$Shipperaddress = $_POST['Shipperaddress'];
$Shippercc = $_POST['Shippercc'];
$Shipperlocker = $_POST['Shipperlocker'];
$Shipperemail = $_POST['Shipperemail'];
$Receivername = $_POST['Receivername'];
$Receiverphone = $_POST['Receiverphone'];
$Receiveraddress = $_POST['Receiveraddress'];
$Receiveremail = $_POST['Receiveremail'];
$Qnty = $_POST['Qnty'];
$Comments = $_POST['Comments'];
$bookingmode = $_POST['bookingmode'];
$Shiptype = $_POST['Shiptype'];
$Mode = $_POST['Mode'];
$dom_internation = $_POST['dom_internation'];
$shipping_subtotal = $_POST['shipping_subtotal'];
$pesoreal = $_POST['pesoreal'];
$totalpeso = $_POST['totalpeso'];
$altura = $_POST['altura'];
$ancho = $_POST['ancho'];
$longitud = $_POST['longitud'];
$Invoiceno = $_POST['Invoiceno'];
$schedule = $_POST['schedule'];
$Pickuptime = $_POST['Pickuptime'];
$state = $_POST['state'];
$ciudad = $_POST['ciudad'];
$paisdestino =  $_POST['paisdestino'];
$zipcode = $_POST['zipcode'];
$state1 = $_POST['state1'];
$city1 = $_POST['city1'];
$zipcode1 = $_POST['zipcode1'];	
$Receivercc_r = $_POST['Receivercc_r'];
$enquiry_date = $_POST['enquiry_date'];
$status = $_POST['status'];
$enquiry_number = $_POST['enquiry_number'];
$shipping_method = $_POST['shipping_method'];
$book_date = date('Y-m-d');

// Insert into database
$query = "INSERT INTO courier (
    enquiry_number, officename, user, ship_name, phone, s_add, cc, cc_r, locker, correo,
    rev_name, r_phone, r_add, email, qty, comments, 
    book_mode, type, mode, shipping_method, dom_internation, shipping_subtotal, 
    pesoreal, totalpeso, altura, ancho, longitud, invice_no, 
    schedule, pick_time, status, enquiry_date, book_date, state, ciudad, zipcode, paisdestino, state1, city1, zipcode1
) VALUES (
    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
)";

mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

$stmt = $dbConn->prepare($query);
$stmt->bind_param(
    'ssssssssssssssssssssssssssssssssssssssss',
    $enquiry_number, $officename, $user, $Shippername, $Shipperphone, $Shipperaddress, $Shippercc, $Receivercc_r, $Shipperlocker, $Shipperemail, 
    $Receivername, $Receiverphone, $Receiveraddress, $Receiveremail, $Qnty, $Comments, 
    $bookingmode, $Shiptype, $Mode, $shipping_method, $dom_internation, $shipping_subtotal, 
    $pesoreal, $totalpeso, $altura, $ancho, $longitud, $Invoiceno,
    $schedule, $Pickuptime, $status, $enquiry_date, $book_date, $state, $ciudad, $zipcode, $paisdestino, $state1, $city1, $zipcode1
);

$pa=mysqli_query($dbConn, "SELECT MAX(cons_no)as maximo FROM c_enquiries");				
			if($row=mysqli_fetch_array($pa)){
				if($row['maximo']==NULL){
					$cons_no='1000000';
				}else{
					$cons_no=$row['maximo']+1;
				}
			}

$sql_1 = "INSERT INTO c_enquiries (enquiry,cons_no,officename,user, book_date)
				VALUES('$enquiry_number','$cons_no','$officename','$user',curdate() )";	
			//echo $sql_1;
		dbQuery($sql_1);
		

if ($stmt->execute()) {
    header("Location: ../../cs-create-enquiry.php?tipo=success&mensaje=Enquiry created successfully!");
} else {
    header("Location: ../../cs-create-enquiry.php?tipo=danger&mensaje=Error creating enquiry: " . $stmt->error);
}
		
$stmt->close();
$dbConn->close();
?>
