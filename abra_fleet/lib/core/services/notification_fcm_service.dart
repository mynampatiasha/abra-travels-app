// NotificationService.js - CLIENT-SIDE SERVICE
// Works with: React Native (Android/iOS) and React Web
// Handles: Permission, Registration, Foreground/Background notifications

// ============================================================================
// 📱 REACT NATIVE VERSION (Android + iOS)
// ============================================================================
// Install: npm install @react-native-firebase/app @react-native-firebase/messaging

import messaging from '@react-native-firebase/messaging';
import { Platform, PermissionsAndroid } from 'react-native';
import axios from 'axios';

const API_BASE_URL = 'https://your-api-domain.com/api'; // CHANGE THIS

class NotificationService {
  constructor() {
    this.fcmToken = null;
    this.onNotificationReceived = null;
    this.onNotificationClicked = null;
  }

  // ========================================================================
  // 🚀 INITIALIZE - Call this on app startup
  // ========================================================================
  async initialize({ onNotificationReceived, onNotificationClicked }) {
    console.log('📱 Initializing Notification Service...');
    
    this.onNotificationReceived = onNotificationReceived;
    this.onNotificationClicked = onNotificationClicked;

    try {
      // Step 1: Request permission
      const hasPermission = await this.requestPermission();
      if (!hasPermission) {
        console.log('❌ Notification permission denied');
        return { success: false, message: 'Permission denied' };
      }

      // Step 2: Get FCM token
      this.fcmToken = await this.getFCMToken();
      if (!this.fcmToken) {
        console.log('❌ Failed to get FCM token');
        return { success: false, message: 'Token generation failed' };
      }

      console.log('✅ FCM Token:', this.fcmToken.substring(0, 30) + '...');

      // Step 3: Register token with backend
      await this.registerDeviceWithBackend(this.fcmToken);

      // Step 4: Setup listeners
      this.setupNotificationListeners();

      // Step 5: Handle notification that opened the app
      await this.checkInitialNotification();

      console.log('✅ Notification Service initialized successfully');
      return { success: true, token: this.fcmToken };

    } catch (error) {
      console.error('❌ Notification initialization failed:', error);
      return { success: false, error: error.message };
    }
  }

  // ========================================================================
  // 🔐 REQUEST PERMISSION
  // ========================================================================
  async requestPermission() {
    try {
      // For iOS
      if (Platform.OS === 'ios') {
        const authStatus = await messaging().requestPermission();
        const enabled =
          authStatus === messaging.AuthorizationStatus.AUTHORIZED ||
          authStatus === messaging.AuthorizationStatus.PROVISIONAL;

        if (enabled) {
          console.log('✅ iOS: Authorization status:', authStatus);
          return true;
        }
        return false;
      }

      // For Android 13+ (API 33+)
      if (Platform.OS === 'android' && Platform.Version >= 33) {
        const granted = await PermissionsAndroid.request(
          PermissionsAndroid.PERMISSIONS.POST_NOTIFICATIONS
        );
        
        if (granted === PermissionsAndroid.RESULTS.GRANTED) {
          console.log('✅ Android: Notification permission granted');
          return true;
        }
        return false;
      }

      // For older Android versions, permission is granted by default
      return true;

    } catch (error) {
      console.error('❌ Permission request failed:', error);
      return false;
    }
  }

  // ========================================================================
  // 🎫 GET FCM TOKEN
  // ========================================================================
  async getFCMToken() {
    try {
      // Check if app has permission
      const hasPermission = await messaging().hasPermission();
      if (!hasPermission) {
        console.log('⚠️  No permission to get FCM token');
        return null;
      }

      // Get token
      const token = await messaging().getToken();
      console.log('✅ FCM Token retrieved');
      return token;

    } catch (error) {
      console.error('❌ Get FCM token failed:', error);
      return null;
    }
  }

  // ========================================================================
  // 📤 REGISTER DEVICE WITH BACKEND
  // ========================================================================
  async registerDeviceWithBackend(deviceToken) {
    try {
      console.log('📤 Registering device with backend...');

      const deviceType = Platform.OS; // 'android' or 'ios'
      const authToken = await this.getAuthToken(); // Your auth token

      const response = await axios.post(
        `${API_BASE_URL}/notifications/register-device`,
        {
          deviceToken: deviceToken,
          deviceType: deviceType,
          deviceInfo: {
            model: Platform.constants?.Model || 'Unknown',
            os: Platform.OS,
            osVersion: Platform.Version,
            appVersion: '1.0.0' // Get from app config
          }
        },
        {
          headers: {
            'Authorization': `Bearer ${authToken}`,
            'Content-Type': 'application/json'
          }
        }
      );

      if (response.data.success) {
        console.log('✅ Device registered with backend');
        return response.data;
      } else {
        console.log('⚠️  Backend registration failed:', response.data.message);
        return null;
      }

    } catch (error) {
      console.error('❌ Backend registration error:', error.message);
      return null;
    }
  }

