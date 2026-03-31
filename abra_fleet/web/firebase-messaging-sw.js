// Service Worker for Firebase Cloud Messaging (Web Push)
// This file handles background notifications when the web app is not open

importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js');

// Initialize Firebase in service worker
firebase.initializeApp({
  apiKey: "AIzaSyBQ5F_6J_8VDMbf7b4U_wIk_Z0HdYDRaDo",
  authDomain: "abrafleet-cec94.firebaseapp.com",
  projectId: "abrafleet-cec94",
  storageBucket: "abrafleet-cec94.firebasestorage.app",
  messagingSenderId: "847585068690",
  appId: "1:847585068690:web:763200ebca6fe684d4884b"
});

const messaging = firebase.messaging();

// Handle background messages
messaging.onBackgroundMessage((payload) => {
  console.log('[Service Worker] Background message received:', payload);
  
  const notificationTitle = payload.notification?.title || 'Abra Fleet';
  const notificationOptions = {
    body: payload.notification?.body || 'New notification',
    icon: '/favicon.png',
    badge: '/favicon.png',
    data: payload.data,
    tag: payload.data?.notificationId || 'default',
    requireInteraction: true, // Keep notification visible until user interacts
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});

// Handle notification click
self.addEventListener('notificationclick', (event) => {
  console.log('[Service Worker] Notification clicked:', event.notification.data);
  
  event.notification.close();
  
  // Open the app or focus existing window
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      // If app is already open, focus it
      for (const client of clientList) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          return client.focus();
        }
      }
      
      // Otherwise, open new window
      if (clients.openWindow) {
        return clients.openWindow('/');
      }
    })
  );
});

console.log('✅ Firebase Messaging Service Worker loaded');
