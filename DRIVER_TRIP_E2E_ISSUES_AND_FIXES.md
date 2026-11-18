# Driver Trip End-to-End Test: Issues Found and How They Were Resolved

Date: 2026-11-18
Scope: create a driver in the admin app, assign a vehicle and a customer trip, then run the trip in the driver app.
Data: fake "E2E" records on the test cluster only. No real drivers, vehicles or customers were touched.

## Summary

| # | Issue | Area | Status |
|---|-------|------|--------|
| 1 | Boarding route missing (`Cannot POST`) | Backend | Fixed |
| 2 | Boarding returned "Passenger not found" | Backend | Fixed |
| 3 | Drop-off OTP returned "OTP not found" | Backend | Fixed |
| 4 | Cancelled trips shared a `tripGroupId` with the live trip (404 on Mark Arrived) | Backend | Fixed in code |
| 5 | Add Driver "Continue" blocked by 6 steps of required fields | Flutter + Backend | Fixed |
| 6 | Add Driver data sent as `employmentDetails` but saved as nothing | Backend | Fixed |
| 7 | Date of birth cannot be typed, only picked | Flutter | Fixed (typeable YYYY-MM-DD plus picker) |
| 8 | Assign Vehicle dialog could close without applying a vehicle | Flutter | Fixed (code), not re-tested in the browser |
| 9 | Leftover fake trips marked a test vehicle as "full" | Test data | Cleaned up |
| 10 | Rosters stayed "assigned" after the trip was completed | Backend | Fixed |
| 11 | Completion notification looked for customer fields that grouped trips do not have | Backend | Fixed |
| 12 | Completed-trip summary showed Start Odometer 0 km | Flutter | Fixed |
| 13 | A trip left in progress past midnight disappears from the driver app and cannot be ended | Backend/Flutter | Open (design decision) |

## Details and approach

### 1. Boarding route missing
- **Symptom:** marking a customer as boarded failed with `Cannot POST .../passenger/:passengerId/board`.
- **Cause:** the driver app calls this route, but the backend never defined it.
- **Approach:** added `POST /trips/:tripGroupId/stop/:stopId/passenger/:passengerId/board` in `abra_fleet_backend/routes/driver_trip_router.js`. It marks the stop's passenger as boarded and records the time.

### 2. "Passenger not found" on boarding
- **Cause:** the app sends the stop ID as the passenger ID. The backend only matched the customer's own ID.
- **Approach:** the lookup now also matches the stop ID. The update targets the exact stop using an array filter (`boardedStop.stopId`) and ignores cancelled trips.

### 3. Drop-off OTP "OTP not found"
- **Cause (two parts):**
  - The office-drop screen sends the passenger as `passenger_0`, `passenger_1`, and so on. The stored OTP uses the real stop ID.
  - The drop-off (step_out) OTP is stored under the pickup stop, not the office-drop stop.
- **Approach:** in `abra_fleet_backend/services/otp_service.js`:
  - `normalizePassengerId` converts `passenger_N` into the real stop ID, using the trip's pickup stops. It is applied in both `verifyOTP` and `resendOTP`.
  - `verifyOTP` falls back to the step_out record for that trip and passenger when no record matches the office-drop stop.
- **Verified:** a wrong code gives "Incorrect OTP. 2 attempt(s) remaining", and the right code verified in the driver app and showed "Dropped Off".
- **Lesson:** the first version of the ID helper had a regex typo (`d+` instead of `\d+`). It was caught by testing the service directly.

### 4. Cancelled trips share a `tripGroupId`
- **Symptom:** "Mark arrived" returned 404 even though the live trip existed.
- **Cause:** a cancelled trip and its replacement get the same `tripGroupId` (`{vehicleId}-{pickup|drop}-{date}`). `findOne` returned the cancelled one first.
- **Approach:** every lookup and update by `tripGroupId` now adds `status: { $ne: 'cancelled' }`. This covers the stop arrive and depart routes in `driver_trip_router.js` and the two trip lookups in `otp_router.js`. For the test data, the cancelled trips' IDs were also renamed with a `-cancelled` suffix.
- **Still worth doing later:** make the ID unique at creation time, or retag it when a trip is cancelled.

### 5. Add Driver "Continue" never advances
- **Cause:** every field in all six steps was required and validated together. The error could be on a step that wasn't visible.
- **Approach (as requested):** only **First Name**, **Email** and **Phone Number** are required.
  - The other fields no longer block the form and are labelled "(optional)".
  - Emergency phone and IFSC are validated only if filled in (10 digits and IFSC format).
  - The backend (`routes/admin-drivers.js`) now requires only first name, email and phone. Last name is no longer mandatory.
- **Files:** `abra_fleet/lib/features/admin/driver_admin_management/driver_admin_management_dialogs.dart` and `abra_fleet_backend/routes/admin-drivers.js`.

### 6. Employment details were dropped
- **Cause:** the form sends `employmentDetails` but the backend only read `employment`, so employee ID, join date, type and salary were never saved.
- **Approach:** the backend accepts either key.

### 7. Date of birth cannot be typed
- The field is now typeable (digits and dashes, format YYYY-MM-DD, validated if filled in) and the calendar icon still opens the picker, starting at 1990 and limited to today. File: `driver_admin_management_dialogs.dart`.

### 8. Assign Vehicle dialog did not apply the vehicle
- **Cause found in code:** the Assign button was enabled with no vehicle selected and just closed the dialog, so nothing was applied. Also, assigned vehicles were matched by `vehicleId` while the list used `_id`, so an already-assigned vehicle could still appear as available.
- **Approach:** Assign is disabled until a vehicle is chosen, and availability now checks both ids as strings. File: `driver_list_page.dart`.

### 9. Test data
- Leftover fake trips made the test vehicle (KA01ZZ0002) look full, so they were cancelled.

### 10-11. End Trip did not complete rosters or notify customers
- **Cause:** the end-trip route (`driver_trip_router.js`) never updated the rosters, and it read `customerEmail` / `customerName` from the trip document. Grouped trips keep customers inside `stops[].customer`, so nobody was notified.
- **Approach:** after the trip is completed, the route marks the trip's rosters `completed` and sends each pickup customer a notification using the email in the stops.
- **Verified:** the finished test trip is `completed` (odometer 12000 to 12018, distance 18 km). Its roster was set to `completed` with the same query. The notification itself was not delivered because the fake customer has no record in the `customers` collection.

### 12. Start Odometer 0 km on the completed summary
- **Cause:** after a page reload the app no longer had the start reading and showed 0.
- **Approach:** the summary now derives it as end reading minus distance when it is missing (`driver_dashboard_screen.dart`). Not re-checked in the browser.

### 13. Trip left in progress past midnight (open)
- The dashboard and the end-trip route only look at trips scheduled for today. A trip started on 17 Nov was invisible on 18 Nov, so End Trip could not be reached until the test trip was moved to today in the database. Decide whether in-progress trips from earlier days should still show.

## Test limits
- The Browser pane blocks the camera, so odometer and start photos used a generated test image.
- OTPs were read from the `trip_otps` collection instead of the customer's app.
- GPS and live location were not exercised.
- Backups of every edited file are in `D:\Fleet_Management_BACKUPS\` (folders `2026-11-17_driver-board-route` and `2026-11-18_add-driver-optional`).

## Remaining to verify
- The admin and customer screens after the trip ends were checked in the database only, not in the app (the admin app needs a login that was not used here).
- A real Add Driver submit with only name, email and phone, and the Assign Vehicle and date-of-birth changes, have not been run in the browser.
- The test trip was moved from 17 Nov to 18 Nov in the test database so the driver app would show it.
