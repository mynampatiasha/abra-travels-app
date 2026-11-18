# Client portal data audit - 18 Nov 2026

Read-only audit. Nothing was edited, no request was sent to the API, and no token was used. Everything below comes from reading the Flutter code (`abra_fleet/lib`) and the backend (`abra_fleet_backend`, mounted in `index.js`, port 3001). HRM files were not looked at. Line numbers are from the working tree on 18 Nov and may shift by a few lines because other sessions are editing Flutter files.

Abbreviations: **DB** = MongoDB database, **dom** = the client's e-mail domain (here `abrafleet.com`).

---

## 1. Metric table

Verdict: **OK** = number is right for what it says; **SUSPICIOUS** = depends on data or hides records; **WRONG** = shows a number that does not mean what the label says.

### 1.1 SOS

| Metric | Where shown | Endpoint and query | Filters / counting rule | Verdict |
|---|---|---|---|---|
| "SOS Alerts: N total alerts", Active/Resolved bars | `client_dashboard_analytics.dart` L330-366 (also `client_dashboard.dart` L331-360) | `GET /api/sos?organizationDomain=<dom>&limit=500` → `sos_router.js` L1859-1897 | Server filters `customerEmail` by regex `<dom>$` (no `@`, not escaped). Total = `pagination.total`. Resolved = status RESOLVED/CLOSED/COMPLETED (upper-cased); **everything else counts as Active** (Active, Pending, In Progress, Escalated, any unknown). | SUSPICIOUS: best count of the three, but "active" is a catch-all. 21 = 7 + 14 |
| Reports > SOS: Total / Active / Resolved / resolution rate | `client_reports_analytics_enhanced.dart` L309-365, rate L585-588 | Two calls: `GET /api/sos?status=ACTIVE&limit=100` and `?status=Resolved&limit=10000`, **no org filter in the query** | Backend regex `^ACTIVE$` case-insensitive, so it matches `Active`, `ACTIVE`, `active` but not Pending / In Progress / Escalated. Then the app keeps rows whose `customerEmail` ends with `@<dom>` **after** the global `limit=100`. Total = active + resolved (not the server total). | SUSPICIOUS: right today by luck (7 active, 14 resolved), but loses records once the platform has more than 100 active SOS, and ignores Pending/In Progress/Escalated |
| SOS Alerts screen: Active (N) tab, summary cards | `client_sos_alerts.dart` L89-160 (poll every 5 s), cards L506-660 | `GET /api/sos?status=ACTIVE&limit=100` via `ApiService`, then client filter | After the server returns rows with status matching `^ACTIVE$` (any case), the app keeps only rows where `status == 'ACTIVE'` **or `'Pending'`** compared **case-sensitively** (L129). The backend stores new SOS as `'Active'` (`sos_router.js` L1594), which fails this test. `'Pending'` can never come back from `status=ACTIVE`. | **WRONG**: root cause of "Active 0 / 6 / 7" (see 2.1) |
| SOS Alerts screen: Resolved (N) | `client_sos_alerts.dart` L164-215 | `GET /api/sos?status=Resolved&limit=100`, then domain filter in the app | Global `limit=100` before the domain filter (Reports uses 10000, the dashboard 500). | SUSPICIOUS: 14 now, but will undercount when the platform has more than 100 resolved alerts |
| Home header "N SOS Active" and SOS module badge | `client_main_shell.dart` L420-430, L1140, L1235 | `GET /api/sos?status=ACTIVE&organizationDomain=<dom>&limit=500` | Server-side org filter, `pagination.total`. Same `^ACTIVE$` rule. Token read from `FlutterSecureStorage` key `auth_token` (L397) while every other screen reads `SharedPreferences` key `jwt_token`; errors are swallowed (L449 `catch (e) {}`), so a bad token silently leaves 0. | SUSPICIOUS |
| Backend Reports SOS (not used by this screen, but available at `GET /api/client/reports/comprehensive`) | `client_reports_router.js` L196-212 | `sos_events.find({'customer.email': /@dom$/})` | Queries field **`customer.email`**, but the SOS insert writes flat **`customerEmail`** (`sos_router.js` L1490-1590). This query returns nothing for documents created by the app. Active list is `['ACTIVE','Pending','In Progress']`, which misses `'Active'` and `'Escalated'`. | **WRONG** (dead today, wrong the moment someone wires it in) |

