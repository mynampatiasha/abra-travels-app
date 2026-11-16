<?php
// =========================================================================
// DIGITAL EXPENSES — WHATSAPP APPROVALS
// =========================================================================
// Two ways in:
//  1. require_once'd by digital-expenses-finance-suite.php — sends the
//     approval request (submitted by, amount, paid to, description with
//     Approve / Reject / View Details) to the L1 or L2 approvers picked in
//     "WhatsApp Approvers", and the rejection notice to the employee.
//     Inside WhatsApp's 24-hour window (the person messaged the E-Logistics
//     number in the last 23 h) a normal message goes; otherwise the template.
//  2. Called over HTTP by whatsapp-webhook.php (E-Logistics number) when an
//     approver taps Approve / Reject, or types the reason after Reject.
//     Returns {"handled":true,"reply":"..."} and the webhook sends the reply.
//
// The decisions made here are the same as the buttons in the app:
//   L1 approve  -> l1 Approved, status "Pending L2 Approval", request goes to L2
//   L1 reject   -> l1 Declined, status Declined, employee notified
//   L2 approve  -> l2 Approved, status Approved (final)
//   L2 reject   -> l2 Declined, status Declined, employee notified
// Override / revert / payment status stay in the app only.
//
// Meta templates this uses (Utility, language set in WhatsApp Approvers):
//   expense_approval_short  body {{1}}..{{6}}, buttons: quick reply Approve,
//                           quick reply Reject, URL View Details (…expense-files.php?t={{1}})
//   expense_rejected_notice body {{1}}..{{4}}
// =========================================================================

if (!defined('DEWA_PHONE_NUMBER_ID')) define('DEWA_PHONE_NUMBER_ID', '1138160196037346');   // E-Logistics number — same one whatsapp-webhook.php serves
if (!defined('DEWA_ACCESS_TOKEN'))    define('DEWA_ACCESS_TOKEN', 'EAAU6AdOvUxYBRQvIwILhF2SlOTMxOZBuUQgzkmekeEd73nKYpbNh7UdZBACEIOGk9qCF6HxkiUZBVcuin733irPWNNioO0mIOojnzVAZC3UZAIurlZCcNnZBaWYwie9qxzZC22yiUL5YwznaCj1koJSzQ1ebnspZBqUTMrrApz5zbnLbAiIHam15D3eiSz22V8wZDZD');
if (!defined('DEWA_TPL_APPROVAL'))    define('DEWA_TPL_APPROVAL', 'expense_approval_short');
if (!defined('DEWA_TPL_REJECTED'))    define('DEWA_TPL_REJECTED', 'expense_rejected_notice');
if (!defined('DEWA_TPL_PAYMENT_INITIATED')) define('DEWA_TPL_PAYMENT_INITIATED', 'expense_payment_initiated');
define('DEWA_REASON_MINUTES', 60);   // how long after tapping Reject the next message is taken as the reason

