import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.pinpop.app',
  appName: 'Pinpop',
  webDir: 'dist',

  ios: {
    // The map and sheets draw their own safe-area padding, so let the web view
    // run full bleed behind the status bar and home indicator.
    contentInset: 'never',
    backgroundColor: '#fff8ef',
  },

  plugins: {
    SplashScreen: {
      // Hidden from JS once the first map frame is ready, so there is no flash
      // of an empty map between the splash and a usable screen.
      launchAutoHide: false,
      backgroundColor: '#fff8ef',
      showSpinner: false,
    },
    // The sheets are absolutely positioned, so letting the web view resize would
    // fight the layout; panels scroll themselves above the keyboard instead.
    Keyboard: {
      resize: 'none',
    },
    PushNotifications: {
      presentationOptions: ['badge', 'sound', 'alert'],
    },
  },
};

export default config;