### 1.2 Employees / customers

| Metric | Where shown | Endpoint and query | Filters / counting rule | Verdict |
|---|---|---|---|---|
| Employee Management: Total 47, Active 40, Inactive 2 | `client_employee_management.dart` L60-135, L232-264 | `CustomerService.getCustomersByDomain` → `GET /api/client/customers?domain=@<dom>&limit=10000` (`customer_service.dart` L395-440; `client-customers.js` L13-80) | Total = list length. Active = status `active`; Inactive = status `inactive` **only**. Any other status (pending, suspended, blank-but-not-null...) is in Total but in neither card. Backend defaults a missing status to `'active'` (L111). | SUSPICIOUS: 40 + 2 = 42, 5 employees are in neither card |
| Reports > Employee statistics: 47 total, 40 active, 7 inactive, 20 departments | `client_reports_analytics_enhanced.dart` L226-265, L560-575 | Same endpoint | Active = `status.toLowerCase()=='active'`; **Inactive = everything else** (L249). Departments = distinct `department`/`organization`, missing → `'General'`. | SUSPICIOUS: "inactive 7" = 2 inactive + 5 other-status; label is wrong for those 5 |
| Home "Customers 47 total, Active 39 (83%), Inactive 8 (17%)" | `client_dashboard.dart` L684-692 (`active = (count * 0.82).round()`; `inactive = count - active`) | Total from `GET /api/admin/client-analytics/trip-stats?limit=200` → `customerCount` | **Active/Inactive is invented**: 47 × 0.82 = 38.5 → 39, inactive 8. Not read from any data. Total is correct (`customers` count by `@dom$`, any status, `admin_client_analytics.js` L79-100). | **WRONG** (hard-coded 82%) |
| Home KPI "Employees" count | `client_main_shell.dart` L402-418 | `trip-stats?limit=50` | Takes `customerCount` of the entry whose `domain` equals the user's domain. The route returns only clients **that have trips**, sorted by trip count, then `slice(0, limit)` (`admin_client_analytics.js` L275-279). If the domain is outside the top 50 (or has no trips) the count stays 0 silently. The dashboard card uses `limit=200`, the shell `50`, the backend default is `10`. | SUSPICIOUS |
| Reports > Fleet statistics "Customers 1" | `client_reports_analytics_enhanced.dart` L398-420 → fleet card | `GET /api/client/trips/dashboard` → `totalCustomers` | This is the **number of distinct passengers with a pickup stop in the domain's trips** (`client_trip_management.js` L89-98), not the number of employees. Same field is shown as "Customers" on the trip dashboard (`client_trip_dashboard_part1.dart` L1157, L1231). | **WRONG** label (it is "passengers on trips") |

### 1.3 Trips

