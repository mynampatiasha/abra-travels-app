# 🚚 Abra Fleet — Fleet Management Application

`Flutter/Dart` `Node.js` `MongoDB` `Redis` `Socket.io` `PHP (HR)`

> Fleet management for Abra Travels — mobile app, real-time backend, and an HR module.

## What is Abra Fleet?

A production fleet management system for Abra Travels — a Flutter app
(driver/dispatch/admin views) backed by a Node.js/Express API, plus a
PHP-based HR management module (attendance, departments, employees) and
supporting career/quote/sales-lead pages for the Abra Travels website.

## ✨ Key Features

| Module | Covers |
|---|---|
| 📱 Mobile App | Driver, dispatch, and admin views (Android/iOS/web/desktop) |
| 🔄 Real-time Backend | Live trip/roster updates via Socket.io & WebSockets |
| 🔔 Push Notifications | OneSignal + Web Push |
| 📊 Reporting | PDF/Excel/CSV export for rosters, distances, and more |
| 🧑‍💼 HR Module | Employee records, attendance, department management (PHP) |
| 📈 Sales/Leads | Careers, custom quotes, contact-sales lead capture |

## 🛠️ Tech Stack

**Mobile app** (`abra_fleet/`)
- Flutter (Android, iOS, web, Windows, Linux, macOS)
- `provider` for state management
- `webview_flutter`, `google_nav_bar`, `fl_chart`
- CSV/Excel/PDF export (`csv`, `excel`, `pdf`, `printing`)

**Backend** (`abra_fleet_backend/`)
- Node.js, Express 5
- MongoDB (Mongoose) + Redis (`ioredis`) + job queues (`bull`)
- Firebase Admin SDK
- Socket.io + WebSockets (`ws`) for real-time updates
- OneSignal / Web Push for notifications
- `node-cron` for scheduled jobs, Nodemailer for email
- PDFKit, ExcelJS, `json2csv`, `xlsx` for reports

**HR module** (`Hrm/`, `Hrm_PHP/`)
- Plain PHP — employee records, attendance, departments, plus Abra Travels
  website lead-capture pages

## 📁 Structure

```
abra_fleet/            # Flutter app (all platform targets)
  lib/                  # Dart application source
  functions/            # Cloud Functions
  Hrm/, Hrm_PHP/         # PHP HR module + travel-site lead pages
abra_fleet_backend/     # Express API
  controllers/, routes/, models/, services/, middleware/, utils/
  scripts/              # one-off maintenance/data-fix scripts
```

## 🚀 Running Locally

**Backend**
```bash
cd abra_fleet_backend
npm install
npm run dev
```

**Mobile app**
```bash
cd abra_fleet
flutter pub get
flutter run
```

**HR/PHP module** — requires a PHP + MySQL environment.

## 🔒 Security

Requires a `.env` with MongoDB/Redis connection strings, Firebase service
account credentials, JWT secret, and push-notification provider keys —
never commit real values for these.
