import { registerPlugin } from '@capacitor/core';
import type { BackgroundGeolocationPlugin } from '@capacitor-community/background-geolocation';

/**
 * This package ships only type definitions and native code, so the JS proxy has
 * to be registered by hand. On the web the proxy exists but every call rejects,
 * which is why callers gate on isNative.
 */
export const BackgroundGeolocation = registerPlugin<BackgroundGeolocationPlugin>(
  'BackgroundGeolocation',
);

export type { Location as BackgroundLocation } from '@capacitor-community/background-geolocation';