| Metric | Where shown | Endpoint and query | Filters / counting rule | Verdict |
|---|---|---|---|---|
| Reports > Trip statistics: Total 64, Scheduled 64, Ongoing 0, Completed 0, Cancelled 0 | `client_reports_analytics_enhanced.dart` L374-440 (also trip dashboard cards `client_trip_dashboard_part1.dart` L189, L959) | `GET /api/client/trips/dashboard` → `client_trip_management.js` L31-112 | Collection **`roster-assigned-trips`**, trips with any stop whose `customer.email` ends `@<dom>`. **All time, no date filter.** Scheduled = status exactly `'assigned'`; ongoing = `started`/`in_progress`; completed = `completed`/`done`/`finished`; cancelled = trip `cancelled` **or any stop cancelled** (so one trip can be both scheduled and cancelled, and counts can sum to more than Total). | SUSPICIOUS: consistent with the data (64 trips all `assigned`) but not date-limited and has overlaps |
| Trip dashboard list: "Loaded 20 trips" | `client_trip_dashboard_part1.dart` L74, L227-259 | `GET /api/client/trips/list?page=1&limit=20` | The log line is just **page 1 with page size 20**; `pagination.total` is the real 64. | OK (misleading log) |
| Home "Daily Trips, last 7 days: 0" | `client_dashboard_analytics.dart` L252-310 and `client_dashboard.dart` | `GET /api/client-trips/my-trips` → `client_trip_routes.js` L336-387 | The route reads **only `client_created_trips`** where `clientEmail` = the logged-in user's own e-mail, default `limit=50`, newest first. The code comment says "fetches from BOTH collections", which is false. The 64 operational trips live in `roster-assigned-trips` and never appear here. Then the app buckets by `substring(0,10)` of an ISO string (UTC date, not local) for the last 7 days only. | **WRONG source** → 0 |
| Home trips donut/total "Last 7 days - N total" | `client_dashboard.dart` L91, L594 | `trips/dashboard` summary | `total = completed + ongoing + cancelled`: **excludes scheduled** and is **all-time**, but the subtitle says "Last 7 days". | **WRONG** label |
| My Trip Requests: Total / Pending / Confirmed / Completed = 0 | `client_all_trips.dart` L100-140, L1198-1204 | `GET /api/client-trips/my-trips` (same route) | Shows only trips the client created through "Request New Trip". Zero is correct for this collection and wrong for the word "trips" elsewhere. Backend limit 50 and no date range. | SUSPICIOUS (same word, different entity) |
| Roster Management trip cards (assigned/ongoing/completed/cancelled) | `client_roster_management.dart` L118-175 | `RosterService.getAssignedTrips` → `GET /api/roster/admin/assigned-trips` (`roster_router.js` L1700-1775) | Reads collection **`rosters`** (not `roster-assigned-trips`). Org filter only if the user document has `companyName`/`organizationName` (L1707, L1730-1737); otherwise **no org filter at all**, then the app keeps rows where `customerEmail.endsWith(domain)`. App counts `status == 'ongoing'` exactly, but real statuses are `started`/`in_progress`, so Ongoing is always 0. | SUSPICIOUS + leak risk |

### 1.4 Fleet, rosters, feedback

| Metric | Where shown | Endpoint and query | Filters / counting rule | Verdict |
|---|---|---|---|---|
| Live Vehicle Tracking: 0 vehicles | `client_based_all_vehicles.dart` L68, L190-196 | `GET /api/client/live-tracking/vehicles?date=<today>&status=active` → `client_live_tracking_service.js` L219-320 | Default filter `active` = only trips in `started`/`in_progress`. Today's 64 trips are all `assigned`, so the default view is empty even though vehicles are assigned. Also limited to the selected date. | SUSPICIOUS: 0 is "no moving trips", not "no vehicles"; the screen does not say so |
| Reports > Fleet statistics: Vehicles 1, Drivers 1 | `client_reports_analytics_enhanced.dart` L398-420 | `trips/dashboard` `totalVehicles`/`totalDrivers` | Distinct `vehicleId`/`driverId` seen in the domain's 64 trips (all time). Not the client's fleet size. Fallback (L533-548) counts distinct names from **pending** rosters when the dashboard returns 0. | SUSPICIOUS label ("vehicles used so far") |
| Reports > Roster statistics: Pending 0, Assigned 49, In progress 0, Completed 1 | `client_reports_analytics_enhanced.dart` L289-306, L1289-1296 | `RosterService.getRosterStats` → `GET /api/roster/admin/stats` (`roster_router.js` L2134-2215) | **Aggregates the whole `rosters` collection for every organisation** (no domain/org filter, no role check). The "Assigned 49 / Completed 1" are platform-wide numbers shown as the client's own. Pending uses a stricter definition than the status list. | **WRONG** (and a data leak, see 3.5) |
| Roster pending badge (shell) and pending list (Reports) | `client_main_shell.dart` L432-440, Reports L276-293 | `GET /api/roster/admin/pending` | Server filters by the requesting user's e-mail domain (`roster_router.js` L1906-1920); app filters again. Shell takes `body['count']`. | OK |
| Reports > Feedback totals, pending/resolved, top drivers | `client_reports_analytics_enhanced.dart` L448-520 | `GET /api/admin/feedback/recent` (`driver_feedback.js` L142-175) | Backend default `limit=20` and no org filter; the app filters by domain **after** taking the platform's latest 20. Client feedback total is therefore almost always an undercount. | SUSPICIOUS |
| Reports/dashboard documents, drivers, customers sections of `/api/client/reports/comprehensive` | backend `client_reports_router.js` | n/a | Unused by the screens traced here. Vehicles/drivers derived from the domain's trips only; customers by `@dom$` (OK). | OK (unused) |

