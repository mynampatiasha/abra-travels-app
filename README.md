# Abra Fleet — Fleet Management Application

A production fleet management system for Abra Travels — a Flutter app
(driver/dispatch/admin views) backed by a Node.js/Express API, plus a PHP-based
HR management module (attendance, departments, employees) and supporting
career/quote/sales-lead pages for the Abra Travels website.

## Tech stack

**Mobile app** (`abra_fleet/`)
- Flutter (Android, iOS, web, Windows, Linux, macOS targets all present)
- `provider` for state management
- `webview_flutter` (in-app web views), `google_nav_bar`, `fl_chart`
- CSV/Excel/PDF export (`csv`, `excel`, `pdf`, `printing`)
- Image picking, file picking, push permission handling

**Backend** (`abra_fleet_backend/`)
- Node.js, Express 5
- MongoDB (Mongoose) + Redis (`ioredis`) + job queues (`bull`)
- Firebase Admin SDK
- Real-time via Socket.io and WebSockets (`ws`)
- Push notifications: OneSignal, Web Push
- Scheduled jobs (`node-cron`), email (`nodemailer`)
- Report/export generation: PDFKit, ExcelJS, `json2csv`, `xlsx`

**HR module** (`abra_fleet/Hrm/`, `Hrm_PHP/`)
- PHP, plain (no framework) — employee records, attendance list/export,
  department management
- `Hrm_PHP/` also includes Abra Travels website pages: careers list, custom
  quote requests, contact-sales leads

## Structure

```
abra_fleet/            # Flutter app (all platform targets)
  lib/                  # Dart application source
  functions/            # Cloud Functions (if used alongside Firebase)
  Hrm/, Hrm_PHP/         # PHP HR module + travel-site lead pages
abra_fleet_backend/     # Express API
  controllers/, routes/, models/, services/, middleware/, utils/
  scripts/              # one-off maintenance/data-fix scripts
```

## Running locally

**Backend**
```bash
cd abra_fleet_backend
npm install
npm run dev
```
Requires a `.env` with MongoDB/Redis connection strings, Firebase service
account credentials, JWT secret, and push-notification provider keys (see
`config/` for exact variable names).

**Mobile app**
```bash
cd abra_fleet
flutter pub get
flutter run
```

**HR/PHP module** — requires a PHP + MySQL environment (see
`Hrm/database-settings.php` for the expected database configuration).
