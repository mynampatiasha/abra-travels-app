<?php
// =========================================================================
// HR AUTO TICKET SYSTEM
// Include this file in header.php or any page that loads for all users
// Raises weekly (every Friday) and monthly (last working day) reminders
// to ALL active employees as system-generated tickets
//
// Auto-created tables tracked via hr_auto_ticket_log
// =========================================================================

function hrRunAutoTickets($con) {

    // ── Ensure log table exists ──────────────────────────────────────────
    mysqli_query($con, "CREATE TABLE IF NOT EXISTS `hr_auto_ticket_log` (
        `id`          INT(11)      NOT NULL AUTO_INCREMENT,
        `ticket_type` VARCHAR(50)  NOT NULL COMMENT 'weekly_review | monthly_calendar | monthly_kpi | monthly_summary',
        `period_key`  VARCHAR(20)  NOT NULL COMMENT 'YYYY-WW for weekly, YYYY-MM for monthly',
        `employee_id` VARCHAR(50)  NOT NULL,
        `ticket_number` VARCHAR(50) DEFAULT NULL,
        `raised_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        UNIQUE KEY `no_dupe` (`ticket_type`, `period_key`, `employee_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
      COMMENT='Tracks auto-raised HR reminder tickets - Created " . date('d-M-Y H:i:s') . "'");

    // ── Ensure submissions table exists ──────────────────────────────────
    mysqli_query($con, "CREATE TABLE IF NOT EXISTS `hr_employee_submissions` (
        `id`            INT(11)      NOT NULL AUTO_INCREMENT,
        `employee_id`   VARCHAR(50)  NOT NULL,
        `employee_name` VARCHAR(150) NOT NULL,
        `submission_type` ENUM('weekly_report','weekly_ppt','monthly_calendar','monthly_kpi','monthly_summary') NOT NULL,
        `period_key`    VARCHAR(20)  NOT NULL COMMENT 'YYYY-WW for weekly, YYYY-MM for monthly',
        `period_label`  VARCHAR(100) NOT NULL COMMENT 'Human readable: Week 23 2025 / April 2025',
        `file_name`     VARCHAR(255) NOT NULL,
        `file_path`     VARCHAR(500) NOT NULL,
        `file_size`     INT(11)      DEFAULT 0,
        `file_ext`      VARCHAR(20)  DEFAULT NULL,
        `notes`         TEXT         DEFAULT NULL,
        `uploaded_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `updated_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_emp_period` (`employee_id`, `period_key`, `submission_type`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
      COMMENT='HR Employee File Submissions - Created " . date('d-M-Y H:i:s') . "'");

    // ── Get today's info ─────────────────────────────────────────────────
    $today     = date('Y-m-d');
    $dow       = date('N');          // 1=Mon … 7=Sun
    $week_num  = date('W');
    $year      = date('Y');
    $month     = date('m');
    $month_name= date('F');

    // ── Fetch all active employees ───────────────────────────────────────
    $emp_res = mysqli_query($con,
        "SELECT id, employee_id, name FROM hr_employees WHERE status='Active' ORDER BY name ASC");
    if (!$emp_res || mysqli_num_rows($emp_res) == 0) return;

    $employees = [];
    while ($e = mysqli_fetch_assoc($emp_res)) $employees[] = $e;

    // ── Helper: get next available ticket number ─────────────────────────
    function getNextTicketNumber($con) {
        $r = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(id) AS max_id FROM tickets"));
        $nextId = (intval($r['max_id'] ?? 0)) + 1;
        return 'TICKET' . date('Y') . str_pad($nextId, 4, '0', STR_PAD_LEFT);
    }

    // ── Helper: insert one ticket ────────────────────────────────────────
    function insertAutoTicket($con, $emp, $subject, $message, $priority, $deadline_hours) {
        $ticket_number = getNextTicketNumber($con);
        $deadline      = date('Y-m-d H:i:s', strtotime("+{$deadline_hours} hours"));
        $timeline_mins = $deadline_hours * 60;
        $sender_name   = 'System - HR Auto Reminder';
        $assigned_to   = intval($emp['id']);
        $created_by    = 0; // system

        $subj = mysqli_real_escape_string($con, $subject);
        $msg  = mysqli_real_escape_string($con, $message);
        $tn   = mysqli_real_escape_string($con, $ticket_number);
        $sn   = mysqli_real_escape_string($con, $sender_name);

        $sql = "INSERT INTO tickets
                    (ticket_number, name, subject, message, status, priority,
                     timeline, deadline, attachment, created_at, updated_at, assigned_to, created_by)
                VALUES
                    ('$tn','$sn','$subj','$msg','open','$priority',
                     $timeline_mins,'$deadline','',NOW(),NOW(),$assigned_to,$created_by)";

        mysqli_query($con, $sql);
        return $ticket_number;
    }

    // ── Helper: log to prevent duplicates ───────────────────────────────
    function logAutoTicket($con, $type, $period_key, $emp_id, $ticket_number) {
        $t  = mysqli_real_escape_string($con, $type);
        $pk = mysqli_real_escape_string($con, $period_key);
        $ei = mysqli_real_escape_string($con, $emp_id);
        $tn = mysqli_real_escape_string($con, $ticket_number);
        mysqli_query($con,
            "INSERT IGNORE INTO hr_auto_ticket_log (ticket_type, period_key, employee_id, ticket_number, raised_at)
             VALUES ('$t','$pk','$ei','$tn',NOW())");
    }

    // ── Helper: already raised? ──────────────────────────────────────────
    function alreadyRaised($con, $type, $period_key, $emp_id) {
        $t  = mysqli_real_escape_string($con, $type);
        $pk = mysqli_real_escape_string($con, $period_key);
        $ei = mysqli_real_escape_string($con, $emp_id);
        $r  = mysqli_query($con,
            "SELECT id FROM hr_auto_ticket_log WHERE ticket_type='$t' AND period_key='$pk' AND employee_id='$ei' LIMIT 1");
        return ($r && mysqli_num_rows($r) > 0);
    }

    // ====================================================================
    // WEEKLY TICKETS — Every Friday (dow=5)
    // ====================================================================
    if ($dow == 5) {
        $period_key = $year . '-W' . str_pad($week_num, 2, '0', STR_PAD_LEFT);
        // Saturday date for the review
        $saturday   = date('d M Y', strtotime('next Saturday'));

        foreach ($employees as $emp) {
            // 1. Weekly Review Reminder
            if (!alreadyRaised($con, 'weekly_review', $period_key, $emp['employee_id'])) {
                $subject = "⏰ Weekly Review Due — Complete before Saturday " . $saturday;
                $message = "Dear {$emp['name']},\n\n"
                    . "This is an automated reminder from the HR System.\n\n"
                    . "📋 ACTION REQUIRED: Weekly Review\n"
                    . "────────────────────────────────\n"
                    . "You have a Weekly Review scheduled for Saturday, $saturday.\n\n"
                    . "Please complete the following before Saturday:\n"
                    . "✅ Review your weekly tasks and progress\n"
                    . "✅ Update your Weekly Calendar on the HR portal\n"
                    . "✅ Upload your Weekly Report\n"
                    . "✅ Prepare your Weekly PPT presentation\n\n"
                    . "👉 Visit: hr-employee-calendar.php to submit your weekly report and PPT.\n\n"
                    . "Period: Week $week_num, $year\n"
                    . "────────────────────────────────\n"
                    . "[System Auto-Generated | Weekly Review | $period_key]";

                $tn = insertAutoTicket($con, $emp, $subject, $message, 'high', 24);
                logAutoTicket($con, 'weekly_review', $period_key, $emp['employee_id'], $tn);
            }

            // 2. Weekly PPT Reminder
            if (!alreadyRaised($con, 'weekly_ppt', $period_key, $emp['employee_id'])) {
                $subject = "📊 Weekly PPT Due — Submit before Saturday " . $saturday;
                $message = "Dear {$emp['name']},\n\n"
                    . "This is an automated reminder from the HR System.\n\n"
                    . "📊 ACTION REQUIRED: Weekly PPT Submission\n"
                    . "────────────────────────────────\n"
                    . "Please prepare and upload your Weekly PPT presentation for:\n"
                    . "Period: Week $week_num, $year\n\n"
                    . "Your PPT should include:\n"
                    . "✅ Summary of work done this week\n"
                    . "✅ Key achievements and milestones\n"
                    . "✅ Challenges faced and solutions\n"
                    . "✅ Plan for next week\n\n"
                    . "👉 Upload at: hr-employee-calendar.php → Weekly PPT section\n\n"
                    . "Deadline: Saturday, $saturday\n"
                    . "────────────────────────────────\n"
                    . "[System Auto-Generated | Weekly PPT | $period_key]";

                $tn = insertAutoTicket($con, $emp, $subject, $message, 'medium', 24);
                logAutoTicket($con, 'weekly_ppt', $period_key, $emp['employee_id'], $tn);
            }
        }
    }

    // ====================================================================
    // MONTHLY TICKETS — Last working day of month (check if tomorrow is
    // a new month, skip Sundays)
    // ====================================================================
    $tomorrow     = date('Y-m-d', strtotime('+1 day'));
    $this_month   = date('m');
    $next_month   = date('m', strtotime('+1 day'));
    $next_month_name = date('F', strtotime('+1 month'));
    $next_year    = date('Y', strtotime('+1 month'));

    // Is today the last working day? (tomorrow is a different month, and today is not Sunday)
    $is_last_working_day = ($next_month != $this_month && $dow != 7);

    if ($is_last_working_day) {
        $period_key   = $year . '-' . $month;
        $next_period  = date('Y-m', strtotime('+1 month'));

        foreach ($employees as $emp) {

            // 1. Monthly Calendar for UPCOMING month
            if (!alreadyRaised($con, 'monthly_calendar', $next_period, $emp['employee_id'])) {
                $subject = "📅 Complete Your Monthly Calendar — $next_month_name $next_year";
                $message = "Dear {$emp['name']},\n\n"
                    . "This is an automated reminder from the HR System.\n\n"
                    . "📅 ACTION REQUIRED: Monthly Calendar Submission\n"
                    . "────────────────────────────────\n"
                    . "The month of $month_name $year is coming to an end.\n\n"
                    . "Please complete and submit your Monthly Calendar for:\n"
                    . "➡️  $next_month_name $next_year\n\n"
                    . "Your monthly calendar should include:\n"
                    . "✅ Daily schedule and time slots for all working days\n"
                    . "✅ Planned activities for each slot\n"
                    . "✅ Leave or absence days marked\n\n"
                    . "👉 Visit: hr-employee-calendar.php to fill and submit your calendar.\n\n"
                    . "Deadline: End of $month_name $year\n"
                    . "────────────────────────────────\n"
                    . "[System Auto-Generated | Monthly Calendar | $next_period]";

                $tn = insertAutoTicket($con, $emp, $subject, $message, 'high', 48);
                logAutoTicket($con, 'monthly_calendar', $next_period, $emp['employee_id'], $tn);
            }

            // 2. Monthly KPI
            if (!alreadyRaised($con, 'monthly_kpi', $period_key, $emp['employee_id'])) {
                $subject = "📈 Submit Your Monthly KPI Report — $month_name $year";
                $message = "Dear {$emp['name']},\n\n"
                    . "This is an automated reminder from the HR System.\n\n"
                    . "📈 ACTION REQUIRED: Monthly KPI Report\n"
                    . "────────────────────────────────\n"
                    . "Please submit your Monthly KPI Report for $month_name $year.\n\n"
                    . "Your KPI report should include:\n"
                    . "✅ Key Performance Indicators achieved this month\n"
                    . "✅ Target vs Actual metrics\n"
                    . "✅ Areas of improvement\n"
                    . "✅ Goals for next month\n\n"
                    . "👉 Upload at: hr-employee-calendar.php → Monthly Reports section\n\n"
                    . "Deadline: End of today, $today\n"
                    . "────────────────────────────────\n"
                    . "[System Auto-Generated | Monthly KPI | $period_key]";

                $tn = insertAutoTicket($con, $emp, $subject, $message, 'high', 24);
                logAutoTicket($con, 'monthly_kpi', $period_key, $emp['employee_id'], $tn);
            }

            // 3. Monthly Summary
            if (!alreadyRaised($con, 'monthly_summary', $period_key, $emp['employee_id'])) {
                $subject = "📝 Submit Your Monthly Summary — $month_name $year Overview";
                $message = "Dear {$emp['name']},\n\n"
                    . "This is an automated reminder from the HR System.\n\n"
                    . "📝 ACTION REQUIRED: Monthly Summary Report\n"
                    . "────────────────────────────────\n"
                    . "Please submit your overall Monthly Summary for $month_name $year.\n\n"
                    . "Your monthly summary should include:\n"
                    . "✅ Overview of all work completed this month\n"
                    . "✅ Projects handled and their status\n"
                    . "✅ Team collaboration highlights\n"
                    . "✅ Learnings and takeaways\n"
                    . "✅ Plan & priorities for $next_month_name $next_year\n\n"
                    . "👉 Upload at: hr-employee-calendar.php → Monthly Reports section\n\n"
                    . "Deadline: End of today, $today\n"
                    . "────────────────────────────────\n"
                    . "[System Auto-Generated | Monthly Summary | $period_key]";

                $tn = insertAutoTicket($con, $emp, $subject, $message, 'medium', 24);
                logAutoTicket($con, 'monthly_summary', $period_key, $emp['employee_id'], $tn);
            }
        }
    }
}

// Run on include — wraps in try/catch to never break the main page
try {
    if (isset($con) && $con) {
        hrRunAutoTickets($con);
    } elseif (isset($dbConn) && $dbConn) {
        hrRunAutoTickets($dbConn);
    }
} catch (Exception $e) {
    error_log('HR Auto Ticket Error: ' . $e->getMessage());
}
?>
