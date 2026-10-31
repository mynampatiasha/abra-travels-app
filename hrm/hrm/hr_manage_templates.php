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

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');

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
if (!$con) die('Database connection failed: ' . mysqli_connect_error());

mysqli_set_charset($con, 'utf8mb4');
date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');
isUser();

$current_page   = basename($_SERVER['PHP_SELF']);
$currentUser    = isset($_SESSION['user_name'])  ? trim($_SESSION['user_name'])  : 'HR';
$companyName    = isset($_SESSION['ge_cname'])   ? trim($_SESSION['ge_cname'])   : 'Company';

// =========================================================================
// AUTO-CREATE TABLES (Only the templates table here for safety)
// =========================================================================
mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_message_templates (
    id          INT(11) AUTO_INCREMENT PRIMARY KEY,
    title       VARCHAR(255) NOT NULL,
    statuses    VARCHAR(500) DEFAULT 'General',
    body        TEXT NOT NULL,
    created_by  VARCHAR(255) DEFAULT '',
    created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// SEED EXAMPLE TEMPLATE IF EMPTY
$check_tpl = mysqli_query($con, "SELECT id FROM hr_message_templates LIMIT 1");
if ($check_tpl && mysqli_num_rows($check_tpl) == 0) {
    $seed_title = mysqli_real_escape_string($con, "Interview Scheduled Reminder");
    $seed_statuses = mysqli_real_escape_string($con, "Scheduled");
    $seed_body = mysqli_real_escape_string($con, "Hi {name},\n\nGreetings from {company}!\n\nThis is a friendly reminder that your interview for the {position} role in our {department} department is confirmed.\n\n📅 Date: {date}\n⏰ Time: {time}\n\nPlease ensure you are available at the scheduled time. If you need to reschedule or have any questions, you can reach out to us at {phone}. \n\nWe look forward to speaking with you!\n\nBest regards,\n{sender}\nHR Team, {company}");
    mysqli_query($con, "INSERT INTO hr_message_templates (title, statuses, body, created_by) VALUES ('$seed_title', '$seed_statuses', '$seed_body', 'System')");
}

$all_statuses = ['New','Called','Interested','Not Interested','Candidate did not answer the call','Candidate disconnected the call','Call Later','Callback','Scheduled','Follow Up','Round 1','Round 2','Round 3','Round 4','Round 5','No Response','Rejected','Hired'];
$status_colors = [
    'New'           => '#6366f1',
    'Called'        => '#3b82f6',
    'Interested'    => '#10b981',
    'Not Interested'=> '#ef4444',
    'Candidate did not answer the call'   => '#fb923c',
    'Candidate disconnected the call'=> '#e11d48',
    'Call Later'    => '#f59e0b',
    'Callback'      => '#f97316',
    'Scheduled'     => '#8b5cf6',
    'Follow Up'     => '#06b6d4',
    'Round 1'       => '#0ea5e9',
    'Round 2'       => '#3b82f6',
    'Round 3'       => '#6366f1',
    'Round 4'       => '#8b5cf6',
    'Round 5'       => '#a855f7',
    'No Response'   => '#94a3b8',
    'Rejected'      => '#dc2626',
    'Hired'         => '#059669',
];

// =========================================================================
// AJAX: GET MESSAGE TEMPLATES
// =========================================================================
if (isset($_GET['get_templates'])) {
    header('Content-Type: application/json');
    $rows = [];
    $q = mysqli_query($con, "SELECT * FROM hr_message_templates ORDER BY title ASC");
    if ($q) while ($r = mysqli_fetch_assoc($q)) {
        $r['statuses'] = array_values(array_filter(array_map('trim', explode(',', $r['statuses']))));
        $rows[] = $r;
    }
    echo json_encode($rows); exit;
}

// =========================================================================
// POST: SAVE MESSAGE TEMPLATE (add or edit)
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'save_template') {
    header('Content-Type: application/json');
    $tid       = intval($_POST['id'] ?? 0);
    $title     = trim($_POST['title'] ?? '');
    $body      = trim($_POST['body'] ?? '');
    $statuses  = isset($_POST['statuses']) && is_array($_POST['statuses']) ? $_POST['statuses'] : [];
    if (empty($statuses)) $statuses = ['General'];
    $statuses_str = mysqli_real_escape_string($con, implode(',', $statuses));
    $title_esc = mysqli_real_escape_string($con, $title);
    $body_esc  = mysqli_real_escape_string($con, $body);
    $by_esc    = mysqli_real_escape_string($con, $currentUser);

    if ($title === '' || $body === '') {
        echo json_encode(['success' => false, 'error' => 'Title and message body are required.']); exit;
    }

    if ($tid > 0) {
        mysqli_query($con, "UPDATE hr_message_templates SET title='$title_esc', statuses='$statuses_str', body='$body_esc' WHERE id=$tid");
    } else {
        mysqli_query($con, "INSERT INTO hr_message_templates (title, statuses, body, created_by) VALUES ('$title_esc','$statuses_str','$body_esc','$by_esc')");
        $tid = mysqli_insert_id($con);
    }
    echo json_encode(['success' => true, 'id' => $tid]); exit;
}

