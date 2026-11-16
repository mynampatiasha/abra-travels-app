<?php
session_start();
error_reporting(E_ALL);
ini_set('display_errors', 1);

// =========================================================================
// HR SCREENING ROUND EVALUATION (KPI)
// =========================================================================

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
require 'requirelanguage.php';

$con = conexion();
if (!$con) {
    die("Database connection failed: " . mysqli_connect_error());
}

// --- ENSURE RESULT TABLES EXIST ---
// Table: hr_screening_round_answers
$check_answers = mysqli_query($con, "SHOW TABLES LIKE 'hr_screening_round_answers'");
if(mysqli_num_rows($check_answers) == 0) {
    mysqli_query($con, "CREATE TABLE hr_screening_round_answers (
        id INT(11) AUTO_INCREMENT PRIMARY KEY,
        screening_id INT(11) NOT NULL,
        round_number INT(11) NOT NULL,
        question_id INT(11) NOT NULL,
        answer_text TEXT,
        marks_obtained INT(11) DEFAULT 0,
        submitted_by VARCHAR(255),
        submitted_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )");
}

// Table: hr_screening_round_results
$check_results = mysqli_query($con, "SHOW TABLES LIKE 'hr_screening_round_results'");
if(mysqli_num_rows($check_results) == 0) {
    mysqli_query($con, "CREATE TABLE hr_screening_round_results (
        id INT(11) AUTO_INCREMENT PRIMARY KEY,
        screening_id INT(11) NOT NULL,
        round_number INT(11) NOT NULL,
        total_marks_possible INT(11) DEFAULT 0,
        marks_obtained INT(11) DEFAULT 0,
        score_percent DECIMAL(5,2) DEFAULT 0,
        result VARCHAR(50) DEFAULT 'pending',
        override_by VARCHAR(255) DEFAULT NULL,
        override_reason TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )");
}

date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');
isUser();

$current_page = basename($_SERVER['PHP_SELF']);
$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

$screening_id = isset($_GET['screening_id']) ? intval($_GET['screening_id']) : 0;
$round_number = isset($_GET['round_number']) ? intval($_GET['round_number']) : 0;

if ($screening_id == 0 || $round_number == 0) {
    die("<div style='padding:50px;text-align:center;font-family:sans-serif;'><h4>Invalid Request.</h4><p>Missing Screening ID or Round Number.</p><a href='hr_screening.php'>Go Back</a></div>");
}

// Fetch candidate details
$candidate_query = mysqli_query($con, "SELECT * FROM hr_screenings WHERE id = $screening_id");
if (mysqli_num_rows($candidate_query) == 0) {
    die("Candidate not found.");
}
$candidate = mysqli_fetch_assoc($candidate_query);

// Try to map candidate's string department to department_id
// Assuming candidate['department'] might be the name or ID
$dept_val = mysqli_real_escape_string($con, $candidate['department']);
$dept_query = mysqli_query($con, "SELECT id, name FROM hr_departments WHERE id = '$dept_val' OR name = '$dept_val' LIMIT 1");
$department_id = 0;
$department_name = $candidate['department'];
if ($row = mysqli_fetch_assoc($dept_query)) {
    $department_id = intval($row['id']);
    $department_name = $row['name'];
}

// Fetch Round Details
$round_query = mysqli_query($con, "SELECT * FROM hr_screening_rounds WHERE department_id = $department_id AND round_number = $round_number LIMIT 1");
$round_name = "Round $round_number";
if (mysqli_num_rows($round_query) > 0) {
    $round_data = mysqli_fetch_assoc($round_query);
    $round_name = $round_data['round_name'];
} else {
    // Round configuration not found for this dept/round_number
    $no_config = true;
}

// Fetch Questions
$questions = [];
if ($department_id > 0) {
    $q_res = mysqli_query($con, "SELECT * FROM hr_screening_questions WHERE department_id = $department_id AND round_number = $round_number ORDER BY id ASC");
    while($q = mysqli_fetch_assoc($q_res)) {
        $questions[] = $q;
    }
}

// Check if already evaluated
$check_existing = mysqli_query($con, "SELECT * FROM hr_screening_round_results WHERE screening_id = $screening_id AND round_number = $round_number");
$existing_result = null;
if (mysqli_num_rows($check_existing) > 0) {
    $existing_result = mysqli_fetch_assoc($check_existing);
}

