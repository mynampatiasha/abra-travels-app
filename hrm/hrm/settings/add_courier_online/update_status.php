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
	require_once('../../database.php');
	require '../../requirelanguage.php';
	require_once('../../database-settings.php');
	include ( "../../css/sms/src/NexmoMessage.php" );
	
    $cid = (int)$_POST['cid'];
	$deliverydate = $_POST['deliverydate'];
	$status = $_POST['status'];
	$deliveruser = $_POST['deliveruser'];	
	$comments = $_POST['comments'];
	$ship_name = $_POST['ship_name'];
	$s_phone = $_POST['s_phone'];
	$email = $_POST['email'];
	$cons_no = $_POST['cons_no'];
	
    $sql = "UPDATE courier_online SET  deliverydate='$deliverydate' , status='$status', comments='$comments', deliveruser='$deliveruser' WHERE cid = '$cid' AND cons_no = '$cons_no'";
	dbQuery($sql);

	## Obtengo datos de la API KEY
	$apiconfig =  mysqli_query($dbConn, "SELECT apikey,apisecret FROM api_sms WHERE id='1' ");

	while($row = mysqli_fetch_array($apiconfig)) {

		$api_key  = $row["apikey"];
		$api_secret  = $row["apisecret"];
	}
	mysqli_free_result($apiconfig);
	
	## Obtengo datos configuracion email
	$settingssms =  mysqli_query($dbConn, "SELECT detailsend,detailinvoice,detailprice FROM api_sms WHERE id='5'");

	while($row = mysqli_fetch_array($settingssms)) {

		$apia  = $row["detailsend"];
		$apib  = $row["detailinvoice"];
		$apic  = $row["detailprice"];
	}
	mysqli_free_result($settingssms);
	
	
	// Step 1: Declare new NexmoMessage.
	$nexmo_sms = new NexmoMessage(''.$api_key.'', ''.$api_secret.'');

	// Step 2: Use sendText( $to, $from, $message ) method to send a message.

	$info = $nexmo_sms->sendText($_POST['s_phone'], $_POST['ship_name'], ''.$ship_name.', '.$apia.' '.$status.'. '.$apib.' '.$deliverydate.'. '.$apic.' '.$comments.'');
	// Step 3: Display an overview of the message
	
	
	$result =  mysqli_query($dbConn, "SELECT * FROM company");
	while($row = mysqli_fetch_array($result)) {
	
	$to  = $row["bemail"];
	$address  = $row["caddress"];
	$namecompanie  = $row["cname"];
	$footer  = $row["footer_website"];
	$web  = $row["website"];
	$url = APP_URL."/logo-image/image_logo.php?id=1'";

    // subject

    $subject = ''.$RESERVALINEA.' | '.$row["cname"].'';
	$from = $row["bemail"];
    // message		   	
	
	// HTML email starts here
	
	$message  = "<html><body>";	
	$message .= "<div style='font-family:HelveticaNeue-Light,Arial,sans-serif;background-color:#eeeeee'>
							<table align='center' width='100%' border='0' cellspacing='0' cellpadding='0' bgcolor='#eeeeee'>
							<tbody>
								<tr>
									<td>
										<table align='center' width='750px' border='0' cellspacing='0' cellpadding='0' bgcolor='#eeeeee' style='width:750px!important'>
										<tbody>
											<tr>
												<td>
													<table width='690' align='center' border='0' cellspacing='0' cellpadding='0' bgcolor='#eeeeee'>
													<tbody>
														<tr>
															<td colspan='3' height='80' align='center' border='0' cellspacing='0' cellpadding='0' bgcolor='#eeeeee' style='padding:0;margin:0;font-size:0;line-height:0'>
																<table width='690' align='center' border='0' cellspacing='0' cellpadding='0'>
																<tbody>
																	<tr>
																		<td width='30'></td>
																		<td align='left' valign='middle' style='padding:0;margin:0;font-size:0;line-height:0'><a href='$web' target='_blank'><img src='$url' height='59' width='310'></a></td>
																		<td width='30'></td>
																	</tr>
																</tbody>
																</table>
															</td>
														</tr>
														<tr>
															<td colspan='3' align='center'>
																<table width='630' align='center' border='0' cellspacing='0' cellpadding='0'>
																<tbody>
																	<tr>
																		<td colspan='3' height='60'></td></tr><tr><td width='25'></td>
																		<td align='center'>
																			<h1 style='font-family:HelveticaNeue-Light,arial,sans-serif;font-size:40px;color:#404040;line-height:40px;font-weight:bold;margin:0;padding:0'>$welcome $namecompanie</h1>
																		</td>
																		<td width='25'></td>
																	</tr>
																	<tr>
																		<td colspan='3' height='40'></td></tr><tr><td colspan='5' align='center'>
																			<p style='color:#404040;font-size:16px;line-height:24px;font-weight:lighter;padding:0;margin:0'>$hola <strong>$ship_name</strong></p><br>
																			<p style='color:#404040;font-size:16px;line-height:22px;font-weight:lighter;padding:0;margin:0'>
																			$actualizalinea <strong>$status</strong></p><br>
																		</td>
																	</tr>
																	<tr>
																</tr>
																<tr><td colspan='3' height='30'></td></tr>
															</tbody>
															</table>
														</td>
													</tr>
													
													<tr bgcolor='#ffffff'>
														<td width='30' bgcolor='#eeeeee'></td>
															<table width='570' align='center' border='0' cellspacing='0' cellpadding='0'>
														<td>
															<tbody>
																<tr>
																	<td colspan='4' align='center'>&nbsp;</td>
																</tr>
																<tr>
																	<td colspan='4' align='center'><h2 style='font-size:24px'>$RESERVALINEA</h2></td>
																</tr>
																<tr>
																	<td colspan='4'>&nbsp;</td>
																</tr>
																<tr>
																	<td width='120' align='right' valign='top'><img src='http://deprixapro.jaom.info/icon-tracking.png' alt='tool' width='139' height='112'></td>
																	<td width='30'></td>
																	<td align='left' valign='middle'>
																		<h3 style='color:#404040;font-size:18px;line-height:24px;font-weight:bold;padding:0;margin:0'>$estadodelenvio</h3>
																		<div style='line-height:5px;padding:0;margin:0'>&nbsp;</div>
																		<div style='color:#404040;font-size:16px;line-height:22px;font-weight:lighter;padding:0;margin:0'><strong>$_Tracking:</strong> <strong>$cons_no</strong></div>
																		<div style='color:#404040;font-size:16px;line-height:22px;font-weight:lighter;padding:0;margin:0'><strong>$estado</strong> <strong>$status</strong></div>
																		<div style='line-height:10px;padding:0;margin:0'>&nbsp;</div>
																		<div style='color:#404040;font-size:16px;line-height:22px;font-weight:lighter;padding:0;margin:0'><strong>$DetallesdelEnvio:</strong> <strong>$reviews</strong></div>
																	</td>
																	<td width='30'></td>
																</tr>
																<tr>
																	<td colspan='4'>&nbsp;</td>
																</tr>
															</tbody>
															</table>
															<table width='570' align='center' border='0' cellspacing='0' cellpadding='0'>
																<tbody>
																	<tr>
																		<td align='center'>
																			<div style='text-align:center;width:100%;padding:40px 0'>
																				<table align='center' cellpadding='0' cellspacing='0' style='margin:0 auto;padding:0'>
																				<tbody>
																					<tr>
																						<td align='center' style='margin:0;text-align:center'><a href='$web' style='font-size:18px;font-family:HelveticaNeue-Light,Arial,sans-serif;line-height:22px;text-decoration:none;color:#ffffff;font-weight:bold;border-radius:2px;background-color:#00a3df;padding:14px 40px;display:block' target='_blank'>$ingresecli</a></td>
																					</tr>
																				</tbody>
																				</table>
																			</div>
																		</td>
																  </tr>
																  <tr><td>&nbsp;</td>
																  </tr>
																  <tr>
																	<td>
																		<h2 style='color:#404040;font-size:22px;font-weight:bold;line-height:26px;padding:0;margin:0'>&nbsp;</h2>
																		<div style='color:#404040;font-size:16px;line-height:22px;font-weight:lighter;padding:0;margin:0'>$hola $ship_name $estaes <br /><br /> <strong> $address $porfavor</div>
																	</td>
																</tr>
																<tr><td>&nbsp;</td>
																</tbody>
															</table>
														</td>
														<td width='30' bgcolor='#eeeeee'></td>
													</tr>
													</tbody>
													</table>
													<table align='center' width='750px' border='0' cellspacing='0' cellpadding='0' bgcolor='#eeeeee' style='width:750px!important'>
													<tbody>
														<tr>
															<td>
																<table width='630' align='center' border='0' cellspacing='0' cellpadding='0' bgcolor='#eeeeee'>
																<tbody>
																	<tr><td colspan='2' height='30'></td></tr>
																	<tr>
																		<td width='360' valign='top'>
																			<div style='color:#a3a3a3;font-size:12px;line-height:12px;padding:0;margin:0'>$footer</div>
																			<div style='line-height:5px;padding:0;margin:0'>&nbsp;</div>
																			<div style='color:#a3a3a3;font-size:12px;line-height:12px;padding:0;margin:0'>$namecompany</div>
																		</td>
																		<td align='right' valign='top'>
																			<span style='line-height:20px;font-size:10px'><a href='' target='_blank'><img src='http://i.imgbox.com/BggPYqAh.png' alt='fb'></a>&nbsp;</span>
																			<span style='line-height:20px;font-size:10px'><a href='' target='_blank'><img src='http://i.imgbox.com/j3NsGLak.png' alt='twit'></a>&nbsp;</span>
																			<span style='line-height:20px;font-size:10px'><a href='' target='_blank'><img src='http://i.imgbox.com/wFyxXQyf.png' alt='g'></a>&nbsp;</span>
																		</td>
																	</tr>
																	<tr><td colspan='2' height='5'></td></tr>
																   
																</tbody>
																</table>
															</td>
														</tr>
													</tbody>
													</table>
												</td>
											</tr>
										</tbody>
										</table>
									</td>
								</tr>
							</tbody>
							</table>
						</div>";	
	$message .= "</body></html>";

	}
    // To send HTML mail, the Content-type header must be set

    $headers  = 'MIME-Version: 1.0' . "\r\n";
    $headers .= 'Content-type: text/html; charset=utf-8' . "\r\n";
   // Additional headers
    $headers .= 'From: '.$from."\r\n";	
    // this line checks that we have a valid email address
	mail($to, $subject, $message, $headers); //This method sends the mail.
	mail($email, $subject, $message, $headers); //This method sends the mail.				   

	         
	 echo "<script type=\"text/javascript\">
				alert(\"$fueupdate ".$status."\");
				window.location = \"../../index.php\"
			</script>";
    
?>