// =========================================================================
// POST: DELETE MESSAGE TEMPLATE
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'delete_template') {
    header('Content-Type: application/json');
    $tid = intval($_POST['id'] ?? 0);
    mysqli_query($con, "DELETE FROM hr_message_templates WHERE id=$tid");
    echo json_encode(['success' => true]); exit;
}

?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title><?php echo htmlspecialchars($companyName); ?> | Manage Message Templates</title>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/jquery.dataTables.min.css"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet"/>
<style>
:root {
    --primary:    #1e3a8a;
    --primary-lt: #1e40af;
    --accent:     #6366f1;
    --success:    #10b981;
    --danger:     #ef4444;
    --warning:    #f59e0b;
    --bg:         #f1f5f9;
    --card:       #ffffff;
    --border:     #e2e8f0;
    --text:       #1e293b;
    --muted:      #64748b;
}

* { margin:0; padding:0; box-sizing:border-box; }
body { font-family:'Inter',sans-serif; background:var(--bg); min-height:100vh; color:var(--text); }

/* ── Layout ── */
.page-wrap { max-width:1600px; margin:0 auto; padding:24px 20px; }

/* ── Header ── */
.page-header {
    background: linear-gradient(135deg, var(--primary) 0%, var(--primary-lt) 100%);
    padding:22px 30px; border-radius:14px;
    box-shadow:0 4px 20px rgba(30,58,138,.25);
    display:flex; justify-content:space-between; align-items:center;
    margin-bottom:22px;
}
.page-header h1 { color:#fff; font-weight:700; font-size:1.6rem; margin:0; }
.page-header .back-btn {
    background:rgba(255,255,255,.15); color:#fff; border:2px solid rgba(255,255,255,.3);
    padding:9px 20px; border-radius:9px; font-weight:600; text-decoration:none;
    transition:.2s;
}
.page-header .back-btn:hover { background:rgba(255,255,255,.25); color:#fff; text-decoration:none; }

.card-ct {
    background:var(--card); border:1px solid var(--border);
    border-radius:12px; box-shadow:0 4px 15px rgba(0,0,0,.03);
    padding:24px; margin-bottom:24px;
}
.btn-primary-custom {
    background:linear-gradient(135deg,var(--accent),#4f46e5); color:#fff;
    border:none; padding:10px 22px; border-radius:9px; font-weight:600; font-size:14px;
    transition:.2s; box-shadow:0 4px 12px rgba(99,102,241,.2); cursor:pointer;
    display:inline-flex; align-items:center; gap:8px;
}
.btn-primary-custom:hover { transform:translateY(-1px); box-shadow:0 6px 16px rgba(99,102,241,.3); color:#fff; text-decoration:none; }

.act-btn {
    border:none; background:transparent; width:32px; height:32px;
    border-radius:8px; display:inline-flex; align-items:center; justify-content:center;
    font-size:13px; cursor:pointer; transition:.15s; margin-right:4px;
}
.act-edit { color:#3b82f6; background:#eff6ff; }
.act-edit:hover { background:#dbeafe; }
.act-del { color:#ef4444; background:#fef2f2; }
.act-del:hover { background:#fee2e2; }

/* Table overrides */
.table th { border-top:none; border-bottom:2px solid var(--border); font-weight:600; color:var(--muted); font-size:13px; text-transform:uppercase; letter-spacing:0.5px; }
.table td { vertical-align:middle; border-bottom:1px solid var(--border); padding:16px 12px; }
</style>
</head>
<body>
<div class="page-wrap">
    <div class="page-header">
        <h1><i class="fas fa-comment-dots mr-3"></i>Manage Message Templates</h1>
        <a href="hr_candidate_tracking.php" class="back-btn"><i class="fas fa-arrow-left mr-2"></i> Back to Tracking</a>
    </div>
    
    <div class="card-ct">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px;">
            <h4 style="margin:0; font-weight:700; color:var(--primary);">Existing Templates</h4>
            <button class="btn-primary-custom" onclick="openTemplateForm()"><i class="fas fa-plus"></i> Add New Template</button>
        </div>
        
        <table id="templatesTable" class="table table-hover" style="width:100%">
            <thead>
                <tr>
                    <th style="width: 25%">Template Title</th>
                    <th style="width: 20%">Applies To Status(es)</th>
                    <th style="width: 45%">Message Preview</th>
                    <th style="width: 10%">Actions</th>
                </tr>
            </thead>
            <tbody id="tplManageList">
                <!-- Data populated by JS -->
            </tbody>
        </table>
    </div>
</div>

<!-- =====================================================================
     MODAL: TEMPLATE FORM
===================================================================== -->
<div class="modal fade" id="templateFormModal" tabindex="-1">
<div class="modal-dialog modal-lg">
<div class="modal-content">
    <div class="modal-header" style="background:linear-gradient(135deg,#f59e0b,#d97706);">
        <h5 class="modal-title" style="color:#fff;" id="templateFormTitle"><i class="fas fa-comment-dots mr-2"></i>Add Template</h5>
        <button type="button" class="close" data-dismiss="modal" style="color:#fff;">&times;</button>
    </div>
    <div class="modal-body">
        <div style="background:#f8fafc;border:2px solid var(--border);border-radius:10px;padding:16px;">
            <input type="hidden" id="tpl_edit_id" value="">
            <div class="mb-3">
                <label class="form-label font-weight-bold">Template Title <span class="text-danger">*</span></label>
                <input type="text" id="tpl_title" class="form-control" placeholder="e.g. Interview Reminder">
            </div>
            <div class="mb-3">
                <label class="form-label font-weight-bold">Applies To Status(es) <small class="text-muted">(select one or more, or leave as General)</small></label>
                <div id="tpl_status_checks" style="display:flex;flex-wrap:wrap;gap:8px 14px;max-height:110px;overflow-y:auto;padding:12px;border:1px solid var(--border);border-radius:8px;background:#fff;"></div>
            </div>
            <div class="mb-3">
                <label class="form-label font-weight-bold">Message Body <span class="text-danger">*</span></label>
                <textarea id="tpl_body" class="form-control" rows="8" placeholder="Hi {name}, your interview for {position} at {company} is scheduled on {date} at {time}..."></textarea>
                <small style="color:var(--muted);font-size:12px;display:block;margin-top:8px;">
                    Available placeholders: <code>{name}</code> <code>{position}</code> <code>{department}</code> <code>{company}</code> <code>{date}</code> <code>{time}</code> <code>{phone}</code> <code>{sender}</code>
                </small>
            </div>
        </div>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
        <button type="button" class="btn-primary-custom" id="tpl_save_btn" onclick="saveTemplate()"><i class="fas fa-save mr-1"></i> Save Template</button>
    </div>
</div></div></div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
<script>
var ALL_STATUSES     = <?php echo json_encode($all_statuses); ?>;
var STATUS_COLORS    = <?php echo json_encode($status_colors); ?>;
var _templatesCache  = [];
var _table           = null;

function escHtml(unsafe) {
    if (!unsafe) return '';
    return String(unsafe)
         .replace(/&/g, "&amp;")
         .replace(/</g, "&lt;")
         .replace(/>/g, "&gt;")
         .replace(/"/g, "&quot;")
         .replace(/'/g, "&#039;");
}

function loadTemplates() {
    fetch('<?php echo $current_page; ?>?get_templates=1')
        .then(function(r) { return r.json(); })
        .then(function(data) {
            _templatesCache = data;
            renderTable();
        });
}

function renderTable() {
    if (_table) {
        _table.destroy();
    }
    
    var tbody = document.getElementById('tplManageList');
    var html = '';
    
    _templatesCache.forEach(function(t) {
        var badges = t.statuses.map(function(s) {
            var c = STATUS_COLORS[s] || '#6366f1';
            return '<span style="background:' + c + ';color:#fff;font-size:10.5px;font-weight:700;padding:3px 8px;border-radius:10px;margin:2px;display:inline-block;">' + escHtml(s) + '</span>';
        }).join('');
        
        var preview = t.body.length > 150 ? t.body.substring(0,150) + '...' : t.body;
        
        html += '<tr>' +
            '<td style="font-weight:600;color:var(--primary);">' + escHtml(t.title) + '</td>' +
            '<td>' + badges + '</td>' +
            '<td style="font-size:13px;white-space:pre-wrap;color:var(--text);">' + escHtml(preview) + '</td>' +
            '<td style="white-space:nowrap;">' +
            '<button class="act-btn act-edit" title="Edit" onclick=\'editTemplate(' + t.id + ')\'><i class="fas fa-edit"></i></button>' +
            '<button class="act-btn act-del" title="Delete" onclick=\'deleteTemplate(' + t.id + ', "' + escHtml(t.title).replace(/"/g,'&quot;') + '")\'><i class="fas fa-trash"></i></button>' +
            '</td>' +
            '</tr>';
    });
    
    tbody.innerHTML = html;
    
    _table = $('#templatesTable').DataTable({
        pageLength: 25,
        order: [[0, 'asc']],
        language: { search: "", searchPlaceholder: "Search templates..." }
    });
    $('.dataTables_filter input').addClass('form-control').css('display', 'inline-block').css('width', 'auto');
}

function buildStatusChecks(selectedList) {
    selectedList = selectedList || [];
    var wrap = document.getElementById('tpl_status_checks');
    var opts = ['General'].concat(ALL_STATUSES);
    wrap.innerHTML = opts.map(function(s) {
        var checked = selectedList.indexOf(s) !== -1 ? 'checked' : '';
        var id = 'tplstat_' + s.replace(/[^a-zA-Z0-9]/g,'_');
        return '<label style="font-size:13px;font-weight:500;display:flex;align-items:center;gap:6px;cursor:pointer;">' +
            '<input type="checkbox" value="' + escHtml(s) + '" ' + checked + ' id="' + id + '"> ' + escHtml(s) +
            '</label>';
    }).join('');
}

function getCheckedStatuses() {
    return Array.from(document.querySelectorAll('#tpl_status_checks input[type=checkbox]:checked')).map(function(i){ return i.value; });
}

function openTemplateForm() {
    document.getElementById('templateFormTitle').innerHTML = '<i class="fas fa-plus mr-2"></i>Add Template';
    document.getElementById('tpl_edit_id').value = '';
    document.getElementById('tpl_title').value = '';
    document.getElementById('tpl_body').value = '';
    buildStatusChecks(['General']);
    $('#templateFormModal').modal('show');
}

function editTemplate(id) {
    var tpl = _templatesCache.find(function(t) { return t.id == id; });
    if (!tpl) return;
    
    document.getElementById('templateFormTitle').innerHTML = '<i class="fas fa-edit mr-2"></i>Edit Template';
    document.getElementById('tpl_edit_id').value = tpl.id;
    document.getElementById('tpl_title').value = tpl.title;
    document.getElementById('tpl_body').value = tpl.body;
    buildStatusChecks(tpl.statuses);
    $('#templateFormModal').modal('show');
}

function saveTemplate() {
    var id     = document.getElementById('tpl_edit_id').value;
    var title  = document.getElementById('tpl_title').value.trim();
    var body   = document.getElementById('tpl_body').value.trim();
    var statuses = getCheckedStatuses();
    
    if (!title || !body) { alert('Title and message body are required.'); return; }

    var fd = new FormData();
    fd.append('action', 'save_template');
    if (id) fd.append('id', id);
    fd.append('title', title);
    fd.append('body', body);
    if (!statuses.length) statuses = ['General'];
    statuses.forEach(function(s) { fd.append('statuses[]', s); });

    var btn = document.getElementById('tpl_save_btn');
    var originalHtml = btn.innerHTML;
    btn.innerHTML = 'Saving...';
    btn.disabled = true;

    fetch('<?php echo $current_page; ?>', { method: 'POST', body: fd })
        .then(function(r) { return r.json(); })
        .then(function(res) {
            btn.innerHTML = originalHtml;
            btn.disabled = false;
            
            if (res.success) {
                $('#templateFormModal').modal('hide');
                loadTemplates();
            } else {
                alert(res.error || 'Failed to save template.');
            }
        });
}

function deleteTemplate(id, title) {
    if (!confirm('Are you sure you want to delete the template "' + title + '"?')) return;
    
    var fd = new FormData();
    fd.append('action', 'delete_template');
    fd.append('id', id);
    
    fetch('<?php echo $current_page; ?>', { method: 'POST', body: fd })
        .then(function(r) { return r.json(); })
        .then(function(res) {
            if (res.success) {
                loadTemplates();
            }
        });
}

$(document).ready(function() {
    loadTemplates();
});
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