  // ========================================================================
  // 🔔 SETUP NOTIFICATION LISTENERS
  // ========================================================================
  setupNotificationListeners() {
    console.log('🔔 Setting up notification listeners...');

    // ======== FOREGROUND NOTIFICATIONS ========
    // When app is OPEN and notification arrives
    this.unsubscribeForeground = messaging().onMessage(async remoteMessage => {
      console.log('📩 Foreground notification received:', remoteMessage);

      // Display notification or update UI
      if (this.onNotificationReceived) {
        this.onNotificationReceived({
          title: remoteMessage.notification?.title,
          body: remoteMessage.notification?.body,
          data: remoteMessage.data,
          type: 'foreground'
        });
      }
    });

    // ======== BACKGROUND NOTIFICATIONS ========
    // When app is in BACKGROUND and notification is clicked
    this.unsubscribeBackground = messaging().onNotificationOpenedApp(remoteMessage => {
      console.log('🔔 Background notification clicked:', remoteMessage);

      // Navigate to specific screen
      if (this.onNotificationClicked) {
        this.handleNotificationClick(remoteMessage);
      }
    });

    // ======== TOKEN REFRESH ========
    // When FCM token is refreshed
    this.unsubscribeTokenRefresh = messaging().onTokenRefresh(token => {
      console.log('🔄 FCM Token refreshed');
      this.fcmToken = token;
      this.registerDeviceWithBackend(token);
    });

    console.log('✅ Notification listeners setup complete');
  }

  // ========================================================================
  // 🔍 CHECK INITIAL NOTIFICATION
  // ========================================================================
  // When app was KILLED and opened by notification click
  async checkInitialNotification() {
    try {
      const remoteMessage = await messaging().getInitialNotification();
      
      if (remoteMessage) {
        console.log('🔔 App opened from killed state by notification:', remoteMessage);
        
        // Navigate to specific screen
        if (this.onNotificationClicked) {
          setTimeout(() => {
            this.handleNotificationClick(remoteMessage);
          }, 1000); // Delay to ensure app is fully loaded
        }
      }
    } catch (error) {
      console.error('❌ Check initial notification error:', error);
    }
  }

  // ========================================================================
  // 🎯 HANDLE NOTIFICATION CLICK
  // ========================================================================
  handleNotificationClick(remoteMessage) {
    const { data, notification } = remoteMessage;
    
    console.log('🎯 Handling notification click:', data);

    // Extract navigation data
    const notificationType = data?.type || 'general';
    const entityId = data?.tripId || data?.entityId;

    // Route to appropriate screen based on type
    const navigationData = {
      type: notificationType,
      title: notification?.title || data?.title,
      body: notification?.body || data?.body,
      data: data,
      
      // Screen routing
      screen: this.getScreenForNotificationType(notificationType),
      params: {
        id: entityId,
        ...data
      }
    };

    // Call the navigation handler
    if (this.onNotificationClicked) {
      this.onNotificationClicked(navigationData);
    }
  }

  // ========================================================================
  // 🗺️ MAP NOTIFICATION TYPE TO SCREEN
  // ========================================================================
  getScreenForNotificationType(type) {
    const screenMap = {
      'trip_assigned': 'TripDetails',
      'trip_accepted_admin': 'TripDetails',
      'trip_declined_admin': 'TripDetails',
      'trip_driver_confirmed': 'TripDetails',
      'trip_started': 'TripTracking',
      'trip_completed': 'TripHistory',
      'trip_cancelled': 'TripHistory',
      'roster_assigned': 'RosterDetails',
      'general': 'Notifications',
      'broadcast': 'Notifications'
    };

    return screenMap[type] || 'Notifications';
  }

  // ========================================================================
  // 🔕 UNREGISTER DEVICE (on logout)
  // ========================================================================
  async unregisterDevice() {
    try {
      console.log('🔕 Unregistering device...');

      const authToken = await this.getAuthToken();

      await axios.delete(
        `${API_BASE_URL}/notifications/unregister-device`,
        {
          data: { deviceToken: this.fcmToken },
          headers: {
            'Authorization': `Bearer ${authToken}`,
            'Content-Type': 'application/json'
          }
        }
      );

      console.log('✅ Device unregistered');

      // Cleanup listeners
      if (this.unsubscribeForeground) this.unsubscribeForeground();
      if (this.unsubscribeBackground) this.unsubscribeBackground();
      if (this.unsubscribeTokenRefresh) this.unsubscribeTokenRefresh();

    } catch (error) {
      console.error('❌ Unregister device error:', error);
    }
  }

  // ========================================================================
  // 🔑 GET AUTH TOKEN (implement based on your auth system)
  // ========================================================================
  async getAuthToken() {
    // IMPLEMENT THIS based on your authentication system
    // Example with AsyncStorage:
    // import AsyncStorage from '@react-native-async-storage/async-storage';
    // return await AsyncStorage.getItem('authToken');
    
    // For now, placeholder:
    return 'YOUR_AUTH_TOKEN_HERE';
  }

