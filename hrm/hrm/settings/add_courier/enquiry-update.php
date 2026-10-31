<?php
	error_reporting(E_ERROR | E_WARNING | E_PARSE);
	session_start();
	require_once('../../database.php');
	require_once('../../database-settings.php');
	
	$cid = (int)$_POST['cid'];
	$Shippername = $_POST['Shippername'];
	$Shipperphone = $_POST['Shipperphone'];
	$Shipperaddress = $_POST['Shipperaddress'];
	$Shippercc = $_POST['Shippercc'];
	
	$Receivername = $_POST['Receivername'];
	$Receiverphone = $_POST['Receiverphone'];
	$Receiveraddress = $_POST['Receiveraddress'];
	$Receivercc_r = $_POST['Receivercc_r'];
	$Receiveremail = $_POST['Receiveremail'];
	
	$Shiptype = $_POST['Shiptype'];
	$shipping_subtotal = $_POST['shipping_subtotal'];
	$Invoiceno = $_POST['Invoiceno'];
	$Qnty = $_POST['Qnty'];
	
	$altura = $_POST['altura'];
	$ancho = $_POST['ancho'];
	$longitud = $_POST['longitud'];
	$totalpeso = $_POST['totalpeso'];
	$pesoreal = $_POST['pesoreal'];
	
	$Bookingmode = $_POST['bookingmode'];	
	$Mode = $_POST['Mode'];
	
	$Schedule = $_POST['Schedule'];
	$Pickuptime = $_POST['Pickuptime'];
	$state = $_POST['state'];
	$ciudad = $_POST['ciudad'];
	
	$paisdestino = $_POST['paisdestino'];
	$state1 = $_POST['state1'];
	$city1 = $_POST['city1'];
	$status = $_POST['status'];
	$Comments = $_POST['Comments'];
	$officename = $_POST['officename'];
	$user = $_POST['user'];	
	
	$zipcode = $_POST['zipcode'];	
	$zipcode1 = $_POST['zipcode1'];	
	$shipping_method = $_POST['shipping_method'];	

	$sql = "UPDATE courier
   SET ship_name='$Shippername',phone='$Shipperphone',s_add='$Shipperaddress', cc='$Shippercc', rev_name='$Receivername',r_phone='$Receiverphone',r_add='$Receiveraddress', cc_r='$Receivercc_r', email='$Receiveremail', type='$Shiptype', invice_no='$Invoiceno', shipping_method='$shipping_method', mode ='$Mode', schedule='$Schedule',pick_time='$Pickuptime',state='$state',ciudad='$ciudad',paisdestino='$paisdestino', state1='$state1',city1='$city1',book_mode='$Bookingmode',qty='$Qnty', shipping_subtotal='$shipping_subtotal', altura='$altura', ancho='$ancho', longitud='$longitud', totalpeso='$totalpeso', status='$status', comments='$Comments', officename='$officename', user='$user' , pesoreal='$pesoreal', zipcode='$zipcode', zipcode1='$zipcode1'
   WHERE cid = '$cid'";	
		//echo $sql;
	dbQuery($sql);	
	
    require '../../requirelanguage.php';
	
	echo "<script type=\"text/javascript\">
			alert(\"$updateexit\");
			window.location = \"../../cs-enquiry-list.php\"
		</script>";

	//echo $Ship;
    
?>