---

## 2. Root causes of the discrepancies, ranked by impact

### 2.1 SOS active = 0 / 6 / 7 (high: wrong alert state on a safety feature)
1. **Case-sensitive status check in the SOS screen.** `client_sos_alerts.dart` L129 keeps only `status == 'ACTIVE' || status == 'Pending'`. The backend writes `'Active'` (`sos_router.js` L1594) and the list endpoint matches case-insensitively, so every `'Active'` document is returned by the API and then thrown away by the screen. Only documents stored as `'ACTIVE'` survive, which explains why the count is 0 at one moment and 6 at another (documents with a different spelling, or ones changed by other code paths). The log "SOS loaded: 7 active" comes from the Reports screen, which does not repeat that check.
2. **No single definition of "active".** Four code paths: dashboard = "anything not resolved", Reports = `^ACTIVE$` any case, SOS screen = exact `ACTIVE`/`Pending`, backend Reports router = `ACTIVE`/`Pending`/`In Progress`. Statuses that can exist: `Active`, `Pending`, `In Progress`, `Resolved`, `Escalated` (`PUT /:id/status`, `sos_router.js` L1722-1735). `Pending`/`In Progress`/`Escalated` alerts vanish from the SOS screen and Reports but are counted as active by the dashboard.
3. **Global `limit` applied before the domain filter** (SOS screen `limit=100`, Reports `limit=100` active and `10000` resolved). Once the platform has more than 100 matching alerts, this client's alerts silently disappear.
4. Poll every 5 s with errors turned into an empty list (L103-105, L112): one failed poll sets `_activeAlerts = []`, so the count flickers to 0.

### 2.2 Inactive employees = 2 / 7 / 8 (high: visibly different numbers for one fact)
1. Dashboard 8 is **fabricated**: `active = round(count × 0.82)` (`client_dashboard.dart` L688-690). It never reads employee status.
2. Employee screen 2 counts `inactive` only; Reports 7 counts "not active" (= 2 inactive + 5 other statuses). 47 = 40 + 2 + 5. The five other-status employees need a name (probably `pending` or a differently cased status) and a card.

### 2.3 Trips 0 / 20 / 64 (high: the same word means three collections)
1. **"My Trip Requests" and the dashboard's daily chart read `client_created_trips`** for the user's own e-mail (limit 50). The operational trips (`roster-assigned-trips`, 64) are what Reports, the trip dashboard and live tracking read. A client who never used "Request New Trip" sees 0.
2. The "20" is only page size of the trip list (`limit=20`, 64 total).
3. Home total excludes `scheduled`, the chart title says "last 7 days" while the total is all-time, so with 64 scheduled trips the donut shows "All clear"/0.
4. Status vocabulary differs per route: `assigned`/`scheduled`/`pending` (analytics), `assigned` only (client trips dashboard), `ongoing` vs `started`/`in_progress` (roster screen).