  // ========================================================================
  // 🧪 TEST NOTIFICATION
  // ========================================================================
  async sendTestNotification() {
    try {
      const authToken = await this.getAuthToken();
      
      const response = await axios.post(
        `${API_BASE_URL}/notifications/test`,
        {},
        {
          headers: {
            'Authorization': `Bearer ${authToken}`,
            'Content-Type': 'application/json'
          }
        }
      );

      console.log('🧪 Test notification response:', response.data);
      return response.data;

    } catch (error) {
      console.error('❌ Test notification error:', error);
      return { success: false, error: error.message };
    }
  }
}

// ============================================================================
// 🌐 WEB BROWSER VERSION (Service Worker + Web Push)
// ============================================================================
// Use this in your React Web app

export class WebNotificationService {
  constructor() {
    this.registration = null;
    this.subscription = null;
  }

  async initialize({ onNotificationReceived, onNotificationClicked }) {
    console.log('🌐 Initializing Web Push...');

    try {
      // Check browser support
      if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
        console.log('❌ Push notifications not supported');
        return { success: false, message: 'Not supported' };
      }

      // Request permission
      const permission = await Notification.requestPermission();
      if (permission !== 'granted') {
        console.log('❌ Notification permission denied');
        return { success: false, message: 'Permission denied' };
      }

      // Register service worker
      this.registration = await navigator.serviceWorker.register('/sw.js');
      console.log('✅ Service Worker registered');

      // Subscribe to push
      this.subscription = await this.subscribeToPush();
      
      // Register with backend
      await this.registerDeviceWithBackend(this.subscription);

      console.log('✅ Web Push initialized');
      return { success: true, subscription: this.subscription };

    } catch (error) {
      console.error('❌ Web Push initialization failed:', error);
      return { success: false, error: error.message };
    }
  }

  async subscribeToPush() {
    const vapidPublicKey = 'YOUR_VAPID_PUBLIC_KEY'; // From backend
    
    const subscription = await this.registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: this.urlBase64ToUint8Array(vapidPublicKey)
    });

    console.log('✅ Push subscription created');
    return subscription;
  }

  async registerDeviceWithBackend(subscription) {
    const authToken = localStorage.getItem('authToken'); // Your auth

    await axios.post(
      `${API_BASE_URL}/notifications/register-device`,
      {
        deviceToken: JSON.stringify(subscription),
        deviceType: 'web',
        deviceInfo: {
          browser: navigator.userAgent,
          platform: navigator.platform
        }
      },
      {
        headers: {
          'Authorization': `Bearer ${authToken}`,
          'Content-Type': 'application/json'
        }
      }
    );

    console.log('✅ Web device registered with backend');
  }

  urlBase64ToUint8Array(base64String) {
    const padding = '='.repeat((4 - base64String.length % 4) % 4);
    const base64 = (base64String + padding)
      .replace(/\-/g, '+')
      .replace(/_/g, '/');

    const rawData = window.atob(base64);
    const outputArray = new Uint8Array(rawData.length);

    for (let i = 0; i < rawData.length; ++i) {
      outputArray[i] = rawData.charCodeAt(i);
    }
    return outputArray;
  }
}

// ============================================================================
// 📤 EXPORT
// ============================================================================
const notificationService = new NotificationService();
export default notificationService;

// ============================================================================
// 📖 USAGE EXAMPLE IN YOUR APP
// ============================================================================
/*

// ======== In App.js or index.js ========

import notificationService from './services/NotificationService';
import { useNavigation } from '@react-navigation/native';

function App() {
  const navigation = useNavigation();

  useEffect(() => {
    // Initialize notification service
    notificationService.initialize({
      
      // Handle foreground notifications (app is open)
      onNotificationReceived: (notification) => {
        console.log('Received:', notification);
        
        // Show in-app notification banner
        Alert.alert(
          notification.title,
          notification.body,
          [
            { text: 'Dismiss', style: 'cancel' },
            { 
              text: 'View', 
              onPress: () => {
                // Navigate to screen
                navigation.navigate(notification.screen, notification.params);
              }
            }
          ]
        );
      },
      
      // Handle notification clicks (app was background/killed)
      onNotificationClicked: (navigationData) => {
        console.log('Clicked:', navigationData);
        
        // Navigate to appropriate screen
        navigation.navigate(navigationData.screen, navigationData.params);
      }
    });

    // Cleanup on unmount
    return () => {
      // notificationService.unregisterDevice(); // Only on logout
    };
  }, []);

  return (
    <NavigationContainer>
      // Your app navigation
    </NavigationContainer>
  );
}

// ======== On User Logout ========
async function handleLogout() {
  await notificationService.unregisterDevice();
  // Clear other user data
}

// ======== Send Test Notification ========
async function testNotifications() {
  const result = await notificationService.sendTestNotification();
  console.log('Test result:', result);
}

*/