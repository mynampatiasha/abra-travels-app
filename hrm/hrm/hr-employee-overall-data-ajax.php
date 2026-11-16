<?php
// --- FLUTTER WEBVIEW AUTH INJECTION ---
if (!headers_sent()) { header('Content-Type: text/html; charset=utf-8'); }
if (session_status() === PHP_SESSION_NONE) { session_start(); }
// Recover the Flutter user's email from (in order): the URL param, our own
// long-lived cookie, or the session. This keeps the login alive across every
// internal link / redirect inside the WebView, even when the PHP session
// cookie is not carried between page loads.
$__fue = $_REQUEST['user_email'] ?? $_COOKIE['abra_hrm_email'] ?? $_SESSION['flutter_user_email'] ?? '';
if ($__fue !== '' && (isset($_REQUEST['user_email']) || empty($_SESSION['user_name']))) {
    require_once('database.php');
    $auth_con = conexion();
    $user_email = mysqli_real_escape_string($auth_con, $__fue);
    $auth_query = mysqli_query($auth_con, "SELECT * FROM hr_employees WHERE TRIM(LOWER(email)) = TRIM(LOWER('$user_email')) OR TRIM(LOWER(personal_email)) = TRIM(LOWER('$user_email')) LIMIT 1");
    if ($auth_query && mysqli_num_rows($auth_query) > 0) {
        $auth_user = mysqli_fetch_assoc($auth_query);
        $_SESSION['user_name'] = $auth_user['name'];
        $_SESSION['user_id'] = $auth_user['id'];
        $_SESSION['role_id'] = $auth_user['role_id'] ?? 0;
        $_SESSION['role_name'] = 'hr';
        $_SESSION['flutter_user_email'] = $__fue;
        $_SESSION['ge_cname'] = $auth_user['company_name'] ?? ($_SESSION['ge_cname'] ?? 'Abra');
        if (empty($_SESSION['ge_timezone'])) { $_SESSION['ge_timezone'] = 'Asia/Kolkata'; }
        if (!headers_sent()) { setcookie('abra_hrm_email', $__fue, ['expires' => time() + 43200, 'path' => '/', 'secure' => true, 'httponly' => false, 'samesite' => 'None']); }
    }
}
// Defaults so page <title> / headers that read these session keys don't warn
// in the WebView (the CRM login normally sets them).
if (!isset($_SESSION['ge_cname']))    { $_SESSION['ge_cname'] = 'Abra'; }
if (!isset($_SESSION['ge_timezone'])) { $_SESSION['ge_timezone'] = 'Asia/Kolkata'; }
// Make the email available to the in-page link fixer (see foot of file).
$GLOBALS['__fue'] = $__fue;
// --------------------------------------
error_reporting(E_ALL);
ini_set('display_errors', 1);
mysqli_report(MYSQLI_REPORT_OFF);

require_once('database.php');
require_once('library.php');
require_once('funciones.php');