function dewaEnsureTables($con) {
    static $done = false;
    if ($done) return;
    $done = true;
    mysqli_query($con, "CREATE TABLE IF NOT EXISTS finance_de_wa_settings (
        id INT PRIMARY KEY,
        enabled TINYINT(1) NOT NULL DEFAULT 0,
        l1_ids TEXT,
        l2_ids TEXT,
        lang VARCHAR(20) NOT NULL DEFAULT 'en',
        crm_base VARCHAR(255) DEFAULT NULL,
        secret VARCHAR(64) DEFAULT NULL,
        updated_by VARCHAR(200) DEFAULT NULL,
        updated_at DATETIME DEFAULT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    mysqli_query($con, "CREATE TABLE IF NOT EXISTS finance_de_wa_pending (
        phone VARCHAR(20) PRIMARY KEY,
        expense_id INT NOT NULL,
        level TINYINT NOT NULL,
        created_at DATETIME NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    mysqli_query($con, "CREATE TABLE IF NOT EXISTS finance_de_wa_log (
        id INT AUTO_INCREMENT PRIMARY KEY,
        expense_id INT NOT NULL,
        phone VARCHAR(20) DEFAULT NULL,
        kind VARCHAR(40) NOT NULL,
        ok TINYINT(1) NOT NULL DEFAULT 0,
        response TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_exp (expense_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    $c = mysqli_query($con, "SHOW COLUMNS FROM finance_digital_expenses LIKE 'wa_file_token'");
    if ($c && mysqli_num_rows($c) === 0) mysqli_query($con, "ALTER TABLE finance_digital_expenses ADD COLUMN wa_file_token VARCHAR(64) DEFAULT NULL");
}

function dewaSettings($con) {
    dewaEnsureTables($con);
    $q = mysqli_query($con, "SELECT * FROM finance_de_wa_settings WHERE id=1 LIMIT 1");
    $row = $q ? mysqli_fetch_assoc($q) : null;
    if (!$row) {
        $secret = bin2hex(random_bytes(16));
        mysqli_query($con, "INSERT INTO finance_de_wa_settings (id, enabled, l1_ids, l2_ids, lang, secret) VALUES (1, 0, '', '', 'en', '$secret')");
        $row = ['id' => 1, 'enabled' => 0, 'l1_ids' => '', 'l2_ids' => '', 'lang' => 'en', 'crm_base' => null, 'secret' => $secret];
    }
    if (empty($row['secret'])) {
        $row['secret'] = bin2hex(random_bytes(16));
        mysqli_query($con, "UPDATE finance_de_wa_settings SET secret='{$row['secret']}' WHERE id=1");
    }
    return $row;
}

// The webhook runs on another domain, so it needs to know where this CRM lives
// (to call back here) — remembered from whichever host the expense page is opened on.
function dewaRememberBase($con) {
    if (empty($_SERVER['HTTP_HOST'])) return;
    $https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https');
    $base = ($https ? 'https' : 'http') . '://' . $_SERVER['HTTP_HOST'] . rtrim(str_replace('\\', '/', dirname($_SERVER['PHP_SELF'])), '/');
    $s = dewaSettings($con);
    if ($s['crm_base'] !== $base) mysqli_query($con, "UPDATE finance_de_wa_settings SET crm_base='" . mysqli_real_escape_string($con, $base) . "' WHERE id=1");
}

function dewaIdList($csv) {
    return array_values(array_filter(array_map('intval', explode(',', (string) $csv))));
}

function dewaPhone($raw) {
    $d = preg_replace('/\D/', '', (string) $raw);
    if (strlen($d) === 10) $d = '91' . $d;
    if (strlen($d) === 11 && $d[0] === '0') $d = '91' . substr($d, 1);
    return strlen($d) >= 11 ? $d : '';
}

function dewaApprovers($con, $level) {
    $s = dewaSettings($con);
    $ids = dewaIdList($level == 2 ? $s['l2_ids'] : $s['l1_ids']);
    if (!$ids) return [];
    $out = [];
    $q = mysqli_query($con, "SELECT id, name, phone FROM hr_employees WHERE id IN (" . implode(',', $ids) . ") AND status='active' ORDER BY name");
    while ($q && ($r = mysqli_fetch_assoc($q))) {
        $r['wa'] = dewaPhone($r['phone']);
        $out[] = $r;
    }
    return $out;
}

// The approver behind an incoming WhatsApp number, if they are picked for this level.
function dewaApproverByPhone($con, $level, $from) {
    $l10 = substr(preg_replace('/\D/', '', (string) $from), -10);
    if (strlen($l10) !== 10) return null;
    foreach (dewaApprovers($con, $level) as $a) {
        if ($a['wa'] !== '' && substr($a['wa'], -10) === $l10) return $a;
    }
    return null;
}

function dewaPost($payload) {
    if (!function_exists('curl_init')) return [false, 'curl not available'];
    $ch = curl_init('https://graph.facebook.com/v19.0/' . DEWA_PHONE_NUMBER_ID . '/messages');
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => json_encode($payload),
        CURLOPT_HTTPHEADER => ['Content-Type: application/json', 'Authorization: Bearer ' . DEWA_ACCESS_TOKEN],
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 15,
    ]);
    $res = curl_exec($ch);
    $err = curl_error($ch);
    curl_close($ch);
    $j = json_decode((string) $res, true);
    $ok = !empty($j['messages'][0]['id']);
    return [$ok, $ok ? '' : ($j['error']['message'] ?? ($err ?: (string) $res))];
}

// Template parameters may not contain new lines, tabs or runs of spaces, and may not be empty.
function dewaParam($s, $max = 200) {
    $s = trim(preg_replace('/\s+/u', ' ', (string) $s));
    if (mb_strlen($s) > $max) $s = rtrim(mb_substr($s, 0, $max - 1)) . '…';
    return ['type' => 'text', 'text' => $s === '' ? '-' : $s];
}

function dewaLog($con, $expId, $phone, $kind, $ok, $resp) {
    mysqli_query($con, "INSERT INTO finance_de_wa_log (expense_id, phone, kind, ok, response) VALUES (" . (int) $expId . ", '" . mysqli_real_escape_string($con, (string) $phone) . "', '" . mysqli_real_escape_string($con, $kind) . "', " . ($ok ? 1 : 0) . ", '" . mysqli_real_escape_string($con, mb_substr((string) $resp, 0, 1000)) . "')");
}

// Same history table / columns as logExpHistory() in the expense page.
function dewaHistory($con, $exp, $action, $details) {
    mysqli_query($con, "INSERT INTO finance_digital_expense_history (action, voucher_number, details, performed_by, employee_id) VALUES ('"
        . mysqli_real_escape_string($con, $action) . "', '" . mysqli_real_escape_string($con, $exp['voucher_number']) . "', '"
        . mysqli_real_escape_string($con, $details) . "', '" . mysqli_real_escape_string($con, (string) $exp['added_by_name']) . "', '"
        . mysqli_real_escape_string($con, (string) $exp['added_by']) . "')");
}

function dewaExpense($con, $id) {
    $q = mysqli_query($con, "SELECT * FROM finance_digital_expenses WHERE id=" . (int) $id . " LIMIT 1");
    return $q ? mysqli_fetch_assoc($q) : null;
}

function dewaFileToken($con, &$exp) {
    if (empty($exp['wa_file_token'])) {
        $exp['wa_file_token'] = bin2hex(random_bytes(16));
        mysqli_query($con, "UPDATE finance_digital_expenses SET wa_file_token='{$exp['wa_file_token']}' WHERE id=" . (int) $exp['id']);
    }
    return $exp['wa_file_token'];
}

// Proof files first, then the files added with the employee's response after a rejection.
function dewaFiles($exp) {
    $out = [];
    foreach (['proof_files' => false, 'rebuttal_proof_files' => true] as $col => $isResponse) {
        $arr = json_decode((string) ($exp[$col] ?? ''), true);
        if (!is_array($arr)) continue;
        foreach ($arr as $f) {
            if (empty($f['path'])) continue;
            $f['response'] = $isResponse;
            $out[] = $f;
        }
    }
    return $out;
}

function dewaRs($n) { return number_format((float) $n, 2); }

// Is this number inside WhatsApp's 24-hour window (they messaged the E-Logistics number in the last 23 h)?
// Then a normal message is allowed and no template is needed.
function dewaWindowOpen($con, $wa) {
    $p = mysqli_real_escape_string($con, $wa);
    $q = @mysqli_query($con, "SELECT MAX(created_at) t FROM wa_messages WHERE phone='$p' AND direction='in'");
    $r = $q ? mysqli_fetch_assoc($q) : null;
    return $r && !empty($r['t']) && (time() - strtotime($r['t'])) < 23 * 3600;
}

// Normal (non-template) messages also go into the E-Logistics inbox, like the webhook's own replies.
function dewaInboxLog($con, $wa, $text) {
    @mysqli_query($con, "INSERT INTO wa_messages (phone, direction, message_text, sent_by, created_at) VALUES ('" . mysqli_real_escape_string($con, $wa) . "', 'out', '" . mysqli_real_escape_string($con, mb_substr($text, 0, 2000)) . "', 'bot', NOW())");
}

function dewaShort($s, $max) {
    $s = trim(preg_replace('/\s+/u', ' ', (string) $s));
    if (mb_strlen($s) > $max) $s = rtrim(mb_substr($s, 0, $max - 1)) . '…';
    return $s === '' ? '-' : $s;
}

// Approvers' message: who submitted it, amount, paid to, description + Approve / Reject / View Details.
// Everything else (all fields, files, earlier rejection, explanation) is on the View Details page.
// Window open -> normal message with buttons; closed (or refused) -> the expense_approval_short template.
// $note (e.g. why it is being sent again) is added to the level line.
function dewaSendLevel($con, $expId, $level, $note = '') {
    $s = dewaSettings($con);
    if (empty($s['enabled'])) return;
    $exp = dewaExpense($con, $expId);
    if (!$exp) return;
    $approvers = dewaApprovers($con, $level);
    if (!$approvers) { dewaHistory($con, $exp, 'WhatsApp', 'No L' . $level . ' WhatsApp approvers are set — approval request not sent'); return; }

    $token = dewaFileToken($con, $exp);
    $lang = $s['lang'] ?: 'en';
    $levelLine = ($level == 2 ? 'L2 – Final approval' : 'L1 – Finance review') . ($note !== '' ? ' (' . $note . ')' : '');
    $viewUrl = rtrim((string) $s['crm_base'], '/') . '/expense-files.php?t=' . $token;
    $vals = [$levelLine, $exp['voucher_number'], $exp['added_by_name'], dewaRs($exp['amount']), $exp['amount_paid_to'], $exp['on_account_of']];
    $text = "*Expense voucher for your approval – " . dewaShort($vals[0], 120) . "*\n\n"
        . "Voucher: " . dewaShort($vals[1], 50) . "\n"
        . "Submitted by: " . dewaShort($vals[2], 100) . "\n"
        . "Amount: ₹" . $vals[3] . "\n"
        . "Paid to: " . dewaShort($vals[4], 100) . "\n"
        . "Description: " . dewaShort($vals[5], 400) . "\n\n"
        . "View details & files: " . $viewUrl;
    $tplBody = [dewaParam($vals[0], 120), dewaParam($vals[1], 50), dewaParam($vals[2], 100), dewaParam($vals[3], 30), dewaParam($vals[4], 100), dewaParam($vals[5], 400)];
    $idA = 'DEXP|A|' . $exp['id'] . '|' . $level;
    $idR = 'DEXP|R|' . $exp['id'] . '|' . $level;

    $sent = []; $failed = [];
    foreach ($approvers as $a) {
        if ($a['wa'] === '') { $failed[] = $a['name'] . ' (no phone number)'; continue; }
        $ok = false; $err = ''; $how = '';
        if (dewaWindowOpen($con, $a['wa'])) {
            list($ok, $err) = dewaPost(['messaging_product' => 'whatsapp', 'to' => $a['wa'], 'type' => 'interactive', 'interactive' => [
                'type' => 'button',
                'body' => ['text' => mb_substr($text, 0, 1024)],
                'action' => ['buttons' => [
                    ['type' => 'reply', 'reply' => ['id' => $idA, 'title' => 'Approve']],
                    ['type' => 'reply', 'reply' => ['id' => $idR, 'title' => 'Reject']],
                ]],
            ]]);
            $how = 'message';
            dewaLog($con, $exp['id'], $a['wa'], 'L' . $level . ' approval (message)', $ok, $err);
            if ($ok) dewaInboxLog($con, $a['wa'], $text . "\n\n🔘 Approve  |  Reject");
        }
        if (!$ok) {   // window closed, or the normal message was refused -> template
            list($ok, $err) = dewaPost(['messaging_product' => 'whatsapp', 'to' => $a['wa'], 'type' => 'template', 'template' => [
                'name' => DEWA_TPL_APPROVAL, 'language' => ['code' => $lang],
                'components' => [
                    ['type' => 'body', 'parameters' => $tplBody],
                    ['type' => 'button', 'sub_type' => 'quick_reply', 'index' => '0', 'parameters' => [['type' => 'payload', 'payload' => $idA]]],
                    ['type' => 'button', 'sub_type' => 'quick_reply', 'index' => '1', 'parameters' => [['type' => 'payload', 'payload' => $idR]]],
                    ['type' => 'button', 'sub_type' => 'url', 'index' => '2', 'parameters' => [['type' => 'text', 'text' => $token]]],
                ],
            ]]);
            $how = 'template';
            dewaLog($con, $exp['id'], $a['wa'], 'L' . $level . ' approval (template)', $ok, $err);
        }
        if ($ok) $sent[] = $a['name'] . ' (' . $how . ')'; else $failed[] = $a['name'] . ' (' . $err . ')';
    }
    $msg = '';
    if ($sent) $msg .= 'L' . $level . ' approval request sent on WhatsApp to ' . implode(', ', $sent) . '. ';
    if ($failed) $msg .= 'WhatsApp could not be sent to ' . implode('; ', $failed) . '.';
    dewaHistory($con, $exp, 'WhatsApp', trim($msg));
}

// Employee is told on WhatsApp only when the voucher is rejected (at L1 or L2).
// Window open -> normal message; closed (or refused) -> the expense_rejected_notice template.
function dewaNotifyRejected($con, $expId, $byName, $reason) {
    $s = dewaSettings($con);
    if (empty($s['enabled'])) return;
    $exp = dewaExpense($con, $expId);
    if (!$exp) return;
    $q = mysqli_query($con, "SELECT phone FROM hr_employees WHERE employee_id='" . mysqli_real_escape_string($con, $exp['added_by']) . "' LIMIT 1");
    $emp = $q ? mysqli_fetch_assoc($q) : null;
    $to = $emp ? dewaPhone($emp['phone']) : '';
    if ($to === '') { dewaHistory($con, $exp, 'WhatsApp', 'Rejection notice not sent — no phone number for ' . $exp['added_by_name']); return; }
    $ok = false; $err = ''; $how = '';
    if (dewaWindowOpen($con, $to)) {
        $text = '❌ Your expense voucher *' . $exp['voucher_number'] . '* for ₹' . dewaRs($exp['amount']) . ' has been rejected by ' . $byName . ".\n\nReason: " . $reason . "\n\nPlease open Digital Expenses to edit it or submit your response.";
        list($ok, $err) = dewaPost(['messaging_product' => 'whatsapp', 'to' => $to, 'type' => 'text', 'text' => ['body' => $text]]);
        $how = 'message';
        dewaLog($con, $exp['id'], $to, 'rejected notice (message)', $ok, $err);
        if ($ok) dewaInboxLog($con, $to, $text);
    }
    if (!$ok) {
        list($ok, $err) = dewaPost(['messaging_product' => 'whatsapp', 'to' => $to, 'type' => 'template', 'template' => [
            'name' => DEWA_TPL_REJECTED, 'language' => ['code' => $s['lang'] ?: 'en'],
            'components' => [['type' => 'body', 'parameters' => [
                dewaParam($exp['voucher_number']), dewaParam(dewaRs($exp['amount'])), dewaParam($byName), dewaParam($reason, 500),
            ]]],
        ]]);
        $how = 'template';
        dewaLog($con, $exp['id'], $to, 'rejected notice (template)', $ok, $err);
    }
    dewaHistory($con, $exp, 'WhatsApp', $ok
        ? 'Rejection notice sent to ' . $exp['added_by_name'] . ' (+' . $to . ') on WhatsApp (' . $how . ')'
        : 'Rejection notice to ' . $exp['added_by_name'] . ' (+' . $to . ') failed: ' . $err);
}

// Normal WhatsApp text, only inside the 24-hour window (no template) — used for the thank-you and the
// payment request. Approvers who tap Approve on WhatsApp have just messaged the number, so it is open.
// Returns [ok, error].
function dewaSendNormal($con, $expId, $wa, $kind, $text) {
    if (!dewaWindowOpen($con, $wa)) { dewaLog($con, $expId, $wa, $kind, false, '24-hour window closed'); return [false, '24-hour window closed']; }
    list($ok, $err) = dewaPost(['messaging_product' => 'whatsapp', 'to' => $wa, 'type' => 'text', 'text' => ['body' => $text]]);
    dewaLog($con, $expId, $wa, $kind, $ok, $err);
    if ($ok) dewaInboxLog($con, $wa, $text);
    return [$ok, $err];
}

function dewaApproverNames($con, $level) {
    $names = array_map(function ($a) { return $a['name']; }, dewaApprovers($con, $level));
    return $names ? implode(', ', $names) : ($level == 2 ? 'the final approver' : 'the finance team');
}

// Thank-you for an approver — also the WhatsApp reply when they approve from WhatsApp.
function dewaThanksText($con, $exp, $level) {
    return '🙏 Thanks for the approval of *' . $exp['voucher_number'] . '* (₹' . dewaRs($exp['amount']) . ', ' . $exp['added_by_name'] . ').'
        . "\n\n" . ($level == 2
            ? 'I will notify ' . dewaApproverNames($con, 1) . ' to initiate the payment.'
            : 'It has been sent to ' . dewaApproverNames($con, 2) . ' for final approval.');
}

// Thank the approver on WhatsApp after an approval made in the app (WhatsApp approvals get it as the reply).
// Normal message only — skipped if their 24-hour window is closed.
function dewaThankApprover($con, $expId, $level, $employeeIdStr, $name) {
    $s = dewaSettings($con);
    if (empty($s['enabled'])) return;
    $exp = dewaExpense($con, $expId);
    if (!$exp) return;
    $q = mysqli_query($con, "SELECT phone FROM hr_employees WHERE employee_id='" . mysqli_real_escape_string($con, $employeeIdStr) . "' LIMIT 1");
    $row = $q ? mysqli_fetch_assoc($q) : null;
    $wa = $row ? dewaPhone($row['phone']) : '';
    if ($wa === '') return;
    list($ok, $err) = dewaSendNormal($con, $exp['id'], $wa, 'thanks L' . $level, dewaThanksText($con, $exp, $level));
    if ($ok) dewaHistory($con, $exp, 'WhatsApp', 'Thank-you sent to ' . $name . ' on WhatsApp');
}

// Final (L2) approval done -> ask every L1 approver (finance team) to initiate the payment.
// Normal message only — anyone whose 24-hour window is closed is listed in the history instead.
function dewaNotifyPayment($con, $expId, $approvedBy) {
    $s = dewaSettings($con);
    if (empty($s['enabled'])) return;
    $exp = dewaExpense($con, $expId);
    if (!$exp) return;
    $token = dewaFileToken($con, $exp);
    $viewUrl = rtrim((string) $s['crm_base'], '/') . '/expense-files.php?t=' . $token;
    $text = '💰 *Please initiate the payment as soon as possible*'
        . "\n\nVoucher: " . $exp['voucher_number']
        . "\nSubmitted by: " . dewaShort($exp['added_by_name'], 100)
        . "\nAmount: ₹" . dewaRs($exp['amount'])
        . "\nPaid to: " . dewaShort($exp['amount_paid_to'], 100)
        . "\nFinal approval by: " . $approvedBy
        . "\n\nView details & files: " . $viewUrl;
    $sent = []; $failed = [];
    foreach (dewaApprovers($con, 1) as $a) {
        if ($a['wa'] === '') { $failed[] = $a['name'] . ' (no phone number)'; continue; }
        list($ok, $err) = dewaSendNormal($con, $exp['id'], $a['wa'], 'payment request', $text);
        if ($ok) $sent[] = $a['name']; else $failed[] = $a['name'] . ' (' . $err . ')';
    }
    $msg = '';
    if ($sent) $msg .= 'Payment request sent on WhatsApp to ' . implode(', ', $sent) . '. ';
    if ($failed) $msg .= 'Payment request not sent to ' . implode('; ', $failed) . '.';
    if ($msg !== '') dewaHistory($con, $exp, 'WhatsApp', trim($msg));
}

// When payment is initiated (e.g. from Digital Expenses popup):
// Automatically notify the L2 Approver so they can release the payment in the bank.
function dewaNotifyPaymentInitiated($con, $expId, $initiatedBy) {
    $s = dewaSettings($con);
    if (empty($s['enabled'])) return;
    $exp = dewaExpense($con, $expId);
    if (!$exp) return;

    // Find the L2 approver(s) to notify
    $l2Recipients = [];

    // 1. Check the specific L2 approver who approved this voucher
    $l2Name = trim((string)($exp['l2_by'] ?: $exp['approved_by']));
    if ($l2Name !== '') {
        $q = mysqli_query($con, "SELECT id, name, phone FROM hr_employees WHERE LOWER(TRIM(name)) = LOWER(TRIM('" . mysqli_real_escape_string($con, $l2Name) . "')) LIMIT 1");
        if ($q && ($r = mysqli_fetch_assoc($q))) {
            $wa = dewaPhone($r['phone']);
            if ($wa !== '') {
                $l2Recipients[$wa] = ['name' => $r['name'], 'wa' => $wa];
            }
        }
    }

    // 2. If not found by name, notify the configured L2 approver(s)
    if (empty($l2Recipients)) {
        foreach (dewaApprovers($con, 2) as $a) {
            if (!empty($a['wa'])) {
                $l2Recipients[$a['wa']] = ['name' => $a['name'], 'wa' => $a['wa']];
            }
        }
    }

    if (empty($l2Recipients)) {
        dewaHistory($con, $exp, 'WhatsApp', 'Payment initiated alert not sent — no phone number found for L2 approver (' . ($l2Name ?: 'L2') . ')');
        return;
    }

    $text = "💳 *Payment Initiated*\n\n"
        . "Payment of *₹" . dewaRs($exp['amount']) . "* for expense voucher *" . $exp['voucher_number'] . "* has been initiated by *" . $initiatedBy . "*.\n\n"
        . "Kindly release the payment as soon as possible.";

    foreach ($l2Recipients as $recip) {
        $wa = $recip['wa'];
        $name = $recip['name'];
        $ok = false; $err = ''; $how = '';

        if (dewaWindowOpen($con, $wa)) {
            list($ok, $err) = dewaPost(['messaging_product' => 'whatsapp', 'to' => $wa, 'type' => 'text', 'text' => ['body' => $text]]);
            $how = 'message';
            dewaLog($con, $exp['id'], $wa, 'payment initiated (message)', $ok, $err);
            if ($ok) dewaInboxLog($con, $wa, $text);
        }
        if (!$ok && defined('DEWA_TPL_PAYMENT_INITIATED') && DEWA_TPL_PAYMENT_INITIATED !== '') {
            list($ok, $err) = dewaPost(['messaging_product' => 'whatsapp', 'to' => $wa, 'type' => 'template', 'template' => [
                'name' => DEWA_TPL_PAYMENT_INITIATED,
                'language' => ['code' => $s['lang'] ?: 'en'],
                'components' => [
                    ['type' => 'body', 'parameters' => [
                        dewaParam(dewaRs($exp['amount']), 30),
                        dewaParam($exp['voucher_number'], 50),
                        dewaParam($initiatedBy, 100)
                    ]]
                ]
            ]]);
            $how = 'template';
            dewaLog($con, $exp['id'], $wa, 'payment initiated (template)', $ok, $err);
        }
        dewaHistory($con, $exp, 'WhatsApp', $ok
            ? 'Payment initiated notification sent to L2 approver ' . $name . ' (+' . $wa . ') on WhatsApp (' . $how . ')'
            : 'Payment initiated notification to L2 approver ' . $name . ' (+' . $wa . ') failed: ' . $err);
    }
}

// Run the WhatsApp sends after the page has answered, so a slow WhatsApp API never delays saving a voucher.
// Each $fn gets its own fresh DB connection — by shutdown time the page's connection may already be closed.
function dewaDefer($fn) {
    static $queue = null;
    if ($queue === null) {
        $queue = [];
        register_shutdown_function(function () use (&$queue) {
            if (!$queue) return;
            ignore_user_abort(true);
            @set_time_limit(180);
            if (function_exists('fastcgi_finish_request')) fastcgi_finish_request();
            elseif (function_exists('litespeed_finish_request')) litespeed_finish_request();
            // pages that open their own connection (e.g. vendors.php) set $GLOBALS['DEWA_CON_FACTORY'] to make a fresh one
            $c = function_exists('conexion') ? conexion() : (is_callable($GLOBALS['DEWA_CON_FACTORY'] ?? null) ? call_user_func($GLOBALS['DEWA_CON_FACTORY']) : null);
            if (!$c) { error_log('dewa: no DB connection for WhatsApp sends'); return; }
            mysqli_set_charset($c, 'utf8mb4');
            foreach ($queue as $f) {
                try { $f($c); } catch (Throwable $e) { error_log('dewa: ' . $e->getMessage()); }
            }
        });
    }
    $queue[] = $fn;
}

// Where the voucher stands, for an approver whose tap came too late.
function dewaStateText($exp) {
    if ($exp['status'] === 'Approved') return '✅ ' . $exp['voucher_number'] . ' is already approved' . (!empty($exp['approved_by']) ? ' by ' . $exp['approved_by'] : '') . '.';
    if ($exp['status'] === 'Declined') {
        $by = $exp['l2_status'] === 'Declined' ? $exp['l2_by'] : $exp['l1_by'];
        return '❌ ' . $exp['voucher_number'] . ' is already rejected' . ($by ? ' by ' . $by : '') . '.';
    }
    if ($exp['status'] === 'Pending L2 Approval') return 'ℹ️ ' . $exp['voucher_number'] . ' is already L1 approved' . (!empty($exp['l1_by']) ? ' by ' . $exp['l1_by'] : '') . ' and is waiting for L2 approval.';
    return 'ℹ️ ' . $exp['voucher_number'] . ' is waiting for L1 (Finance) review.';
}

function dewaIsPendingAt($exp, $level) {
    if ($level == 1) return $exp['l1_status'] === 'Pending' && in_array($exp['status'], ['Pending', 'Response Submitted']);
    return $exp['l1_status'] === 'Approved' && $exp['l2_status'] === 'Pending' && $exp['status'] === 'Pending L2 Approval';
}

// Apply an Approve / Reject made on WhatsApp — the same updates as the app's L1/L2 buttons.
// Only succeeds if the voucher is still waiting at that level (so two approvers can't both act).
function dewaDecide($con, $expId, $level, $approve, $reason, $actorName) {
    $exp = dewaExpense($con, $expId);
    if (!$exp) return 'That voucher no longer exists.';
    if (!dewaIsPendingAt($exp, $level)) return dewaStateText($exp);
    $id = (int) $exp['id'];
    $nameEsc = mysqli_real_escape_string($con, $actorName);
    $reasonEsc = mysqli_real_escape_string($con, $reason);
    if ($level == 1) {
        $where = "WHERE id=$id AND l1_status='Pending' AND status IN ('Pending','Response Submitted')";
        $sql = $approve
            ? "UPDATE finance_digital_expenses SET l1_status='Approved', l1_by='$nameEsc', l1_at=NOW(), l1_reason=NULL, status='Pending L2 Approval' $where"
            : "UPDATE finance_digital_expenses SET l1_status='Declined', l1_by='$nameEsc', l1_at=NOW(), l1_reason='$reasonEsc', status='Declined', manager_reason='$reasonEsc' $where";
    } else {
        $where = "WHERE id=$id AND l1_status='Approved' AND l2_status='Pending' AND status='Pending L2 Approval'";
        $sql = $approve
            ? "UPDATE finance_digital_expenses SET l2_status='Approved', l2_by='$nameEsc', l2_at=NOW(), l2_reason=NULL, status='Approved', manager_reason=NULL, approved_by='$nameEsc', approved_at=NOW() $where"
            : "UPDATE finance_digital_expenses SET l2_status='Declined', l2_by='$nameEsc', l2_at=NOW(), l2_reason='$reasonEsc', status='Declined', manager_reason='$reasonEsc', approved_by=NULL, approved_at=NULL $where";
    }
    mysqli_query($con, $sql);
    if (mysqli_affected_rows($con) !== 1) { $now = dewaExpense($con, $id); return $now ? dewaStateText($now) : 'That voucher no longer exists.'; }

    $v = $exp['voucher_number'] . ' (₹' . dewaRs($exp['amount']) . ', ' . $exp['added_by_name'] . ')';
    if ($approve) {
        dewaHistory($con, $exp, 'L' . $level . ' Approved', 'L' . $level . ($level == 2 ? ' (admin)' : '') . ' approved by ' . $actorName . ' via WhatsApp');
        if ($level == 1) dewaSendLevel($con, $id, 2);
        else dewaNotifyPayment($con, $id, $actorName);
        return dewaThanksText($con, $exp, $level);
    }
    dewaHistory($con, $exp, 'L' . $level . ' Declined', 'L' . $level . ' declined by ' . $actorName . ' via WhatsApp: ' . $reason);
    dewaNotifyRejected($con, $id, $actorName, $reason);
    return '❌ ' . $v . ' rejected. Reason saved: "' . $reason . '". The employee has been informed.';
}

// A tap or a typed reason from whatsapp-webhook.php. Returns the text to send back ('' = nothing).
function dewaHandleIncoming($con, $from, $kind, $payload, $text) {
    $fromD = preg_replace('/\D/', '', (string) $from);
    if ($kind === 'tap') {
        $p = explode('|', (string) $payload);
        if (count($p) !== 4 || $p[0] !== 'DEXP') return '';
        $act = $p[1]; $id = (int) $p[2]; $level = (int) $p[3] === 2 ? 2 : 1;
        $who = dewaApproverByPhone($con, $level, $fromD);
        if (!$who) return 'This WhatsApp number is not set up as an L' . $level . ' approver for digital expenses. Please use the app.';
        $exp = dewaExpense($con, $id);
        if (!$exp) return 'That voucher no longer exists.';
        if ($act === 'A') return dewaDecide($con, $id, $level, true, '', $who['name']);
        if ($act === 'R') {
            if (!dewaIsPendingAt($exp, $level)) return dewaStateText($exp);
            mysqli_query($con, "REPLACE INTO finance_de_wa_pending (phone, expense_id, level, created_at) VALUES ('$fromD', $id, $level, NOW())");
            return '✍️ Please type the reason for rejecting *' . $exp['voucher_number'] . '* (₹' . dewaRs($exp['amount']) . ', ' . $exp['added_by_name'] . ").\n\nReply *cancel* to leave it pending.";
        }
        return '';
    }
    // typed text — only taken as a reason if this number tapped Reject recently
    $q = mysqli_query($con, "SELECT * FROM finance_de_wa_pending WHERE phone='$fromD' AND created_at > NOW() - INTERVAL " . DEWA_REASON_MINUTES . " MINUTE LIMIT 1");
    $pend = $q ? mysqli_fetch_assoc($q) : null;
    if (!$pend) return '';
    mysqli_query($con, "DELETE FROM finance_de_wa_pending WHERE phone='$fromD'");
    $exp = dewaExpense($con, $pend['expense_id']);
    $reason = trim((string) $text);
    if (!$exp) return 'That voucher no longer exists.';
    if (strtolower($reason) === 'cancel') return 'Okay — ' . $exp['voucher_number'] . ' was not rejected. It is still pending.';
    if (mb_strlen($reason) < 3) {
        mysqli_query($con, "REPLACE INTO finance_de_wa_pending (phone, expense_id, level, created_at) VALUES ('$fromD', " . (int) $pend['expense_id'] . ", " . (int) $pend['level'] . ", NOW())");
        return 'Please type the reason in a few words (or reply *cancel*).';
    }
    $who = dewaApproverByPhone($con, (int) $pend['level'], $fromD);
    if (!$who) return 'This WhatsApp number is no longer set up as an approver. Please use the app.';
    return dewaDecide($con, (int) $pend['expense_id'], (int) $pend['level'], false, $reason, $who['name']);
}

// ---------- HTTP entry point for whatsapp-webhook.php ----------
if (isset($_SERVER['SCRIPT_FILENAME']) && realpath($_SERVER['SCRIPT_FILENAME']) === realpath(__FILE__)) {
    error_reporting(E_ALL);
    ini_set('display_errors', 0);
    date_default_timezone_set('Asia/Kolkata');
    require_once('database.php');
    require_once('database-settings.php');
    require_once('library.php');
    require_once('funciones.php');
    while (ob_get_level()) ob_end_clean();
    header('Content-Type: application/json');
    $con = conexion();
    if (!$con) { echo json_encode(['handled' => false, 'error' => 'db']); exit; }
    mysqli_set_charset($con, 'utf8mb4');
    mysqli_query($con, "SET time_zone = '+05:30'");
    $in = json_decode(file_get_contents('php://input'), true);
    $s = dewaSettings($con);
    if (!is_array($in) || empty($in['secret']) || !hash_equals((string) $s['secret'], (string) $in['secret'])) {
        http_response_code(403);
        echo json_encode(['handled' => false, 'error' => 'forbidden']);
        exit;
    }
    $reply = dewaHandleIncoming($con, $in['from'] ?? '', $in['kind'] ?? '', $in['payload'] ?? '', $in['text'] ?? '');
    echo json_encode(['handled' => true, 'reply' => $reply]);
    exit;
}
