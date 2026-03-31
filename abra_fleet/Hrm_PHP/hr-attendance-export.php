<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
require 'requirelanguage.php';
$con = conexion();

date_default_timezone_set($_SESSION['ge_timezone']);


isUser();														 
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title><?php echo $_SESSION['ge_cname']; ?> | <?php echo $manejooficinas; ?></title>
  <meta name="description" content="<?php echo $_SESSION['ge_description']; ?>"/>
  <meta name="keywords" content="<?php echo $_SESSION['ge_keywords']; ?>" />
  <meta name="author" content="Jaomweb">	
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
  
  <link rel="shortcut icon" type="image/png" href="img/favicon.png"/>

  <link rel="stylesheet" href="../bower_components/bootstrap/dist/css/bootstrap.css" type="text/css" />
  <link rel="stylesheet" href="../bower_components/animate.css/animate.css" type="text/css" />
  <link rel="stylesheet" href="../bower_components/font-awesome/css/font-awesome.min.css" type="text/css" />
  <link rel="stylesheet" href="../bower_components/simple-line-icons/css/simple-line-icons.css" type="text/css" />
  <link rel="stylesheet" href="css/font.css" type="text/css" />
  <link rel="stylesheet" href="css/app.css" type="text/css" />
  <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
	<style type="text/css">
	.parsley-error {
	  border-color: #ff5d48 !important; }

	.parsley-errors-list {
	  display: none;
	  margin: 0;
	  padding: 0; }

	.parsley-errors-list.filled {
	  display: block; }
	  
	.parsley-errors-list > li {
	  font-size: 12px;
	  list-style: none;
	  color: #ff5d48;
	  margin-top: 5px; }
	</style>
</head>
<body>
<?php
include("header.php");
?>
  
 <!-- content -->
  <div id="content" class="app-content" role="main">
    <div class="app-content-body ">     

<div class="hbox hbox-auto-xs hbox-auto-sm" ng-init="
    app.settings.asideFolded = false; 
    app.settings.asideDock = false;
  ">
  <!-- main -->
  <div class="col">
    <!-- main header -->
    <div class="bg-light lter b-b wrapper-md">

    </div>
    <!-- / main header -->
    <div class="wrapper-md" ng-controller="FlotChartDemoCtrl">

			  <!-- service -->
		<div class="panel hbox hbox-auto-xs no-border">
			<div class="col wrapper">
			    <div class="row">
					<div class="col-xs-12" align="center">
					<h2>Attendance Report Export</h2>
					<br>
					</div>
				</div>
					<center>
				<!-- Form to select month and year -->
				<form action="settings/hr-employee/export-attendance.php" method="POST" style="margin-bottom:50px;">
					<label for="month">Select Month:</label>
					<select id="month" class="gentxt1" name="month">
						<?php
						for ($i = 1; $i <= 12; $i++) {
							$month_num = str_pad($i, 2, "0", STR_PAD_LEFT);
							echo "<option value=\"$month_num\">" . date("F", strtotime("2024-$month_num-01")) . "</option>";
						}
						?>
					</select>

					<label for="year">Select Year:</label>
					<select id="year" class="gentxt1" name="year">
						<?php
						$current_year = date('Y');
						for ($i = $current_year; $i >= 2020; $i--) {
							echo "<option value=\"$i\">$i</option>";
						}
						?>
					</select>

					<button class="btn btn-md btn-danger" style="margin-top: -10px;" type="submit">Export Report</button>
				</form>
					</center>
				</div>       
			  </div>
			</div>
		  </div>
		</div>
    </div>
  </div>
  <!-- / content -->

<?php
include("footer.php");
?>

</div>

<script src="../bower_components/jquery/dist/jquery.min.js"></script>
<script src="../bower_components/bootstrap/dist/js/bootstrap.js"></script>
<script src="jquery.min.js"></script>
<script src="js/ui-load.js"></script>
<script src="js/ui-jp.config.js"></script>
<script src="js/ui-jp.js"></script>
<script src="js/ui-nav.js"></script>
<script src="js/ui-toggle.js"></script>
<script src="js/delivery.js"></script>

<!-- Validation js (Parsleyjs) -->
<script type="text/javascript" src="js/parsley.min.js"></script>

<script type="text/javascript">
	$(document).ready(function() {
		$('form').parsley();
	});
</script>

<script>
	// Toggle attendance when present or absent is clicked
	function toggleAttendance(element, employeeId, status) {
		// Get the row and uncheck the opposite checkbox
		var row = $(element).closest('tr');
		if (status === 'present') {
			row.find('.absent-checkbox').prop('checked', false);
		} else {
			row.find('.present-checkbox').prop('checked', false);
		}

		// Update attendance via AJAX
		var date = "<?php echo $date; ?>"; // Use the selected date
		$.ajax({
			url: 'settings/hr-employee/update-attendance.php',
			method: 'POST',
			data: {
				employee_id: employeeId,
				date: date,
				status: status
			},
			success: function (response) {
				console.log(response); // Log response for debugging
			}
		});
	}
</script>
	
</body>
</html>
