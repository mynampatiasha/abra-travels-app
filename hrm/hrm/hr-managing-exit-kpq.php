<?php
session_start();
error_reporting(E_ALL);
ini_set('display_errors', 1);
mysqli_report(MYSQLI_REPORT_OFF);

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');

$con = conexion();
if (!$con) die("Database connection failed: " . mysqli_connect_error());

// --- ENSURE TABLES EXIST ---
$check_q = mysqli_query($con, "SHOW TABLES LIKE 'hr_exit_interview_questions'");
if ($check_q && mysqli_num_rows($check_q) == 0) {
    mysqli_query($con, "CREATE TABLE hr_exit_interview_questions (
        id INT(11) AUTO_INCREMENT PRIMARY KEY,
        department_id INT(11) NOT NULL DEFAULT 0,
        position_id INT(11) NOT NULL DEFAULT 0,
        question_text TEXT NOT NULL,
        input_type VARCHAR(50) DEFAULT 'text',
        options_json TEXT DEFAULT NULL,
        sort_order INT(11) DEFAULT 0,
        is_active TINYINT(1) DEFAULT 1,
        created_by VARCHAR(255) DEFAULT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
}

date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');
isUser();
$current_page   = basename($_SERVER['PHP_SELF']);
$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

// =========================================================================
// AJAX: GET POSITIONS FOR DEPARTMENT
// =========================================================================
if (isset($_GET['get_positions'])) {
    header('Content-Type: application/json');
    $dept_id = intval($_GET['dept_id']);
    $out = [];
    if ($dept_id > 0) {
        $q = mysqli_query($con, "SELECT id, title FROM hr_positions WHERE department_id=$dept_id ORDER BY title ASC");
        if ($q) { while ($r = mysqli_fetch_assoc($q)) $out[] = $r; }
    }
    echo json_encode($out);
    exit;
}

$selected_dept = isset($_GET['dept_id'])    ? intval($_GET['dept_id'])    : 0;
$selected_pos  = isset($_GET['position_id'])? intval($_GET['position_id']): 0;

// Positions for selected dept
$positions = [];
if ($selected_dept > 0) {
    $pq = mysqli_query($con, "SELECT id, title FROM hr_positions WHERE department_id=$selected_dept ORDER BY title ASC");
    if ($pq) { while ($p = mysqli_fetch_assoc($pq)) $positions[] = $p; }
}

// =========================================================================
// EXPORT CSV
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] == 'GET' && isset($_GET['action']) && $_GET['action'] == 'export') {
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=exit_questions_export_'.date('Y-m-d').'.csv');
    $output = fopen('php://output', 'w');
    $where = [];
    if ($selected_dept > 0) $where[] = "q.department_id=$selected_dept";
    if (isset($_GET['position_id'])) $where[] = "q.position_id=$selected_pos";
    $wsql = !empty($where) ? "WHERE ".implode(' AND ', $where) : '';
    fputcsv($output, ['Department Name','Position','Question Text','Input Type','Options (comma separated)','Sort Order']);
    $eq = mysqli_query($con, "SELECT d.name as dept_name, p.title as pos_title, q.position_id, q.question_text, q.input_type, q.options_json, q.sort_order
        FROM hr_exit_interview_questions q
        LEFT JOIN hr_departments d ON q.department_id=d.id
        LEFT JOIN hr_positions p ON q.position_id=p.id
        $wsql ORDER BY d.name, p.title, q.sort_order, q.id");
    if ($eq) {
        while ($row = mysqli_fetch_assoc($eq)) {
            $opts = (!empty($row['options_json'])) ? implode(', ', (json_decode($row['options_json'], true) ?: [])) : '';
            $pdisplay = ($row['position_id'] == 0) ? 'Global (All Positions)' : ($row['pos_title'] ?: '—');
            fputcsv($output, [$row['dept_name'], $pdisplay, $row['question_text'], $row['input_type'], $opts, $row['sort_order']]);
        }
    }
    fclose($output);
    exit;
}

// DOWNLOAD TEMPLATE
if (isset($_GET['action']) && $_GET['action'] == 'download_template') {
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=exit_questions_template.csv');
    $output = fopen('php://output', 'w');
    fputcsv($output, ['Question Text','Input Type','Options (CSV)','Sort Order']);
    fputcsv($output, ['Why did you decide to leave?','textarea','','1']);
    fputcsv($output, ['Rate relationship with manager','select','Excellent,Good,Average,Poor','2']);
    fputcsv($output, ['Were you equipped to do your job well?','radio','Yes,No','3']);
    fclose($output);
    exit;
}

// =========================================================================
// HANDLE POST SUBMISSIONS
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['action'])) {
    $act = $_POST['action'];

    if ($act == 'add_question' || $act == 'edit_question') {
        $dept_id       = intval($_POST['department_id']);
        $pos_id        = intval($_POST['position_id']);
        $question_text = mysqli_real_escape_string($con, trim($_POST['question_text'] ?? ''));
        $input_type    = mysqli_real_escape_string($con, trim($_POST['input_type'] ?? 'text'));
        $sort_order    = intval($_POST['sort_order'] ?? 0);
        $opts_json     = 'NULL';
        if (in_array($input_type, ['select','radio','checkbox']) && !empty($_POST['options_csv'])) {
            $clean = array_filter(array_map('trim', explode(',', $_POST['options_csv'])));
            $opts_json = "'" . mysqli_real_escape_string($con, json_encode(array_values($clean))) . "'";
        }

        if ($act == 'add_question' && $dept_id > 0 && !empty($question_text)) {
            mysqli_query($con, "INSERT INTO hr_exit_interview_questions (department_id,position_id,question_text,input_type,options_json,sort_order,created_by)
                VALUES ($dept_id,$pos_id,'$question_text','$input_type',$opts_json,$sort_order,'$currentUserName')");
            $_SESSION['success_message'] = "Question added successfully.";
        } elseif ($act == 'edit_question') {
            $id = intval($_POST['id']);
            if ($id > 0 && $dept_id > 0 && !empty($question_text)) {
                mysqli_query($con, "UPDATE hr_exit_interview_questions SET question_text='$question_text',input_type='$input_type',options_json=$opts_json,sort_order=$sort_order WHERE id=$id");
                $_SESSION['success_message'] = "Question updated.";
            }
        } else {
            $_SESSION['error_message'] = "Please fill all required fields.";
        }
        header("Location: $current_page?dept_id=$dept_id&position_id=$pos_id");
        exit;
    }

    if ($act == 'delete_question') {
        $id = intval($_POST['id']);
        if ($id > 0) mysqli_query($con, "DELETE FROM hr_exit_interview_questions WHERE id=$id");
        $_SESSION['success_message'] = "Question deleted.";
        $ref = isset($_SERVER['HTTP_REFERER']) ? $_SERVER['HTTP_REFERER'] : $current_page;
        header("Location: $ref"); exit;
    }

    if ($act == 'delete_questions_bulk') {
        $ids = isset($_POST['ids']) ? array_filter(array_map('intval', (array)$_POST['ids'])) : [];
        if (!empty($ids)) {
            mysqli_query($con, "DELETE FROM hr_exit_interview_questions WHERE id IN (" . implode(',', $ids) . ")");
            $_SESSION['success_message'] = count($ids) . " question(s) deleted.";
        }
        $ref = isset($_SERVER['HTTP_REFERER']) ? $_SERVER['HTTP_REFERER'] : $current_page;
        header("Location: $ref"); exit;
    }

    if ($act == 'import_questions' && isset($_FILES['import_file']) && $_FILES['import_file']['error'] === UPLOAD_ERR_OK) {
        $idept = intval($_POST['dept_id'] ?? 0);
        $ipos  = intval($_POST['position_id'] ?? 0);
        if ($idept <= 0) { $_SESSION['error_message'] = "Select a department first."; header("Location: $current_page"); exit; }
        $fh = fopen($_FILES['import_file']['tmp_name'], 'r');
        fgetcsv($fh); // skip header
        $imp = 0;
        while (($data = fgetcsv($fh)) !== false) {
            if (count($data) < 2) continue;
            $qt = mysqli_real_escape_string($con, trim($data[0]));
            $it = mysqli_real_escape_string($con, trim($data[1]));
            $oc = isset($data[2]) ? trim($data[2]) : '';
            $so = isset($data[3]) ? intval($data[3]) : 0;
            $oj = 'NULL';
            if (!empty($oc) && in_array($it, ['select','radio','checkbox'])) {
                $oa = array_filter(array_map('trim', explode(',', $oc)));
                $oj = "'" . mysqli_real_escape_string($con, json_encode(array_values($oa))) . "'";
            }
            if (!empty($qt)) {
                mysqli_query($con, "INSERT INTO hr_exit_interview_questions (department_id,position_id,question_text,input_type,options_json,sort_order,created_by) VALUES ($idept,$ipos,'$qt','$it',$oj,$so,'$currentUserName')");
                $imp++;
            }
        }
        fclose($fh);
        $_SESSION['success_message'] = "Imported $imp question(s).";
        header("Location: $current_page?dept_id=$idept&position_id=$ipos"); exit;
    }
}

// =========================================================================
// FETCH DATA FOR VIEW
// =========================================================================
$departments_arr = [];
$dq = mysqli_query($con, "SELECT * FROM hr_departments ORDER BY name ASC");
if ($dq) { while ($d = mysqli_fetch_assoc($dq)) $departments_arr[] = $d; }

// Coverage matrix
$coverage_matrix = [];
foreach ($departments_arr as $d) {
    $coverage_matrix[$d['id'].'_0'] = ['department_id'=>$d['id'],'position_id'=>0,'dept_name'=>$d['name'],'pos_title'=>'Global (All Positions)','question_count'=>0];
    $pq2 = mysqli_query($con, "SELECT id,title FROM hr_positions WHERE department_id=".$d['id']." ORDER BY title ASC");
    if ($pq2) { while ($p = mysqli_fetch_assoc($pq2)) {
        $coverage_matrix[$d['id'].'_'.$p['id']] = ['department_id'=>$d['id'],'position_id'=>$p['id'],'dept_name'=>$d['name'],'pos_title'=>$p['title'],'question_count'=>0];
    }}
}
$cov_result = mysqli_query($con, "SELECT department_id,position_id,COUNT(*) as cnt FROM hr_exit_interview_questions WHERE is_active=1 GROUP BY department_id,position_id");
if ($cov_result) { while ($cr = mysqli_fetch_assoc($cov_result)) {
    $k = $cr['department_id'].'_'.$cr['position_id'];
    if (isset($coverage_matrix[$k])) $coverage_matrix[$k]['question_count'] = intval($cr['cnt']);
}}
$display_matrix = array_filter($coverage_matrix, fn($c) => $c['question_count'] > 0 || $c['position_id'] == 0);
$coverage_configured = count(array_filter($coverage_matrix, fn($c) => $c['question_count'] > 0));

// Questions for selected filter
$q_result = null;
$questions_list = [];
if ($selected_dept > 0) {
    $q_result = mysqli_query($con, "SELECT * FROM hr_exit_interview_questions WHERE department_id=$selected_dept AND position_id=$selected_pos ORDER BY sort_order ASC, id ASC");
    if ($q_result) { while ($row = mysqli_fetch_assoc($q_result)) $questions_list[] = $row; }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title><?php echo isset($_SESSION['ge_cname']) ? htmlspecialchars($_SESSION['ge_cname']) : 'HR'; ?> | Exit Interview Configuration</title>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css" />
  <link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/jquery.dataTables.min.css" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700&display=swap" rel="stylesheet">
  <style>
    * { margin:0; padding:0; box-sizing:border-box; }
    body { font-family:'Poppins',sans-serif; background:#f0f4f8; min-height:100vh; padding:20px 0; }
    .container-fluid { max-width:1400px; margin:0 auto; padding:0 20px; }
    .page-header { background:linear-gradient(135deg,#0f2557,#1a3fc4); padding:20px 30px; border-radius:10px; box-shadow:0 4px 15px rgba(30,58,138,.3); margin-bottom:20px; display:flex; justify-content:space-between; align-items:center; }
    .page-header h1 { color:#fff; font-weight:600; margin:0; font-size:1.8rem; }
    .page-header p  { color:rgba(255,255,255,.7); font-size:12px; margin:4px 0 0; }
    .action-bar { background:#fff; padding:20px; border-radius:10px; box-shadow:0 2px 10px rgba(0,0,0,.08); margin-bottom:20px; display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:10px; }
    .card-box { background:#fff; padding:20px; border-radius:10px; box-shadow:0 2px 10px rgba(0,0,0,.08); margin-bottom:20px; }
    .table th { background:#f8fafc; color:#1e293b; font-weight:600; border-top:none; }
    .coverage-header { background:#f1f5f9; padding:15px 25px; border-bottom:1px solid #e2e8f0; display:flex; justify-content:space-between; align-items:center; cursor:pointer; }
    .coverage-header:hover { background:#e2e8f0; }
    .coverage-header h5 { margin:0; font-weight:700; color:#0f2557; }
    .cov-table { width:100%; border-collapse:collapse; }
    .cov-table th { padding:10px 14px; background:#f8fafc; color:#64748b; font-weight:700; font-size:11px; text-transform:uppercase; border-bottom:2px solid #e2e8f0; }
    .cov-table td { padding:9px 14px; border-bottom:1px solid #eef2f6; font-size:13px; }
    .rc-count { display:inline-block; padding:3px 10px; border-radius:20px; font-size:11px; font-weight:700; text-decoration:none; }
    .rc-ok  { background:#dcfce7; color:#15803d; }
    .rc-ok:hover  { background:#16a34a; color:#fff; text-decoration:none; }
    .rc-miss{ background:#f1f5f9; color:#64748b; }
    .btn-add { border:none; padding:10px 20px; border-radius:8px; font-weight:600; color:#fff; background:#10b981; cursor:pointer; }
  </style>
</head>
<body>
<div class="container-fluid">

  <?php if (isset($_SESSION['success_message'])): ?>
    <div class="alert alert-success alert-dismissible fade show mt-2"><i class="fas fa-check-circle mr-2"></i><?php echo $_SESSION['success_message']; unset($_SESSION['success_message']); ?><button type="button" class="close" data-dismiss="alert">&times;</button></div>
  <?php endif; ?>
  <?php if (isset($_SESSION['error_message'])): ?>
    <div class="alert alert-danger alert-dismissible fade show mt-2"><i class="fas fa-exclamation-circle mr-2"></i><?php echo $_SESSION['error_message']; unset($_SESSION['error_message']); ?><button type="button" class="close" data-dismiss="alert">&times;</button></div>
  <?php endif; ?>

  <div class="page-header">
    <div>
      <h1><i class="fas fa-clipboard-list mr-2"></i>Exit Interview Configuration</h1>
      <p>Setup Department &amp; Position-wise non-scoring questions for candidate exit interviews.</p>
    </div>
    <div style="display:flex;gap:10px;">
      <a href="hr-exit-initiation.php" class="btn btn-light"><i class="fas fa-arrow-left mr-1"></i>Back</a>
      <a href="hr-exit-employee-interview.php" class="btn btn-light"><i class="fas fa-play mr-1"></i>Conduct Interviews</a>
    </div>
  </div>

  <!-- COVERAGE SUMMARY -->
  <div class="card-box" style="padding:0;overflow:hidden;">
    <div class="coverage-header" onclick="var el=document.getElementById('covContent'); el.style.display=el.style.display==='none'?'block':'none';">
      <h5><i class="fas fa-th-list mr-2"></i>Question Coverage Summary (Click to Toggle)</h5>
      <span class="badge" style="background:#dcfce7;color:#15803d;font-size:12px;padding:6px 12px;"><?php echo $coverage_configured; ?> configuration(s) have questions</span>
    </div>
    <div id="covContent" style="display:none;overflow-x:auto;">
      <table class="cov-table">
        <thead><tr><th>Department</th><th>Position</th><th>Questions</th></tr></thead>
        <tbody>
          <?php if (empty($display_matrix)): ?>
            <tr><td colspan="3" class="text-center text-muted p-3">No departments found.</td></tr>
          <?php else: foreach ($display_matrix as $combo): ?>
            <tr>
              <td style="font-weight:700;color:#0f2557;"><?php echo htmlspecialchars($combo['dept_name']); ?></td>
              <td style="color:#475569;"><?php echo htmlspecialchars($combo['pos_title']); ?></td>
              <td>
                <a href="?dept_id=<?php echo $combo['department_id']; ?>&position_id=<?php echo $combo['position_id']; ?>"
                   class="rc-count <?php echo $combo['question_count'] > 0 ? 'rc-ok' : 'rc-miss'; ?>">
                  <?php echo $combo['question_count']; ?> Q<?php echo $combo['question_count'] != 1 ? 's' : ''; ?>
                </a>
              </td>
            </tr>
          <?php endforeach; endif; ?>
        </tbody>
      </table>
    </div>
  </div>

  <!-- FILTER BAR -->
  <div class="action-bar">
    <form method="GET" class="form-inline" style="gap:10px;">
      <label class="mr-1 font-weight-bold">Department:</label>
      <select name="dept_id" class="form-control mr-3" onchange="this.form.submit()">
        <option value="0">-- Select --</option>
        <?php foreach ($departments_arr as $d): ?>
          <option value="<?php echo $d['id']; ?>" <?php echo $selected_dept==$d['id']?'selected':''; ?>><?php echo htmlspecialchars($d['name']); ?></option>
        <?php endforeach; ?>
      </select>
      <label class="mr-1 font-weight-bold">Position:</label>
      <select name="position_id" class="form-control mr-3" onchange="this.form.submit()">
        <option value="0">Global (All Positions)</option>
        <?php foreach ($positions as $p): ?>
          <option value="<?php echo $p['id']; ?>" <?php echo $selected_pos==$p['id']?'selected':''; ?>><?php echo htmlspecialchars($p['title']); ?></option>
        <?php endforeach; ?>
      </select>
    </form>
    <div style="display:flex;gap:8px;flex-wrap:wrap;">
      <button type="button" class="btn btn-sm btn-danger font-weight-bold" id="bulkDeleteBtn" style="display:none;" onclick="bulkDelete()"><i class="fas fa-trash-alt mr-1"></i>Delete Selected</button>
      <button class="btn-add" data-toggle="modal" data-target="#addModal" <?php echo $selected_dept==0?'disabled':''; ?>><i class="fas fa-plus mr-1"></i>Add Question</button>
      <a href="?action=export&dept_id=<?php echo $selected_dept; ?>&position_id=<?php echo $selected_pos; ?>" class="btn btn-sm btn-primary font-weight-bold"><i class="fas fa-file-download mr-1"></i>Export CSV</a>
      <button class="btn btn-sm btn-warning font-weight-bold" data-toggle="modal" data-target="#importModal" <?php echo $selected_dept==0?'disabled':''; ?>><i class="fas fa-file-upload mr-1"></i>Import CSV</button>
    </div>
  </div>

  <!-- QUESTIONS TABLE -->
  <div class="card-box">
    <?php if ($selected_dept == 0): ?>
      <div class="text-center p-5">
        <i class="fas fa-hand-pointer fa-3x text-muted mb-3"></i>
        <h4 class="text-muted">Select a Department to manage questions</h4>
        <p class="text-muted">You can configure global or position-specific questions.</p>
      </div>
    <?php else: ?>
      <form id="bulkForm" method="POST">
        <input type="hidden" name="action" value="delete_questions_bulk">
        <table class="table table-hover" id="questionsTable">
          <thead><tr>
            <th style="width:40px;"><input type="checkbox" id="selAll"></th>
            <th>Question</th><th>Input Type</th><th>Options</th><th>Sort</th><th>Actions</th>
          </tr></thead>
          <tbody>
            <?php if (empty($questions_list)): ?>
              <tr><td colspan="6" class="text-center text-muted p-4">No questions configured for this selection.</td></tr>
            <?php else: foreach ($questions_list as $row):
                $opts_arr = (!empty($row['options_json'])) ? (json_decode($row['options_json'], true) ?: []) : [];
            ?>
              <tr>
                <td><input type="checkbox" name="ids[]" class="qchk" value="<?php echo $row['id']; ?>"></td>
                <td><strong><?php echo htmlspecialchars($row['question_text']); ?></strong></td>
                <td><span class="badge badge-secondary"><?php echo htmlspecialchars(ucfirst($row['input_type'])); ?></span></td>
                <td><small class="text-muted"><?php echo !empty($opts_arr) ? htmlspecialchars(implode(', ', $opts_arr)) : '—'; ?></small></td>
                <td><?php echo intval($row['sort_order']); ?></td>
                <td>
                  <button type="button" class="btn btn-sm btn-warning" onclick='editQ(<?php echo json_encode($row); ?>)'><i class="fas fa-edit"></i></button>
                  <button type="button" class="btn btn-sm btn-danger" onclick="if(confirm('Delete?')){document.getElementById('dq<?php echo $row['id']; ?>').submit();}"><i class="fas fa-trash"></i></button>
                </td>
              </tr>
            <?php endforeach; endif; ?>
          </tbody>
        </table>
      </form>
      <!-- Individual delete forms -->
      <?php foreach ($questions_list as $row): ?>
        <form id="dq<?php echo $row['id']; ?>" method="POST" style="display:none;">
          <input type="hidden" name="action" value="delete_question">
          <input type="hidden" name="id" value="<?php echo $row['id']; ?>">
        </form>
      <?php endforeach; ?>
    <?php endif; ?>
  </div>

</div><!-- /container -->

<!-- ADD QUESTION MODAL -->
<div class="modal fade" id="addModal" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog modal-lg"><div class="modal-content">
    <form method="POST">
      <input type="hidden" name="action" value="add_question">
      <div class="modal-header"><h5 class="modal-title">Add Question</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
      <div class="modal-body">
        <div class="row">
          <div class="col-md-6 form-group">
            <label>Department</label>
            <select name="department_id" class="form-control" required onchange="fetchPositions(this.value,'add_pos')">
              <option value="">-- Select --</option>
              <?php foreach ($departments_arr as $d): ?>
                <option value="<?php echo $d['id']; ?>" <?php echo $selected_dept==$d['id']?'selected':''; ?>><?php echo htmlspecialchars($d['name']); ?></option>
              <?php endforeach; ?>
            </select>
          </div>
          <div class="col-md-6 form-group">
            <label>Position</label>
            <select name="position_id" id="add_pos" class="form-control">
              <option value="0">Global (All Positions)</option>
              <?php foreach ($positions as $p): ?>
                <option value="<?php echo $p['id']; ?>" <?php echo $selected_pos==$p['id']?'selected':''; ?>><?php echo htmlspecialchars($p['title']); ?></option>
              <?php endforeach; ?>
            </select>
          </div>
        </div>
        <div class="form-group">
          <label>Question Text <span class="text-danger">*</span></label>
          <textarea name="question_text" class="form-control" rows="2" required></textarea>
        </div>
        <div class="row">
          <div class="col-md-6 form-group">
            <label>Input Type</label>
            <select name="input_type" class="form-control" onchange="toggleOptions(this.value,'add_opts')">
              <option value="text">Short Text</option>
              <option value="textarea">Long Text</option>
              <option value="select">Dropdown</option>
              <option value="radio">Radio Buttons</option>
              <option value="checkbox">Checkboxes</option>
            </select>
          </div>
          <div class="col-md-6 form-group">
            <label>Sort Order</label>
            <input type="number" name="sort_order" class="form-control" value="0">
          </div>
        </div>
        <div class="form-group" id="add_opts" style="display:none;">
          <label>Options (comma separated) <span class="text-danger">*</span></label>
          <input type="text" name="options_csv" class="form-control" placeholder="e.g. Excellent, Good, Average, Poor">
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
        <button type="submit" class="btn btn-primary">Save Question</button>
      </div>
    </form>
  </div></div>
</div>

<!-- EDIT QUESTION MODAL -->
<div class="modal fade" id="editModal" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog modal-lg"><div class="modal-content">
    <form method="POST">
      <input type="hidden" name="action" value="edit_question">
      <input type="hidden" name="id" id="edit_id">
      <div class="modal-header"><h5 class="modal-title">Edit Question</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
      <div class="modal-body">
        <div class="row">
          <div class="col-md-6 form-group">
            <label>Department</label>
            <select name="department_id" id="edit_dept" class="form-control" required onchange="fetchPositions(this.value,'edit_pos')">
              <?php foreach ($departments_arr as $d): ?>
                <option value="<?php echo $d['id']; ?>"><?php echo htmlspecialchars($d['name']); ?></option>
              <?php endforeach; ?>
            </select>
          </div>
          <div class="col-md-6 form-group">
            <label>Position</label>
            <select name="position_id" id="edit_pos" class="form-control"></select>
          </div>
        </div>
        <div class="form-group">
          <label>Question Text</label>
          <textarea name="question_text" id="edit_text" class="form-control" rows="2" required></textarea>
        </div>
        <div class="row">
          <div class="col-md-6 form-group">
            <label>Input Type</label>
            <select name="input_type" id="edit_type" class="form-control" onchange="toggleOptions(this.value,'edit_opts')">
              <option value="text">Short Text</option>
              <option value="textarea">Long Text</option>
              <option value="select">Dropdown</option>
              <option value="radio">Radio Buttons</option>
              <option value="checkbox">Checkboxes</option>
            </select>
          </div>
          <div class="col-md-6 form-group">
            <label>Sort Order</label>
            <input type="number" name="sort_order" id="edit_sort" class="form-control">
          </div>
        </div>
        <div class="form-group" id="edit_opts" style="display:none;">
          <label>Options (comma separated)</label>
          <input type="text" name="options_csv" id="edit_options_val" class="form-control">
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
        <button type="submit" class="btn btn-warning">Update Question</button>
      </div>
    </form>
  </div></div>
</div>

<!-- IMPORT MODAL -->
<div class="modal fade" id="importModal" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog"><div class="modal-content">
    <form method="POST" enctype="multipart/form-data">
      <input type="hidden" name="action" value="import_questions">
      <input type="hidden" name="dept_id" value="<?php echo $selected_dept; ?>">
      <input type="hidden" name="position_id" value="<?php echo $selected_pos; ?>">
      <div class="modal-header"><h5 class="modal-title">Import Questions from CSV</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
      <div class="modal-body">
        <div class="mb-3">
          <a href="?action=download_template" class="btn btn-sm btn-outline-info"><i class="fas fa-download mr-1"></i>Download Template</a>
        </div>
        <div class="form-group">
          <label>Select CSV File</label>
          <input type="file" name="import_file" class="form-control-file" accept=".csv" required>
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
        <button type="submit" class="btn btn-warning">Import</button>
      </div>
    </form>
  </div></div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
<script>
$(document).ready(function() {
    if ($('#questionsTable tbody tr td').length > 1) {
        try { $('#questionsTable').DataTable({ pageLength:25, columnDefs:[{orderable:false,targets:[0,5]}], order:[[4,'asc']] }); } catch(e){}
    }
    $('#selAll').on('click', function() { $('.qchk').prop('checked', this.checked); toggleBulk(); });
    $(document).on('click', '.qchk', function() { if (!this.checked) $('#selAll').prop('checked', false); toggleBulk(); });
});
function toggleBulk() { $('#bulkDeleteBtn').toggle($('.qchk:checked').length > 0); }
function bulkDelete() { if (confirm('Delete selected questions?')) $('#bulkForm').submit(); }
function toggleOptions(val, wrapId) {
    var show = ['select','radio','checkbox'].includes(val);
    document.getElementById(wrapId).style.display = show ? 'block' : 'none';
}
function fetchPositions(deptId, targetId) {
    var $t = $('#'+targetId);
    $t.html('<option value="0">Global (All Positions)</option>');
    if (deptId > 0) {
        $.getJSON('?get_positions=1&dept_id='+deptId, function(data) {
            data.forEach(function(p){ $t.append('<option value="'+p.id+'">'+p.title+'</option>'); });
        });
    }
}
function editQ(data) {
    $('#edit_id').val(data.id);
    $('#edit_dept').val(data.department_id);
    $('#edit_text').val(data.question_text);
    $('#edit_type').val(data.input_type);
    $('#edit_sort').val(data.sort_order);
    toggleOptions(data.input_type, 'edit_opts');
    // Load positions then set position
    var $ep = $('#edit_pos');
    $ep.html('<option value="0">Global (All Positions)</option>');
    if (data.department_id > 0) {
        $.getJSON('?get_positions=1&dept_id='+data.department_id, function(res) {
            res.forEach(function(p){ $ep.append('<option value="'+p.id+'">'+p.title+'</option>'); });
            $ep.val(data.position_id);
        });
    }
    // Set options
    if (['select','radio','checkbox'].includes(data.input_type) && data.options_json) {
        try {
            var opts = JSON.parse(data.options_json);
            $('#edit_options_val').val(Array.isArray(opts) ? opts.join(', ') : '');
        } catch(e) { $('#edit_options_val').val(''); }
    } else { $('#edit_options_val').val(''); }
    $('#editModal').modal('show');
}
</script>
</body>
</html>
