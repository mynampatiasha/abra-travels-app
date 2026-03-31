// routes/live_track.js
// ============================================================================
// PUBLIC LIVE TRACKING PAGE — No auth required
// GET /live-track/:tripId        → Serves the branded HTML tracking page
// GET /api/live-track/:tripId/data → JSON polling endpoint (called by the page)
// ============================================================================

const express = require('express');
const router  = express.Router();
const liveTrackingService = require('../services/admin_live_tracking_service');

// ============================================================================
// GET /live-track/:tripId
// Serves the fully self-contained branded HTML tracking page
// ============================================================================
router.get('/:tripId', async (req, res) => {
  const { tripId } = req.params;

  // Basic tripId format validation
  if (!tripId || tripId.length < 10) {
    return res.status(400).send('<h2>Invalid tracking link.</h2>');
  }

  // Serve the self-contained HTML page — the page itself polls /api/live-track/:tripId/data
  const html = getLiveTrackHtml(tripId);
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'no-cache, no-store');
  res.send(html);
});

// ============================================================================
// GET /:tripId/data (mounted at /api/live-track in index.js)
// JSON endpoint polled every 10 seconds by the tracking page
// Full path: /api/live-track/:tripId/data
// ============================================================================
router.get('/:tripId/data', async (req, res) => {
  try {
    const { tripId } = req.params;

    console.log('🔍 Live track API called for tripId:', tripId);

    // ✅ Try to fetch trip by MongoDB _id first, then by tripGroupId
    let trip = await liveTrackingService.fetchTripById(req.db, tripId);

    // If not found by _id, try searching by tripGroupId (which may have date suffix)
    if (!trip) {
      trip = await liveTrackingService.fetchTripByGroupId(req.db, tripId);
    }

    if (!trip) {
      console.log('❌ Trip not found:', tripId);
      return res.status(404).json({ success: false, message: 'Trip not found' });
    }

    // ✅ Debug logging to see what data we have
    console.log('✅ Trip found:', {
      tripId:          trip.tripId,
      vehicleNumber:   trip.vehicleNumber,
      currentLocation: trip.currentLocation ? {
        lat:   trip.currentLocation.latitude,
        lng:   trip.currentLocation.longitude,
        speed: trip.currentLocation.speed,
      } : null,
      stops:  trip.stops?.length || 0,
      status: trip.status,
    });

    res.json({
      success: true,
      data: {
        tripId:            trip.tripId,
        tripNumber:        trip.tripNumber,
        source:            trip.source,
        status:            trip.status,
        vehicleNumber:     trip.vehicleNumber,
        driverName:        trip.driverName,
        driverPhone:       trip.driverPhone,
        customerName:      trip.customerName,
        pickupAddress:     trip.pickupAddress || trip.stops?.[0]?.location?.address || '',
        dropAddress:       trip.dropAddress   || trip.stops?.[trip.stops.length - 1]?.location?.address || '',
        currentLocation:   trip.currentLocation,
        stops:             trip.stops,
        currentStopIndex:  trip.currentStopIndex || 0,
        totalDistance:     trip.totalDistance || 0,
        progress:          trip.progress,
        estimatedDuration: trip.estimatedDuration,
        lastUpdated:       trip.lastUpdated,
      },
    });

  } catch (err) {
    console.error('❌ live-track data error:', err);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// ============================================================================
// HTML GENERATOR — self-contained, no build step needed
// ============================================================================
function getLiveTrackHtml(tripId) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
  <title>Live Tracking — ABRA Tours and Travels</title>
  <meta name="description" content="Track your ABRA Tours and Travels vehicle in real time." />

  <!-- Leaflet CSS -->
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css" />
  <!-- Leaflet Routing Machine CSS -->
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/leaflet-routing-machine/3.2.12/leaflet-routing-machine.min.css" />
  <!-- Google Fonts -->
  <link href="https://fonts.googleapis.com/css2?family=Nunito:wght@400;600;700;800;900&family=Rajdhani:wght@500;600;700&display=swap" rel="stylesheet" />

  <style>
    /* ── CSS VARIABLES ─────────────────────────────────────────────────────── */
    :root {
      --primary:      #0D47A1;
      --primary-dark: #082e70;
      --primary-mid:  #1565C0;
      --accent:       #1E88E5;
      --accent-light: #42A5F5;
      --success:      #00C853;
      --warning:      #FF9800;
      --danger:       #F44336;
      --bg:           #F0F4FF;
      --card:         #FFFFFF;
      --text:         #1A237E;
      --text-soft:    #5C6BC0;
      --border:       rgba(13,71,161,0.12);
      --shadow:       0 4px 24px rgba(13,71,161,0.13);
      --shadow-lg:    0 8px 40px rgba(13,71,161,0.18);
      --radius:       16px;
      --radius-sm:    10px;
    }

    /* ── RESET ─────────────────────────────────────────────────────────────── */
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    html, body { height: 100%; font-family: 'Nunito', sans-serif; background: var(--bg); color: var(--text); overflow: hidden; }

    /* ── LAYOUT ────────────────────────────────────────────────────────────── */
    #app {
      display: flex;
      flex-direction: column;
      height: 100dvh;
    }

    /* ── TOP HEADER ────────────────────────────────────────────────────────── */
    #header {
      background: linear-gradient(135deg, var(--primary-dark) 0%, var(--primary-mid) 100%);
      padding: 10px 16px;
      display: flex;
      align-items: center;
      gap: 12px;
      box-shadow: 0 2px 16px rgba(0,0,0,0.25);
      z-index: 1000;
      flex-shrink: 0;
    }

    #header .logo-wrap {
      width: 42px; height: 42px;
      background: white;
      border-radius: 10px;
      display: flex; align-items: center; justify-content: center;
      flex-shrink: 0;
      overflow: hidden;
      box-shadow: 0 2px 8px rgba(0,0,0,0.2);
    }

    #header .logo-svg {
      width: 36px; height: 36px;
    }

    #header .brand {
      flex: 1;
    }

    #header .brand-name {
      font-family: 'Rajdhani', sans-serif;
      font-size: 16px; font-weight: 700;
      color: white; letter-spacing: 0.5px;
      line-height: 1.2;
    }

    #header .brand-tagline {
      font-size: 10px; font-weight: 600;
      color: rgba(255,255,255,0.65);
      letter-spacing: 0.8px;
      text-transform: uppercase;
    }

    .live-badge {
      display: flex; align-items: center; gap: 5px;
      background: rgba(0,200,83,0.18);
      border: 1px solid rgba(0,200,83,0.5);
      border-radius: 20px;
      padding: 4px 10px;
      flex-shrink: 0;
    }

    .live-dot {
      width: 7px; height: 7px;
      background: var(--success);
      border-radius: 50%;
      animation: pulse 1.4s ease-in-out infinite;
      flex-shrink: 0;
    }

    .live-text {
      font-size: 11px; font-weight: 800;
      color: var(--success);
      letter-spacing: 1px;
    }

    @keyframes pulse {
      0%, 100% { opacity: 1; transform: scale(1); box-shadow: 0 0 0 0 rgba(0,200,83,0.5); }
      50%       { opacity: 0.8; transform: scale(1.15); box-shadow: 0 0 0 6px rgba(0,200,83,0); }
    }

    /* ── MAP ───────────────────────────────────────────────────────────────── */
    #map {
      flex: 1;
      z-index: 1;
      position: relative;
      min-height: 0;
    }

    /* ── BOTTOM PANEL ──────────────────────────────────────────────────────── */
    #panel {
      background: var(--card);
      border-radius: var(--radius) var(--radius) 0 0;
      box-shadow: 0 -4px 30px rgba(13,71,161,0.15);
      flex-shrink: 0;
      max-height: 52vh;
      overflow-y: auto;
      z-index: 500;
    }

    /* drag handle */
    .drag-handle {
      display: flex; justify-content: center;
      padding: 10px 0 4px;
    }
    .drag-handle span {
      width: 40px; height: 4px;
      background: var(--border);
      border-radius: 4px;
    }

    /* trip header row */
    .trip-header {
      padding: 4px 16px 12px;
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: 12px;
    }

    .trip-number {
      font-family: 'Rajdhani', sans-serif;
      font-size: 13px; font-weight: 600;
      color: var(--text-soft);
      letter-spacing: 0.5px;
      text-transform: uppercase;
    }

    .trip-status-badge {
      display: inline-flex; align-items: center; gap: 5px;
      padding: 3px 10px; border-radius: 20px;
      font-size: 11px; font-weight: 800;
      letter-spacing: 0.5px;
      flex-shrink: 0;
    }

    .trip-status-badge.active   { background: rgba(0,200,83,0.12); color: #00A040; border: 1px solid rgba(0,200,83,0.3); }
    .trip-status-badge.assigned { background: rgba(13,71,161,0.1);  color: var(--primary); border: 1px solid var(--border); }
    .trip-status-badge.done     { background: rgba(100,100,100,0.1); color: #555; border: 1px solid #ddd; }

    /* vehicle + driver card */
    .vehicle-card {
      margin: 0 16px 12px;
      background: linear-gradient(135deg, var(--primary) 0%, var(--accent) 100%);
      border-radius: var(--radius-sm);
      padding: 14px 16px;
      display: flex;
      align-items: center;
      gap: 14px;
      box-shadow: var(--shadow);
    }

    .vehicle-icon {
      width: 48px; height: 48px;
      background: rgba(255,255,255,0.18);
      border-radius: 12px;
      display: flex; align-items: center; justify-content: center;
      flex-shrink: 0;
    }

    .vehicle-icon svg { width: 28px; height: 28px; fill: white; }

    .vehicle-info { flex: 1; }

    .vehicle-number {
      font-family: 'Rajdhani', sans-serif;
      font-size: 20px; font-weight: 700;
      color: white; letter-spacing: 1px;
    }

    .driver-name {
      font-size: 13px; font-weight: 600;
      color: rgba(255,255,255,0.85);
      margin-top: 2px;
    }

    .call-btn {
      width: 42px; height: 42px;
      background: var(--success);
      border-radius: 50%;
      display: flex; align-items: center; justify-content: center;
      text-decoration: none;
      flex-shrink: 0;
      box-shadow: 0 3px 10px rgba(0,200,83,0.4);
      transition: transform 0.15s, box-shadow 0.15s;
    }
    .call-btn:active { transform: scale(0.93); box-shadow: 0 1px 4px rgba(0,200,83,0.3); }
    .call-btn svg { width: 20px; height: 20px; fill: white; }

    /* speed + ETA pills row */
    .stats-row {
      display: flex; gap: 10px;
      padding: 0 16px 14px;
    }

    .stat-pill {
      flex: 1;
      background: var(--bg);
      border-radius: var(--radius-sm);
      border: 1px solid var(--border);
      padding: 10px 12px;
      display: flex; align-items: center; gap: 8px;
    }

    .stat-icon {
      width: 32px; height: 32px;
      border-radius: 8px;
      display: flex; align-items: center; justify-content: center;
      flex-shrink: 0;
    }
    .stat-icon.speed  { background: rgba(255,152,0,0.15); }
    .stat-icon.eta    { background: rgba(13,71,161,0.1); }
    .stat-icon.dist   { background: rgba(30,136,229,0.12); }
    .stat-icon svg { width: 17px; height: 17px; }

    .stat-label { font-size: 10px; font-weight: 700; color: var(--text-soft); text-transform: uppercase; letter-spacing: 0.5px; }
    .stat-value { font-family: 'Rajdhani', sans-serif; font-size: 18px; font-weight: 700; color: var(--text); line-height: 1; }
    .stat-unit  { font-size: 10px; font-weight: 600; color: var(--text-soft); }

    /* ── TRIP PROGRESS BAR ─────────────────────────────────────────────────── */
    .progress-section {
      padding: 0 16px 14px;
    }

    .progress-label {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 6px;
    }

    .progress-label span {
      font-size: 11px; font-weight: 700;
      color: var(--text-soft);
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }

    .progress-label strong {
      font-size: 12px; font-weight: 800;
      color: var(--primary);
    }

    .progress-track {
      height: 6px;
      background: #E8EDF8;
      border-radius: 10px;
      overflow: hidden;
    }

    .progress-fill {
      height: 100%;
      background: linear-gradient(90deg, var(--success), #00E676);
      border-radius: 10px;
      transition: width 0.6s ease;
    }

    /* ── ROUTE STOPS ───────────────────────────────────────────────────────── */
    .stops-section { padding: 0 16px 20px; }
    .stops-title {
      font-size: 12px; font-weight: 800;
      color: var(--text-soft);
      letter-spacing: 0.8px;
      text-transform: uppercase;
      margin-bottom: 10px;
    }

    .stop-item {
      display: flex; align-items: flex-start; gap: 12px;
      padding-bottom: 16px;
      position: relative;
    }

    .stop-item:not(:last-child)::after {
      content: '';
      position: absolute;
      left: 12px; top: 28px;
      width: 2px;
      bottom: 0;
      background: linear-gradient(to bottom, var(--accent-light), transparent);
    }

    /* completed stops — grey connector line */
    .stop-item.completed:not(:last-child)::after {
      background: linear-gradient(to bottom, #B0BEC5, transparent);
    }

    .stop-dot-wrap {
      display: flex; flex-direction: column; align-items: center;
      flex-shrink: 0; padding-top: 2px;
    }

    .stop-dot {
      width: 24px; height: 24px;
      border-radius: 50%;
      display: flex; align-items: center; justify-content: center;
      flex-shrink: 0;
    }

    /* PENDING pickup — green */
    .stop-dot.pickup  { background: linear-gradient(135deg, #00C853, #00E676); box-shadow: 0 2px 8px rgba(0,200,83,0.4); }
    /* PENDING drop — red */
    .stop-dot.drop    { background: linear-gradient(135deg, var(--danger), #FF6F60); box-shadow: 0 2px 8px rgba(244,67,54,0.4); }
    /* COMPLETED — grey with tick */
    .stop-dot.done    { background: #B0BEC5; box-shadow: none; }
    /* NEXT/CURRENT stop — pulsing orange */
    .stop-dot.next    {
      background: linear-gradient(135deg, #FF9800, #FFB300);
      box-shadow: 0 2px 12px rgba(255,152,0,0.6);
      animation: nextDotPulse 1.5s ease-in-out infinite;
    }

    @keyframes nextDotPulse {
      0%, 100% { box-shadow: 0 2px 12px rgba(255,152,0,0.6); }
      50%       { box-shadow: 0 2px 20px rgba(255,152,0,0.9), 0 0 0 6px rgba(255,152,0,0.15); }
    }

    .stop-dot svg { width: 13px; height: 13px; fill: white; }

    .stop-content { flex: 1; }

    .stop-label { font-size: 10px; font-weight: 800; text-transform: uppercase; letter-spacing: 0.8px; margin-bottom: 2px; }
    .stop-label.pickup { color: #00A040; }
    .stop-label.drop   { color: var(--danger); }
    .stop-label.done   { color: #90A4AE; }
    .stop-label.next   { color: #E65100; }

    .stop-address  { font-size: 13px; font-weight: 600; color: var(--text); line-height: 1.4; }
    .stop-customer { font-size: 12px; color: var(--text-soft); margin-top: 2px; }

    /* faded / strikethrough for completed stops */
    .stop-item.completed .stop-address  { color: #90A4AE; text-decoration: line-through; }
    .stop-item.completed .stop-customer { color: #B0BEC5; }

    /* highlighted background for the next/current stop */
    .stop-item.is-next {
      background: rgba(255,152,0,0.06);
      border-radius: var(--radius-sm);
      padding: 8px 8px 16px;
      margin: 0 -8px;
    }

    /* ── LOADING / ERROR STATES ────────────────────────────────────────────── */
    #loading-overlay {
      position: fixed; inset: 0;
      background: linear-gradient(135deg, var(--primary-dark), var(--accent));
      display: flex; flex-direction: column;
      align-items: center; justify-content: center;
      z-index: 9999;
      gap: 20px;
      transition: opacity 0.5s;
    }
    #loading-overlay.hidden { opacity: 0; pointer-events: none; }

    .spinner {
      width: 56px; height: 56px;
      border: 4px solid rgba(255,255,255,0.2);
      border-top-color: white;
      border-radius: 50%;
      animation: spin 0.85s linear infinite;
    }
    @keyframes spin { to { transform: rotate(360deg); } }

    .loading-text { color: white; font-size: 15px; font-weight: 700; letter-spacing: 0.5px; }
    .loading-sub  { color: rgba(255,255,255,0.6); font-size: 12px; }

    /* refresh indicator */
    #refresh-bar {
      position: absolute;
      top: 0; left: 0; right: 0;
      height: 3px;
      background: linear-gradient(90deg, var(--success), var(--accent-light));
      transform: scaleX(0);
      transform-origin: left;
      transition: transform 0.3s;
      z-index: 600;
      border-radius: 0 3px 3px 0;
    }

    #last-update {
      position: absolute;
      bottom: 6px; right: 10px;
      font-size: 10px; font-weight: 600;
      color: rgba(255,255,255,0.7);
      background: rgba(0,0,0,0.35);
      padding: 3px 8px;
      border-radius: 20px;
      z-index: 400;
      pointer-events: none;
    }

    /* ── MAP CUSTOM MARKERS ────────────────────────────────────────────────── */
    .vehicle-marker-wrap {
      position: relative;
    }

    /* ── NO GPS STATE ──────────────────────────────────────────────────────── */
    #no-gps {
      position: absolute;
      top: 50%; left: 50%;
      transform: translate(-50%, -50%);
      background: white;
      border-radius: var(--radius);
      padding: 24px 28px;
      text-align: center;
      box-shadow: var(--shadow-lg);
      z-index: 300;
      display: none;
      max-width: 260px;
    }
    #no-gps.show { display: block; }
    #no-gps .no-gps-icon { font-size: 40px; margin-bottom: 10px; }
    #no-gps h3 { font-size: 15px; font-weight: 800; color: var(--text); margin-bottom: 4px; }
    #no-gps p  { font-size: 12px; color: var(--text-soft); line-height: 1.5; }

    /* ── MOBILE TWEAKS ─────────────────────────────────────────────────────── */
    @media (min-width: 600px) {
      #app { flex-direction: row; }
      #panel {
        width: 340px;
        max-height: none;
        border-radius: 0;
        box-shadow: 4px 0 20px rgba(13,71,161,0.1);
        overflow-y: auto;
        order: -1;
      }
      #map { flex: 1; }
      .drag-handle { display: none; }
    }

    /* leaflet overrides */
    .leaflet-control-attribution { font-size: 9px !important; }
    .leaflet-routing-container { display: none !important; }
    .leaflet-container { width: 100% !important; height: 100% !important; }
  </style>
</head>
<body>

<!-- LOADING OVERLAY -->
<div id="loading-overlay">
  <div class="spinner"></div>
  <div>
    <div class="loading-text">Locating your vehicle…</div>
    <div class="loading-sub">ABRA Tours and Travels Live Tracking</div>
  </div>
</div>

<div id="app">
  <!-- MAP -->
  <div id="map">
    <div id="refresh-bar"></div>
    <div id="last-update">Updating…</div>
    <div id="no-gps">
      <div class="no-gps-icon">📡</div>
      <h3>GPS Signal Unavailable</h3>
      <p>Driver's location will appear here once tracking begins. Please wait.</p>
    </div>
  </div>

  <!-- BOTTOM / SIDE PANEL -->
  <div id="panel">
    <div class="drag-handle"><span></span></div>

    <!-- Trip Header -->
    <div class="trip-header">
      <div>
        <div class="trip-number" id="trip-number">Loading…</div>
      </div>
      <div class="trip-status-badge assigned" id="trip-status-badge">—</div>
    </div>

    <!-- Vehicle Card -->
    <div class="vehicle-card">
      <div class="vehicle-icon">
        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <path d="M18.92 6.01C18.72 5.42 18.16 5 17.5 5h-11c-.66 0-1.21.42-1.42 1.01L3 12v8c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-1h12v1c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-8l-2.08-5.99zM6.5 16c-.83 0-1.5-.67-1.5-1.5S5.67 13 6.5 13s1.5.67 1.5 1.5S7.33 16 6.5 16zm11 0c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5zM5 11l1.5-4.5h11L19 11H5z"/>
        </svg>
      </div>
      <div class="vehicle-info">
        <div class="vehicle-number" id="vehicle-number">—</div>
        <div class="driver-name" id="driver-name">Loading driver…</div>
      </div>
      <a href="#" class="call-btn" id="call-btn" onclick="return false;">
        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <path d="M6.62 10.79c1.44 2.83 3.76 5.14 6.59 6.59l2.2-2.2c.27-.27.67-.36 1.02-.24 1.12.37 2.33.57 3.57.57.55 0 1 .45 1 1V20c0 .55-.45 1-1 1-9.39 0-17-7.61-17-17 0-.55.45-1 1-1h3.5c.55 0 1 .45 1 1 0 1.25.2 2.45.57 3.57.11.35.03.74-.25 1.02l-2.2 2.2z"/>
        </svg>
      </a>
    </div>

    <!-- Trip Progress Bar -->
    <div class="progress-section">
      <div class="progress-label">
        <span>Trip Progress</span>
        <strong id="progress-text">0 / 0 stops</strong>
      </div>
      <div class="progress-track">
        <div class="progress-fill" id="progress-fill" style="width:0%"></div>
      </div>
    </div>

    <!-- Stats -->
    <div class="stats-row">
      <div class="stat-pill">
        <div class="stat-icon speed">
          <svg viewBox="0 0 24 24" fill="#FF9800" xmlns="http://www.w3.org/2000/svg">
            <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm-1-13h2v6h-2zm0 8h2v2h-2z"/>
          </svg>
        </div>
        <div>
          <div class="stat-label">Speed</div>
          <div><span class="stat-value" id="speed-val">—</span> <span class="stat-unit">km/h</span></div>
        </div>
      </div>

      <div class="stat-pill">
        <div class="stat-icon dist">
          <svg viewBox="0 0 24 24" fill="#1E88E5" xmlns="http://www.w3.org/2000/svg">
            <path d="M13.5 5.5c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zM9.8 8.9L7 23h2.1l1.8-8 2.1 2v6h2v-7.5l-2.1-2 .6-3C14.8 12 16.8 13 19 13v-2c-1.9 0-3.5-1-4.3-2.4l-1-1.6c-.4-.6-1-1-1.7-1-.3 0-.5.1-.8.1L6 8.3V13h2V9.6l1.8-.7"/>
          </svg>
        </div>
        <div>
          <div class="stat-label">Distance</div>
          <div><span class="stat-value" id="dist-val">—</span> <span class="stat-unit">km</span></div>
        </div>
      </div>

      <div class="stat-pill">
        <div class="stat-icon eta">
          <svg viewBox="0 0 24 24" fill="#0D47A1" xmlns="http://www.w3.org/2000/svg">
            <path d="M11.99 2C6.47 2 2 6.48 2 12s4.47 10 9.99 10C17.52 22 22 17.52 22 12S17.52 2 11.99 2zM12 20c-4.42 0-8-3.58-8-8s3.58-8 8-8 8 3.58 8 8-3.58 8-8 8zm.5-13H11v6l5.25 3.15.75-1.23-4.5-2.67V7z"/>
          </svg>
        </div>
        <div>
          <div class="stat-label">ETA</div>
          <div><span class="stat-value" id="eta-val">—</span> <span class="stat-unit">min</span></div>
        </div>
      </div>
    </div>

    <!-- Route Stops -->
    <div class="stops-section">
      <div class="stops-title">Route</div>
      <div id="stops-list">
        <!-- injected by JS -->
      </div>
    </div>
  </div>
</div>

<!-- Leaflet JS -->
<script src="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js"></script>

<script>
(function () {
  'use strict';

  const TRIP_ID  = '${tripId}';
  const POLL_MS  = 10000;   // 10 seconds
  const API_URL  = '/api/live-track/' + encodeURIComponent(TRIP_ID) + '/data';

  let map, vehicleMarker;
  let stopMarkers = [];
  let routeLines  = [];  // one polyline per segment (so we can colour them differently)
  let tripData    = null;
  let pollTimer   = null;
  let firstLoad   = true;

  // ── GEOCODE CACHE — address → {lat, lng} ─────────────────────────────────
  // Uses Nominatim (free, no API key) to resolve stop addresses to correct
  // coordinates. Results are cached so each unique address is only fetched once.
  const geocodeCache = {};

  async function geocodeAddress(address) {
    if (!address) return null;
    if (geocodeCache[address]) return geocodeCache[address];
    try {
      const url = 'https://nominatim.openstreetmap.org/search?format=json&limit=1&q='
                + encodeURIComponent(address);
      const res  = await fetch(url, { headers: { 'Accept-Language': 'en' } });
      const json = await res.json();
      if (json && json[0]) {
        const result = { lat: parseFloat(json[0].lat), lng: parseFloat(json[0].lon) };
        geocodeCache[address] = result;
        console.log('📍 Geocoded:', address, '→', result);
        return result;
      }
    } catch (e) {
      console.warn('Geocode failed for:', address, e);
    }
    return null;
  }

  // ── INIT MAP ──────────────────────────────────────────────────────────────
  map = L.map('map', {
    center: [12.9716, 77.5946],   // Bengaluru default
    zoom: 13,
    zoomControl: true,
    attributionControl: true,
  });

  // OpenStreetMap tiles
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
    maxZoom: 19,
  }).addTo(map);

  // Force map to fill container correctly after DOM settles
  setTimeout(() => map.invalidateSize(), 200);
  window.addEventListener('resize', () => map.invalidateSize());

  // ── CUSTOM ICONS ──────────────────────────────────────────────────────────

  // Blue pulsing circle — vehicle
  function vehicleIcon() {
    return L.divIcon({
      className: '',
      iconSize:  [48, 48],
      iconAnchor:[24, 24],
      html: \`<div style="
        width:48px;height:48px;
        background:linear-gradient(135deg,#0D47A1,#1E88E5);
        border-radius:50%;
        border:3px solid white;
        box-shadow:0 4px 16px rgba(13,71,161,0.5);
        display:flex;align-items:center;justify-content:center;
        animation:markerPulse 2s ease-in-out infinite;
      ">
        <svg width="26" height="26" viewBox="0 0 24 24" fill="white">
          <path d="M18.92 6.01C18.72 5.42 18.16 5 17.5 5h-11c-.66 0-1.21.42-1.42 1.01L3 12v8c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-1h12v1c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-8l-2.08-5.99zM6.5 16c-.83 0-1.5-.67-1.5-1.5S5.67 13 6.5 13s1.5.67 1.5 1.5S7.33 16 6.5 16zm11 0c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5zM5 11l1.5-4.5h11L19 11H5z"/>
        </svg>
      </div>\`,
    });
  }

  // Green teardrop with stop number — pending pickup
  function pendingPickupIcon(num) {
    return L.divIcon({
      className: '',
      iconSize:  [36, 44],
      iconAnchor:[18, 44],
      html: \`<div style="position:relative;width:36px;height:44px;">
        <div style="
          width:36px;height:36px;
          background:linear-gradient(135deg,#00C853,#00E676);
          border-radius:50% 50% 50% 0;
          transform:rotate(-45deg);
          border:3px solid white;
          box-shadow:0 3px 10px rgba(0,200,83,0.45);
          display:flex;align-items:center;justify-content:center;">
          <span style="transform:rotate(45deg);color:white;font-weight:800;font-size:13px;font-family:Nunito,sans-serif;">\${num}</span>
        </div>
      </div>\`,
    });
  }

  // Orange pulsing teardrop with number — next / current stop
  function nextStopIcon(num) {
    return L.divIcon({
      className: '',
      iconSize:  [40, 48],
      iconAnchor:[20, 48],
      html: \`<div style="position:relative;width:40px;height:48px;">
        <div style="
          width:40px;height:40px;
          background:linear-gradient(135deg,#FF9800,#FFB300);
          border-radius:50% 50% 50% 0;
          transform:rotate(-45deg);
          border:3px solid white;
          box-shadow:0 3px 14px rgba(255,152,0,0.7);
          display:flex;align-items:center;justify-content:center;
          animation:nextIconPulse 1.5s ease-in-out infinite;">
          <span style="transform:rotate(45deg);color:white;font-weight:900;font-size:14px;font-family:Nunito,sans-serif;">\${num}</span>
        </div>
      </div>\`,
    });
  }

  // Small grey circle with white tick — completed stop
  function completedIcon() {
    return L.divIcon({
      className: '',
      iconSize:  [28, 28],
      iconAnchor:[14, 14],
      html: \`<div style="
        width:28px;height:28px;
        background:#B0BEC5;
        border-radius:50%;
        border:2px solid white;
        box-shadow:0 2px 6px rgba(0,0,0,0.15);
        display:flex;align-items:center;justify-content:center;">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="white">
          <path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/>
        </svg>
      </div>\`,
    });
  }

  // Red teardrop — pending drop
  function pendingDropIcon() {
    return L.divIcon({
      className: '',
      iconSize:  [36, 44],
      iconAnchor:[18, 44],
      html: \`<div style="
        width:36px;height:36px;
        background:linear-gradient(135deg,#F44336,#FF6F60);
        border-radius:50% 50% 50% 0;
        transform:rotate(-45deg);
        border:3px solid white;
        box-shadow:0 3px 10px rgba(244,67,54,0.45);
        display:flex;align-items:center;justify-content:center;">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="white" style="transform:rotate(45deg)">
          <path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/>
        </svg>
      </div>\`,
    });
  }

  // Add all animation keyframes to head
  const styleEl = document.createElement('style');
  styleEl.textContent = \`
    @keyframes markerPulse {
      0%,100% { box-shadow:0 4px 16px rgba(13,71,161,0.5); }
      50%      { box-shadow:0 4px 28px rgba(13,71,161,0.85), 0 0 0 10px rgba(13,71,161,0.1); }
    }
    @keyframes nextIconPulse {
      0%,100% { box-shadow:0 3px 14px rgba(255,152,0,0.7); }
      50%      { box-shadow:0 3px 24px rgba(255,152,0,1), 0 0 0 8px rgba(255,152,0,0.15); }
    }
  \`;
  document.head.appendChild(styleEl);

  // ── STOP STATE HELPER ─────────────────────────────────────────────────────
  // Returns 'completed' | 'next' | 'pending' for each stop
  function getStopState(stop, index, currentStopIndex, tripStatus) {
    if (stop.status === 'completed')  return 'completed';
    if (tripStatus === 'completed')   return 'completed';
    if (index < currentStopIndex)     return 'completed';
    if (index === currentStopIndex)   return 'next';
    return 'pending';
  }

  // ── UPDATE UI ─────────────────────────────────────────────────────────────
  function updateUI(data) {
    // Trip number & status
    document.getElementById('trip-number').textContent = 'Trip ' + (data.tripNumber || '');

    const badge    = document.getElementById('trip-status-badge');
    const status   = data.status || '';
    const isActive = status === 'started' || status === 'in_progress';
    const isDone   = status === 'completed';

    badge.textContent = isActive ? '🟢 Live' : isDone ? '✔ Completed' : '📋 ' + status;
    badge.className   = 'trip-status-badge ' + (isActive ? 'active' : isDone ? 'done' : 'assigned');

    // Vehicle & driver
    document.getElementById('vehicle-number').textContent = data.vehicleNumber || '—';
    document.getElementById('driver-name').textContent    = '👤 ' + (data.driverName || 'Driver');

    const callBtn = document.getElementById('call-btn');
    if (data.driverPhone) {
      callBtn.href    = 'tel:' + data.driverPhone;
      callBtn.onclick = null;
    }

    // Stats
    const loc = data.currentLocation;
    document.getElementById('speed-val').textContent = loc?.speed != null ? Math.round(loc.speed) : '0';
    document.getElementById('dist-val').textContent  = data.totalDistance != null ? Number(data.totalDistance).toFixed(1) : '—';
    document.getElementById('eta-val').textContent   = data.estimatedDuration || '—';

    // Last updated
    document.getElementById('last-update').textContent =
      '↻ ' + new Date().toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit', second: '2-digit' });

    // Progress bar
    const stops         = data.stops || [];
    const currentIdx    = data.currentStopIndex || 0;
    const completedCnt  = stops.filter((s, i) => getStopState(s, i, currentIdx, status) === 'completed').length;
    const totalCnt      = stops.length;
    const pct           = totalCnt > 0 ? Math.round((completedCnt / totalCnt) * 100) : 0;
    document.getElementById('progress-fill').style.width = pct + '%';
    document.getElementById('progress-text').textContent  = completedCnt + ' / ' + totalCnt + ' stops';

    // Stops list in panel
    renderStops(data.stops || [], currentIdx, status);

    // Map markers (async — geocodes addresses)
    updateMap(data);
  }

  // ── RENDER STOP LIST ──────────────────────────────────────────────────────
  function renderStops(stops, currentStopIndex, tripStatus) {
    const container = document.getElementById('stops-list');
    if (!stops.length) {
      container.innerHTML = '<div style="color:#999;font-size:13px;text-align:center;padding:10px 0">No stop information available.</div>';
      return;
    }

    let pickupNum = 0;

    container.innerHTML = stops.map((stop, i) => {
      const isPickup = stop.type === 'pickup';
      const state    = getStopState(stop, i, currentStopIndex, tripStatus);
      const addr     = stop.location?.address || (
        stop.location?.coordinates?.latitude
          ? stop.location.coordinates.latitude.toFixed(4) + ', ' + stop.location.coordinates.longitude.toFixed(4)
          : 'Location unavailable'
      );
      const name = stop.customer?.name || '';

      if (isPickup && state !== 'completed') pickupNum++;

      // Dot CSS class
      const dotClass = state === 'completed' ? 'done'
                     : state === 'next'      ? 'next'
                     : isPickup              ? 'pickup'
                     :                         'drop';

      // Label CSS class + text
      const labelClass = state === 'completed' ? 'done'
                       : state === 'next'      ? 'next'
                       : isPickup              ? 'pickup'
                       :                         'drop';

      const labelText = state === 'completed' ? (isPickup ? '✓ Picked up' : '✓ Dropped')
                      : state === 'next'      ? (isPickup ? '🚗 Next pickup' : '🚗 Heading to drop')
                      : isPickup              ? '🟢 Pickup'
                      :                         '🔴 Drop';

      // Dot SVG icon
      const dotSvg = state === 'completed'
        ? '<svg viewBox="0 0 24 24"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg>'
        : '<svg viewBox="0 0 24 24"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></svg>';

      return \`
        <div class="stop-item \${state === 'completed' ? 'completed' : ''} \${state === 'next' ? 'is-next' : ''}">
          <div class="stop-dot-wrap">
            <div class="stop-dot \${dotClass}">\${dotSvg}</div>
          </div>
          <div class="stop-content">
            <div class="stop-label \${labelClass}">\${labelText}</div>
            <div class="stop-address">\${addr}</div>
            \${name ? '<div class="stop-customer">👤 ' + name + '</div>' : ''}
          </div>
        </div>
      \`;
    }).join('');
  }

  // ── UPDATE MAP ────────────────────────────────────────────────────────────
  async function updateMap(data) {
    const loc              = data.currentLocation;
    const noGps            = document.getElementById('no-gps');
    const stops            = data.stops || [];
    const status           = data.status || '';
    const currentStopIndex = data.currentStopIndex || 0;

    // Clear old stop markers and route lines on every update
    stopMarkers.forEach(m => map.removeLayer(m));
    stopMarkers = [];
    routeLines.forEach(l => map.removeLayer(l));
    routeLines = [];

    const hasGPS = loc?.latitude && loc?.longitude;

    // ── Vehicle marker ────────────────────────────────────────────────────
    let vehicleLatLng = null;
    if (hasGPS) {
      noGps.classList.remove('show');
      vehicleLatLng = [loc.latitude, loc.longitude];

      if (!vehicleMarker) {
        vehicleMarker = L.marker(vehicleLatLng, { icon: vehicleIcon(), zIndexOffset: 1000 }).addTo(map);
        vehicleMarker.bindPopup(
          '<b>' + (data.vehicleNumber || '') + '</b><br>' +
          (data.driverName || '') + '<br>' +
          '<small>Speed: ' + Math.round(loc.speed || 0) + ' km/h</small>'
        );
      } else {
        vehicleMarker.setLatLng(vehicleLatLng);
        vehicleMarker.setIcon(vehicleIcon());
      }
    } else {
      noGps.classList.add('show');
    }

    // ── Stop markers — geocode address for correct coordinates ────────────
    // We geocode from the address string because DB coordinates may be
    // dummy/wrong. Nominatim results are cached so each address is fetched once.
    //
    // DUPLICATE COORDINATE FIX: When multiple stops resolve to the exact same
    // coordinates (e.g. all stops at "Koramangala 5th Block, Bangalore"),
    // we spiral-offset each duplicate so all markers are visible & clickable.
    const allPoints  = vehicleLatLng ? [vehicleLatLng] : [];
    const coordCount = {}; // tracks how many markers share the same geocoded point
    const stopCoords = []; // parallel array of final [lat,lng] per stop (for route lines)
    let   pickupNum  = 0;

    for (const [i, stop] of stops.entries()) {
      const isPickup     = stop.type === 'pickup';
      const address      = stop.location?.address || '';
      const customerName = stop.customer?.name || '';
      const state        = getStopState(stop, i, currentStopIndex, status);

      if (isPickup && state !== 'completed') pickupNum++;
      const displayNum = isPickup ? pickupNum : '✦';

      // Geocode address → correct lat/lng
      const geo = await geocodeAddress(address);
      if (!geo) {
        console.warn('⚠️ Could not geocode stop', i + 1, ':', address);
        stopCoords.push(null);
        continue;
      }

      // Count how many stops already landed on this coordinate
      const coordKey = geo.lat.toFixed(4) + ',' + geo.lng.toFixed(4);
      const count    = coordCount[coordKey] || 0;
      coordCount[coordKey] = count + 1;

      // Spiral offset so stacked markers don't hide each other.
      // count=0 → no offset (first marker at exact location)
      // count=1,2,3… → small spiral nudge (~150m radius per step)
      const offsetLat = count === 0 ? 0 : (Math.cos(count * 1.5) * 0.0015 * count);
      const offsetLng = count === 0 ? 0 : (Math.sin(count * 1.5) * 0.0015 * count);

      const finalLat = geo.lat + offsetLat;
      const finalLng = geo.lng + offsetLng;

      stopCoords.push([finalLat, finalLng]);

      // Choose icon based on state
      let icon;
      if (state === 'completed') {
        icon = completedIcon();
      } else if (state === 'next') {
        icon = isPickup ? nextStopIcon(displayNum) : pendingDropIcon();
      } else {
        icon = isPickup ? pendingPickupIcon(displayNum) : pendingDropIcon();
      }

      const marker = L.marker([finalLat, finalLng], {
        icon,
        zIndexOffset: state === 'next' ? 900 : state === 'completed' ? 100 : 500,
      }).addTo(map);

      // Popup content
      const popupColor = state === 'completed' ? '#90A4AE'
                       : state === 'next'      ? '#E65100'
                       : isPickup              ? '#00A040'
                       :                         '#F44336';
      const popupLabel = state === 'completed' ? '✓ Done'
                       : state === 'next'      ? '🚗 Next Stop'
                       : isPickup              ? '🟢 Pickup'
                       :                         '🔴 Drop';

      marker.bindPopup(
        '<div style="font-family:Nunito,sans-serif;min-width:150px">' +
        '<b style="color:' + popupColor + '">' + popupLabel + '</b>' +
        (customerName ? '<br>👤 <b>' + customerName + '</b>' : '') +
        '<br><span style="font-size:12px;color:#555">' + address + '</span>' +
        '</div>'
      );

      // Auto-open popup for the next/current stop
      if (state === 'next') {
        setTimeout(() => marker.openPopup(), 800);
      }

      stopMarkers.push(marker);
      // Only include pending/next stops in the fit-bounds viewport
      if (state !== 'completed') allPoints.push([finalLat, finalLng]);
    }

    // ── Route lines — segment by segment ─────────────────────────────────
    // Completed segments are grey dashed, upcoming are blue dashed
    const sequence = vehicleLatLng ? [vehicleLatLng] : [];
    stops.forEach((stop, i) => { if (stopCoords[i]) sequence.push(stopCoords[i]); });

    for (let s = 0; s < sequence.length - 1; s++) {
      const from      = sequence[s];
      const to        = sequence[s + 1];
      // s=0 is vehicle→stop[0], s=1 is stop[0]→stop[1], etc.
      const stopIdx   = s; // stop index corresponding to segment end
      const segState  = stopIdx < stops.length
        ? getStopState(stops[stopIdx], stopIdx, currentStopIndex, status)
        : 'pending';

      const isDone = segState === 'completed';

      const line = L.polyline([from, to], {
        color:     isDone ? '#B0BEC5' : '#1E88E5',
        weight:    isDone ? 2 : 3,
        dashArray: isDone ? '4,4' : '8,6',
        opacity:   isDone ? 0.5 : 0.75,
      }).addTo(map);

      routeLines.push(line);
    }

    // ── On first load: fit map bounds to show vehicle + all pending stops ─
    if (firstLoad && allPoints.length > 0) {
      firstLoad = false;
      if (allPoints.length === 1) {
        map.setView(allPoints[0], 15, { animate: true });
      } else {
        map.fitBounds(L.latLngBounds(allPoints), { padding: [60, 60], maxZoom: 15 });
      }
      setTimeout(() => map.invalidateSize(), 300);
    }
  }

  // ── POLL ──────────────────────────────────────────────────────────────────
  async function poll() {
    const bar = document.getElementById('refresh-bar');
    bar.style.transform = 'scaleX(0.3)';

    try {
      const res  = await fetch(API_URL);
      bar.style.transform = 'scaleX(0.8)';

      if (!res.ok) throw new Error('HTTP ' + res.status);

      const json = await res.json();
      bar.style.transform = 'scaleX(1)';

      if (json.success && json.data) {
        tripData = json.data;
        updateUI(json.data);

        // Hide loading overlay on first successful poll
        document.getElementById('loading-overlay').classList.add('hidden');
      }

    } catch (err) {
      console.warn('Poll error:', err);
      document.getElementById('last-update').textContent = '⚠ Connection issue';
    }

    setTimeout(() => { bar.style.transform = 'scaleX(0)'; }, 400);
  }

  // ── START ─────────────────────────────────────────────────────────────────
  poll();
  pollTimer = setInterval(poll, POLL_MS);

  // Pause polling when tab is hidden, resume when visible
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      clearInterval(pollTimer);
    } else {
      poll();
      pollTimer = setInterval(poll, POLL_MS);
    }
  });

})();
</script>
</body>
</html>`;
}

module.exports = router;