# 🧪 FCM Floating Notifications - Testing Guide

## 🎯 Quick Test (5 Minutes)

### **Prerequisites:**
- ✅ Backend running on `http://localhost:3001`
- ✅ Driver app running (web or mobile)
- ✅ Admin panel open

### **Test Steps:**

1. **Login as Driver**
   - Email: `deepak.joshi@abrafleet.com`
   - Password: `abrafleet123`
   - Keep app **OPEN** (foreground)

2. **Open Admin Panel**
   - Navigate to "Start New Trip"
   - Fill in trip details:
     - Select vehicle with driver assigned
     - Set pickup/drop locations
     - Enter customer details
     - Click "Create Trip"

3. **Watch Driver App**
   - **Expected:** Floating banner appears **INSTANTLY** (within 1 second)
   - **Banner shows:** Trip number, vehicle, customer name
   - **Duration:** 5 seconds
   - **Color:** Blue (high priority)

4. **Check Console Logs**
   ```
   📩 FCM MESSAGE RECEIVED IN DRIVER APP
      Title: 🚗 New Trip Assigned
      Body: You have been assigned a new trip...
   🎨 Showing floating banner via FCM...
   ✅ FCM notification processed successfully
   ```

5. **Check Notification Bell**
   - Click bell icon in driver app
   - **Expected:** Notification appears in list
   - **Status:** Unread (blue dot)

---

## ✅ Success Checklist

- [ ] Floating banner appears within 1 second
- [ ] Banner shows correct trip information
- [ ] Banner auto-dismisses after 5 seconds
- [ ] Notification appears in bell icon
- [ ] Console shows FCM logs
- [ ] No duplicate banners shown
- [ ] No errors in console

---

## 🐛 Troubleshooting

### **Problem:** No floating banner appears

**Check 1:** FCM initialized?
```
Look for: "🔥 INITIALIZING FCM LISTENER FOR DRIVER"
```

**Check 2:** Notification permissions granted?
```
Browser: Check site settings → Notifications → Allow
Mobile: Check app settings → Notifications → Enabled
```

**Check 3:** Backend sending FCM?
```
Backend logs should show:
"📤 FCM Sent: 1 device(s)"
```

**Check 4:** Firebase configured?
```
Check: firebase_options.dart exists
Check: Firebase project ID matches
```

---

### **Problem:** Duplicate banners appear

**Expected:** Duplicate prevention should block this
**Check:** Console should show:
```
⚠️ Duplicate notification detected, skipping: [id]
```

**If duplicates still appear:**
- Check if notification IDs are unique
- Check if `_processedNotificationIds` is working

---

### **Problem:** Banner appears but delayed (8+ seconds)

**Cause:** FCM listener not working, falling back to polling

**Check 1:** FCM subscription active?
```
Look for: "_fcmSubscription = FirebaseMessaging.onMessage.listen"
```

**Check 2:** Firebase token registered?
```
Backend logs: "✅ Device registered with backend"
```

---

## 📊 Performance Comparison

### **Before (Polling Only):**
- ⏱️ Delay: 0-8 seconds
- 🔋 Battery: Constant API calls
- 📡 Network: Request every 8 seconds

### **After (FCM + Polling):**
- ⏱️ Delay: **Instant** (< 1 second)
- 🔋 Battery: **Event-driven** (better)
- 📡 Network: **Only when notification arrives**

---

## 🎬 Demo Scenario

**Scenario:** Admin assigns urgent trip to driver

1. **T+0s:** Admin clicks "Create Trip"
2. **T+0.5s:** Backend sends FCM notification
3. **T+1s:** Driver sees floating banner 🎉
4. **T+1s:** Driver clicks banner → Opens trip details
5. **T+2s:** Driver accepts trip
6. **T+2.5s:** Admin sees "Trip Accepted" notification

**Total time:** 2.5 seconds (vs 10+ seconds with polling)

---

## 📝 Test Report Template

```
Date: _______________
Tester: _______________
Environment: [ ] Web [ ] Android [ ] iOS

Test Results:
[ ] Floating banner appears instantly
[ ] Banner shows correct information
[ ] No duplicate notifications
[ ] Notification in bell icon
[ ] Console logs correct
[ ] No errors

Issues Found:
_________________________________
_________________________________

Notes:
_________________________________
_________________________________
```

---

## 🚀 Next Steps After Testing

1. ✅ **If all tests pass:** Deploy to production
2. ⚠️ **If issues found:** Check troubleshooting guide
3. 📊 **Monitor:** Check Firebase Console for delivery stats
4. 🔄 **Iterate:** Adjust notification content/timing as needed

---

**Happy Testing! 🎉**
