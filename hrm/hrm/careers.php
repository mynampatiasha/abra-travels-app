<?php
if (!headers_sent()) { header('Content-Type: text/html; charset=utf-8'); }
// ============================================================
// ABRA TRAVELS — CAREERS PAGE  (career.php)
// Live jobs from career_jobs table · Submits to career_submit.php
// ============================================================
require_once('database.php');
require_once('library.php');

$con = null;
if (function_exists('conexion'))          $con = conexion();
elseif (isset($dbConn))                   $con = $dbConn;
elseif (function_exists('dbConnection')) $con = dbConnection();

$live_jobs = [];
if ($con) {
    mysqli_set_charset($con, 'utf8mb4');
    // Ensure tables exist
    mysqli_query($con, "CREATE TABLE IF NOT EXISTS `career_jobs` (
        `id` int(11) NOT NULL AUTO_INCREMENT,
        `title` varchar(200) NOT NULL,
        `department` varchar(100) DEFAULT NULL,
        `location` varchar(100) DEFAULT NULL,
        `job_type` varchar(50) DEFAULT 'Full Time',
        `experience` varchar(100) DEFAULT NULL,
        `salary_range` varchar(100) DEFAULT NULL,
        `description` text DEFAULT NULL,
        `requirements` text DEFAULT NULL,
        `responsibilities` text DEFAULT NULL,
        `skills_required` text DEFAULT NULL,
        `vacancies` int(11) DEFAULT 1,
        `deadline` date DEFAULT NULL,
        `status` varchar(20) DEFAULT 'active',
        `posted_by` varchar(200) DEFAULT NULL,
        `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
        `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $r = mysqli_query($con, "SELECT * FROM career_jobs WHERE status='active' ORDER BY created_at DESC");
    if ($r) while ($row = mysqli_fetch_assoc($r)) $live_jobs[] = $row;
}

$dept_icons = ['Sales'=>'fa-headset','Operations'=>'fa-map-location-dot','Marketing'=>'fa-bullhorn',
    'Logistics'=>'fa-truck','Support'=>'fa-phone-volume','Finance'=>'fa-coins',
    'HR'=>'fa-users','IT'=>'fa-laptop-code','General'=>'fa-circle-plus'];

$depts = [];
foreach ($live_jobs as $j) {
    $d = trim($j['department'] ?? '');
    if ($d && !in_array($d, $depts)) $depts[] = $d;
}
?>
<?php include('includes/html_codes.php'); way_top(); ?>
<title>Careers — Abra Tours &amp; Travels</title>
<meta name="description" content="Join the Abra Travels family. Browse open positions and apply online.">
<?php head_nav(); ?>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/swiper@11/swiper-bundle.min.css"/>
<style>
*,*::before,*::after{box-sizing:border-box}
body,h1,h2,h3,h4,h5,h6,p,span,a,td,th,label,input,select,textarea,button,small,li,div{font-family:'Poppins',sans-serif!important}

/* ── HERO ── */
.cr-hero{background:linear-gradient(135deg,#0f172a 0%,#1e3a8a 55%,#1e40af 100%);padding:80px 0 65px;position:relative;overflow:hidden}
.cr-hero::before{content:'';position:absolute;top:-30%;right:-8%;width:520px;height:520px;border-radius:50%;background:rgba(255,255,255,.05);pointer-events:none}
.cr-hero::after{content:'';position:absolute;bottom:-20%;left:-5%;width:300px;height:300px;border-radius:50%;background:rgba(255,255,255,.04);pointer-events:none}
.cr-hero-content{position:relative;z-index:2;text-align:center}
.cr-hero-badge{display:inline-block;background:rgba(255,255,255,.13);border:1px solid rgba(255,255,255,.25);color:#93c5fd;padding:7px 20px;border-radius:50px;font-size:13px;font-weight:700;margin-bottom:18px}
.cr-hero h1{color:#fff;font-size:2.6rem;font-weight:900;margin-bottom:14px;line-height:1.2}
.cr-hero p{color:rgba(255,255,255,.8);font-size:1.05rem;max-width:560px;margin:0 auto 28px}
.hero-btns{display:flex;gap:14px;justify-content:center;flex-wrap:wrap;margin-bottom:20px}
.btn-hp{background:linear-gradient(135deg,#3b82f6,#1e40af);color:#fff!important;padding:14px 32px;border-radius:12px;font-size:15px;font-weight:800;text-decoration:none!important;display:inline-flex;align-items:center;gap:9px;box-shadow:0 8px 25px rgba(59,130,246,.4);transition:.25s;border:none;cursor:pointer}
.btn-hp:hover{transform:translateY(-2px);box-shadow:0 14px 35px rgba(59,130,246,.5);color:#fff!important}
.btn-hs{background:rgba(255,255,255,.12);color:#fff!important;padding:14px 26px;border-radius:12px;font-size:15px;font-weight:700;text-decoration:none!important;display:inline-flex;align-items:center;gap:8px;border:1.5px solid rgba(255,255,255,.3);transition:.2s}
.btn-hs:hover{background:rgba(255,255,255,.22);color:#fff!important}
.hero-count{color:rgba(255,255,255,.6);font-size:13.5px;font-weight:600}
.hero-count strong{color:#86efac}

/* ── SECTION HEADER ── */
.cr-sec{text-align:center;margin-bottom:36px}
.cr-badge{font-size:.72rem;font-weight:800;color:#1e40af;text-transform:uppercase;letter-spacing:1.6px;display:block;margin-bottom:8px}
.cr-sec h2{font-size:1.7rem;font-weight:900;color:#1e293b;margin-bottom:8px}
.cr-sec p{color:#64748b;font-size:14.5px}

/* ── JOBS SECTION ── */
.cr-jobs{background:#fff;padding:60px 0 50px}

/* Dept filter tabs */
.dtabs{display:flex;flex-wrap:wrap;gap:8px;justify-content:center;margin-bottom:30px}
.dtab{background:#f8fafc;border:2px solid #e2e8f0;color:#64748b;padding:7px 18px;border-radius:50px;font-size:13px;font-weight:700;cursor:pointer;transition:.2s}
.dtab:hover,.dtab.active{background:#eff6ff;border-color:#1e3a8a;color:#1e3a8a}

/* Job grid */
.jobs-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(320px,1fr));gap:22px}
.job-card{background:#fff;border-radius:18px;border:2px solid #e2e8f0;box-shadow:0 2px 14px rgba(0,0,0,.06);transition:all .25s;overflow:hidden;display:flex;flex-direction:column;position:relative}
.job-card:hover{border-color:#1e3a8a;box-shadow:0 10px 32px rgba(30,58,138,.15);transform:translateY(-4px)}
.job-card-top{background:linear-gradient(135deg,#eff6ff,#dbeafe);padding:20px 22px 16px;border-bottom:2px solid #dbeafe}
.jc-icon{width:50px;height:50px;background:linear-gradient(135deg,#1e3a8a,#3b82f6);border-radius:14px;display:flex;align-items:center;justify-content:center;font-size:20px;color:#fff;margin-bottom:14px}
.job-card h4{font-size:16px;font-weight:900;color:#1e293b;margin-bottom:10px}
.jc-tags{display:flex;flex-wrap:wrap;gap:6px}
.jt{padding:3px 11px;border-radius:20px;font-size:11.5px;font-weight:700;display:inline-flex;align-items:center;gap:4px}
.jt-d{background:#eff6ff;color:#1e40af;border:1.5px solid #bfdbfe}
.jt-t{background:#f0fdf4;color:#16a34a;border:1.5px solid #86efac}
.jt-l{background:#f8fafc;color:#475569;border:1.5px solid #e2e8f0}
.jt-e{background:#fef3c7;color:#92400e;border:1.5px solid #fcd34d}
.jt-hot{background:#fef2f2;color:#dc2626;border:1.5px solid #fecaca}
.job-card-body{padding:18px 22px;flex:1;display:flex;flex-direction:column}
.jc-desc{font-size:13.5px;color:#64748b;line-height:1.7;margin-bottom:14px;flex:1;display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}
.jc-meta{display:flex;flex-wrap:wrap;gap:10px;margin-bottom:14px}
.jc-meta span{font-size:12.5px;color:#94a3b8;font-weight:600;display:flex;align-items:center;gap:5px}
.jc-skills{display:flex;flex-wrap:wrap;gap:5px;margin-bottom:14px}
.jc-skill{background:#f1f5f9;border:1.5px solid #e2e8f0;color:#475569;padding:2px 9px;border-radius:5px;font-size:11.5px;font-weight:700}
.vac-badge{position:absolute;top:14px;right:14px;background:#1e3a8a;color:#fff;padding:3px 10px;border-radius:20px;font-size:11px;font-weight:800}
.btn-view-job{background:linear-gradient(135deg,#1e3a8a,#1e40af);color:#fff!important;padding:11px 20px;border-radius:10px;font-size:13.5px;font-weight:800;text-decoration:none;display:flex;align-items:center;justify-content:center;gap:7px;border:none;cursor:pointer;transition:.2s;width:100%}
.btn-view-job:hover{background:linear-gradient(135deg,#1e40af,#2563eb);transform:translateY(-1px)}
.no-jobs{text-align:center;padding:80px 30px;color:#94a3b8;grid-column:1/-1}
.no-jobs i{font-size:52px;opacity:.2;display:block;margin-bottom:16px}
.no-jobs h4{font-size:18px;font-weight:800;color:#64748b;margin-bottom:8px}

/* ── WHY JOIN (LIGHT) ── */
.cr-why{background:#f8fafc;padding:60px 0 50px;border-top:2px solid #e2e8f0}
.why-swiper{overflow:hidden;padding-bottom:44px!important}
.why-swiper .swiper-wrapper{align-items:stretch}
.why-card{background:#fff;border-radius:20px;overflow:hidden;border:2px solid #e2e8f0;height:100%;display:flex;flex-direction:column;transition:border-color .25s,transform .25s,box-shadow .25s}
.why-card:hover{border-color:#1e3a8a;transform:translateY(-5px);box-shadow:0 12px 32px rgba(30,58,138,.13)}
.why-img-wrap{position:relative;overflow:hidden}
.why-img{width:100%;height:200px;object-fit:cover;display:block;filter:brightness(.9);transition:filter .3s,transform .4s}
.why-card:hover .why-img{filter:brightness(1);transform:scale(1.04)}
.why-img-wrap::after{content:'';position:absolute;bottom:0;left:0;right:0;height:60px;background:linear-gradient(to top,#fff,transparent);pointer-events:none}
.why-body{padding:18px 22px 22px;flex:1;display:flex;flex-direction:column}
.why-icon{width:44px;height:44px;background:linear-gradient(135deg,#1e3a8a,#3b82f6);border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:18px;color:#fff;margin-bottom:12px}
.why-body h5{font-size:15px;font-weight:800;color:#1e293b;margin-bottom:7px}
.why-body p{font-size:13px;color:#64748b;margin:0;line-height:1.65}
.why-swiper .swiper-pagination{bottom:8px}
.why-swiper .swiper-pagination-bullet{background:#bfdbfe;opacity:1;width:8px;height:8px}
.why-swiper .swiper-pagination-bullet-active{background:#1e3a8a;width:24px;border-radius:4px}
.why-nav{display:flex;gap:10px;justify-content:flex-end;margin-top:14px}
.why-nav-btn{width:38px;height:38px;background:#eff6ff;border:2px solid #bfdbfe;border-radius:50%;color:#1e3a8a;font-size:13px;cursor:pointer;display:flex;align-items:center;justify-content:center;transition:.2s}
.why-nav-btn:hover{background:#1e3a8a;border-color:#1e3a8a;color:#fff}

/* ── FORM AREA ── */
.cr-form-wrap{background:#f8fafc;padding:50px 0 70px}
.cr-form-inner{max-width:960px;margin:0 auto}
.cr-card{background:#fff;border-radius:20px;box-shadow:0 4px 24px rgba(0,0,0,.08);overflow:hidden;margin-bottom:22px}
.cr-card-hdr{background:linear-gradient(135deg,#eff6ff,#dbeafe);padding:18px 26px;border-bottom:2px solid #bfdbfe;display:flex;align-items:center;gap:14px}
.cr-card-icon{width:46px;height:46px;background:linear-gradient(135deg,#1e3a8a,#3b82f6);border-radius:12px;display:flex;align-items:center;justify-content:center;color:#fff;font-size:20px;flex-shrink:0}
.cr-card-hdr h3{font-size:1.05rem;font-weight:800;color:#1e3a8a;margin:0 0 2px}
.cr-card-hdr p{font-size:12.5px;color:#3b82f6;margin:0;font-weight:600}
.cr-card-body{padding:26px 28px}
.cr-lbl{font-size:13px;font-weight:700;color:#334155;margin-bottom:7px;display:block}
.req{color:#dc2626}.opt{font-size:10.5px;font-weight:700;color:#64748b;background:#f1f5f9;padding:2px 8px;border-radius:5px;margin-left:6px;vertical-align:middle}
.cr-inp{border:2px solid #e2e8f0;border-radius:10px;padding:10px 14px;font-size:14px;height:48px;color:#1e293b;width:100%;transition:border-color .2s;background:#fff}
.cr-inp:focus{border-color:#1e3a8a;outline:none;box-shadow:0 0 0 3px rgba(30,58,138,.1)}
.cr-inp::placeholder{color:#94a3b8}
textarea.cr-inp{height:auto;min-height:100px;resize:vertical}
select.cr-inp{-webkit-appearance:auto}
.ctc-row{display:flex;gap:10px;align-items:center}
.ctc-row .cr-inp{flex:1}
.ctc-sep{color:#94a3b8;font-weight:700;font-size:16px;flex-shrink:0}
.notice-pills{display:flex;flex-wrap:wrap;gap:8px}
.np{background:#f8fafc;border:2px solid #e2e8f0;color:#64748b;padding:8px 16px;border-radius:50px;font-size:13px;font-weight:700;cursor:pointer;transition:.2s}
.np:hover,.np.sel{background:#eff6ff;border-color:#1e3a8a;color:#1e3a8a}
.file-zone{border:2.5px dashed #bfdbfe;border-radius:14px;padding:28px 20px;text-align:center;cursor:pointer;transition:all .2s;background:#fafcff;position:relative}
.file-zone:hover,.file-zone.over{border-color:#1e3a8a;background:#eff6ff}
.file-zone input[type=file]{position:absolute;inset:0;opacity:0;cursor:pointer;width:100%;height:100%}
.fz-icon{font-size:36px;color:#93c5fd;margin-bottom:10px}
.fz-title{font-size:14px;font-weight:800;color:#1e3a8a;margin-bottom:4px}
.fz-sub{font-size:12.5px;color:#64748b;margin:0}
.file-chosen{background:#eff6ff;border:2px solid #bfdbfe;border-radius:9px;padding:9px 14px;margin-top:12px;font-size:13px;font-weight:700;color:#1e3a8a;display:none;align-items:center;gap:8px}
.file-chosen.show{display:flex}
.skills-wrap{border:2px solid #e2e8f0;border-radius:10px;padding:8px 12px;min-height:48px;display:flex;flex-wrap:wrap;gap:6px;align-items:center;cursor:text}
.skills-wrap:focus-within{border-color:#1e3a8a;box-shadow:0 0 0 3px rgba(30,58,138,.1)}
.sk-tag{background:#eff6ff;border:1.5px solid #bfdbfe;color:#1e40af;padding:4px 10px;border-radius:6px;font-size:12.5px;font-weight:700;display:flex;align-items:center;gap:5px}
.sk-del{cursor:pointer;font-size:11px;color:#94a3b8}.sk-del:hover{color:#dc2626}
.sk-inp{border:none;outline:none;font-size:13.5px;color:#1e293b;min-width:120px;flex:1;background:transparent}
.sk-hint{font-size:12px;color:#94a3b8;margin-top:5px}
.sk-suggestions{position:absolute;z-index:999;background:#fff;border:2px solid #bfdbfe;border-radius:9px;padding:4px 0;min-width:200px;box-shadow:0 8px 24px rgba(0,0,0,.1);display:none}
.sk-sug-item{padding:8px 14px;font-size:13.5px;cursor:pointer;color:#334155}
.sk-sug-item:hover{background:#eff6ff}

/* Selected job banner */
.sel-job-banner{background:linear-gradient(135deg,#eff6ff,#dbeafe);border:2px solid #bfdbfe;border-radius:14px;padding:14px 20px;margin-bottom:22px;display:flex;align-items:center;gap:14px;flex-wrap:wrap}
.sjb-icon{font-size:22px;color:#1e40af;flex-shrink:0}
.sjb-text{flex:1}
.sjb-title{font-size:14.5px;font-weight:800;color:#1e293b}
.sjb-dept{font-size:12.5px;color:#3b82f6;font-weight:600}
.sjb-clear{background:none;border:none;color:#94a3b8;cursor:pointer;font-size:18px;padding:4px;transition:.15s}
.sjb-clear:hover{color:#dc2626}

/* Submit */
.cr-submit-box{background:linear-gradient(135deg,#0f172a,#1e3a8a);border-radius:20px;padding:38px;text-align:center}
.cr-submit-box h3{color:#fff;font-size:1.3rem;font-weight:800;margin-bottom:8px}
.cr-submit-box p{color:rgba(255,255,255,.7);font-size:14px;margin-bottom:24px}
.btn-submit{background:linear-gradient(135deg,#3b82f6,#1e40af);color:#fff;border:none;border-radius:13px;padding:16px 44px;font-size:16px;font-weight:900;cursor:pointer;display:inline-flex;align-items:center;gap:10px;box-shadow:0 8px 25px rgba(59,130,246,.4);transition:all .25s}
.btn-submit:hover{transform:translateY(-2px);box-shadow:0 14px 35px rgba(59,130,246,.5)}
.btn-submit:disabled{opacity:.7;cursor:not-allowed;transform:none}
.sub-error{background:rgba(239,68,68,.15);border:1px solid rgba(239,68,68,.3);border-radius:10px;padding:10px 16px;font-size:13.5px;color:#fca5a5;margin-top:14px;display:none}
.sub-note{color:rgba(255,255,255,.35);font-size:12px;margin-top:12px}

/* Success */
.cr-success{display:none;background:#fff;border-radius:20px;padding:70px 40px;text-align:center;box-shadow:0 4px 30px rgba(0,0,0,.09);max-width:700px;margin:0 auto}
.s-ico{font-size:72px;color:#16a34a;margin-bottom:20px;animation:popIn .4s ease}
@keyframes popIn{from{transform:scale(.6);opacity:0}to{transform:scale(1);opacity:1}}
.cr-success h2{font-size:1.9rem;font-weight:900;color:#1e293b;margin-bottom:10px}
.cr-success p{color:#64748b;font-size:15px;max-width:460px;margin:0 auto 24px}
.ref-box{background:#f0fdf4;border:2px solid #86efac;border-radius:12px;padding:16px 28px;display:inline-block}
.ref-lbl{font-size:12px;color:#64748b;font-weight:700;text-transform:uppercase}
.ref-id{font-size:1.5rem;font-weight:900;color:#16a34a}

/* Job detail modal */
.jd-overlay{position:fixed;inset:0;background:rgba(0,0,0,.6);z-index:9990;display:none;align-items:center;justify-content:center;padding:20px}
.jd-overlay.show{display:flex}
.jd-modal{background:#fff;border-radius:20px;width:720px;max-width:100%;max-height:90vh;overflow-y:auto;box-shadow:0 24px 60px rgba(0,0,0,.25);animation:mIn .3s cubic-bezier(.4,0,.2,1)}
@keyframes mIn{from{transform:scale(.92);opacity:0}to{transform:scale(1);opacity:1}}
.jdm-head{background:linear-gradient(135deg,#1e3a8a,#1e40af);padding:24px 28px;position:sticky;top:0;z-index:2;display:flex;justify-content:space-between;align-items:flex-start}
.jdm-head h3{color:#fff;font-size:1.15rem;font-weight:900;margin:0 0 8px}
.jdm-close{background:rgba(255,255,255,.2);border:none;color:#fff;width:34px;height:34px;border-radius:50%;cursor:pointer;font-size:15px;display:flex;align-items:center;justify-content:center;flex-shrink:0;transition:.15s;margin-top:2px}
.jdm-close:hover{background:rgba(255,255,255,.35)}
.jdm-body{padding:26px 28px 32px}
.jdm-meta{display:grid;grid-template-columns:repeat(2,1fr);gap:12px;margin-bottom:22px}
.jdm-meta-item{background:#f8fafc;border:2px solid #e2e8f0;border-radius:10px;padding:12px 15px}
.jdm-meta-item label{font-size:10.5px;font-weight:800;color:#94a3b8;text-transform:uppercase;letter-spacing:.4px;display:block;margin-bottom:4px}
.jdm-meta-item span{font-size:14px;font-weight:700;color:#1e293b}
.jdm-sec{margin-bottom:20px}
.jdm-sec h4{font-size:13.5px;font-weight:800;color:#1e3a8a;border-bottom:2px solid #e2e8f0;padding-bottom:8px;margin-bottom:12px}
.jdm-sec p,.jdm-sec li{font-size:14px;color:#475569;line-height:1.75}
.jdm-sec ul{padding-left:18px;margin:0}
.jdm-sec ul li{margin-bottom:5px}
.btn-apply-modal{background:linear-gradient(135deg,#1e3a8a,#1e40af);color:#fff!important;padding:14px 32px;border-radius:12px;font-size:15px;font-weight:900;border:none;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:9px;width:100%;transition:.2s;margin-top:4px;text-decoration:none}
.btn-apply-modal:hover{background:linear-gradient(135deg,#1e40af,#2563eb);color:#fff!important}

@media(max-width:768px){
    .cr-hero h1{font-size:1.9rem}
    .jobs-grid{grid-template-columns:1fr}
    .jdm-meta{grid-template-columns:1fr}
    .cr-card-body{padding:18px 16px}
    .ctc-row{flex-direction:column}
    .jd-modal{max-height:95vh}
}
</style>

<!-- HERO -->
<section class="cr-hero">
<div class="container">
<div class="cr-hero-content">
    <div class="cr-hero-badge"><i class="fa-solid fa-briefcase"></i> &nbsp;We're Hiring!</div>
    <h1>Build Your Career with<br>Abra Tours &amp; Travels</h1>
    <p>Join a passionate team dedicated to creating unforgettable travel experiences across India and beyond.</p>
    <div class="hero-btns">
        <a href="#open-jobs" class="btn-hp"><i class="fa-solid fa-magnifying-glass"></i> View Open Positions</a>
        <a href="#apply-now" class="btn-hs"><i class="fa-solid fa-paper-plane"></i> Apply Now</a>
    </div>
    <?php if (count($live_jobs) > 0): ?>
    <div class="hero-count"><strong><?= count($live_jobs) ?></strong> active position<?= count($live_jobs) != 1 ? 's' : '' ?> open right now</div>
    <?php else: ?>
    <div class="hero-count">We're always looking for great talent — send us your application!</div>
    <?php endif; ?>
</div>
</div>
</section>

<!-- LIVE JOB LISTINGS -->
<section class="cr-jobs" id="open-jobs">
<div class="container">
    <div class="cr-sec">
        <span class="cr-badge"><i class="fa-solid fa-briefcase-blank"></i> &nbsp;Current Openings</span>
        <h2>Open Positions</h2>
        <p>Click any role to view the full job description and apply</p>
    </div>

    <?php if (!empty($depts)): ?>
    <div class="dtabs">
        <div class="dtab active" onclick="filterJobs('all',this)">All Departments</div>
        <?php foreach ($depts as $d): ?>
        <div class="dtab" onclick="filterJobs('<?= htmlspecialchars($d) ?>',this)"><?= htmlspecialchars($d) ?></div>
        <?php endforeach; ?>
    </div>
    <?php endif; ?>

    <div class="jobs-grid" id="jobsGrid">
    <?php if (empty($live_jobs)): ?>
        <div class="no-jobs">
            <i class="fa-solid fa-briefcase"></i>
            <h4>No Open Positions Right Now</h4>
            <p>We're always growing — submit a general application below and we'll reach out when the right role opens up.</p>
            <a href="#apply-now" class="btn-hp" style="display:inline-flex;margin-top:18px;"><i class="fa-solid fa-paper-plane"></i> Submit Open Application</a>
        </div>
    <?php else: ?>
    <?php foreach ($live_jobs as $job):
        $ico = $dept_icons[$job['department'] ?? ''] ?? 'fa-briefcase';
        $skarr = array_slice(array_filter(array_map('trim', explode(',', $job['skills_required'] ?? ''))), 0, 4);
        $dl = null; $dl_days = null;
        if (!empty($job['deadline'])) { $dl_days = (int)ceil((strtotime($job['deadline']) - time()) / 86400); }
        $urgent = $dl_days !== null && $dl_days <= 7 && $dl_days >= 0;
    ?>
    <div class="job-card" data-dept="<?= htmlspecialchars($job['department'] ?? '') ?>">
        <?php if (!empty($job['vacancies']) && $job['vacancies'] > 1): ?>
        <span class="vac-badge"><?= $job['vacancies'] ?> vacancies</span>
        <?php endif; ?>
        <div class="job-card-top">
            <div class="jc-icon"><i class="fa-solid <?= $ico ?>"></i></div>
            <h4><?= htmlspecialchars($job['title']) ?></h4>
            <div class="jc-tags">
                <?php if ($job['department']): ?><span class="jt jt-d"><?= htmlspecialchars($job['department']) ?></span><?php endif; ?>
                <?php if ($job['job_type']): ?><span class="jt jt-t"><i class="fa-solid fa-clock"></i><?= htmlspecialchars($job['job_type']) ?></span><?php endif; ?>
                <?php if ($job['location']): ?><span class="jt jt-l"><i class="fa-solid fa-location-dot"></i><?= htmlspecialchars($job['location']) ?></span><?php endif; ?>
                <?php if ($job['experience']): ?><span class="jt jt-e"><i class="fa-solid fa-chart-line"></i><?= htmlspecialchars($job['experience']) ?></span><?php endif; ?>
                <?php if ($urgent): ?><span class="jt jt-hot"><i class="fa-solid fa-fire"></i>Closing soon</span><?php endif; ?>
            </div>
        </div>
        <div class="job-card-body">
            <?php if ($job['description']): ?>
            <p class="jc-desc"><?= htmlspecialchars($job['description']) ?></p>
            <?php endif; ?>
            <div class="jc-meta">
                <?php if ($job['salary_range']): ?><span><i class="fa-solid fa-indian-rupee-sign"></i><?= htmlspecialchars($job['salary_range']) ?></span><?php endif; ?>
                <?php if ($dl_days !== null && $dl_days >= 0): ?>
                <span><i class="fa-solid fa-calendar-xmark"></i><?= $dl_days == 0 ? 'Closes today!' : "Closes in {$dl_days} day".($dl_days!=1?'s':'') ?></span>
                <?php endif; ?>
            </div>
            <?php if ($skarr): ?>
            <div class="jc-skills"><?php foreach ($skarr as $sk): ?><span class="jc-skill"><?= htmlspecialchars($sk) ?></span><?php endforeach; ?></div>
            <?php endif; ?>
            <button class="btn-view-job" onclick="openJob(<?= (int)$job['id'] ?>)"><i class="fa-solid fa-eye"></i> View Details &amp; Apply</button>
        </div>
    </div>
    <?php endforeach; ?>
    <?php endif; ?>
    </div>

    <p style="text-align:center;margin-top:26px;font-size:14px;color:#64748b;font-weight:600;">
        Don't see your role? <a href="#apply-now" style="color:#1e40af;font-weight:800;text-decoration:none;">Submit an open application</a> — we're always looking for great people.
    </p>
</div>
</section>

<!-- WHY JOIN (LIGHT) -->
<section class="cr-why">
<div class="container">
    <div class="cr-sec" style="margin-bottom:28px;">
        <span class="cr-badge"><i class="fa-solid fa-star"></i> &nbsp;Why Abra Travels</span>
        <h2>Why Join Our Team?</h2>
        <p>We invest in our people just as much as our travellers</p>
    </div>
    <div style="position:relative;">
    <div class="swiper why-swiper" id="whySwiper">
    <div class="swiper-wrapper">
        <?php
        $why = [
            ['img'=>'https://images.unsplash.com/photo-1554224155-6726b3ff858f?w=600&q=80&auto=format&fit=crop','icon'=>'fa-indian-rupee-sign','title'=>'Competitive Pay','desc'=>'Market-competitive salaries with performance-based incentives and annual appraisals'],
            ['img'=>'https://images.unsplash.com/photo-1436491865332-7a61a109cc05?w=600&q=80&auto=format&fit=crop','icon'=>'fa-plane-departure','title'=>'Travel Perks','desc'=>'Subsidised travel packages, familiarity trips and discounts for employees and family'],
            ['img'=>'https://images.unsplash.com/photo-1522202176988-66273c2fd55f?w=600&q=80&auto=format&fit=crop','icon'=>'fa-chart-line','title'=>'Growth Path','desc'=>'Clear career ladders with internal promotions, skill training and certification support'],
            ['img'=>'https://images.unsplash.com/photo-1600880292203-757bb62b4baf?w=600&q=80&auto=format&fit=crop','icon'=>'fa-people-group','title'=>'Great Culture','desc'=>'Young, diverse and supportive team with flat hierarchy and open-door leadership'],
            ['img'=>'https://images.unsplash.com/photo-1576091160550-2173dba999ef?w=600&q=80&auto=format&fit=crop','icon'=>'fa-shield-halved','title'=>'Benefits','desc'=>'Health insurance, PF, paid leaves and flexible working arrangements for eligible roles'],
            ['img'=>'https://images.unsplash.com/photo-1524492412937-b28074a5d7da?w=600&q=80&auto=format&fit=crop','icon'=>'fa-location-dot','title'=>'Pan-India Ops','desc'=>'Work across multiple cities — we operate destinations nationwide and internationally'],
        ];
        foreach ($why as $w): ?>
        <div class="swiper-slide" style="height:auto;">
            <div class="why-card">
                <div class="why-img-wrap"><img class="why-img" src="<?= $w['img'] ?>" alt="<?= $w['title'] ?>" loading="lazy"></div>
                <div class="why-body">
                    <div class="why-icon"><i class="fa-solid <?= $w['icon'] ?>"></i></div>
                    <h5><?= $w['title'] ?></h5>
                    <p><?= $w['desc'] ?></p>
                </div>
            </div>
        </div>
        <?php endforeach; ?>
    </div>
    <div class="swiper-pagination"></div>
    </div>
    <div class="why-nav">
        <button class="why-nav-btn" id="whyPrev"><i class="fa-solid fa-chevron-left"></i></button>
        <button class="why-nav-btn" id="whyNext"><i class="fa-solid fa-chevron-right"></i></button>
    </div>
    </div>
</div>
</section>

<!-- APPLICATION FORM -->
<section class="cr-form-wrap" id="apply-now">
<div class="container"><div class="cr-form-inner">

    <!-- SUCCESS -->
    <div class="cr-success" id="crSuccess">
        <div class="s-ico"><i class="fa-solid fa-circle-check"></i></div>
        <h2>Application Submitted!</h2>
        <p>Thank you for applying to Abra Tours &amp; Travels. Our HR team will review and get back to you within <strong>5–7 working days</strong>.</p>
        <div class="ref-box"><div class="ref-lbl">Your Application ID</div><div class="ref-id" id="successId">—</div></div>
        <div style="margin-top:28px;display:flex;gap:12px;justify-content:center;flex-wrap:wrap;">
            <a href="career.php" class="btn-hp" style="text-decoration:none;"><i class="fa-solid fa-arrow-left"></i> Back to Careers</a>
            <a href="index.php" style="background:#16a34a;color:#fff;padding:14px 28px;border-radius:12px;font-size:15px;font-weight:800;text-decoration:none;display:inline-flex;align-items:center;gap:8px;"><i class="fa-solid fa-house"></i> Home</a>
        </div>
    </div>

    <div id="crFormWrap">

        <!-- Selected job banner -->
        <div class="sel-job-banner" id="selJobBanner" style="display:none;">
            <span class="sjb-icon"><i class="fa-solid fa-briefcase"></i></span>
            <div class="sjb-text"><div class="sjb-title" id="sjbTitle">—</div><div class="sjb-dept" id="sjbDept">—</div></div>
            <button class="sjb-clear" onclick="clearJob()" title="Clear"><i class="fa-solid fa-xmark"></i></button>
        </div>

        <!-- STEP 1 -->
        <div class="cr-card">
            <div class="cr-card-hdr"><div class="cr-card-icon"><i class="fa-solid fa-briefcase"></i></div>
            <div><h3>Step 1 — Position Details</h3><p>Which role are you applying for?</p></div></div>
            <div class="cr-card-body"><div class="row">
                <div class="col-md-6"><div class="form-group">
                    <label class="cr-lbl">Position Applied For <span class="req">*</span></label>
                    <input type="text" id="f-position" class="cr-inp" placeholder="e.g. Travel Sales Executive" required>
                </div></div>
                <div class="col-md-6"><div class="form-group">
                    <label class="cr-lbl">Department <span class="req">*</span></label>
                    <select id="f-department" class="cr-inp" required>
                        <option value="">-- Select Department --</option>
                        <option value="Sales">Sales</option><option value="Operations">Operations</option>
                        <option value="Marketing">Marketing</option><option value="Logistics">Logistics</option>
                        <option value="Support">Customer Support</option><option value="Finance">Finance &amp; Accounts</option>
                        <option value="HR">Human Resources</option><option value="IT">IT / Technology</option>
                        <option value="General">General / Other</option>
                    </select>
                </div></div>
                <div class="col-md-6"><div class="form-group mb-0">
                    <label class="cr-lbl">Available / Joining Date <span class="req">*</span></label>
                    <input type="date" id="f-availability" class="cr-inp" min="<?= date('Y-m-d') ?>" required>
                </div></div>
                <div class="col-md-6"><div class="form-group mb-0">
                    <label class="cr-lbl">Notice Period <span class="req">*</span></label>
                    <div class="notice-pills">
                        <div class="np sel" onclick="selNotice('Immediately',this)">Immediately</div>
                        <div class="np" onclick="selNotice('15 Days',this)">15 Days</div>
                        <div class="np" onclick="selNotice('30 Days',this)">30 Days</div>
                        <div class="np" onclick="selNotice('60 Days',this)">60 Days</div>
                        <div class="np" onclick="selNotice('90 Days',this)">90 Days</div>
                    </div>
                    <input type="hidden" id="f-notice" value="Immediately">
                </div></div>
            </div></div>
        </div>

        <!-- STEP 2 -->
        <div class="cr-card">
            <div class="cr-card-hdr"><div class="cr-card-icon"><i class="fa-solid fa-user"></i></div>
            <div><h3>Step 2 — Personal Information</h3><p>Tell us about yourself</p></div></div>
            <div class="cr-card-body"><div class="row">
                <div class="col-md-6"><div class="form-group"><label class="cr-lbl">Full Name <span class="req">*</span></label><input type="text" id="f-name" class="cr-inp" placeholder="e.g. Priya Sharma" required></div></div>
                <div class="col-md-6"><div class="form-group"><label class="cr-lbl">Email Address <span class="req">*</span></label><input type="email" id="f-email" class="cr-inp" placeholder="e.g. priya@gmail.com" required></div></div>
                <div class="col-md-6"><div class="form-group"><label class="cr-lbl">Mobile Number <span class="req">*</span></label><input type="tel" id="f-phone" class="cr-inp" placeholder="9876543210" maxlength="15" required></div></div>
                <div class="col-md-6"><div class="form-group"><label class="cr-lbl">Current City <span class="req">*</span></label><input type="text" id="f-location" class="cr-inp" placeholder="e.g. Bangalore" required></div></div>
                <div class="col-md-6"><div class="form-group"><label class="cr-lbl">LinkedIn Profile <span class="opt">Optional</span></label><input type="url" id="f-linkedin" class="cr-inp" placeholder="https://linkedin.com/in/..."></div></div>
                <div class="col-md-6"><div class="form-group"><label class="cr-lbl">Portfolio / Website <span class="opt">Optional</span></label><input type="url" id="f-portfolio" class="cr-inp" placeholder="https://yourwebsite.com"></div></div>
                <div class="col-md-12"><div class="form-group mb-0"><label class="cr-lbl">How did you hear about us? <span class="opt">Optional</span></label>
                    <select id="f-how-heard" class="cr-inp">
                        <option value="">-- Select --</option><option>LinkedIn</option><option>Naukri.com</option>
                        <option>Indeed</option><option>Company Website</option><option>Employee Referral</option>
                        <option>Social Media</option><option>Job Fair</option><option>Other</option>
                    </select>
                </div></div>
            </div></div>
        </div>

        <!-- STEP 3 -->
        <div class="cr-card">
            <div class="cr-card-hdr"><div class="cr-card-icon"><i class="fa-solid fa-chart-bar"></i></div>
            <div><h3>Step 3 — Professional Background</h3><p>Experience, qualifications and skills</p></div></div>
            <div class="cr-card-body"><div class="row">
                <div class="col-md-4"><div class="form-group"><label class="cr-lbl">Total Experience <span class="req">*</span></label>
                    <select id="f-experience" class="cr-inp" required>
                        <option value="">-- Select --</option>
                        <option>Fresher (0 years)</option><option>Less than 1 year</option>
                        <option>1-2 years</option><option>2-3 years</option><option>3-5 years</option>
                        <option>5-7 years</option><option>7-10 years</option><option>10+ years</option>
                    </select>
                </div></div>
                <div class="col-md-4"><div class="form-group"><label class="cr-lbl">Highest Qualification <span class="req">*</span></label>
                    <select id="f-qualification" class="cr-inp" required>
                        <option value="">-- Select --</option>
                        <option>10th / SSLC</option><option>12th / PUC</option><option>Diploma</option>
                        <option>Bachelor's Degree</option><option>Master's Degree</option>
                        <option>MBA</option><option>PhD</option><option>Other</option>
                    </select>
                </div></div>
                <div class="col-md-4"><div class="form-group"><label class="cr-lbl">Current Company <span class="opt">Optional</span></label><input type="text" id="f-company" class="cr-inp" placeholder="e.g. XYZ Travels Pvt Ltd"></div></div>
                <div class="col-md-12"><div class="form-group"><label class="cr-lbl">Current CTC &amp; Expected CTC (₹ per annum) <span class="opt">Optional</span></label>
                    <div class="ctc-row">
                        <input type="text" id="f-current-ctc" class="cr-inp" placeholder="Current CTC e.g. 3,60,000">
                        <span class="ctc-sep">→</span>
                        <input type="text" id="f-expected-ctc" class="cr-inp" placeholder="Expected CTC e.g. 4,80,000">
                    </div>
                </div></div>
                <div class="col-md-12"><div class="form-group mb-0"><label class="cr-lbl">Key Skills <span class="req">*</span></label>
                    <div style="position:relative;">
                        <div class="skills-wrap" id="skWrap" onclick="document.getElementById('skInp').focus()">
                            <input class="sk-inp" id="skInp" placeholder="Type a skill and press Enter..." onkeydown="skKey(event)" oninput="skSuggest(this.value)">
                        </div>
                        <input type="hidden" id="f-skills">
                        <div class="sk-hint"><i class="fa-solid fa-circle-info"></i> Press <strong>Enter</strong> or <strong>comma</strong> after each skill</div>
                        <div class="sk-suggestions" id="skSug"></div>
                    </div>
                </div></div>
            </div></div>
        </div>

        <!-- STEP 4 -->
        <div class="cr-card">
            <div class="cr-card-hdr"><div class="cr-card-icon"><i class="fa-solid fa-file-arrow-up"></i></div>
            <div><h3>Step 4 — Documents</h3><p>Upload your resume (required) and cover letter (optional)</p></div></div>
            <div class="cr-card-body"><div class="row">
                <div class="col-md-6"><div class="form-group"><label class="cr-lbl">Resume / CV <span class="req">*</span></label>
                    <div class="file-zone" id="resumeZone">
                        <input type="file" id="f-resume" accept=".pdf,.doc,.docx" onchange="showFile('resume',this)">
                        <div class="fz-icon"><i class="fa-solid fa-file-pdf"></i></div>
                        <div class="fz-title">Upload Your Resume</div>
                        <p class="fz-sub">PDF, DOC or DOCX · Max 5 MB</p>
                        <div class="file-chosen" id="resume-chosen"><i class="fa-solid fa-file-circle-check"></i><span id="resume-nm"></span></div>
                    </div>
                </div></div>
                <div class="col-md-6"><div class="form-group"><label class="cr-lbl">Cover Letter <span class="opt">Optional</span></label>
                    <div class="file-zone" id="coverZone">
                        <input type="file" id="f-cover" accept=".pdf,.doc,.docx" onchange="showFile('cover',this)">
                        <div class="fz-icon"><i class="fa-solid fa-envelope-open-text"></i></div>
                        <div class="fz-title">Upload Cover Letter</div>
                        <p class="fz-sub">PDF, DOC or DOCX · Max 5 MB</p>
                        <div class="file-chosen" id="cover-chosen"><i class="fa-solid fa-file-circle-check"></i><span id="cover-nm"></span></div>
                    </div>
                </div></div>
                <div class="col-md-12"><div class="form-group mb-0"><label class="cr-lbl">Message / Cover Note <span class="opt">Optional</span></label>
                    <textarea id="f-message" class="cr-inp" rows="4" placeholder="Tell us why you want to join Abra Travels..."></textarea>
                </div></div>
            </div></div>
        </div>

        <!-- SUBMIT -->
        <div class="cr-submit-box">
            <h3><i class="fa-solid fa-paper-plane" style="margin-right:8px;"></i>Ready to Join Our Team?</h3>
            <p>Our HR team reviews every application within 5–7 working days.</p>
            <button class="btn-submit" id="submitBtn" onclick="doSubmit()"><i class="fa-solid fa-paper-plane"></i> Submit Application</button>
            <div class="sub-error" id="subErr"></div>
            <div class="sub-note">By submitting you agree that Abra Travels may contact you regarding your application.</div>
        </div>

    </div><!-- /crFormWrap -->
</div></div>
</section>

<!-- JOB DETAIL MODAL -->
<div class="jd-overlay" id="jdOverlay" onclick="closeModalBg(event)">
<div class="jd-modal" id="jdModal">
    <div class="jdm-head">
        <div><h3 id="jd-title">Loading…</h3><div id="jd-tags" style="display:flex;flex-wrap:wrap;gap:6px;"></div></div>
        <button class="jdm-close" onclick="closeModal()"><i class="fa-solid fa-xmark"></i></button>
    </div>
    <div class="jdm-body" id="jdBody"><div style="text-align:center;padding:60px;color:#94a3b8;"><i class="fa-solid fa-spinner fa-spin fa-3x"></i></div></div>
</div>
</div>

<?php if (function_exists('footer_section')) footer_section(); ?>

<script src="https://cdn.jsdelivr.net/npm/swiper@11/swiper-bundle.min.js"></script>
<script>
var JOBS = <?= json_encode(array_values($live_jobs)) ?>;
var skills = [], selJobId = null;
var COMMON_SKILLS = ['MS Office','Customer Service','Communication','Team Player','Sales','Excel',
    'Tally','GDS','Amadeus','Tour Planning','Marketing','Social Media','Accounts','CRM',
    'English','Hindi','Leadership','Problem Solving','Data Entry'];

// ── DEPT FILTER ──
function filterJobs(dept, el) {
    document.querySelectorAll('.dtab').forEach(t => t.classList.remove('active'));
    el.classList.add('active');
    document.querySelectorAll('.job-card').forEach(c => {
        c.style.display = (dept === 'all' || c.dataset.dept === dept) ? 'flex' : 'none';
    });
}

// ── JOB MODAL ──
function openJob(id) {
    var j = JOBS.find(x => parseInt(x.id) === id);
    if (!j) return;
    selJobId = id;
    document.getElementById('jdOverlay').classList.add('show');
    document.getElementById('jd-title').textContent = j.title || '';
    // Tags
    var t = '';
    if (j.department) t += badge(j.department);
    if (j.job_type)   t += badge(j.job_type, 'rgba(22,163,74,.25)');
    if (j.location)   t += badge('📍 ' + j.location);
    document.getElementById('jd-tags').innerHTML = t;
    // Body
    var b = '<div class="jdm-meta">';
    if (j.experience)   b += metaItem('Experience Required', j.experience);
    if (j.salary_range) b += metaItem('Salary Range (CTC)', j.salary_range, '#16a34a');
    if (j.job_type)     b += metaItem('Job Type', j.job_type);
    if (j.vacancies)    b += metaItem('Vacancies', j.vacancies + ' position' + (j.vacancies > 1 ? 's' : ''));
    if (j.deadline)     b += metaItem('Application Deadline', fmtDate(j.deadline), '#dc2626');
    if (j.department)   b += metaItem('Department', j.department);
    b += '</div>';
    if (j.description)      b += sec('About This Role', '<p>' + nl2br(esc(j.description)) + '</p>');
    if (j.responsibilities) b += sec('Key Responsibilities', '<ul>' + bulletList(j.responsibilities) + '</ul>');
    if (j.requirements)     b += sec('Requirements', '<ul>' + bulletList(j.requirements) + '</ul>');
    if (j.skills_required) {
        var sks = j.skills_required.split(',').map(s=>s.trim()).filter(Boolean);
        if (sks.length) b += sec('Skills Required', '<div style="display:flex;flex-wrap:wrap;gap:8px;">' +
            sks.map(s=>'<span style="background:#eff6ff;border:1.5px solid #bfdbfe;color:#1e40af;padding:5px 12px;border-radius:8px;font-size:13px;font-weight:700;">'+esc(s)+'</span>').join('') + '</div>');
    }
    b += '<button class="btn-apply-modal" onclick="applyJob('+id+')"><i class="fa-solid fa-paper-plane"></i> Apply for This Position</button>';
    document.getElementById('jdBody').innerHTML = b;
}
function applyJob(id) {
    var j = JOBS.find(x => parseInt(x.id) === id);
    if (!j) return;
    closeModal();
    selJobId = id;
    document.getElementById('f-position').value = j.title || '';
    if (j.department) document.getElementById('f-department').value = j.department;
    if (j.skills_required) j.skills_required.split(',').map(s=>s.trim()).filter(Boolean).forEach(s => { if (!skills.includes(s)) addSkill(s); });
    document.getElementById('sjbTitle').textContent = j.title || '';
    document.getElementById('sjbDept').textContent  = (j.department||'') + (j.location ? ' · ' + j.location : '');
    document.getElementById('selJobBanner').style.display = 'flex';
    document.getElementById('apply-now').scrollIntoView({behavior:'smooth'});
}
function clearJob() {
    selJobId = null;
    document.getElementById('selJobBanner').style.display = 'none';
    document.getElementById('f-position').value = '';
}
function closeModal() { document.getElementById('jdOverlay').classList.remove('show'); }
function closeModalBg(e) { if (e.target === document.getElementById('jdOverlay')) closeModal(); }
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeModal(); });

// Helpers
function badge(t, bg) { bg = bg || 'rgba(255,255,255,.2)'; return '<span style="background:'+bg+';color:#fff;padding:3px 11px;border-radius:20px;font-size:12px;font-weight:700;">'+esc(t)+'</span>'; }
function metaItem(l, v, vc) { return '<div class="jdm-meta-item"><label>'+esc(l)+'</label><span style="'+(vc?'color:'+vc+';font-weight:900;':'')+'">'+esc(v)+'</span></div>'; }
function sec(h, html) { return '<div class="jdm-sec"><h4>'+h+'</h4>'+html+'</div>'; }
function bulletList(txt) { return txt.split('\n').filter(Boolean).map(l=>'<li>'+esc(l.replace(/^[-•*]\s*/,''))+'</li>').join(''); }
function fmtDate(d) { try { return new Date(d).toLocaleDateString('en-IN',{day:'2-digit',month:'short',year:'numeric'}); } catch(e){return d;} }
function esc(s) { return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
function nl2br(s) { return s.replace(/\n/g,'<br>'); }

// ── NOTICE PERIOD ──
function selNotice(v, el) {
    document.querySelectorAll('.np').forEach(p => p.classList.remove('sel'));
    el.classList.add('sel');
    document.getElementById('f-notice').value = v;
}

// ── SKILLS ──
function skKey(e) {
    if (e.key === 'Enter' || e.key === ',') {
        e.preventDefault();
        var v = e.target.value.trim().replace(/,$/, '');
        if (v) addSkill(v);
        e.target.value = ''; hideSug();
    } else if (e.key === 'Backspace' && !e.target.value && skills.length) {
        removeSkill(skills.length - 1);
    }
}
function addSkill(s) {
    s = s.trim(); if (!s || skills.includes(s)) return;
    skills.push(s); renderSkills();
}
function removeSkill(i) { skills.splice(i, 1); renderSkills(); }
function renderSkills() {
    var w = document.getElementById('skWrap'), inp = document.getElementById('skInp');
    w.querySelectorAll('.sk-tag').forEach(t => t.remove());
    skills.forEach((s, i) => {
        var t = document.createElement('div'); t.className = 'sk-tag';
        t.innerHTML = esc(s) + '<span class="sk-del" onclick="removeSkill('+i+')">✕</span>';
        w.insertBefore(t, inp);
    });
    document.getElementById('f-skills').value = skills.join(', ');
}
function skSuggest(v) {
    var el = document.getElementById('skSug');
    if (!v) { el.style.display = 'none'; return; }
    var m = COMMON_SKILLS.filter(s => s.toLowerCase().startsWith(v.toLowerCase()) && !skills.includes(s));
    if (!m.length) { el.style.display = 'none'; return; }
    el.innerHTML = m.slice(0,5).map(s => '<div class="sk-sug-item" onmousedown="addSkill(\''+esc(s)+'\');document.getElementById(\'skInp\').value=\'\';hideSug();">'+esc(s)+'</div>').join('');
    el.style.display = 'block';
}
function hideSug() { document.getElementById('skSug').style.display = 'none'; }
document.addEventListener('click', e => { if (!e.target.closest('#skWrap')) hideSug(); });

// ── FILE ──
function showFile(type, inp) {
    var f = inp.files[0]; if (!f) return;
    if (f.size > 5*1024*1024) { alert('File must be under 5 MB'); inp.value=''; return; }
    document.getElementById(type+'-nm').textContent = f.name;
    document.getElementById(type+'-chosen').classList.add('show');
}
['resumeZone','coverZone'].forEach(zid => {
    var z = document.getElementById(zid); if (!z) return;
    z.addEventListener('dragover',  e => { e.preventDefault(); z.classList.add('over'); });
    z.addEventListener('dragleave', () => z.classList.remove('over'));
    z.addEventListener('drop', e => {
        e.preventDefault(); z.classList.remove('over');
        var inp = z.querySelector('input[type=file]');
        if (e.dataTransfer.files.length) { inp.files = e.dataTransfer.files; inp.dispatchEvent(new Event('change')); }
    });
});

// ── SUBMIT ──
function doSubmit() {
    var err = document.getElementById('subErr');
    err.style.display = 'none';
    var errs = [];
    if (!document.getElementById('f-position').value.trim())  errs.push('Position');
    if (!document.getElementById('f-department').value)        errs.push('Department');
    if (!document.getElementById('f-availability').value)      errs.push('Available / Joining Date');
    if (!document.getElementById('f-name').value.trim())       errs.push('Full name');
    if (!document.getElementById('f-email').value.trim())      errs.push('Email');
    if (!document.getElementById('f-phone').value.trim())      errs.push('Mobile number');
    if (!document.getElementById('f-location').value.trim())   errs.push('Current city');
    if (!document.getElementById('f-experience').value)        errs.push('Experience');
    if (!document.getElementById('f-qualification').value)     errs.push('Qualification');
    if (!skills.length)                                         errs.push('At least one skill');
    if (!document.getElementById('f-resume').files.length)     errs.push('Resume (required)');
    if (errs.length) {
        err.innerHTML = '<i class="fa-solid fa-triangle-exclamation"></i> Please provide: ' + errs.join(', ');
        err.style.display = 'block';
        document.getElementById('apply-now').scrollIntoView({behavior:'smooth'});
        return;
    }
    var btn = document.getElementById('submitBtn');
    btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Submitting...';
    var fd = new FormData();
    fd.append('job_id',            selJobId || '');
    fd.append('full_name',         document.getElementById('f-name').value.trim());
    fd.append('email',             document.getElementById('f-email').value.trim());
    fd.append('phone',             document.getElementById('f-phone').value.trim());
    fd.append('position_applied',  document.getElementById('f-position').value.trim());
    fd.append('department',        document.getElementById('f-department').value);
    fd.append('availability_date', document.getElementById('f-availability').value);
    fd.append('notice_period',     document.getElementById('f-notice').value);
    fd.append('location',          document.getElementById('f-location').value.trim());
    fd.append('linkedin_url',      document.getElementById('f-linkedin').value.trim());
    fd.append('portfolio_url',     document.getElementById('f-portfolio').value.trim());
    fd.append('how_heard',         document.getElementById('f-how-heard').value);
    fd.append('experience_years',  document.getElementById('f-experience').value);
    fd.append('qualification',     document.getElementById('f-qualification').value);
    fd.append('current_company',   document.getElementById('f-company').value.trim());
    fd.append('current_ctc',       document.getElementById('f-current-ctc').value.trim());
    fd.append('expected_ctc',      document.getElementById('f-expected-ctc').value.trim());
    fd.append('skills',            skills.join(', '));
    fd.append('cover_letter_text', document.getElementById('f-message').value.trim());
    var ri = document.getElementById('f-resume'), ci = document.getElementById('f-cover');
    if (ri.files.length) fd.append('resume_file',       ri.files[0]);
    if (ci.files.length) fd.append('cover_letter_file', ci.files[0]);

    fetch('career_submit.php', { method:'POST', body:fd })
        .then(r => { if (!r.ok) throw new Error('Server error ' + r.status); return r.text(); })
        .then(txt => {
            var d; try { d = JSON.parse(txt); } catch(e) { throw new Error('Invalid server response'); }
            if (d.success) {
                document.getElementById('crFormWrap').style.display = 'none';
                document.getElementById('crSuccess').style.display = 'block';
                document.getElementById('successId').textContent = 'APP-' + String(d.id).padStart(5,'0');
                window.scrollTo({top:0,behavior:'smooth'});
            } else {
                err.innerHTML = '<i class="fa-solid fa-triangle-exclamation"></i> ' + (d.message || 'Submission failed. Please try again.');
                err.style.display = 'block';
                btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-paper-plane"></i> Submit Application';
            }
        })
        .catch(e => {
            err.innerHTML = '<i class="fa-solid fa-triangle-exclamation"></i> ' + e.message;
            err.style.display = 'block';
            btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-paper-plane"></i> Submit Application';
        });
}

// ── SWIPER ──
document.addEventListener('DOMContentLoaded', function() {
    if (typeof Swiper !== 'undefined') {
        new Swiper('#whySwiper', {
            slidesPerView:1, spaceBetween:20, loop:true,
            autoplay:{delay:3400, disableOnInteraction:false, pauseOnMouseEnter:true},
            pagination:{el:'#whySwiper .swiper-pagination', clickable:true},
            navigation:{nextEl:'#whyNext', prevEl:'#whyPrev'},
            breakpoints:{600:{slidesPerView:2,spaceBetween:18},1024:{slidesPerView:3,spaceBetween:22},1280:{slidesPerView:4,spaceBetween:22}}
        });
    }
});
</script>