### 2.4 Customers 1 vs 47 and fleet 1/1/1 (medium)
`totalCustomers/Drivers/Vehicles` in `/api/client/trips/dashboard` count distinct people and vehicles that appear in this domain's trips, but the UI labels them "Customers", "Drivers", "Vehicles" next to the employee total. 64 trips used one passenger, one vehicle, one driver.

### 2.5 Roster statistics are not this client's (high: leak plus wrong numbers)
`GET /api/roster/admin/stats` aggregates every roster of every organisation. Assigned 49 / Completed 1 are platform totals.

### 2.6 Live Vehicle Tracking = 0 (medium)
Default filter `active` (started/in_progress) and a single date. When every trip is still `assigned`, the screen shows nothing and gives no hint that "All" or "Assigned" would show vehicles.

### 2.7 Silent zeroes (medium)
Failures fall back to 0 or empty with only a `debugPrint`: customer count (`client_dashboard_analytics.dart` L340-345), shell KPIs (`client_main_shell.dart` L449), Reports trips (L426-436 sets everything to 0), feedback (L507-514), employees (L262-264), roster stats. A 401, timeout or a different token store looks the same as "no data". The shell reads its token from secure storage `auth_token`, the other screens from SharedPreferences `jwt_token`; if these differ the shell counters stay 0.

---

## 3. Data mis-use and leak risks

Ranked by severity. These are code-level findings; I did not call the API, so each is "present in code", not "reproduced".

1. **Unauthenticated employee list for any organisation** - `index.js` L579 mounts `clientCustomersRouter` at `/api/client/customers` **before** any `verifyJWT`; the router (`client-customers.js` L13-80) has no auth and takes the domain from the query string. Anyone who can reach port 3001 can read name, e-mail, phone, employee id, department and status of any company's employees with `?domain=@othercompany.com`. The later authenticated mount (L812) is never reached for `GET /`.
2. **Unauthenticated SOS API, including delete** - `index.js` L558 mounts `sosRoutes` at `/api/sos` with the comment "Public endpoint". In `sos_router.js` all of these are open: `GET /` (L1859, every organisation's SOS with customer name, e-mail, phone, location unless `organizationDomain` is passed), `GET /:id`, `PUT /:id/status`, `PUT /:id/resolve`, `DELETE /:id` (L1939), `POST /resolve`. Org scoping is a query parameter the caller chooses. Also `new RegExp('^' + status + '$')` (L1868) and `organizationDomain + '$'` (L1872) build regex from raw input (regex injection: `status=.*` returns everything; an invalid pattern gives a 500). `organizationDomain` has no `@` prefix and is not escaped, so `abrafleet.com` also matches `x@notabrafleet.com`.
3. **All clients' analytics sent to every client** - `GET /api/admin/client-analytics/trip-stats` (`index.js` L739, route `admin_client_analytics.js` L19) only requires a valid login (no admin role check). It returns every client with company name, trips, and customer counts, and the Flutter apps pick their own row (dashboard L316, shell L411). Any client user sees competitors' data in the response.
4. **Platform-wide roster stats** - `GET /api/roster/admin/stats` (`roster_router.js` L2134): no org filter, any logged-in user.
5. **Assigned-trips with no org filter in some cases** - `GET /api/roster/admin/assigned-trips` filters by `companyName`/`organizationName` only when the user document has one (L1707, L1730). Without it, every organisation's assigned rosters are returned and the app hides other organisations only in Dart (`client_roster_management.dart` L137-139).
6. **Client-side only filtering** after downloading platform data (the data is already on the phone): SOS screen, Reports SOS, Reports feedback (`/api/admin/feedback/recent`, no org filter, `limit=20`), Roster screen.
7. **Domain matching by `endsWith`**: SOS screen and Reports use `endsWith('@<dom>')` (OK), dashboard/shell send the domain without `@` to the server (matches look-alike domains). A user registered as `x@sub.abrafleet.com` is a different domain but `@`-less matching could cross over.
8. **Hidden records**: global limits before filtering (see 2.1 item 3, feedback limit 20, `my-trips` limit 50, `trip-stats` limit 50/200/10), trips shown only if some stop's customer e-mail matches the domain (a trip with only another domain's stops, or customers with a different e-mail domain such as gmail, is invisible), and the `status` default of `'active'` for employees with no status.
9. **Shared trips expose other organisations' passengers**: `GET /api/client/trips/:id/details` and `/bulk-report` (`client_trip_management.js` L229-273) return the whole trip document for any trip that has one stop from this domain; other companies' stops on the same vehicle are included. Not confirmed in data (needs a multi-company trip to test).

