<?php
// *************************************************************************
// *                                                                       *
// * DEPRIXA -  logistics Worldwide Software                               *
// * Copyright (c) JAOMWEB. All Rights Reserved                            *
// *                                                                       *
// *************************************************************************
// *                                                                       *
// * Email: osorio2380@yahoo.es                                            *
// * Website: http://www.jaom.info                                         *
// *                                                                       *
// *************************************************************************
// *                                                                       *
// * This software is furnished under a license and may be used and copied *
// * only  in  accordance  with  the  terms  of such  license and with the *
// * inclusion of the above copyright notice.                              *
// * If you Purchased from Codecanyon, Please read the full License from   *
// * here- http://codecanyon.net/licenses/standard                         *
// *                                                                       *
// *************************************************************************
 
	error_reporting(E_ERROR | E_WARNING | E_PARSE);
	session_start();
	require_once('../../database-settings.php');
	require_once('../../database.php');
	require '../../requirelanguage.php';
	require '../../css/GUMP/gump.class.php';

	#
	## Validos los valores que llegan del formulario
	$validator = new GUMP();

	// sanitizo la variable POST
	$_POST = $validator->sanitize($_POST);

	// defino reglas y filtros
	$validator->filter_rules( array(
		'detailsend'	=>	'trim|sanitize_string',
		'detailprice'	=>	'trim|sanitize_string',
		'detailinvoice'	=>	'trim|sanitize_string'));		

		$validator->validation_rules( array(
		'detailsend' 	    => 'required',
		'detailprice' 	    => 'required',
		'detailinvoice' 	=> 'required'));
		
		

		// se realiza las validaciones
		$validated_data = $validator->run($_POST);

		# si hubo errores lo informamos
		if($validated_data === false) {
			header ( "Location: ../../notificationsms.php?tipo=danger&mensaje=".$validator->get_readable_errors(true));

		} else {
		
		$detailsend = $_POST['detailsend'];
		$detailprice = $_POST['detailprice'];
		$detailinvoice = $_POST['detailinvoice'];


		$sql = "UPDATE api_sms SET detailsend='$detailsend',detailinvoice='$detailinvoice',detailprice='$detailprice' WHERE id='4'";
		dbQuery($sql);
		
		echo "<script type=\"text/javascript\">
				alert(\"$changeexits\");
				window.location = \"../../notificationsms.php\"
			</script>";	
	 
		}
    
    
?>