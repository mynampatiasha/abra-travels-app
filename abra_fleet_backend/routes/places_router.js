// routes/places_router.js
// ============================================================================
// GOOGLE PLACES SEARCH PROXY
// ----------------------------------------------------------------------------
// Used by the roster pickup/drop location picker. The Google API key stays on
// the server (GOOGLE_MAPS_API_KEY in .env) and is never sent to the app/web.
//
//   GET /api/places/search?q=<text>&limit=8&lat=12.97&lng=77.59
//
// Response: { success: true, data: [{ title, subtitle, lat, lng, placeId, types }] }
// If the key is missing or Google fails, a non-200 is returned and the app
// falls back to its existing OpenStreetMap search, so nothing breaks.
// ============================================================================

const express = require('express');
const router = express.Router();

const PLACES_URL = 'https://places.googleapis.com/v1/places:searchText';
const DEFAULT_CENTER = { latitude: 12.9716, longitude: 77.5946 }; // Bengaluru
const FIELD_MASK = [
  'places.id',
  'places.displayName',
  'places.formattedAddress',
  'places.location',
  'places.types',
].join(',');

router.get('/search', async (req, res) => {
  const apiKey = process.env.GOOGLE_MAPS_API_KEY;
  if (!apiKey) {
    return res.status(503).json({ success: false, message: 'Places search is not configured' });
  }

  const q = String(req.query.q || '').trim();
  if (q.length < 2 || q.length > 200) {
    return res.status(400).json({ success: false, message: 'q must be 2-200 characters' });
  }

  const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 8, 1), 10);
  const lat = parseFloat(req.query.lat);
  const lng = parseFloat(req.query.lng);

  const body = {
    textQuery: q,
    regionCode: 'IN',
    languageCode: 'en',
    pageSize: limit,
  };
  if (Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180) {
    body.locationBias = { circle: { center: { latitude: lat, longitude: lng }, radius: 50000 } };
  } else {
    // No GPS (e.g. desktop browser): bias to Bengaluru, otherwise local company
    // names such as "Abra Group" return nothing. Bias only, not a restriction.
    body.locationBias = { circle: { center: DEFAULT_CENTER, radius: 50000 } };
  }

  try {
    const response = await fetch(PLACES_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': FIELD_MASK,
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(8000),
    });

    if (!response.ok) {
      // Do not forward Google's body (may echo request details); log status only.
      console.error(`[places] Google responded ${response.status}`);
      return res.status(502).json({ success: false, message: 'Places search failed' });
    }

    const json = await response.json();
    const data = (json.places || [])
      .filter((p) => p.location && Number.isFinite(p.location.latitude) && Number.isFinite(p.location.longitude))
      .map((p) => ({
        title: (p.displayName && p.displayName.text) || p.formattedAddress || q,
        subtitle: p.formattedAddress || '',
        lat: p.location.latitude,
        lng: p.location.longitude,
        placeId: p.id || null,
        types: p.types || [],
      }));

    return res.json({ success: true, data });
  } catch (err) {
    console.error('[places] search error:', err && err.name ? err.name : 'unknown');
    return res.status(502).json({ success: false, message: 'Places search failed' });
  }
});

module.exports = router;