---

## 4. Minimal fixes (described, not applied)

| # | Problem | Fix | Belongs to |
|---|---|---|---|
| 1 | SOS screen drops `'Active'` | Compare `status?.toLowerCase()` and accept `active`, `pending`, `in progress`, `escalated`; do not request `status=ACTIVE` from the server, request all non-resolved or use one shared helper `isActiveSos(status)` used by the SOS screen, Reports, dashboard and shell | `client_sos_alerts.dart` L123-130 |
| 2 | Different definitions of active | Add one helper (e.g. in `lib/core/`) `bool isSosResolved(String)`; make backend `GET /api/sos` accept `status=active` meaning "not resolved" and normalise status on write to one spelling | `sos_router.js` L1594, L1866-1869, plus the four screens |
| 3 | `limit` before filtering | Send `organizationDomain=@<dom>` (with `@`) on every SOS call; derive the domain on the server from the JWT, ignore the query value | `sos_router.js` GET `/`; `client_sos_alerts.dart` L95, L165; Reports L320-335 |
| 4 | Fabricated 82% | Return `{total, active, inactive, pending, other}` from one endpoint (reuse `GET /api/client/customers` `statistics` or add to `trip-stats`) and render it; never compute from a ratio | `client_dashboard.dart` L684-692; `admin_client_analytics.js` |
| 5 | Inactive 2 vs 7 | One definition: Active, Inactive, and "Other/Pending" shown as a third card; Reports: `inactive = status=='inactive'` and `other` separately | `client_employee_management.dart` L232-233; Reports L246-252 |
| 6 | Trips 0 vs 64 | Dashboard daily chart and "Trips" tiles: use `/api/client/trips/list` (or a new `daily` endpoint on `client_trip_management.js` grouped by `scheduledDate` for the last 7 days and the user's domain). Rename the My Trip Requests screen "Trips I requested". Fix the false code comment. | `client_dashboard_analytics.dart` L252-310; `client_trip_management.js`; `client_all_trips.dart` title |
| 7 | Home total / subtitle | Use `trips.total` from the server summary (includes scheduled), and either pass a 7-day `fromDate/toDate` or change the label to "All time" | `client_dashboard.dart` L91, L594 |
| 8 | Customers/Drivers/Vehicles labels | Rename to "Passengers on trips / Drivers used / Vehicles used", or return real fleet counts from the client's own assignments; separate "Employees" (customers collection) | `client_trip_management.js` L84-99; trip dashboard and Reports labels |
| 9 | Roster stats global | Filter the aggregate by the caller's domain (`customerEmail` regex) or `organizationName`; for the client portal compute from the filtered `rosters`/`roster-assigned-trips`; gate the route with `requireRole('admin')` and add a client version | `roster_router.js` L2134 |
| 10 | Roster screen "Ongoing" always 0 | Count `ongoing`, `in_progress`, `started` | `client_roster_management.dart` L170-173 |
| 11 | Live Tracking empty | Default `status=all` (or show a chip "0 moving - N assigned today") | `client_based_all_vehicles.dart` L68 |
| 12 | Silent zeroes | Keep last good value and show an error chip/snack on failure; share one token getter | `client_dashboard_analytics.dart`, `client_main_shell.dart` L397-449, Reports |
| 13 | Feedback undercount | Add `organizationDomain` filter server-side and pass `limit=1000`, or call the reports endpoint | `driver_feedback.js` L142; Reports L448-460 |
| 14 | `trip-stats` for clients | Add `requireRole(['admin','super_admin'])`; add `GET /api/client/customers/count` use for the client (already exists in `client-customers.js` L155) | `index.js` L739, `admin_client_analytics.js`; dashboard and shell calls |
| 15 | Unauthenticated customers list | Mount `/api/client/customers` behind `verifyJWT` and derive `domain` from `req.user.email` for client roles (ignore the query value) | `index.js` L579, `client-customers.js` L13-35 |
| 16 | Unauthenticated SOS API | Keep only `POST /` public (device alert); put the rest behind `verifyJWT` and role checks; escape regex input; validate `status` against a whitelist | `index.js` L558, `sos_router.js` |
| 17 | assigned-trips without org | If the user has no `companyName`, fall back to e-mail-domain match on `customerEmail` instead of no filter | `roster_router.js` L1707-1737 |
| 18 | Dead backend query | Change `'customer.email'` to `customerEmail` in the SOS section | `client_reports_router.js` L196-205 |

---

## 5. What I could not verify

- **The database contents.** I cannot see MongoDB. To confirm the SOS cause run (read-only) `db.sos_events.aggregate([{ $match: { customerEmail: /abrafleet\.com$/i } }, { $group: { _id: '$status', n: { $sum: 1 } } }])`. Expected: a mix such as `Active` / `ACTIVE` / `Pending` / `Resolved`; any spelling other than `ACTIVE` is dropped by the SOS screen. Also check how many `sos_events` exist platform-wide (if more than 100 active or resolved, issue 2.1 item 3 is already hiding records).
- **Why the SOS screen showed exactly 6.** The code explains 0 (no document spelled `ACTIVE`/`Pending`) but 6 requires six documents stored as `ACTIVE`/`Pending` while the Reports screen counts 7; I could not see which one differs. Confirm with the aggregate above.
- **The 5 employees counted as "inactive" by Reports but not by the employee screen.** Run `db.customers.aggregate([{ $match: { email: /@abrafleet\.com$/i } }, { $group: { _id: '$status', n: { $sum: 1 } } }])`. Expected 40 `active`, 2 `inactive`, 5 other.
- **Where "Active 0 / Resolved 14 / Total 14" in the SOS screen came from** (assumed: the Active tab count of 0 plus resolved 14). I did not read `client_sos_alerts.dart` L500-660 line by line.
- **Whether `client_created_trips` has rows for this client** (My Trip Requests 0 suggests none). Check `db.client_created_trips.countDocuments({ clientEmail: '<user email>' })`.
- **Whether the 64 trips are in the last 7 days.** All have status `assigned`; I could not see their `scheduledDate`. A query on `roster-assigned-trips` grouped by `scheduledDate` would show it. The chart is 0 anyway because it reads another collection.
- **Whether the user document has `companyName`/`organizationName`**, which decides if assigned-trips leaks other organisations (finding 3.5).
- **Leak findings 3.1-3.4 are from code only.** Confirm in a safe environment by calling the endpoints without a token on a test server (read-only GET). I did not call them.
- **Token storage mismatch** between `FlutterSecureStorage` (`auth_token`) and `SharedPreferences` (`jwt_token`): both may be written at login; I did not trace the login code.
- **Mobile vs web differences**, caches in `ApiService`, and any other branch of `RosterService` (`getPendingRosters` has a cache-busting parameter; `forceRefresh` paths) were not examined.
- Files not read in full: `client_trip_dashboard_part2.dart`, `client_trip_details.dart`, `client_profile_page.dart`, `bulk_import_rosters.dart`, `leave_request_management.dart` (no counts traced from them). HRM screens and endpoints were out of scope.