// =========================================================================
// HANDLE FORM SUBMISSION
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['action']) && $_POST['action'] == 'submit_evaluation') {
    
    $total_possible = 0;
    $total_obtained = 0;
    $answers_to_insert = [];

    foreach ($questions as $q) {
        $qid = $q['id'];
        $possible = intval($q['marks']);
        $total_possible += $possible;

        $ans_text = isset($_POST["q_{$qid}_ans"]) ? mysqli_real_escape_string($con, is_array($_POST["q_{$qid}_ans"]) ? implode(', ', $_POST["q_{$qid}_ans"]) : $_POST["q_{$qid}_ans"]) : '';
        $marks_obt = isset($_POST["q_{$qid}_marks"]) ? intval($_POST["q_{$qid}_marks"]) : 0;
        
        // Safety bounds for marks
        if ($marks_obt < 0) $marks_obt = 0;
        if ($marks_obt > $possible) $marks_obt = $possible;
        
        $total_obtained += $marks_obt;

        $answers_to_insert[] = "($screening_id, $round_number, $qid, '$ans_text', $marks_obt, '$currentUserName')";
    }

    $score_percent = 0;
    if ($total_possible > 0) {
        $score_percent = round(($total_obtained / $total_possible) * 100, 2);
    }

    $result_status = ($score_percent >= 90) ? 'passed' : 'failed';
    $override_reason = '';
    
    // Check if HR Overrode it directly on submission
    if (isset($_POST['is_override']) && $_POST['is_override'] == '1' && !empty($_POST['override_reason'])) {
        $result_status = 'overridden';
        $override_reason = mysqli_real_escape_string($con, $_POST['override_reason']);
    }

    // Insert answers
    if (!empty($answers_to_insert)) {
        mysqli_query($con, "DELETE FROM hr_screening_round_answers WHERE screening_id = $screening_id AND round_number = $round_number");
        mysqli_query($con, "INSERT INTO hr_screening_round_answers (screening_id, round_number, question_id, answer_text, marks_obtained, submitted_by) VALUES " . implode(',', $answers_to_insert));
    }

    // Insert or Update result
    if ($existing_result) {
        $rid = $existing_result['id'];
        $override_sql = $result_status == 'overridden' ? ", override_by='$currentUserName', override_reason='$override_reason'" : ", override_by=NULL, override_reason=NULL";
        mysqli_query($con, "UPDATE hr_screening_round_results SET total_marks_possible=$total_possible, marks_obtained=$total_obtained, score_percent=$score_percent, result='$result_status' $override_sql WHERE id=$rid");
    } else {
        $override_by = $result_status == 'overridden' ? "'$currentUserName'" : "NULL";
        $reason = $result_status == 'overridden' ? "'$override_reason'" : "NULL";
        mysqli_query($con, "INSERT INTO hr_screening_round_results (screening_id, round_number, total_marks_possible, marks_obtained, score_percent, result, override_by, override_reason) VALUES ($screening_id, $round_number, $total_possible, $total_obtained, $score_percent, '$result_status', $override_by, $reason)");
    }
    
    $_SESSION['success_message'] = "Evaluation submitted successfully! Score: $score_percent% - Result: " . strtoupper($result_status);
    header("Location: $current_page?screening_id=$screening_id&round_number=$round_number");
    exit;
}

// Handle post-evaluation Override
if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['action']) && $_POST['action'] == 'override_result') {
    if ($existing_result && $existing_result['result'] == 'failed') {
        $rid = $existing_result['id'];
        $reason = mysqli_real_escape_string($con, $_POST['override_reason']);
        mysqli_query($con, "UPDATE hr_screening_round_results SET result='overridden', override_by='$currentUserName', override_reason='$reason' WHERE id=$rid");
        $_SESSION['success_message'] = "Round successfully overridden.";
    }
    header("Location: $current_page?screening_id=$screening_id&round_number=$round_number");
    exit;
}

