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

// =========================================================================
// HR ONBOARDING CHECKLIST CONFIGURATION (Department + Position scoped)
// =========================================================================

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');

// =========================================================================
// ADMIN CHECK FOR DASHBOARD BUTTON
// =========================================================================
$btn_currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';
$btn_authorized_admin_names = array('Abishek Veeraswamy', 'Abishek', 'abishek');
$btn_isAdmin = false;
foreach($btn_authorized_admin_names as $admin_name) {
    if(stripos($btn_currentUserName, $admin_name) !== false || stripos($admin_name, $btn_currentUserName) !== false) {
        $btn_isAdmin = true;
        break;
    }
}
$dashboard_url = $btn_isAdmin ? 'index.php' : 'raise-a-ticket.php';

require_once('funciones.php');
require 'requirelanguage.php';

$con = conexion();
if (!$con) {
    die("Database connection failed: " . mysqli_connect_error());
}

date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');
isUser();

$current_page = basename($_SERVER['PHP_SELF']);
$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

// =========================================================================
// ENSURE TABLES EXIST
// =========================================================================

// Headings: position_id = 0 means "Department-level" (applies to all positions in dept).
// position_id > 0 means "Position-level" (applies only to that specific position).
$check_headings = mysqli_query($con, "SHOW TABLES LIKE 'hr_checklist_headings'");
if (mysqli_num_rows($check_headings) == 0) {
    mysqli_query($con, "CREATE TABLE hr_checklist_headings (
        id INT(11) AUTO_INCREMENT PRIMARY KEY,
        department_id INT(11) NOT NULL,
        position_id INT(11) DEFAULT 0,
        heading_name VARCHAR(255) NOT NULL,
        sort_order INT(11) DEFAULT 0,
        created_by VARCHAR(255) DEFAULT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
}

$check_items = mysqli_query($con, "SHOW TABLES LIKE 'hr_checklist_items'");
if (mysqli_num_rows($check_items) == 0) {
    mysqli_query($con, "CREATE TABLE hr_checklist_items (
        id INT(11) AUTO_INCREMENT PRIMARY KEY,
        heading_id INT(11) NOT NULL,
        department_id INT(11) NOT NULL,
        position_id INT(11) DEFAULT 0,
        item_text VARCHAR(500) NOT NULL,
        description TEXT DEFAULT NULL,
        document_path VARCHAR(500) DEFAULT NULL,
        document_filename VARCHAR(255) DEFAULT NULL,
        video_path VARCHAR(500) DEFAULT NULL,
        video_filename VARCHAR(255) DEFAULT NULL,
        sort_order INT(11) DEFAULT 0,
        is_active TINYINT(1) DEFAULT 1,
        visible_to_employee TINYINT(1) DEFAULT 0,
        require_signature TINYINT(1) DEFAULT 0,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
}

// Add columns if table already existed before this update
$col_checks_cfg = [
    ["hr_checklist_items", "visible_to_employee", "ALTER TABLE hr_checklist_items ADD COLUMN visible_to_employee TINYINT(1) DEFAULT 0 AFTER is_active"],
    ["hr_checklist_items", "require_signature",   "ALTER TABLE hr_checklist_items ADD COLUMN require_signature TINYINT(1) DEFAULT 0 AFTER visible_to_employee"],
    ["hr_checklist_items", "item_type",           "ALTER TABLE hr_checklist_items ADD COLUMN item_type VARCHAR(30) DEFAULT 'tick' AFTER require_signature"],
    ["hr_checklist_items", "field_schema",        "ALTER TABLE hr_checklist_items ADD COLUMN field_schema LONGTEXT DEFAULT NULL AFTER item_type"],
    ["hr_checklist_items", "template_key",        "ALTER TABLE hr_checklist_items ADD COLUMN template_key VARCHAR(50) DEFAULT NULL AFTER field_schema"],
];
foreach ($col_checks_cfg as [$tbl, $col, $sql]) {
    $chk = mysqli_query($con, "SHOW COLUMNS FROM `$tbl` LIKE '$col'");
    if ($chk && mysqli_num_rows($chk) == 0) mysqli_query($con, $sql);
}

// Upload directory for checklist documents/videos
$upload_dir = 'uploads/hr_checklist/';
if (!is_dir($upload_dir)) {
    @mkdir($upload_dir, 0755, true);
}

// Human-readable reason for a failed file upload, so failures aren't silent
function hr_checklist_upload_error_msg($code) {
    switch ($code) {
        case UPLOAD_ERR_INI_SIZE:
        case UPLOAD_ERR_FORM_SIZE:
            return 'the file is larger than the server allows (upload_max_filesize/post_max_size limit)';
        case UPLOAD_ERR_PARTIAL:
            return 'the file was only partially uploaded — try again';
        case UPLOAD_ERR_NO_TMP_DIR:
            return 'the server is missing a temp folder for uploads';
        case UPLOAD_ERR_CANT_WRITE:
            return 'the server failed to write the file to disk';
        case UPLOAD_ERR_EXTENSION:
            return 'a server extension blocked the upload';
        default:
            return 'unknown upload error (code ' . $code . ')';
    }
}

// =========================================================================
// SEED DEFAULT SIGNATURE-REQUIRED DOCUMENTS (one-time, idempotent)
// =========================================================================
$seed_heading_check = mysqli_query($con, "SELECT id FROM hr_checklist_headings WHERE department_id=0 AND position_id=0 AND heading_name='Company Documents & Declarations' LIMIT 1");
if ($seed_heading_check) {
    if (mysqli_num_rows($seed_heading_check) == 0) {
        mysqli_query($con, "INSERT INTO hr_checklist_headings (department_id, position_id, heading_name, sort_order, created_by) VALUES (0, 0, 'Company Documents & Declarations', 999, 'system_seed')");
        $seed_heading_id = mysqli_insert_id($con);
    } else {
        $seed_heading_row = mysqli_fetch_assoc($seed_heading_check);
        $seed_heading_id = $seed_heading_row['id'];
    }

    $seed_docs = [
        [
            'key' => 'health_safety',
            'text' => 'Health and Safety Guidelines Acknowledgment',
            'fields' => [],
            'body' => "I, {{name}}, acknowledge that I have received, read, and understood the Health and Safety Guidelines of Abra Groups. I understand that these guidelines are essential to ensuring a safe, secure, and healthy work environment for all employees and that following them is a shared responsibility.\nBy signing this acknowledgment, I confirm that:\n<strong>Commitment to Safety:</strong> I am committed to following Abra Groups' health and safety protocols to prevent accidents and ensure my well-being and that of my colleagues.\n<strong>Understanding and Compliance:</strong> I agree to abide by all safety procedures, including the use of any required protective equipment and adherence to safety protocols specific to my role. I understand that compliance with these guidelines is mandatory.\n<strong>Responsibility to Report:</strong> I will immediately report any unsafe conditions, hazards, or incidents that I observe in the workplace to the appropriate personnel to help prevent accidents or health risks.\n<strong>Emergency Preparedness:</strong> I am familiar with the emergency response procedures at Abra Groups, including evacuation routes, emergency exits, and locations of safety equipment. I understand that knowing these procedures is essential to ensure readiness in case of an emergency.\n<strong>Continuous Improvement and Training:</strong> I am open to receiving additional training and updates on safety protocols as provided by Abra Groups to enhance workplace safety continuously.\n<strong>Consequences of Non-Compliance:</strong> I understand that failure to follow health and safety guidelines may result in corrective actions, up to and including termination of employment, as per Abra Groups' policies.\nBy signing below, I affirm my commitment to maintaining a safe and healthy work environment at Abra Groups."
        ],
        [
            'key' => 'tax_declaration',
            'text' => 'Acknowledgment of Completed Tax Declaration',
            'fields' => [['key'=>'fiscal_year','label'=>'Fiscal Year','type'=>'text','placeholder'=>'e.g. 2025-26']],
            'body' => "I, {{name}}, hereby confirm that I have submitted my completed tax declaration for the fiscal year {{fiscal_year}} as required by Abra Groups' policies and relevant tax regulations.\nBy signing below, I certify that:\nAll the information provided in my tax declaration is accurate and complete to the best of my knowledge.\nI have submitted all necessary documents, as requested by Abra's HR/Finance Department, to verify the details in my tax declaration.\nI understand that any misrepresentation or omission of information in my tax declaration may lead to corrective action as per company policy.\nI acknowledge that Abra Groups will process my tax information in accordance with applicable laws and company guidelines to ensure compliance and transparency."
        ],
        [
            'key' => 'nda',
            'text' => 'Non-Disclosure Agreement (NDA)',
            'fields' => [],
            'body' => "This Non-Disclosure Agreement is made and entered into by and between Abra Groups and {{name}}.\n<strong>1. Definition of Confidential Information</strong>\nFor purposes of this Agreement, \"Confidential Information\" shall include, without limitation, all data, materials, products, technology, computer programs, specifications, manuals, business plans, software, marketing plans, financial information, or other information disclosed or made available by the Disclosing Party to the Receiving Party, either directly or indirectly, in writing, orally, or by inspection of tangible objects (including without limitation documents, prototypes, samples, equipment, and facilities).\n<strong>2. Obligations of the Receiving Party</strong>\nThe Receiving Party agrees to the following obligations with respect to Confidential Information:\n<strong>Non-Disclosure:</strong> The Receiving Party shall keep all Confidential Information received from the Disclosing Party confidential and shall not disclose it to any third party without the prior written consent of the Disclosing Party.\n<strong>Limitation on Use:</strong> The Receiving Party shall use the Confidential Information solely for the purpose of performing tasks related to their engagement with Abra Groups and for no other purpose.\n<strong>Protection of Information:</strong> The Receiving Party agrees to take all reasonable measures to protect the secrecy of, and to avoid disclosure and unauthorized use of, the Confidential Information. Such measures shall include at least the same degree of care that the Receiving Party uses to protect its own confidential information of a similar nature, but in no case less than reasonable care.\n<strong>3. Exclusions from Confidential Information</strong>\nThe obligations of confidentiality do not apply to any information that:\nWas known to the Receiving Party prior to receiving it from the Disclosing Party;\nIs or becomes publicly known through no breach of this Agreement by the Receiving Party;\nIs independently developed by the Receiving Party without reference to or reliance upon the Confidential Information;\nIs lawfully obtained by the Receiving Party from a third party without restriction on use or disclosure.\n<strong>4. Term and Termination</strong>\nThe obligations of the Receiving Party under this Agreement shall commence on the Effective Date and shall continue indefinitely, or until the Confidential Information no longer qualifies as confidential under the terms outlined in this Agreement.\n<strong>5. Return of Materials</strong>\nUpon the request of the Disclosing Party or upon termination of this Agreement, the Receiving Party shall promptly return to the Disclosing Party all materials containing Confidential Information or certify in writing that all such materials have been destroyed.\n<strong>6. No License</strong>\nNothing in this Agreement grants the Receiving Party any rights in or to the Confidential Information, except the limited right to use it for the specified purposes.\n<strong>7. Remedies</strong>\nThe Receiving Party acknowledges that any breach of this Agreement may cause irreparable harm to the Disclosing Party for which monetary damages would be inadequate. The Disclosing Party shall, therefore, be entitled to seek injunctive or other equitable relief to enforce this Agreement, in addition to any other rights or remedies available under law.\n<strong>8. Miscellaneous</strong>\n<strong>Governing Law:</strong> This Agreement shall be governed by the laws of [State/Country], without regard to its conflict of laws provisions.\n<strong>Entire Agreement:</strong> This Agreement constitutes the entire understanding between the parties with respect to the subject matter hereof and supersedes all prior discussions, agreements, and understandings of any kind.\n<strong>Amendments:</strong> Any amendment or modification of this Agreement must be in writing and signed by both parties.\n<strong>Severability:</strong> If any provision of this Agreement is found to be unenforceable, it shall be deemed severable, and the remaining provisions shall continue in full force and effect."
        ],
        [
            'key' => 'policies_ack',
            'text' => 'Acknowledgment of Company Policies',
            'fields' => [],
            'body' => "I, {{name}}, acknowledge that I have received, read, and understood Abra's Code of Conduct, Anti-Harassment Policy, and IT Policy. I understand that these policies are essential to fostering a safe, respectful, and productive work environment and are vital to maintaining the integrity of our workplace.\n<strong>Code of Conduct:</strong> I acknowledge my commitment to uphold Abra's values by adhering to ethical standards, professionalism, and accountability in all interactions and responsibilities. I understand that maintaining these principles is essential to representing Abra's standards and mission.\n<strong>Anti-Harassment Policy:</strong> I acknowledge that Abra enforces a zero-tolerance approach to any form of harassment, discrimination, or bullying within the workplace. I commit to respecting the personal and professional dignity of my colleagues and understand that any violation of this policy will be taken seriously and may result in disciplinary action.\n<strong>IT Policy:</strong> I recognize the importance of securing Abra's digital resources and data. I agree to use company-provided equipment, software, and internet resources responsibly and in compliance with the company's IT guidelines. I understand that unauthorized access, misuse, or sharing of company data and resources is prohibited and may lead to disciplinary action.\nBy signing below, I affirm my understanding of these policies and my commitment to abide by them while employed with Abra. I understand that failure to adhere to these guidelines may result in corrective action, up to and including termination of employment."
        ],
        [
            'key' => 'asset_handover',
            'text' => 'Asset Handover Form',
            'fields' => [
                ['key'=>'handed_over_to','label'=>'Handed Over To (Name)','type'=>'text'],
                ['key'=>'contact_num','label'=>'Contact Number','type'=>'text'],
                ['key'=>'department_branch','label'=>'Department/Branch','type'=>'text'],
                ['key'=>'handover_date','label'=>'Handover Date','type'=>'date'],
                ['key'=>'return_date','label'=>'Return Date (if needed)','type'=>'date'],
            ],
            'table' => ['columns' => ['Serial No','Item Description','Model','Quantity','Status (Permanent/Temporary)','Remark']],
            'body' => "I hereby acknowledge the receipt of the above-mentioned asset(s) in good working order and that it will be in my possession during my service with Abra Groups. I assure that I will take good care of the asset(s) to the best possible extent. I acknowledge that the item(s) handed over are my responsibility until I return them. If the asset(s) are stolen, lost, or damaged while in my care, I will be responsible for replacing them at my own cost."
        ],
        [
            'key' => 'joining_checklist',
            'text' => 'New Employee Joining Checklist',
            'fields' => [],
            'checklist' => [
                ['section' => '1. Pre-Joining Documentation', 'items' => [
                    'Signed offer letter and employment contract',
                    'Completed joining form',
                    'Copy of ID proof (e.g., Aadhar Card, Passport, Driving License)',
                    'Copy of address proof (e.g., Utility Bill, Bank Statement)',
                    'Passport-sized photographs (2)',
                    'Proof of educational qualifications (Certificates, Marksheets)',
                    'Experience letters from previous employers (if applicable)',
                    'Bank details (Cancelled cheque or Bank statement for account verification)',
                ]],
                ['section' => '2. Company Forms and Policies', 'items' => [
                    'Signed NDA (Non-Disclosure Agreement)',
                    'Acknowledgement of company policies (Code of Conduct, Anti-Harassment, IT Policy)',
                    'Completed tax declaration form (if applicable)',
                    'Health and safety guidelines acknowledgment',
                ]],
                ['section' => '3. HR and IT Setup', 'items' => [
                    'HR orientation session scheduled',
                    'Employee ID card issued',
                    'Email account and login credentials created',
                    'Access to required software and systems provided',
                    'Assigned workspace and IT equipment (Laptop/desktop, accessories)',
                    'Set up payroll account in the HR system',
                ]],
                ['section' => '4. Department-Specific Orientation', 'items' => [
                    'Meet with the team and reporting manager',
                    'Departmental orientation and introduction to role responsibilities',
                    'Review of current projects and immediate tasks',
                    'Access to any specialized tools or resources for the role',
                ]],
                ['section' => '5. Training and Development', 'items' => [
                    'Schedule initial job-specific training (if needed)',
                    'Compliance training (data privacy, workplace ethics, etc.)',
                    "Review Abra's mission, vision, and values with HR or team lead",
                ]],
                ['section' => '6. Final Checklist for HR', 'items' => [
                    'Confirm all required documents have been received',
                    'Collect completed onboarding forms and policy acknowledgements',
                    'Schedule 30-day, 60-day, and 90-day check-ins with new employee',
                    'Provide contact information for HR support and reporting manager',
                ]],
            ],
            'body' => "I, {{name}}, confirm that the items checked above have been completed as part of my onboarding at Abra Groups, and I acknowledge my responsibility for anything still marked incomplete."
        ],
    ];

    // Previous versions these items' bodies have held (original condensed seed text, then the
    // first full-text pass without bold labels). Used below to detect rows still holding a
    // stale version so they can be self-healed to the latest wording, without ever touching a
    // row an admin has since customized via the Edit form.
    $old_seed_bodies = [
        'health_safety' => [
            "I, {{name}}, acknowledge that I have received, read, and understood the Health and Safety Guidelines of Abra Groups. I understand these guidelines are essential to ensuring a safe, secure, and healthy work environment and that following them is a shared responsibility.\n\nBy signing, I confirm my commitment to safety protocols, compliance with all procedures, responsibility to report hazards, familiarity with emergency preparedness, and openness to continuous training. I understand that failure to follow these guidelines may result in corrective action, up to and including termination of employment.",
            "I, {{name}}, acknowledge that I have received, read, and understood the Health and Safety Guidelines of Abra Groups. I understand that these guidelines are essential to ensuring a safe, secure, and healthy work environment for all employees and that following them is a shared responsibility.\n\nBy signing this acknowledgment, I confirm that:\n\nCommitment to Safety: I am committed to following Abra Groups' health and safety protocols to prevent accidents and ensure my well-being and that of my colleagues.\n\nUnderstanding and Compliance: I agree to abide by all safety procedures, including the use of any required protective equipment and adherence to safety protocols specific to my role. I understand that compliance with these guidelines is mandatory.\n\nResponsibility to Report: I will immediately report any unsafe conditions, hazards, or incidents that I observe in the workplace to the appropriate personnel to help prevent accidents or health risks.\n\nEmergency Preparedness: I am familiar with the emergency response procedures at Abra Groups, including evacuation routes, emergency exits, and locations of safety equipment. I understand that knowing these procedures is essential to ensure readiness in case of an emergency.\n\nContinuous Improvement and Training: I am open to receiving additional training and updates on safety protocols as provided by Abra Groups to enhance workplace safety continuously.\n\nConsequences of Non-Compliance: I understand that failure to follow health and safety guidelines may result in corrective actions, up to and including termination of employment, as per Abra Groups' policies.\n\nBy signing below, I affirm my commitment to maintaining a safe and healthy work environment at Abra Groups.",
        ],
        'tax_declaration' => [
            "I, {{name}}, hereby confirm that I have submitted my completed tax declaration for the fiscal year {{fiscal_year}} as required by Abra Groups' policies and relevant tax regulations. I certify that all information provided is accurate and complete, and that I have submitted all necessary supporting documents to Abra's HR/Finance Department.",
            "I, {{name}}, hereby confirm that I have submitted my completed tax declaration for the fiscal year {{fiscal_year}} as required by Abra Groups' policies and relevant tax regulations.\n\nBy signing below, I certify that:\n\nAll the information provided in my tax declaration is accurate and complete to the best of my knowledge.\n\nI have submitted all necessary documents, as requested by Abra's HR/Finance Department, to verify the details in my tax declaration.\n\nI understand that any misrepresentation or omission of information in my tax declaration may lead to corrective action as per company policy.\n\nI acknowledge that Abra Groups will process my tax information in accordance with applicable laws and company guidelines to ensure compliance and transparency.",
        ],
        'nda' => [
            "This Non-Disclosure Agreement is entered into between Abra Groups and {{name}}. I agree to keep all Confidential Information disclosed to me confidential, to use it solely for the purpose of my engagement with Abra Groups, and to take all reasonable measures to protect it from unauthorized disclosure or use, during and after my employment.",
            "This Non-Disclosure Agreement is made and entered into by and between Abra Groups and {{name}}.\n\n1. Definition of Confidential Information\nFor purposes of this Agreement, \"Confidential Information\" shall include, without limitation, all data, materials, products, technology, computer programs, specifications, manuals, business plans, software, marketing plans, financial information, or other information disclosed or made available by the Disclosing Party to the Receiving Party, either directly or indirectly, in writing, orally, or by inspection of tangible objects (including without limitation documents, prototypes, samples, equipment, and facilities).\n\n2. Obligations of the Receiving Party\nThe Receiving Party agrees to the following obligations with respect to Confidential Information:\nNon-Disclosure: The Receiving Party shall keep all Confidential Information received from the Disclosing Party confidential and shall not disclose it to any third party without the prior written consent of the Disclosing Party.\nLimitation on Use: The Receiving Party shall use the Confidential Information solely for the purpose of performing tasks related to their engagement with Abra Groups and for no other purpose.\nProtection of Information: The Receiving Party agrees to take all reasonable measures to protect the secrecy of, and to avoid disclosure and unauthorized use of, the Confidential Information. Such measures shall include at least the same degree of care that the Receiving Party uses to protect its own confidential information of a similar nature, but in no case less than reasonable care.\n\n3. Exclusions from Confidential Information\nThe obligations of confidentiality do not apply to any information that:\nWas known to the Receiving Party prior to receiving it from the Disclosing Party;\nIs or becomes publicly known through no breach of this Agreement by the Receiving Party;\nIs independently developed by the Receiving Party without reference to or reliance upon the Confidential Information;\nIs lawfully obtained by the Receiving Party from a third party without restriction on use or disclosure.\n\n4. Term and Termination\nThe obligations of the Receiving Party under this Agreement shall commence on the Effective Date and shall continue indefinitely, or until the Confidential Information no longer qualifies as confidential under the terms outlined in this Agreement.\n\n5. Return of Materials\nUpon the request of the Disclosing Party or upon termination of this Agreement, the Receiving Party shall promptly return to the Disclosing Party all materials containing Confidential Information or certify in writing that all such materials have been destroyed.\n\n6. No License\nNothing in this Agreement grants the Receiving Party any rights in or to the Confidential Information, except the limited right to use it for the specified purposes.\n\n7. Remedies\nThe Receiving Party acknowledges that any breach of this Agreement may cause irreparable harm to the Disclosing Party for which monetary damages would be inadequate. The Disclosing Party shall, therefore, be entitled to seek injunctive or other equitable relief to enforce this Agreement, in addition to any other rights or remedies available under law.\n\n8. Miscellaneous\nGoverning Law: This Agreement shall be governed by the laws of [State/Country], without regard to its conflict of laws provisions.\nEntire Agreement: This Agreement constitutes the entire understanding between the parties with respect to the subject matter hereof and supersedes all prior discussions, agreements, and understandings of any kind.\nAmendments: Any amendment or modification of this Agreement must be in writing and signed by both parties.\nSeverability: If any provision of this Agreement is found to be unenforceable, it shall be deemed severable, and the remaining provisions shall continue in full force and effect.",
        ],
        'policies_ack' => [
            "I, {{name}}, acknowledge that I have received, read, and understood Abra's Code of Conduct, Anti-Harassment Policy, and IT Policy. I commit to upholding these standards and understand that failure to adhere to them may result in corrective action, up to and including termination of employment.",
            "I, {{name}}, acknowledge that I have received, read, and understood Abra's Code of Conduct, Anti-Harassment Policy, and IT Policy. I understand that these policies are essential to fostering a safe, respectful, and productive work environment and are vital to maintaining the integrity of our workplace.\n\nCode of Conduct: I acknowledge my commitment to uphold Abra's values by adhering to ethical standards, professionalism, and accountability in all interactions and responsibilities. I understand that maintaining these principles is essential to representing Abra's standards and mission.\n\nAnti-Harassment Policy: I acknowledge that Abra enforces a zero-tolerance approach to any form of harassment, discrimination, or bullying within the workplace. I commit to respecting the personal and professional dignity of my colleagues and understand that any violation of this policy will be taken seriously and may result in disciplinary action.\n\nIT Policy: I recognize the importance of securing Abra's digital resources and data. I agree to use company-provided equipment, software, and internet resources responsibly and in compliance with the company's IT guidelines. I understand that unauthorized access, misuse, or sharing of company data and resources is prohibited and may lead to disciplinary action.\n\nBy signing below, I affirm my understanding of these policies and my commitment to abide by them while employed with Abra. I understand that failure to adhere to these guidelines may result in corrective action, up to and including termination of employment.",
        ],
    ];

    foreach ($seed_docs as $idx => $sd) {
        $tkey_e = mysqli_real_escape_string($con, $sd['key']);
        $existing = mysqli_fetch_assoc(mysqli_query($con, "SELECT id, field_schema FROM hr_checklist_items WHERE heading_id=$seed_heading_id AND template_key='$tkey_e'"));

        $schema = ['fields' => $sd['fields'], 'body' => $sd['body']];
        if (isset($sd['table'])) $schema['table'] = $sd['table'];
        if (isset($sd['checklist'])) $schema['checklist'] = $sd['checklist'];
        $schema_json = mysqli_real_escape_string($con, json_encode($schema));

        if (!$existing) {
            $item_text_e = mysqli_real_escape_string($con, $sd['text']);
            mysqli_query($con, "INSERT INTO hr_checklist_items (heading_id, department_id, position_id, item_text, description, sort_order, visible_to_employee, require_signature, item_type, field_schema, template_key) VALUES ($seed_heading_id, 0, 0, '$item_text_e', '', $idx, 1, 1, 'fillable_signature', '$schema_json', '$tkey_e')");
        } else {
            // Self-heal once: only overwrite if the row still holds one of the known stale
            // versions, so any later manual edit via the dashboard is left alone.
            $old_bodies_v = $old_seed_bodies[$sd['key']] ?? [];
            $current_schema = json_decode($existing['field_schema'] ?? '', true);
            if (isset($current_schema['body']) && in_array($current_schema['body'], $old_bodies_v, true)) {
                mysqli_query($con, "UPDATE hr_checklist_items SET field_schema='$schema_json' WHERE id=" . intval($existing['id']));
            }
        }
    }
}

// =========================================================================
// PREVIEW A FILLABLE DOCUMENT TEMPLATE (blank sample — no real employee data)
// =========================================================================
if (isset($_GET['preview_item'])) {
    $item_row_id = intval($_GET['preview_item']);
    $item = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_checklist_items WHERE id=$item_row_id LIMIT 1"));
    if (!$item) { die("<div style='padding:50px;text-align:center;font-family:sans-serif;'><h3>Item not found.</h3></div>"); }

    $schema_v = !empty($item['field_schema']) ? json_decode($item['field_schema'], true) : ['fields'=>[], 'body'=>''];
    $sample_name = 'Sample Employee';
    $body_txt_v = str_replace('{{name}}', htmlspecialchars($sample_name), $schema_v['body'] ?? '');
    foreach (($schema_v['fields'] ?? []) as $sf) {
        $body_txt_v = str_replace('{{' . $sf['key'] . '}}', '_______________________', $body_txt_v);
    }
    ?>
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8"/>
    <title>Preview — <?php echo htmlspecialchars($item['item_text']); ?></title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
    <style>
    body { font-family: Arial, sans-serif; background: #f0f4f8; padding: 20px; color: #000; }
    .pdf-preview { width: 210mm; min-height: 297mm; margin: 0 auto; background: #fff; box-shadow: 0 4px 15px rgba(0,0,0,0.2); box-sizing: border-box; display: flex; flex-direction: column; }
    .pdf-content-wrapper { padding: 0 20mm; flex: 1 0 auto; }
    .pdf-preview table { flex: 1 0 auto; display: flex; flex-direction: column; }
    .pdf-preview table tbody { flex: 1 0 auto; display: block; }
    .letter-wave-bottom { margin-top: auto !important; }
    table { width: 100%; border-collapse: collapse; }
    .letter-wave-top{width:100%;line-height:0;display:block;margin:0;padding:0;}
    .letter-wave-top svg{width:100%;height:70px;display:block;}
    .letter-wave-bottom{width:100%;line-height:0;display:block;margin-top:40px;}
    .letter-wave-bottom svg{width:100%;height:80px;display:block;}
    .letter-header{display:flex;justify-content:space-between;align-items:center;padding:10px 40px 15px 40px;border-bottom:3px solid #3b5998;background:#fff;}
    .letter-header-left{font-size:19px;color:#0f2557;line-height:1.6;font-weight:800;margin-top:0;margin-left:30px;}
    .letter-header-left span{display:flex;align-items:center;gap:10px;}
    .letter-header-left i{width:26px;text-align:center;font-size:26px;}
    .letter-header-right{text-align:right;}
    .letter-header-right img{max-height:140px;max-width:270px;object-fit:contain;display:block;margin-left:auto;}
    .print-only-spacer, .print-only-spacer-foot { display: none; }
    .doc-title { font-size:16px; font-weight:800; text-align:center; text-decoration:underline; margin:25px 0; color:#0f2557; }
    .doc-field { margin-bottom:14px; }
    .doc-field label { font-weight:700; font-size:13px; display:block; margin-bottom:4px; color:#334155; }
    .doc-field .val { border-bottom:1px solid #94a3b8; padding:6px 4px; font-size:14px; min-height:18px; color:#94a3b8; }
    table.asset-tbl { width:100%; border-collapse:collapse; margin:20px 0; font-size:13px; table-layout:fixed; }
    table.asset-tbl th, table.asset-tbl td { border:1px solid #cbd5e1; padding:10px 12px; text-align:left; vertical-align:middle; word-wrap:break-word; }
    table.asset-tbl th { background:#0f2557; color:#fff; font-weight:700; font-size:12px; text-transform:uppercase; letter-spacing:0.3px; }
    .checklist-section { font-weight:800; color:#0f2557; font-size:13px; margin:16px 0 8px; }
    .checklist-item { font-size:13px; color:#334155; margin-bottom:6px; padding-left:24px; position:relative; }
    .checklist-item .box { position:absolute; left:0; top:1px; width:15px; height:15px; border:2px solid #94a3b8; border-radius:3px; display:inline-block; }
    .doc-body { font-size:14px; line-height:1.8; color:#1a202c; margin:20px 0; white-space:pre-wrap; }
    .sig-area { margin-top:40px; display:flex; justify-content:space-between; }
    .sig-box { width:260px; }
    .sig-line { border-top:1px solid #334155; margin-top:80px; padding-top:6px; font-size:12px; font-weight:700; }
    .no-print { text-align:center; margin-bottom:20px; }
    .preview-banner { max-width:800px; margin:0 auto 16px; background:#fff7ed; border:1px solid #fcd34d; border-radius:10px; padding:12px 18px; font-size:13px; color:#92400e; font-weight:600; text-align:center; }
    </style>
    </head>
    <body>
    <div class="no-print" style="text-align:center; margin-bottom:20px;">
       <button onclick="window.print()" style="padding:14px 28px; background:#0f2557; color:#fff; border:none; border-radius:10px; font-weight:bold; cursor:pointer;">🖨️ Print</button>
    </div>
    <div class="preview-banner">⚠️ Template Preview — shows sample placeholder data. Real employee name, filled fields, and signature will appear once an employee completes this document.</div>
    <div class="pdf-preview">
        <div class="letter-wave-top">
            <svg viewBox="0 0 1440 100" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M0,0 L1440,0 L1440,30 C900,30 400,100 0,90 Z" fill="#42598a"/>
                <path d="M0,0 L1440,0 L1440,10 C1000,40 500,80 0,60 Z" fill="#0f2557"/>
            </svg>
        </div>
        <div class="letter-header">
            <div class="letter-header-left"><span><i class="fas fa-phone-alt"></i> [Company Phone]</span></div>
            <div class="letter-header-right"></div>
        </div>
        <table style="width:100%; border-collapse:collapse; border:none;">
        <tbody><tr><td style="padding: 0; border:none;">
        <div class="pdf-content-wrapper">
            <div class="doc-title"><?php echo htmlspecialchars($item['item_text']); ?></div>

            <?php foreach (($schema_v['fields'] ?? []) as $sf): ?>
            <div class="doc-field">
                <label><?php echo htmlspecialchars($sf['label']); ?></label>
                <div class="val">_______________________</div>
            </div>
            <?php endforeach; ?>

            <?php if (!empty($schema_v['table'])): ?>
            <table class="asset-tbl">
                <thead><tr><?php foreach ($schema_v['table']['columns'] as $col): ?><th><?php echo htmlspecialchars($col); ?></th><?php endforeach; ?></tr></thead>
                <tbody><tr><?php echo str_repeat('<td>&nbsp;</td>', count($schema_v['table']['columns'])); ?></tr></tbody>
            </table>
            <?php endif; ?>

            <?php if (!empty($schema_v['checklist'])): ?>
                <?php foreach ($schema_v['checklist'] as $section): ?>
                    <div class="checklist-section"><?php echo htmlspecialchars($section['section']); ?></div>
                    <?php foreach ($section['items'] as $ci): ?>
                        <div class="checklist-item"><span class="box"></span><?php echo htmlspecialchars($ci); ?></div>
                    <?php endforeach; ?>
                <?php endforeach; ?>
            <?php endif; ?>

            <div class="doc-body"><?php echo nl2br($body_txt_v); ?></div>

            <div class="sig-area">
                <div class="sig-box"><div class="sig-line">For [Company Name]<br>Authorized Signatory</div></div>
                <div class="sig-box"><div class="sig-line">Signature: [Employee Name]<br>Date: _______________________</div></div>
            </div>
        </div>
        </td></tr></tbody>
        </table>
        <div class="letter-wave-bottom">
            <svg viewBox="0 0 1440 120" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M0,120 L1440,120 L1440,30 C1000,110 500,120 0,80 Z" fill="#42598a"/>
                <path d="M0,120 L1440,120 L1440,60 C900,130 400,90 0,110 Z" fill="#0f2557"/>
            </svg>
        </div>
    </div>
    </body>
    </html>
    <?php
    exit;
}

// =========================================================================
// EXPORT SELECTED CHECKLIST ITEMS (CSV / Excel) — template structure only
// =========================================================================
if (isset($_GET['export']) && in_array($_GET['export'], ['csv', 'excel'])) {
    $selected_ids = isset($_GET['ids']) ? array_filter(array_map('intval', explode(',', $_GET['ids']))) : [];
    if (empty($selected_ids)) {
        die("No items selected for export.");
    }

    $ids_sql = implode(',', $selected_ids);
    $items_res = mysqli_query($con, "
        SELECT i.*, h.heading_name
        FROM hr_checklist_items i
        JOIN hr_checklist_headings h ON h.id = i.heading_id
        WHERE i.id IN ($ids_sql)
        ORDER BY h.sort_order ASC, i.sort_order ASC
    ");

    $ext  = $_GET['export'] === 'excel' ? 'xls' : 'csv';
    $mime = $_GET['export'] === 'excel' ? 'application/vnd.ms-excel' : 'text/csv';
    header("Content-Type: $mime; charset=utf-8");
    header('Content-Disposition: attachment; filename=checklist_template_export_' . date('Y-m-d_His') . '.' . $ext);

    $out = fopen('php://output', 'w');
    fprintf($out, chr(0xEF).chr(0xBB).chr(0xBF));

    fputcsv($out, ['Heading', 'Item Text', 'Description', 'Document Attachment', 'Video Attachment', 'Visible to Employee', 'Signature Required', 'Active']);

    while ($it = mysqli_fetch_assoc($items_res)) {
        fputcsv($out, [
            $it['heading_name'],
            $it['item_text'],
            $it['description'] ?: '',
            $it['document_filename'] ?: '',
            $it['video_filename'] ?: '',
            $it['visible_to_employee'] ? 'Yes' : 'No',
            $it['require_signature'] ? 'Yes' : 'No',
            $it['is_active'] ? 'Yes' : 'No'
        ]);
    }
    fclose($out);
    exit;
}

// =========================================================================
// FORM SUBMISSIONS
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] == 'POST') {

    // --- ADD HEADING ---
    if (isset($_POST['action']) && $_POST['action'] == 'add_heading') {
        $heading  = mysqli_real_escape_string($con, trim($_POST['heading_name']));

        if (!empty($heading)) {
            $max_sort = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(sort_order) as m FROM hr_checklist_headings WHERE department_id=0 AND position_id=0"));
            $next_sort = ($max_sort && $max_sort['m'] !== null) ? intval($max_sort['m']) + 1 : 0;
            mysqli_query($con, "INSERT INTO hr_checklist_headings (department_id, position_id, heading_name, sort_order, created_by) VALUES (0, 0, '$heading', $next_sort, '$currentUserName')");
            $_SESSION['success_message'] = "Heading added successfully.";
        } else {
            $_SESSION['error_message'] = "Please enter a Heading name.";
        }
        header("Location: $current_page");
        exit;
    }

    // --- EDIT HEADING ---
    if (isset($_POST['action']) && $_POST['action'] == 'edit_heading') {
        $id      = intval($_POST['id']);
        $heading = mysqli_real_escape_string($con, trim($_POST['heading_name']));
        if ($id > 0 && !empty($heading)) {
            $old_name_res = mysqli_fetch_assoc(mysqli_query($con, "SELECT heading_name FROM hr_checklist_headings WHERE id=$id"));
            if ($old_name_res) {
                $old_name = mysqli_real_escape_string($con, $old_name_res['heading_name']);
                mysqli_query($con, "UPDATE hr_checklist_run_items SET heading_name='$heading' WHERE heading_name='$old_name'");
            }
            mysqli_query($con, "UPDATE hr_checklist_headings SET heading_name='$heading' WHERE id=$id");
            $_SESSION['success_message'] = "Heading updated successfully.";
        }
        header("Location: " . $_SERVER['HTTP_REFERER']);
        exit;
    }

    // --- DELETE HEADING (cascade items) ---
    if (isset($_POST['action']) && $_POST['action'] == 'delete_heading') {
        $id = intval($_POST['id']);
        // Clean up uploaded files belonging to items under this heading first
        $items_res = mysqli_query($con, "SELECT id, document_path, video_path FROM hr_checklist_items WHERE heading_id=$id");
        while ($it = mysqli_fetch_assoc($items_res)) {
            if (!empty($it['document_path']) && file_exists($it['document_path'])) @unlink($it['document_path']);
            if (!empty($it['video_path']) && file_exists($it['video_path'])) @unlink($it['video_path']);
            
            // Cascade delete to existing runs
            $it_id = $it['id'];
            mysqli_query($con, "DELETE FROM hr_checklist_run_items WHERE item_id=$it_id");
        }
        mysqli_query($con, "DELETE FROM hr_checklist_items WHERE heading_id=$id");
        mysqli_query($con, "DELETE FROM hr_checklist_headings WHERE id=$id");
        $_SESSION['success_message'] = "Heading and its items deleted successfully.";
        header("Location: " . $_SERVER['HTTP_REFERER']);
        exit;
    }

    // Auto-sync missing items into existing runs (fixes items that failed to cascade)
    mysqli_query($con, "
        INSERT INTO hr_checklist_run_items (run_id, heading_name, heading_sort, scope_level, item_id, item_text, description, document_path, document_filename, video_path, video_filename, item_sort, visible_to_employee, require_signature)
        SELECT 
            r.id, h.heading_name, h.sort_order, 'global', i.id, i.item_text, i.description, i.document_path, i.document_filename, i.video_path, i.video_filename, i.sort_order, i.visible_to_employee, i.require_signature
        FROM hr_checklist_items i
        JOIN hr_checklist_headings h ON i.heading_id = h.id
        JOIN hr_checklist_runs r
        LEFT JOIN hr_checklist_run_items ri ON ri.run_id = r.id AND ri.item_id = i.id
        WHERE ri.id IS NULL
    ");

    // --- ADD ITEM (with optional document / video upload) ---
    if (isset($_POST['action']) && $_POST['action'] == 'add_item') {
        $heading_id  = intval($_POST['heading_id']);
        $item_text   = mysqli_real_escape_string($con, trim($_POST['item_text']));
        $description = mysqli_real_escape_string($con, trim($_POST['description'] ?? ''));

        $doc_path = ''; $doc_fname = '';
        $vid_path = ''; $vid_fname = '';
        $upload_warning = '';

        if (isset($_FILES['document_file']) && $_FILES['document_file']['error'] !== UPLOAD_ERR_NO_FILE) {
            $df = $_FILES['document_file'];
            if ($df['error'] === UPLOAD_ERR_OK) {
                $dext = strtolower(pathinfo($df['name'], PATHINFO_EXTENSION));
                $allowed_docs = ['pdf','doc','docx','ppt','pptx','xls','xlsx','txt'];
                if (in_array($dext, $allowed_docs)) {
                    $dpath = $upload_dir . 'doc_' . time() . '_' . rand(1000,9999) . '.' . $dext;
                    if (move_uploaded_file($df['tmp_name'], $dpath)) {
                        $doc_path = $dpath;
                        $doc_fname = $df['name'];
                    } else {
                        $upload_warning .= "Document upload failed: the server could not save the file (check uploads/hr_checklist/ folder permissions). ";
                    }
                } else {
                    $upload_warning .= "Document upload failed: \".$dext\" is not an allowed document type. ";
                }
            } else {
                $upload_warning .= "Document upload failed: " . hr_checklist_upload_error_msg($df['error']) . ". ";
            }
        }

        if (isset($_FILES['video_file']) && $_FILES['video_file']['error'] !== UPLOAD_ERR_NO_FILE) {
            $vf = $_FILES['video_file'];
            if ($vf['error'] === UPLOAD_ERR_OK) {
                $vext = strtolower(pathinfo($vf['name'], PATHINFO_EXTENSION));
                $allowed_vids = ['mp4','mov','avi','wmv','webm','mkv'];
                if (in_array($vext, $allowed_vids)) {
                    $vpath = $upload_dir . 'vid_' . time() . '_' . rand(1000,9999) . '.' . $vext;
                    if (move_uploaded_file($vf['tmp_name'], $vpath)) {
                        $vid_path = $vpath;
                        $vid_fname = $vf['name'];
                    } else {
                        $upload_warning .= "Video upload failed: the server could not save the file (check uploads/hr_checklist/ folder permissions). ";
                    }
                } else {
                    $upload_warning .= "Video upload failed: \".$vext\" is not an allowed video type. ";
                }
            } else {
                $upload_warning .= "Video upload failed: " . hr_checklist_upload_error_msg($vf['error']) . ". ";
            }
        }

        if ($heading_id > 0 && !empty($item_text)) {
            $max_sort = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(sort_order) as m FROM hr_checklist_items WHERE heading_id=$heading_id"));
            $next_sort = ($max_sort && $max_sort['m'] !== null) ? intval($max_sort['m']) + 1 : 0;
            $doc_path_sql  = $doc_path ? "'" . mysqli_real_escape_string($con, $doc_path) . "'" : "NULL";
            $doc_fname_sql = $doc_fname ? "'" . mysqli_real_escape_string($con, $doc_fname) . "'" : "NULL";
            $vid_path_sql  = $vid_path ? "'" . mysqli_real_escape_string($con, $vid_path) . "'" : "NULL";
            $vid_fname_sql = $vid_fname ? "'" . mysqli_real_escape_string($con, $vid_fname) . "'" : "NULL";

            $vis_emp_val = isset($_POST['visible_to_employee']) ? 1 : 0;
            $req_sig_val = (isset($_POST['require_signature']) && $vis_emp_val) ? 1 : 0;
            mysqli_query($con, "INSERT INTO hr_checklist_items (heading_id, department_id, position_id, item_text, description, document_path, document_filename, video_path, video_filename, sort_order, visible_to_employee, require_signature) VALUES ($heading_id, 0, 0, '$item_text', '$description', $doc_path_sql, $doc_fname_sql, $vid_path_sql, $vid_fname_sql, $next_sort, $vis_emp_val, $req_sig_val)");
            
            $new_item_id = mysqli_insert_id($con);
            
            // Cascade to existing runs so employees instantly see the new item
            $run_q = mysqli_query($con, "SELECT r.id, h.heading_name, h.sort_order as h_sort FROM hr_checklist_runs r JOIN hr_checklist_headings h ON h.id=$heading_id");
            if ($run_q) {
                while ($rq = mysqli_fetch_assoc($run_q)) {
                    $r_id = $rq['id'];
                    $hname = mysqli_real_escape_string($con, $rq['heading_name']);
                    $hsort = intval($rq['h_sort']);
                    mysqli_query($con, "INSERT INTO hr_checklist_run_items (run_id, heading_name, heading_sort, scope_level, item_id, item_text, description, document_path, document_filename, video_path, video_filename, item_sort, visible_to_employee, require_signature) VALUES ($r_id, '$hname', $hsort, 'global', $new_item_id, '" . mysqli_real_escape_string($con, $item_text) . "', '" . mysqli_real_escape_string($con, $description) . "', $doc_path_sql, $doc_fname_sql, $vid_path_sql, $vid_fname_sql, $next_sort, $vis_emp_val, $req_sig_val)");
                }
            }

            $_SESSION['success_message'] = "Checklist item added successfully.";
            if (!empty($upload_warning)) {
                $_SESSION['error_message'] = trim($upload_warning);
            }
        } else {
            $_SESSION['error_message'] = "Please enter item text.";
        }
        header("Location: " . $_SERVER['HTTP_REFERER']);
        exit;
    }

    // --- EDIT ITEM ---
    if (isset($_POST['action']) && $_POST['action'] == 'edit_item') {
        $id          = intval($_POST['id']);
        $item_text   = mysqli_real_escape_string($con, trim($_POST['item_text']));
        $description = mysqli_real_escape_string($con, trim($_POST['description'] ?? ''));

        $set_extra = '';
        $upload_warning = '';

        if (isset($_FILES['document_file']) && $_FILES['document_file']['error'] !== UPLOAD_ERR_NO_FILE) {
            $df = $_FILES['document_file'];
            if ($df['error'] === UPLOAD_ERR_OK) {
                $dext = strtolower(pathinfo($df['name'], PATHINFO_EXTENSION));
                $allowed_docs = ['pdf','doc','docx','ppt','pptx','xls','xlsx','txt'];
                if (in_array($dext, $allowed_docs)) {
                    $dpath = $upload_dir . 'doc_' . time() . '_' . rand(1000,9999) . '.' . $dext;
                    if (move_uploaded_file($df['tmp_name'], $dpath)) {
                        // Remove old document only after the new one is safely saved
                        $old = mysqli_fetch_assoc(mysqli_query($con, "SELECT document_path FROM hr_checklist_items WHERE id=$id"));
                        if ($old && !empty($old['document_path']) && file_exists($old['document_path'])) @unlink($old['document_path']);
                        $set_extra .= ", document_path='" . mysqli_real_escape_string($con, $dpath) . "', document_filename='" . mysqli_real_escape_string($con, $df['name']) . "'";
                    } else {
                        $upload_warning .= "Document upload failed: the server could not save the file (check uploads/hr_checklist/ folder permissions). ";
                    }
                } else {
                    $upload_warning .= "Document upload failed: \".$dext\" is not an allowed document type. ";
                }
            } else {
                $upload_warning .= "Document upload failed: " . hr_checklist_upload_error_msg($df['error']) . ". ";
            }
        }

        if (isset($_FILES['video_file']) && $_FILES['video_file']['error'] !== UPLOAD_ERR_NO_FILE) {
            $vf = $_FILES['video_file'];
            if ($vf['error'] === UPLOAD_ERR_OK) {
                $vext = strtolower(pathinfo($vf['name'], PATHINFO_EXTENSION));
                $allowed_vids = ['mp4','mov','avi','wmv','webm','mkv'];
                if (in_array($vext, $allowed_vids)) {
                    $vpath = $upload_dir . 'vid_' . time() . '_' . rand(1000,9999) . '.' . $vext;
                    if (move_uploaded_file($vf['tmp_name'], $vpath)) {
                        $old = mysqli_fetch_assoc(mysqli_query($con, "SELECT video_path FROM hr_checklist_items WHERE id=$id"));
                        if ($old && !empty($old['video_path']) && file_exists($old['video_path'])) @unlink($old['video_path']);
                        $set_extra .= ", video_path='" . mysqli_real_escape_string($con, $vpath) . "', video_filename='" . mysqli_real_escape_string($con, $vf['name']) . "'";
                    } else {
                        $upload_warning .= "Video upload failed: the server could not save the file (check uploads/hr_checklist/ folder permissions). ";
                    }
                } else {
                    $upload_warning .= "Video upload failed: \".$vext\" is not an allowed video type. ";
                }
            } else {
                $upload_warning .= "Video upload failed: " . hr_checklist_upload_error_msg($vf['error']) . ". ";
            }
        }

        $vis_emp_val = isset($_POST['visible_to_employee']) ? 1 : 0;
        $req_sig_val = (isset($_POST['require_signature']) && $vis_emp_val) ? 1 : 0;
        if ($id > 0 && !empty($item_text)) {
            mysqli_query($con, "UPDATE hr_checklist_items SET item_text='$item_text', description='$description', visible_to_employee=$vis_emp_val, require_signature=$req_sig_val$set_extra WHERE id=$id");

            // Cascade changes to existing run items so employees instantly see visibility/text updates
            mysqli_query($con, "UPDATE hr_checklist_run_items SET item_text='$item_text', description='$description', visible_to_employee=$vis_emp_val, require_signature=$req_sig_val$set_extra WHERE item_id=$id");

            $_SESSION['success_message'] = "Checklist item updated successfully.";
            if (!empty($upload_warning)) {
                $_SESSION['error_message'] = trim($upload_warning);
            }
        }
        header("Location: " . $_SERVER['HTTP_REFERER']);
        exit;
    }

    // --- REMOVE DOCUMENT / VIDEO FROM ITEM ---
    if (isset($_POST['action']) && $_POST['action'] == 'remove_attachment') {
        $id   = intval($_POST['id']);
        $type = $_POST['attachment_type'] == 'video' ? 'video' : 'document';
        $row = mysqli_fetch_assoc(mysqli_query($con, "SELECT document_path, video_path FROM hr_checklist_items WHERE id=$id"));
        if ($row) {
            $path_col = $type . '_path';
            $fname_col = $type . '_filename';
            if (!empty($row[$path_col]) && file_exists($row[$path_col])) @unlink($row[$path_col]);
            mysqli_query($con, "UPDATE hr_checklist_items SET $path_col=NULL, $fname_col=NULL WHERE id=$id");
        }
        header("Location: " . $_SERVER['HTTP_REFERER']);
        exit;
    }

    // --- DELETE ITEM ---
    if (isset($_POST['action']) && $_POST['action'] == 'delete_item') {
        $id = intval($_POST['id']);
        $row = mysqli_fetch_assoc(mysqli_query($con, "SELECT document_path, video_path FROM hr_checklist_items WHERE id=$id"));
        if ($row) {
            if (!empty($row['document_path']) && file_exists($row['document_path'])) @unlink($row['document_path']);
            if (!empty($row['video_path']) && file_exists($row['video_path'])) @unlink($row['video_path']);
        }
        mysqli_query($con, "DELETE FROM hr_checklist_items WHERE id=$id");
        mysqli_query($con, "DELETE FROM hr_checklist_run_items WHERE item_id=$id");
        $_SESSION['success_message'] = "Checklist item deleted successfully.";
        header("Location: " . $_SERVER['HTTP_REFERER']);
        exit;
    }
}

// =========================================================================
// PAGE DATA
// =========================================================================

// Fetch all global headings and items
function fetch_global_headings($con) {
    $out = [];
    $h_res = mysqli_query($con, "SELECT * FROM hr_checklist_headings ORDER BY sort_order ASC, id ASC");
    while ($h = mysqli_fetch_assoc($h_res)) {
        $h['items'] = [];
        $i_res = mysqli_query($con, "SELECT * FROM hr_checklist_items WHERE heading_id=" . $h['id'] . " ORDER BY sort_order ASC, id ASC");
        while ($i = mysqli_fetch_assoc($i_res)) $h['items'][] = $i;
        $out[] = $h;
    }
    return $out;
}

$global_headings = fetch_global_headings($con);

?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title><?php echo isset($_SESSION['ge_cname']) ? $_SESSION['ge_cname'] : 'Abra'; ?> | Onboarding Checklist Configuration</title>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />

  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700&display=swap" rel="stylesheet">

  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Poppins', sans-serif; background: #f0f4f8; min-height: 100vh; padding: 20px 0; }
    .container-fluid { max-width: 1400px; margin: 0 auto; padding: 0 20px; }

    .page-header {
      background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%);
      padding: 20px 30px; border-radius: 10px; box-shadow: 0 4px 15px rgba(30, 58, 138, 0.3);
      margin-bottom: 20px; display: flex; justify-content: space-between; align-items: center;
    }
    .page-header h1 { color: white; font-weight: 600; margin: 0; font-size: 1.8rem; }

    .action-bar {
      background: white; padding: 20px; border-radius: 10px;
      box-shadow: 0 2px 10px rgba(0,0,0,0.08); margin-bottom: 20px;
      display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 12px;
    }
    .btn-action {
      border: none; padding: 10px 20px; border-radius: 8px; font-weight: 600;
      color: white; background: #10b981; cursor: pointer;
    }
    .card-box { background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.08); margin-bottom: 20px; }

    .scope-section-title {
      font-weight: 700; color: #1e3a8a; font-size: 1.05rem; margin-bottom: 14px;
      display: flex; align-items: center; gap: 8px; padding-bottom: 10px; border-bottom: 2px solid #eef2ff;
    }
    .scope-badge { font-size: 11px; font-weight: 800; padding: 3px 10px; border-radius: 20px; text-transform: uppercase; }
    .scope-badge.dept { background: #dbeafe; color: #1e40af; }
    .scope-badge.pos { background: #ede9fe; color: #5b21b6; }

    .heading-block {
      border: 1px solid #e0e7ff; border-radius: 10px; margin-bottom: 16px; overflow: hidden;
    }
    .heading-block-head {
      background: #f8faff; padding: 14px 18px; display: flex; justify-content: space-between; align-items: center;
      border-bottom: 1px solid #e0e7ff;
    }
    .heading-block-head h6 { margin: 0; font-weight: 800; color: #0f2557; font-size: 14px; }
    .heading-block-body { padding: 14px 18px; }

    .checklist-item-row {
      display: flex; justify-content: space-between; align-items: flex-start; gap: 12px;
      padding: 12px 14px; background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; margin-bottom: 10px;
    }
    .item-text { font-weight: 700; color: #0f2557; font-size: 13.5px; margin-bottom: 4px; }
    .item-desc { font-size: 12px; color: #64748b; margin-bottom: 6px; }
    .attach-pill {
      display: inline-flex; align-items: center; gap: 5px; font-size: 11px; font-weight: 700;
      padding: 4px 10px; border-radius: 14px; margin-right: 6px; text-decoration: none;
    }
    .attach-pill.doc { background: #ede9fe; color: #5b21b6; }
    .attach-pill.vid { background: #fef9c3; color: #713f12; }
    .attach-pill.none { background: #f1f5f9; color: #94a3b8; }

    .empty-hint { text-align: center; padding: 40px; color: #94a3b8; }

    /* Navigation Tabs */
    .nav-tabs-container { display: flex; gap: 10px; margin-bottom: 24px; }
    .nav-btn {
        padding: 12px 25px; background: white; border-radius: 12px; color: #64748b;
        font-weight: 600; text-decoration: none; box-shadow: 0 2px 5px rgba(0,0,0,0.05); 
        display: flex; align-items: center; gap: 8px; border: 2px solid transparent;
    }
    .nav-btn:hover { text-decoration: none; color: #1e3a8a; }
    .nav-btn.active { background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); color: white; }
  </style>
</head>
<body>

<div class="container-fluid">

    <?php if(isset($_SESSION['success_message'])): ?>
        <div class="alert alert-success alert-dismissible fade show">
            <i class="fas fa-check-circle mr-2"></i> <?php echo $_SESSION['success_message']; ?>
            <button type="button" class="close" data-dismiss="alert">&times;</button>
        </div>
        <?php unset($_SESSION['success_message']); ?>
    <?php endif; ?>
    <?php if(isset($_SESSION['error_message'])): ?>
        <div class="alert alert-danger alert-dismissible fade show">
            <i class="fas fa-exclamation-circle mr-2"></i> <?php echo $_SESSION['error_message']; ?>
            <button type="button" class="close" data-dismiss="alert">&times;</button>
        </div>
        <?php unset($_SESSION['error_message']); ?>
    <?php endif; ?>

    <div class="page-header">
        <h1><i class="fas fa-clipboard-check mr-2"></i> Onboarding Checklist Configuration</h1>
        <?php
        $is_admin = isset($_SESSION['user_name']) && in_array(trim($_SESSION['user_name']), ['Abishek Veeraswamy', 'Abishek', 'abishek']);
        $dashboard_url_header = $is_admin ? 'index.php' : 'raise-a-ticket.php';
        ?>
        
    </div>

    <!-- NAVIGATION TABS -->
    <div class="nav-tabs-container">
        <a href="hr-employee-onboarding-pending-list.php" class="nav-btn">
            <i class="fas fa-user-plus"></i> Onboarding
        </a>
        <a href="hr-checklist-employee.php" class="nav-btn active">
            <i class="fas fa-tasks"></i> Internal Checklist
        </a>
        <a href="hr-checklist.php" class="nav-btn">
            <i class="fas fa-clipboard-check"></i> Employee Checklist
        </a>
    </div>

    <div class="action-bar">



        <div>
            <!-- Filters removed for Global Checklist -->
        </div>
        <div>
            <button class="btn-action" data-toggle="modal" data-target="#addHeadingModal"><i class="fas fa-plus"></i> Add Checklist Heading</button>
        </div>
    </div>

    <div class="card-box">
        <div class="scope-section-title">
            <span class="scope-badge dept"><i class="fas fa-globe mr-1"></i> Global Checklist</span>
            Applies universally to ALL new employees during onboarding.
        </div>
        
        <?php if (empty($global_headings)): ?>
            <div class="empty-hint">
                <i class="fas fa-list-ul fa-3x mb-3"></i>
                <h5>No checklists found.</h5>
                <p>Click "Add Checklist Heading" above to create your first global checklist.</p>
            </div>
        <?php else: ?>
            <?php foreach ($global_headings as $h): ?>
                <div class="heading-block">
                    <div class="heading-block-head">
                        <h6><i class="fas fa-layer-group mr-2" style="color:#1e3a8a;"></i><?php echo htmlspecialchars($h['heading_name']); ?></h6>
                        <div>
                            <button class="btn btn-sm btn-warning" onclick='editHeading(<?php echo htmlspecialchars(json_encode($h), ENT_QUOTES, "UTF-8"); ?>)'><i class="fas fa-edit"></i></button>
                            <button class="btn btn-sm btn-info" onclick="openAddItemModal(<?php echo $h['id']; ?>, '<?php echo htmlspecialchars(addslashes($h['heading_name'])); ?>')"><i class="fas fa-plus"></i> Item</button>
                            <form method="POST" style="display:inline;" onsubmit="return confirm('Delete this heading and ALL its items?');">
                                <input type="hidden" name="action" value="delete_heading">
                                <input type="hidden" name="id" value="<?php echo $h['id']; ?>">
                                <button type="submit" class="btn btn-sm btn-danger"><i class="fas fa-trash"></i></button>
                            </form>
                        </div>
                    </div>
                    <div class="heading-block-body">
                        <?php if (empty($h['items'])): ?>
                            <p class="text-muted small mb-0">No items under this heading yet.</p>
                        <?php else: foreach ($h['items'] as $item): ?>
                            <div class="checklist-item-row">
                                <input type="checkbox" class="export-select-checkbox" data-item-id="<?php echo $item['id']; ?>" style="width:18px;height:18px;margin-top:3px;margin-right:10px;cursor:pointer;flex-shrink:0;" title="Select for export" onchange="updateExportBar()">
                                <div style="flex:1;">
                                    <div class="item-text"><?php echo htmlspecialchars($item['item_text']); ?></div>
                                    <?php if (!empty($item['description'])): ?>
                                        <div class="item-desc"><?php echo htmlspecialchars($item['description']); ?></div>
                                    <?php endif; ?>
                                    <div>
                                        <?php if (($item['item_type'] ?? 'tick') === 'fillable_signature'): ?>
                                            <span class="attach-pill" style="background:#ede9fe;color:#6d28d9;"><i class="fas fa-file-signature"></i> Fillable + Signature Document</span>
                                        <?php elseif (!empty($item['document_path'])): ?>
                                            <a class="attach-pill doc" href="<?php echo htmlspecialchars($item['document_path']); ?>" target="_blank" title="View document" style="cursor:pointer;"><i class="fas fa-file-alt"></i> <?php echo htmlspecialchars($item['document_filename']); ?> <i class="fas fa-external-link-alt" style="font-size:9px;opacity:0.7;"></i></a>
                                        <?php endif; ?>
                                        <?php if (!empty($item['video_path'])): ?>
                                            <a class="attach-pill vid" href="javascript:void(0);" onclick='playVideoPreview(<?php echo json_encode($item["video_path"]); ?>, <?php echo json_encode($item["video_filename"]); ?>)' title="Play video" style="cursor:pointer;"><i class="fas fa-play-circle"></i> <?php echo htmlspecialchars($item['video_filename']); ?></a>
                                        <?php endif; ?>
                                        <?php if (($item['item_type'] ?? 'tick') !== 'fillable_signature' && empty($item['document_path']) && empty($item['video_path'])): ?>
                                            <span class="attach-pill none"><i class="fas fa-ban"></i> No attachment</span>
                                        <?php endif; ?>
                                    </div>
                                </div>
                                <div style="white-space:nowrap;">
                                    <?php if (($item['item_type'] ?? 'tick') === 'fillable_signature'): ?>
                                    <button class="btn btn-sm btn-outline-primary" onclick="window.open('?preview_item=<?php echo $item['id']; ?>', '_blank')" title="Preview document template"><i class="fas fa-eye"></i> Preview</button>
                                    <?php endif; ?>
                                    <button class="btn btn-sm btn-warning" onclick='editItem(<?php echo htmlspecialchars(json_encode($item), ENT_QUOTES, "UTF-8"); ?>)'><i class="fas fa-edit"></i></button>
                                    <form method="POST" style="display:inline;" onsubmit="return confirm('Delete this item?');">
                                        <input type="hidden" name="action" value="delete_item">
                                        <input type="hidden" name="id" value="<?php echo $item['id']; ?>">
                                        <button type="submit" class="btn btn-sm btn-danger"><i class="fas fa-trash"></i></button>
                                    </form>
                                </div>
                            </div>
                        <?php endforeach; endif; ?>
                    </div>
                </div>
            <?php endforeach; ?>
        <?php endif; ?>
    </div>

    <div id="exportBar" style="display:none;margin-top:20px;padding:16px 20px;background:linear-gradient(135deg,#f0fdf4,#dcfce7);border:2px solid #86efac;border-radius:12px;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;">
        <div>
            <h6 style="color:#065f46;font-weight:800;margin:0;font-size:13px;"><i class="fas fa-check-square mr-1"></i> <span id="exportCount">0</span> item(s) selected</h6>
            <p style="color:#059669;font-size:11px;margin:0;">Choose a format to export the selected checklist items.</p>
        </div>
        <div style="display:flex;gap:8px;">
            <button type="button" class="btn btn-success" onclick="exportSelected('csv')"><i class="fas fa-file-csv"></i> Export CSV</button>
            <button type="button" class="btn btn-success" onclick="exportSelected('excel')" style="background:#047857;border-color:#047857;"><i class="fas fa-file-excel"></i> Export Excel</button>
        </div>
    </div>

</div>

<!-- Add Heading Modal -->
<div class="modal fade" id="addHeadingModal" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <form method="POST">
                <input type="hidden" name="action" value="add_heading">
                <div class="modal-header">
                    <h4 class="modal-title">Add New Heading</h4>
                    <button type="button" class="close" data-dismiss="modal">&times;</button>
                </div>
                <div class="modal-body">
                    <!-- Scope inputs removed for global checklist -->
                    <div class="form-group">
                        <label>Heading Name (e.g. "Induction", "Documentation")</label>
                        <input type="text" name="heading_name" class="form-control" required>
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
                    <button type="submit" class="btn btn-primary">Save Heading</button>
                </div>
            </form>
        </div>
    </div>
</div>

<!-- Edit Heading Modal -->
<div class="modal fade" id="editHeadingModal" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <form method="POST">
                <input type="hidden" name="action" value="edit_heading">
                <input type="hidden" name="id" id="edit_heading_id">
                <div class="modal-header">
                    <h4 class="modal-title">Edit Heading</h4>
                    <button type="button" class="close" data-dismiss="modal">&times;</button>
                </div>
                <div class="modal-body">
                    <div class="form-group">
                        <label>Heading Name</label>
                        <input type="text" name="heading_name" id="edit_heading_name" class="form-control" required>
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
                    <button type="submit" class="btn btn-warning">Update Heading</button>
                </div>
            </form>
        </div>
    </div>
</div>

<!-- Add Item Modal -->
<div class="modal fade" id="addItemModal" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog modal-lg" role="document">
        <div class="modal-content">
            <form method="POST" enctype="multipart/form-data">
                <input type="hidden" name="action" value="add_item">
                <input type="hidden" name="heading_id" id="add_item_heading_id">
                <div class="modal-header">
                    <h4 class="modal-title">Add Item to "<span id="add_item_heading_label"></span>"</h4>
                    <button type="button" class="close" data-dismiss="modal">&times;</button>
                </div>
                <div class="modal-body">
                    <div class="form-group">
                        <label>Item Text (e.g. "About the Company")</label>
                        <input type="text" name="item_text" class="form-control" required>
                    </div>
                    <div class="form-group">
                        <label>Description (optional)</label>
                        <textarea name="description" class="form-control" rows="2"></textarea>
                    </div>
                    <div class="form-group">
                        <label>Document Upload (PPT, PDF, DOC, XLS, etc. — optional)</label>
                        <input type="file" name="document_file" class="form-control-file" accept=".pdf,.doc,.docx,.ppt,.pptx,.xls,.xlsx,.txt">
                    </div>
                    <div class="form-group">
                        <label>Video Upload (optional)</label>
                        <input type="file" name="video_file" class="form-control-file" accept=".mp4,.mov,.avi,.wmv,.webm,.mkv">
                    </div>
                    <hr>
                    <div class="form-group mb-1">
                        <div class="custom-control custom-switch">
                            <input type="checkbox" class="custom-control-input" name="visible_to_employee" id="add_visible_to_employee" onchange="document.getElementById('add_require_sig_wrap').style.opacity=this.checked?'1':'0.4'; if(!this.checked) document.getElementById('add_require_signature').checked=false;">
                            <label class="custom-control-label font-weight-bold" for="add_visible_to_employee">
                                <i class="fas fa-eye mr-1 text-success"></i> Visible to Employee
                            </label>
                        </div>
                        <small class="text-muted">Employee will see this item in their onboarding checklist.</small>
                    </div>
                    <div class="form-group mb-0" id="add_require_sig_wrap" style="opacity:0.4;">
                        <div class="custom-control custom-switch">
                            <input type="checkbox" class="custom-control-input" name="require_signature" id="add_require_signature">
                            <label class="custom-control-label font-weight-bold" for="add_require_signature">
                                <i class="fas fa-pen-nib mr-1 text-purple" style="color:#6d28d9;"></i> Require Digital Signature
                            </label>
                        </div>
                        <small class="text-muted">Employee must draw a signature to mark this item complete. Only available when Visible to Employee is on.</small>
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
                    <button type="submit" class="btn btn-primary">Save Item</button>
                </div>
            </form>
        </div>
    </div>
</div>

<!-- Edit Item Modal -->
<div class="modal fade" id="editItemModal" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog modal-lg" role="document">
        <div class="modal-content">
            <form method="POST" enctype="multipart/form-data">
                <input type="hidden" name="action" value="edit_item">
                <input type="hidden" name="id" id="edit_item_id">
                <div class="modal-header">
                    <h4 class="modal-title">Edit Item</h4>
                    <button type="button" class="close" data-dismiss="modal">&times;</button>
                </div>
                <div class="modal-body">
                    <div class="form-group">
                        <label>Item Text</label>
                        <input type="text" name="item_text" id="edit_item_text" class="form-control" required>
                    </div>
                    <div class="form-group">
                        <label>Description (optional)</label>
                        <textarea name="description" id="edit_item_description" class="form-control" rows="2"></textarea>
                    </div>
                    <div class="form-group">
                        <label>Current Document</label>
                        <div id="edit_item_current_doc" class="mb-2"></div>
                        <label>Replace Document (optional)</label>
                        <input type="file" name="document_file" class="form-control-file" accept=".pdf,.doc,.docx,.ppt,.pptx,.xls,.xlsx,.txt">
                    </div>
                    <div class="form-group">
                        <label>Current Video</label>
                        <div id="edit_item_current_vid" class="mb-2"></div>
                        <label>Replace Video (optional)</label>
                        <input type="file" name="video_file" class="form-control-file" accept=".mp4,.mov,.avi,.wmv,.webm,.mkv">
                    </div>
                    <hr>
                    <div class="form-group mb-1">
                        <div class="custom-control custom-switch">
                            <input type="checkbox" class="custom-control-input" name="visible_to_employee" id="edit_visible_to_employee" onchange="document.getElementById('edit_require_sig_wrap').style.opacity=this.checked?'1':'0.4'; if(!this.checked) document.getElementById('edit_require_signature').checked=false;">
                            <label class="custom-control-label font-weight-bold" for="edit_visible_to_employee">
                                <i class="fas fa-eye mr-1 text-success"></i> Visible to Employee
                            </label>
                        </div>
                        <small class="text-muted">Employee will see this item in their onboarding checklist.</small>
                    </div>
                    <div class="form-group mb-0" id="edit_require_sig_wrap" style="opacity:0.4;">
                        <div class="custom-control custom-switch">
                            <input type="checkbox" class="custom-control-input" name="require_signature" id="edit_require_signature">
                            <label class="custom-control-label font-weight-bold" for="edit_require_signature">
                                <i class="fas fa-pen-nib mr-1" style="color:#6d28d9;"></i> Require Digital Signature
                            </label>
                        </div>
                        <small class="text-muted">Employee must draw a signature to mark this item complete. Only available when Visible to Employee is on.</small>
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
                    <button type="submit" class="btn btn-info">Update Item</button>
                </div>
            </form>
        </div>
    </div>
</div>

<!-- Standalone remove-attachment forms (submitted via JS confirm) -->
<form method="POST" id="removeAttachForm" style="display:none;">
    <input type="hidden" name="action" value="remove_attachment">
    <input type="hidden" name="id" id="removeAttachId">
    <input type="hidden" name="attachment_type" id="removeAttachType">
</form>

<!-- Video Preview Modal -->
<div class="modal fade" id="videoPreviewModal" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog modal-lg" role="document">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="videoPreviewTitle">Video</h5>
                <button type="button" class="close" data-dismiss="modal">&times;</button>
            </div>
            <div class="modal-body text-center">
                <video id="videoPreviewPlayer" controls style="width:100%;max-height:70vh;background:#000;"></video>
            </div>
        </div>
    </div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script>
function editHeading(h) {
    document.getElementById('edit_heading_id').value = h.id;
    document.getElementById('edit_heading_name').value = h.heading_name;
    $('#editHeadingModal').modal('show');
}

function openAddItemModal(headingId, headingName) {
    document.getElementById('add_item_heading_id').value = headingId;
    document.getElementById('add_item_heading_label').textContent = headingName;
    $('#addItemModal').modal('show');
}

function editItem(item) {
    document.getElementById('edit_item_id').value = item.id;
    document.getElementById('edit_item_text').value = item.item_text;
    document.getElementById('edit_item_description').value = item.description || '';

    var docBox = document.getElementById('edit_item_current_doc');
    if (item.document_path) {
        docBox.innerHTML = '<a href="' + item.document_path + '" target="_blank" class="badge badge-info" style="font-size:12px;padding:6px 10px;"><i class="fas fa-file-alt mr-1"></i>' + item.document_filename + '</a> ' +
            '<button type="button" class="btn btn-sm btn-outline-danger ml-1" onclick="removeAttachment(' + item.id + ', \'document\')"><i class="fas fa-times"></i> Remove</button>';
    } else {
        docBox.innerHTML = '<span class="text-muted small">No document attached.</span>';
    }

    var vidBox = document.getElementById('edit_item_current_vid');
    if (item.video_path) {
        vidBox.innerHTML = '<a href="' + item.video_path + '" target="_blank" class="badge badge-warning" style="font-size:12px;padding:6px 10px;"><i class="fas fa-video mr-1"></i>' + item.video_filename + '</a> ' +
            '<button type="button" class="btn btn-sm btn-outline-danger ml-1" onclick="removeAttachment(' + item.id + ', \'video\')"><i class="fas fa-times"></i> Remove</button>';
    } else {
        vidBox.innerHTML = '<span class="text-muted small">No video attached.</span>';
    }

    // Restore visible_to_employee + require_signature toggles
    var visChk = document.getElementById('edit_visible_to_employee');
    var sigChk = document.getElementById('edit_require_signature');
    var sigWrap = document.getElementById('edit_require_sig_wrap');
    visChk.checked = item.visible_to_employee == 1;
    sigChk.checked = item.require_signature == 1;
    sigWrap.style.opacity = visChk.checked ? '1' : '0.4';

    $('#editItemModal').modal('show');
}

function playVideoPreview(path, filename) {
    document.getElementById('videoPreviewTitle').textContent = filename || 'Video';
    var player = document.getElementById('videoPreviewPlayer');
    player.src = path;
    $('#videoPreviewModal').modal('show');
    player.play();
}
$('#videoPreviewModal').on('hidden.bs.modal', function () {
    var player = document.getElementById('videoPreviewPlayer');
    player.pause();
    player.src = '';
});

function removeAttachment(id, type) {
    if (!confirm('Remove this ' + type + '?')) return;
    document.getElementById('removeAttachId').value = id;
    document.getElementById('removeAttachType').value = type;
    document.getElementById('removeAttachForm').submit();
}
function updateExportBar() {
    var checkboxes = document.querySelectorAll('.export-select-checkbox:checked');
    var bar = document.getElementById('exportBar');
    var countEl = document.getElementById('exportCount');
    if (countEl) countEl.textContent = checkboxes.length;
    if (bar) bar.style.display = checkboxes.length > 0 ? 'flex' : 'none';
}

function exportSelected(type) {
    var checkboxes = document.querySelectorAll('.export-select-checkbox:checked');
    if (checkboxes.length === 0) { alert('Please select at least one item to export.'); return; }
    var ids = Array.from(checkboxes).map(function(cb) { return cb.getAttribute('data-item-id'); });
    window.location.href = window.location.pathname + '?export=' + type + '&ids=' + ids.join(',');
}
</script>

</body>

<script>
(function(){
  var UE = <?php echo json_encode($GLOBALS['__fue'] ?? ''); ?>;
  if(!UE) return;
  function add(u){
    if(!u) return u;
    if(/^(https?:|\/\/|#|mailto:|tel:|javascript:|data:)/i.test(u)) return u;
    if(u.indexOf('.php')===-1) return u;
    // this folder is served via an alias, so links can come out as bare
    // 'foo.php' or as '/dashboard/foo.php' - both must resolve under /hrm/.
    if(/^\/dashboard\/hr[_-][A-Za-z0-9._-]*\.php(\?|$)/.test(u)) u = u.replace(/^\/dashboard\//, '/hrm/');
    else if(/^[A-Za-z0-9._-]+\.php(\?|$)/.test(u)) u = '/hrm/' + u;
    if(/[?&]user_email=/.test(u)) return u;
    return u + (u.indexOf('?')===-1?'?':'&') + 'user_email=' + encodeURIComponent(UE);
  }
  function fix(){
    document.querySelectorAll('a[href]').forEach(function(a){ a.setAttribute('href', add(a.getAttribute('href'))); });
    document.querySelectorAll('form').forEach(function(f){
      var m=(f.getAttribute('method')||'get').toLowerCase();
      var act=f.getAttribute('action');
      if(act!==null) f.setAttribute('action', add(act));
      if(!f.querySelector('input[name="user_email"]')){
        var i=document.createElement('input'); i.type='hidden'; i.name='user_email'; i.value=UE; f.appendChild(i);
      }
    });
  }
  if(document.readyState!=='loading') fix(); else document.addEventListener('DOMContentLoaded', fix);
  document.addEventListener('click', function(e){
    var a=e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if(a) a.setAttribute('href', add(a.getAttribute('href')));
  }, true);
  // --- carry user_email on EVERY same-site .php AJAX call too ---
  try{ var _f=window.fetch; if(_f) window.fetch=function(i,init){ try{ if(typeof i==='string') i=add(i); else if(i&&i.url) i=new Request(add(i.url),i); }catch(e){} return _f.call(this,i,init); }; }catch(e){}
  try{ var _o=XMLHttpRequest.prototype.open; XMLHttpRequest.prototype.open=function(m,u){ try{ if(typeof u==='string') u=add(u); }catch(e){} return _o.apply(this,[m,u].concat([].slice.call(arguments,2))); }; }catch(e){}
  try{ if(window.jQuery&&window.jQuery.ajaxPrefilter) window.jQuery.ajaxPrefilter(function(o){ try{ o.url=add(o.url); }catch(e){} }); }catch(e){}
})();
</script>
</html>