$con = conexion();
if (!$con) die("<div class='alert alert-danger'>Database connection failed.</div>");

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'get_timeline') {
    $candidate_id = intval($_POST['candidate_id']);
    
    // Fetch Screening
    $sq = mysqli_query($con, "SELECT created_at, hr_decision, department, position_applied, candidate_email, candidate_phone FROM hr_screenings WHERE id=$candidate_id LIMIT 1");
    $screen = $sq ? mysqli_fetch_assoc($sq) : null;
    
    if (!$screen) {
        echo "<div class='alert alert-warning'>No record found for this candidate.</div>";
        exit;
    }
    
    // Build Timeline Events
    $events = [];
    
    // 1. Screening
    $events[] = [
        'step_order' => 1,
        'date' => $screen['created_at'],
        'title' => 'Application Received',
        'desc' => "Applied for {$screen['position_applied']} in {$screen['department']}.",
        'icon' => 'fa-file-alt',
        'color' => '#64748b'
    ];
    
    if ($screen['hr_decision']) {
        $events[] = [
            'step_order' => 2,
            'date' => $screen['created_at'],
            'title' => 'Screening Decision',
            'desc' => "Status updated to: {$screen['hr_decision']}",
            'icon' => 'fa-user-check',
            'color' => strtolower($screen['hr_decision']) == 'selected' || strtolower($screen['hr_decision']) == 'hired' ? '#f97316' : '#ef4444'
        ];
    }
    
    // 1.5 Screening Interviews
    $iq = mysqli_query($con, "SELECT round_number, evaluator_name, percentage, rating_label, status, created_at FROM hr_screening_evaluations WHERE screening_id=$candidate_id ORDER BY round_number ASC");
    if ($iq) {
        while($iv = mysqli_fetch_assoc($iq)) {
            $status_txt = $iv['status'] == 'Passed' ? 'Passed' : ($iv['status'] == 'Failed' ? 'Failed' : $iv['status']);
            $color = $iv['status'] == 'Passed' ? '#10b981' : ($iv['status'] == 'Failed' ? '#ef4444' : '#3b82f6');
            $rating = $iv['rating_label'] ? " - {$iv['rating_label']}" : "";
            $events[] = [
                'step_order' => 1.5,
                'date' => $iv['created_at'],
                'title' => 'Interview Round ' . $iv['round_number'] . $rating,
                'desc' => "Evaluated by {$iv['evaluator_name']}. Score: {$iv['percentage']}%. Result: {$status_txt}.",
                'icon' => 'fa-comments',
                'color' => $color
            ];
        }
    }
    
    // 2. Offer Letter
    $oq = mysqli_query($con, "SELECT status, sent_at, candidate_action_at FROM hr_offer_letters WHERE candidate_id=$candidate_id LIMIT 1");
    if ($oq && $offer = mysqli_fetch_assoc($oq)) {
        $sent_date = !empty($offer['sent_at']) ? $offer['sent_at'] : '';
        $events[] = [
            'step_order' => 3,
            'date' => $sent_date,
            'title' => 'Offer Sent',
            'desc' => 'Offer letter dispatched to candidate.',
            'icon' => 'fa-envelope-open-text',
            'color' => '#eab308'
        ];
        
        if (in_array($offer['status'], ['accepted', 'rejected'])) {
            $events[] = [
                'step_order' => 4,
                'date' => !empty($offer['candidate_action_at']) ? $offer['candidate_action_at'] : '',
                'title' => 'Offer ' . ucfirst($offer['status']),
                'desc' => "Candidate has {$offer['status']} the offer.",
                'icon' => $offer['status'] == 'accepted' ? 'fa-handshake' : 'fa-times-circle',
                'color' => $offer['status'] == 'accepted' ? '#22c55e' : '#ef4444'
            ];
        }
    }
    
    // 3. Document Verification
    $dq = mysqli_query($con, "SELECT status, submitted_at, verified_at FROM hr_dv_requests WHERE candidate_id=$candidate_id LIMIT 1");
    if ($dq && $dv = mysqli_fetch_assoc($dq)) {
        $sub_date = !empty($dv['submitted_at']) ? $dv['submitted_at'] : '';
        $events[] = [
            'step_order' => 5,
            'date' => $sub_date,
            'title' => 'Documents Requested / Submitted',
            'desc' => 'Candidate documents request initiated.',
            'icon' => 'fa-folder-open',
            'color' => '#a855f7'
        ];
        
        if ($dv['status'] == 'verified') {
            $events[] = [
                'step_order' => 6,
                'date' => !empty($dv['verified_at']) ? $dv['verified_at'] : '',
                'title' => 'Documents Verified',
                'desc' => "Document verification status: {$dv['status']}.",
                'icon' => 'fa-check-double',
                'color' => '#8b5cf6'
            ];
        }
    }
    
    // 4. Onboarding
    $bq = mysqli_query($con, "SELECT status, submitted_at FROM hr_employee_onboarding_pending WHERE candidate_id=$candidate_id LIMIT 1");
    if ($bq && $ob = mysqli_fetch_assoc($bq)) {
        $ob_date = !empty($ob['submitted_at']) ? $ob['submitted_at'] : '';
        $events[] = [
            'step_order' => 7,
            'date' => $ob_date,
            'title' => 'Onboarding Initiated',
            'desc' => "Onboarding status: {$ob['status']}.",
            'icon' => 'fa-id-card',
            'color' => '#0ea5e9'
        ];
    }
    
    // 5. Employee Active
    $passed_employee_id = isset($_POST['employee_id']) ? intval($_POST['employee_id']) : 0;
    $emp_id = 0;
    
    if ($passed_employee_id > 0) {
        $eq = mysqli_query($con, "SELECT id, status, hire_date FROM hr_employees WHERE id=$passed_employee_id LIMIT 1");
        if ($eq && $emp = mysqli_fetch_assoc($eq)) {
            $emp_id = $emp['id'];
            $events[] = [
                'step_order' => 8,
                'date' => $emp['hire_date'],
                'title' => 'Employee Profile Created',
                'desc' => "Status: {$emp['status']}",
                'icon' => 'fa-user-tie',
                'color' => '#14b8a6'
            ];
        }
    } else {
        $c_email = mysqli_real_escape_string($con, $screen['candidate_email'] ?? '');
        $c_phone = mysqli_real_escape_string($con, $screen['candidate_phone'] ?? '');
        
        $emp_cond = [];
        if (!empty($c_email)) $emp_cond[] = "personal_email='$c_email'";
        if (!empty($c_phone)) $emp_cond[] = "phone='$c_phone'";
        
        $eq = null;
        if (!empty($emp_cond)) {
            $eq = mysqli_query($con, "SELECT id, status, hire_date FROM hr_employees WHERE (" . implode(' OR ', $emp_cond) . ") ORDER BY id DESC LIMIT 1");
        }
        if ($eq && $emp = mysqli_fetch_assoc($eq)) {
            $emp_id = $emp['id'];
            $events[] = [
                'step_order' => 8,
                'date' => $emp['hire_date'],
                'title' => 'Employee Profile Created',
                'desc' => "Status: {$emp['status']}",
                'icon' => 'fa-user-tie',
                'color' => '#14b8a6'
            ];
        }
    }
    
    // 6. Detailed Training / OJE Progress
    if ($emp_id > 0) {
        $tq = mysqli_query($con, "SELECT * FROM hr_oje_employee_progress WHERE employee_id=$emp_id LIMIT 1");
        if ($tq && $train = mysqli_fetch_assoc($tq)) {
            if (!empty($train['training_started_at'])) {
                $events[] = [
                    'step_order' => 9.1,
                    'date' => $train['training_started_at'],
                    'title' => 'Training Materials Started',
                    'desc' => 'Employee began training materials.',
                    'icon' => 'fa-book-open',
                    'color' => '#3b82f6'
                ];
            }
            if (!empty($train['training_completed_at'])) {
                $events[] = [
                    'step_order' => 9.2,
                    'date' => $train['training_completed_at'],
                    'title' => 'Training Materials Completed',
                    'desc' => 'Employee completed training materials.',
                    'icon' => 'fa-book',
                    'color' => '#2563eb'
                ];
            }
            
            if (!empty($train['oje_started_at'])) {
                $events[] = [
                    'step_order' => 9.4,
                    'date' => $train['oje_started_at'],
                    'title' => 'OJE Materials Started',
                    'desc' => 'Employee began OJE reading materials.',
                    'icon' => 'fa-chalkboard',
                    'color' => '#8b5cf6'
                ];
            }
            if (!empty($train['oje_reading_done_at'])) {
                $events[] = [
                    'step_order' => 9.5,
                    'date' => $train['oje_reading_done_at'],
                    'title' => 'OJE Materials Completed',
                    'desc' => 'Employee completed OJE reading materials.',
                    'icon' => 'fa-chalkboard-teacher',
                    'color' => '#7c3aed'
                ];
            }
            
            if ($train['stage'] == 'certified' || !empty($train['certified_at'])) {
                $events[] = [
                    'step_order' => 10.0,
                    'date' => !empty($train['certified_at']) ? $train['certified_at'] : '',
                    'title' => 'OJE Certified',
                    'desc' => 'Employee fully OJE certified.',
                    'icon' => 'fa-medal',
                    'color' => '#10b981'
                ];
            }
        }
        
        // Fetch test attempts
        $ttq = mysqli_query($con, "SELECT type, attempt_number, percentage, passed FROM hr_oje_test_attempts WHERE employee_id=$emp_id ORDER BY id ASC");
        if ($ttq) {
            while($test = mysqli_fetch_assoc($ttq)) {
                $lbl = $test['type'] == 'training' ? 'Training Test' : 'OJE Test';
                $so = $test['type'] == 'training' ? 9.3 : 9.6;
                $status_txt = $test['passed'] ? 'Passed' : 'Failed';
                $color = $test['passed'] ? '#10b981' : '#ef4444';
                $events[] = [
                    'step_order' => $so,
                    'date' => '',
                    'title' => "{$lbl} (Attempt {$test['attempt_number']})",
                    'desc' => "Score: {$test['percentage']}%. Result: {$status_txt}.",
                    'icon' => 'fa-tasks',
                    'color' => $color
                ];
            }
        }
    }    
        
        // 7. Cross-Training (hr_oje_cross_training)
        $ctq = mysqli_query($con, "
            SELECT c.*, d.name as to_dept_name 
            FROM hr_oje_cross_training c 
            LEFT JOIN hr_departments d ON c.to_dept_id = d.id 
            WHERE c.employee_id=$emp_id 
            ORDER BY c.created_at ASC
        ");
        if ($ctq) {
            $ct_order = 11;
            while($ct = mysqli_fetch_assoc($ctq)) {
                $title = 'Cross-Training Initiated';
                $icon = 'fa-exchange-alt';
                $color = '#6366f1';
                $date = $ct['created_at'];
                $dept_name = $ct['to_dept_name'] ? $ct['to_dept_name'] : 'another department';
                $desc = "Cross-training to $dept_name.";
                
                if ($ct['status'] == 'completed') {
                    $title = 'Cross-Training Completed';
                    $icon = 'fa-check-circle';
                    $color = '#4ade80';
                    $date = $ct['updated_at'] ? $ct['updated_at'] : $ct['created_at'];
                    $desc = "Successfully completed cross-training for $dept_name.";
                } else if ($ct['status'] == 'cancelled') {
                    $title = 'Cross-Training Cancelled';
                    $icon = 'fa-ban';
                    $color = '#ef4444';
                    $date = $ct['updated_at'] ? $ct['updated_at'] : $ct['created_at'];
                    $desc = "Cross-training to $dept_name was cancelled.";
                }

                $events[] = [
                    'step_order' => $ct_order,
                    'date' => $date,
                    'title' => $title,
                    'desc' => $desc,
                    'icon' => $icon,
                    'color' => $color
                ];
                $ct_order++;
            }
        }
        
        // 8. Recertification Attempts (hr_oje_recert_attempts)
        $rq = mysqli_query($con, "
            SELECT r.*, d.name as dept_name
            FROM hr_oje_recert_attempts r
            LEFT JOIN hr_departments d ON r.department_id = d.id
            WHERE r.employee_id=$emp_id
            ORDER BY r.attempted_at ASC
        ");
        if ($rq) {
            $r_order = 20;
            while($recert = mysqli_fetch_assoc($rq)) {
                $status_text = $recert['passed'] == 1 ? 'Passed' : 'Failed';
                $color = $recert['passed'] == 1 ? '#10b981' : '#f43f5e';
                $icon = $recert['passed'] == 1 ? 'fa-award' : 'fa-times-circle';
                $dept_name = $recert['dept_name'] ? $recert['dept_name'] : 'Department';
                
                $events[] = [
                    'step_order' => $r_order,
                    'date' => $recert['attempted_at'],
                    'title' => "Recertification - {$status_text}",
                    'desc' => "{$dept_name} Recertification (Cycle {$recert['cycle_number']}, Attempt {$recert['attempt_number']}). Score: {$recert['percentage']}%.",
                    'icon' => $icon,
                    'color' => $color
                ];
                $r_order++;
            }
        }
    
    // Sort events logically by step_order, and then by date if needed
    usort($events, function($a, $b) {
        if ($a['step_order'] == $b['step_order']) {
            $timeA = !empty($a['date']) ? strtotime($a['date']) : 0;
            $timeB = !empty($b['date']) ? strtotime($b['date']) : 0;
            return $timeA - $timeB;
        }
        return ($a['step_order'] < $b['step_order']) ? -1 : 1;
    });
    
    if (empty($events)) {
        echo "<div class='alert alert-info'>No timeline events found.</div>";
        exit;
    }
    
    echo '<div class="timeline">';
    foreach ($events as $ev) {
        $dt = !empty($ev['date']) ? date('d M Y, h:i A', strtotime($ev['date'])) : '<i>Date Not Recorded</i>';
        echo "
        <div class='timeline-item' style='--dot-color: {$ev['color']}'>
            <div class='timeline-date'>{$dt}</div>
            <div class='timeline-content' style='border-left: 4px solid {$ev['color']}'>
                <div class='timeline-title'><i class='fas {$ev['icon']} mr-2' style='color: {$ev['color']}'></i>{$ev['title']}</div>
                <p class='timeline-desc'>{$ev['desc']}</p>
            </div>
        </div>";
    }
    echo '</div>';
    echo '<style>
    .timeline-item::before { background: var(--dot-color, #312e81) !important; }
    </style>';
}
?>
