<?php
 = [
    'hr-career.php' => 'hr-career.php',
    'hr-employee-overall-data.php' => 'hr-employee-overall-data.php',
    'hr_screening.php' => 'hr_screening (3).php',
    'hr-employee-onboarding-pending-list.php' => 'hr-employee-onboarding-pending-list.php',
    'hr-OJE.php' => 'hr-OJE (1).php',
    'hr-employee-preview-checklist.php' => 'hr-employee-preview-checklist (1).php',
    'hr-employee-OJE.php' => 'hr-employee-OJE (1).php',
    'hr-exit-initiation.php' => 'hr-exit-initiation.php',
    'hr-exit-handover.php' => 'hr-exit-handover.php',
    'hr-exit-employee-interview.php' => 'hr-exit-employee-interview.php',
    'hr-exit-settlement.php' => 'hr-exit-settlement.php',
    'hr-employees-list.php' => 'hr-employees-list (2).php',
    'hr-departments-list.php' => 'hr-departments-list.php',
    'hr-attendance-list.php' => 'hr-attendance-list (1).php',
    'hr-leave-requests.php' => 'hr-leave-requests.php',
    'hr-payroll.php' => 'hr-payroll.php',
    'hr-notices.php' => 'hr-notices.php',
    'hr-feedback.php' => 'hr-feedback.php',
    'hr-pantry.php' => 'hr-pantry.php'
];

 = <<<'EOD'
// =========================================================================
// IDENTIFY LOGGED-IN EMPLOYEE (Flutter WebView Auth)
// =========================================================================
 = isset(['user_email']) ? trim(['user_email']) :
                   (isset(['user_email']) ? trim(['user_email']) : '');
 = trim(['user_name'] ?? '');
 = null;
 = isset() ?  : (isset() ?  : null);

if ( && !empty()) {
     = mysqli_real_escape_string(, );
     = mysqli_query(, "
        SELECT id, employee_id, name, department, position 
        FROM hr_employees 
        WHERE (email = '' OR personal_email = '') 
        AND status = 'Active' 
        LIMIT 1
    ");
    if ( && mysqli_num_rows() > 0) {
         = mysqli_fetch_assoc();
        ['user_name'] = ['name'];
        ['user_id'] = ['id'];
         = ['name'];
         = ['name'];
         = ['id'];
    }
}
EOD;

 = 'D:/Fleet_Management/Fleet_Management/Fleet Management/crm/';
 = 'D:/Fleet_Management/Fleet_Management/Fleet Management/hrm/hrm/';

foreach ( as  => ) {
     =  . ;
     =  . ;
    
    if (!file_exists()) {
        echo "MISSING: \\n";
        continue;
    }
    
     = file_get_contents();
    
    // 1. Remove header.php includes
     = preg_replace("/require_once\s*\(\s*['\"]header\.php['\"]\s*\)\s*;/i", "", );
     = preg_replace("/include_once\s*\(\s*['\"]header\.php['\"]\s*\)\s*;/i", "", );
    
    // 2. Auth block
     = preg_replace("/session_start\(\);/i", "session_start();\n\n" . \, \, 1);
    
    // 3. Remove isUser();
     = preg_replace("/isUser\(\);/i", "// isUser(); // Disabled for Flutter Auth", \);
    
    // 4. Node Ticket API replacement (if INSERT INTO tickets exists)
    // Actually, we'll do ticket replacement manually or explicitly for files that need it, 
    // because each file might construct the ticket differently.
    
    file_put_contents(\, \);
    echo "UPDATED: \\n";
}
echo "DONE\n";
?>