?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Evaluate Candidate | <?php echo isset($_SESSION['ge_cname']) ? $_SESSION['ge_cname'] : 'Abra'; ?></title>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />

  <!-- CSS Resources -->
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700&display=swap" rel="stylesheet">

  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Poppins', sans-serif; background: #f0f4f8; min-height: 100vh; padding: 20px 0; }
    
    .container-fluid { max-width: 1000px; margin: 0 auto; padding: 0 20px; }

    /* Header */
    .page-header {
      background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%);
      padding: 20px 30px; border-radius: 10px; box-shadow: 0 4px 15px rgba(30, 58, 138, 0.3);
      margin-bottom: 20px; color: white; display: flex; justify-content: space-between; align-items: center;
    }
    .page-header h1 { font-weight: 600; margin: 0; font-size: 1.6rem; }
    
    .card-box { background: white; padding: 25px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.08); margin-bottom: 25px;}
    
    .candidate-info { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; margin-bottom: 20px; }
    .candidate-info p { margin: 0; font-size: 15px; }
    .candidate-info strong { color: #1e293b; }

    .question-block { border: 1px solid #e2e8f0; border-radius: 8px; padding: 20px; margin-bottom: 20px; background: #f8fafc; }
    .question-text { font-size: 16px; font-weight: 600; margin-bottom: 15px; color: #0f172a; }
    .marks-input-group { background: white; padding: 10px 15px; border-radius: 6px; border: 1px solid #cbd5e1; display: inline-flex; align-items: center; gap: 10px;}
    
    .result-banner { padding: 20px; border-radius: 10px; margin-bottom: 25px; font-size: 18px; font-weight: 600; text-align: center;}
    .result-passed { background: #d1fae5; color: #065f46; border: 2px solid #34d399; }
    .result-failed { background: #fee2e2; color: #991b1b; border: 2px solid #f87171; }
    .result-overridden { background: #fef3c7; color: #92400e; border: 2px solid #fbbf24; }
  </style>
</head>
<body>

<div class="container-fluid">
    
    <!-- Alerts -->
    <?php if(isset($_SESSION['success_message'])): ?>
        <div class="alert alert-success alert-dismissible fade show">
            <i class="fas fa-check-circle mr-2"></i> <?php echo $_SESSION['success_message']; ?>
            <button type="button" class="close" data-dismiss="alert">&times;</button>
        </div>
        <?php unset($_SESSION['success_message']); ?>
    <?php endif; ?>

    <div class="page-header">
        <div>
            <h1><i class="fas fa-clipboard-check mr-2"></i> Evaluate Candidate</h1>
            <p class="mb-0 mt-2 opacity-75">Round <?php echo $round_number; ?>: <?php echo htmlspecialchars($round_name); ?></p>
        </div>
        <a href="hr_screening.php" class="btn btn-light"><i class="fas fa-arrow-left"></i> Back</a>
    </div>

    <div class="card-box">
        <h4 class="mb-4" style="border-bottom: 2px solid #e2e8f0; padding-bottom: 10px;">Candidate Details</h4>
        <div class="candidate-info">
            <p><strong>Name:</strong> <?php echo htmlspecialchars($candidate['candidate_name']); ?></p>
            <p><strong>Position Applied:</strong> <?php echo htmlspecialchars($candidate['position_applied']); ?></p>
            <p><strong>Department:</strong> <?php echo htmlspecialchars($department_name); ?></p>
            <p><strong>AI Eligibility Score:</strong> <span class="badge badge-info" style="font-size: 14px;"><?php echo $candidate['eligibility_score']; ?>%</span></p>
        </div>
    </div>

    <?php if (isset($no_config) && $no_config): ?>
        <div class="alert alert-warning">
            <i class="fas fa-exclamation-triangle"></i> No round configuration found for this department and round number. Please ask HR to configure the round in the Management portal.
        </div>
    <?php elseif (empty($questions)): ?>
        <div class="alert alert-info">
            <i class="fas fa-info-circle"></i> No questions have been added for this round yet.
        </div>
    <?php else: ?>

        <?php if ($existing_result): ?>
            <!-- Show Result -->
            <div class="result-banner result-<?php echo strtolower($existing_result['result']); ?>">
                Overall Score: <?php echo $existing_result['score_percent']; ?>% 
                <br>
                Status: <?php echo strtoupper($existing_result['result']); ?>
                <?php if($existing_result['result'] == 'overridden'): ?>
                    <div style="font-size: 14px; margin-top: 10px; font-weight: normal;">
                        <strong>Overridden By:</strong> <?php echo htmlspecialchars($existing_result['override_by']); ?><br>
                        <strong>Reason:</strong> <?php echo nl2br(htmlspecialchars($existing_result['override_reason'])); ?>
                    </div>
                <?php endif; ?>
            </div>
            
            <?php if ($existing_result['result'] == 'failed'): ?>
                <div class="text-center mb-4">
                    <button class="btn btn-warning btn-lg shadow-sm" data-toggle="modal" data-target="#overrideModal">
                        <i class="fas fa-unlock-alt"></i> HR Override (Manually Pass)
                    </button>
                </div>

                <!-- Override Modal -->
                <div class="modal fade" id="overrideModal">
                    <div class="modal-dialog">
                        <div class="modal-content">
                            <form method="POST">
                                <input type="hidden" name="action" value="override_result">
                                <div class="modal-header bg-warning">
                                    <h4 class="modal-title text-dark">HR Override</h4>
                                    <button type="button" class="close" data-dismiss="modal">&times;</button>
                                </div>
                                <div class="modal-body">
                                    <p>The candidate scored <strong><?php echo $existing_result['score_percent']; ?>%</strong> (Below 90% threshold).</p>
                                    <p>By overriding, you are manually passing the candidate to the next round.</p>
                                    <div class="form-group mt-3">
                                        <label class="font-weight-bold">Reason for Override:</label>
                                        <textarea name="override_reason" class="form-control" rows="3" required placeholder="e.g. Strong technical skills, poor communication but acceptable..."></textarea>
                                    </div>
                                </div>
                                <div class="modal-footer">
                                    <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
                                    <button type="submit" class="btn btn-warning font-weight-bold text-dark">Confirm Override</button>
                                </div>
                            </form>
                        </div>
                    </div>
                </div>
            <?php endif; ?>
            
            <!-- We could show readonly answers here, but for simplicity we allow re-submission if needed, or just lock it -->
            <div class="alert alert-secondary text-center"><i class="fas fa-lock"></i> Evaluation has been submitted.</div>
            
        <?php else: ?>
        
            <!-- Form to evaluate -->
            <form method="POST" id="evaluationForm">
                <input type="hidden" name="action" value="submit_evaluation">
                <input type="hidden" name="is_override" id="is_override" value="0">
                <input type="hidden" name="override_reason" id="override_reason_input" value="">
                
                <?php foreach($questions as $index => $q): ?>
                    <div class="question-block">
                        <div class="question-text">
                            Q<?php echo $index + 1; ?>. <?php echo nl2br(htmlspecialchars($q['question_text'])); ?>
                            <span class="badge badge-info float-right">Max Marks: <?php echo $q['marks']; ?></span>
                        </div>
                        
                        <div class="form-group mb-3">
                            <?php 
                            $name = "q_{$q['id']}_ans";
                            $options = [];
                            if (!empty($q['options_json'])) {
                                $options = json_decode($q['options_json'], true) ?: [];
                            }
                            ?>
                            
                            <?php if($q['input_type'] == 'text'): ?>
                                <input type="text" name="<?php echo $name; ?>" class="form-control">
                            <?php elseif($q['input_type'] == 'textarea'): ?>
                                <textarea name="<?php echo $name; ?>" class="form-control" rows="3"></textarea>
                            <?php elseif($q['input_type'] == 'number'): ?>
                                <input type="number" name="<?php echo $name; ?>" class="form-control" style="max-width: 200px;">
                            <?php elseif($q['input_type'] == 'select'): ?>
                                <select name="<?php echo $name; ?>" class="form-control" style="max-width: 300px;">
                                    <option value="">-- Select --</option>
                                    <?php foreach($options as $opt): ?>
                                        <option value="<?php echo htmlspecialchars($opt); ?>"><?php echo htmlspecialchars($opt); ?></option>
                                    <?php endforeach; ?>
                                </select>
                            <?php elseif($q['input_type'] == 'radio'): ?>
                                <div>
                                <?php foreach($options as $opt): ?>
                                    <div class="custom-control custom-radio custom-control-inline">
                                        <input type="radio" id="r_<?php echo $q['id'].'_'.md5($opt); ?>" name="<?php echo $name; ?>" class="custom-control-input" value="<?php echo htmlspecialchars($opt); ?>">
                                        <label class="custom-control-label" for="r_<?php echo $q['id'].'_'.md5($opt); ?>"><?php echo htmlspecialchars($opt); ?></label>
                                    </div>
                                <?php endforeach; ?>
                                </div>
                            <?php elseif($q['input_type'] == 'rating'): ?>
                                <select name="<?php echo $name; ?>" class="form-control" style="max-width: 150px;">
                                    <option value="">-- Rating --</option>
                                    <option value="1">1 - Poor</option>
                                    <option value="2">2 - Fair</option>
                                    <option value="3">3 - Good</option>
                                    <option value="4">4 - Very Good</option>
                                    <option value="5">5 - Excellent</option>
                                </select>
                            <?php endif; ?>
                        </div>
                        
                        <div class="marks-input-group mt-3">
                            <label class="mb-0 font-weight-bold text-primary">Marks Awarded:</label>
                            <input type="number" name="q_{$q['id']}_marks" class="form-control marks-input" style="width: 100px; text-align: center; font-weight: bold;" min="0" max="<?php echo $q['marks']; ?>" value="0" required>
                            <span class="text-muted">/ <?php echo $q['marks']; ?></span>
                        </div>
                    </div>
                <?php endforeach; ?>

                <div class="card-box sticky-bottom" style="position: sticky; bottom: 20px; z-index: 100; border: 2px solid #3b82f6;">
                    <div class="d-flex justify-content-between align-items-center">
                        <div>
                            <h5 class="mb-0">Estimated Total: <span id="liveTotal" class="text-primary font-weight-bold">0</span> / <span id="maxTotal"><?php echo array_sum(array_column($questions, 'marks')); ?></span></h5>
                            <small id="livePercent" class="text-muted font-weight-bold">0%</small>
                        </div>
                        <button type="button" class="btn btn-primary btn-lg px-5 shadow" onclick="submitEvaluation()">Submit Evaluation</button>
                    </div>
                </div>
            </form>

            <!-- Pre-Submit Override Modal (if score < 90) -->
            <div class="modal fade" id="preSubmitOverrideModal">
                <div class="modal-dialog">
                    <div class="modal-content">
                        <div class="modal-header bg-danger text-white">
                            <h4 class="modal-title">Low Score Alert</h4>
                            <button type="button" class="close text-white" data-dismiss="modal">&times;</button>
                        </div>
                        <div class="modal-body">
                            <p class="font-weight-bold text-danger text-center" style="font-size: 20px;">Score: <span id="modalScoreVal"></span>%</p>
                            <p>This candidate has scored below the 90% threshold and will be marked as <strong>FAILED</strong>.</p>
                            <p>Do you want to manually override and pass the candidate anyway?</p>
                            
                            <div class="form-group mt-3">
                                <label class="font-weight-bold">Reason for Override (Optional):</label>
                                <textarea id="pre_override_reason" class="form-control" rows="3" placeholder="If overriding, provide a reason..."></textarea>
                            </div>
                        </div>
                        <div class="modal-footer justify-content-between">
                            <button type="button" class="btn btn-danger px-4" onclick="finalizeSubmit(false)">Submit as Failed</button>
                            <button type="button" class="btn btn-warning font-weight-bold text-dark px-4" onclick="finalizeSubmit(true)">Override & Pass</button>
                        </div>
                    </div>
                </div>
            </div>

            <script>
            function updateLiveScore() {
                let total = 0;
                let max = parseInt(document.getElementById('maxTotal').innerText);
                document.querySelectorAll('.marks-input').forEach(function(input) {
                    total += parseInt(input.value || 0);
                });
                document.getElementById('liveTotal').innerText = total;
                let pct = max > 0 ? ((total / max) * 100).toFixed(1) : 0;
                let pctEl = document.getElementById('livePercent');
                pctEl.innerText = pct + '%';
                
                if (pct >= 90) {
                    pctEl.className = 'text-success font-weight-bold';
                } else {
                    pctEl.className = 'text-danger font-weight-bold';
                }
            }

            document.querySelectorAll('.marks-input').forEach(function(input) {
                input.addEventListener('input', updateLiveScore);
            });

            function submitEvaluation() {
                // Check form validity
                if (!document.getElementById('evaluationForm').checkValidity()) {
                    document.getElementById('evaluationForm').reportValidity();
                    return;
                }

                let max = parseInt(document.getElementById('maxTotal').innerText);
                let total = 0;
                document.querySelectorAll('.marks-input').forEach(function(input) {
                    total += parseInt(input.value || 0);
                });
                let pct = max > 0 ? ((total / max) * 100).toFixed(1) : 0;

                if (pct < 90) {
                    document.getElementById('modalScoreVal').innerText = pct;
                    $('#preSubmitOverrideModal').modal('show');
                } else {
                    document.getElementById('evaluationForm').submit();
                }
            }

            function finalizeSubmit(isOverride) {
                if (isOverride) {
                    let reason = document.getElementById('pre_override_reason').value.trim();
                    if (reason === '') {
                        alert('Please provide an override reason.');
                        document.getElementById('pre_override_reason').focus();
                        return;
                    }
                    document.getElementById('is_override').value = '1';
                    document.getElementById('override_reason_input').value = reason;
                }
                document.getElementById('evaluationForm').submit();
            }
            </script>
        <?php endif; ?>
    <?php endif; ?>

</div>

<!-- Scripts -->
<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>

</body>
</html>
