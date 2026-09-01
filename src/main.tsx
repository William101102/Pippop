import React from 'react';
import ReactDOM from 'react-dom/client';
import 'leaflet/dist/leaflet.css';
import './styles.css';
import App from './App';
import { initNativeShell, isNative } from './lib/native';
import { applyTheme, readThemePreference } from './lib/theme';

// Resolve the theme before React mounts, so the first paint is already the
// right appearance instead of flashing light and then correcting.
applyTheme(readThemePreference());

/**
 * On a desktop browser the product is still a phone app, so wrap it in a
 * device frame and reuse the native layout. A real phone (or Capacitor) goes
 * full-bleed. CSS viewport queries cannot see the frame, so the frame also
 * sets body.phone-preview / body.native to force the mobile rules.
 */
function installPhonePreview() {
  document.body.classList.add('native');
  if (isNative) {
    void initNativeShell();
    return;
  }
  if (window.innerWidth < 560) return;

  document.body.classList.add('phone-preview');
  const root = document.getElementById('root');
  if (!root || root.parentElement?.classList.contains('phone-bezel')) return;

  const stage = document.createElement('div');
  stage.className = 'phone-stage';
  const bezel = document.createElement('div');
  bezel.className = 'phone-bezel';
  const status = document.createElement('div');
  status.className = 'phone-status';
  status.innerHTML = '<span>9:41</span><i></i><span>100%</span>';
  const home = document.createElement('div');
  home.className = 'phone-home';

  root.parentNode!.insertBefore(stage, root);
  stage.appendChild(bezel);
  bezel.appendChild(status);
  bezel.appendChild(root);
  bezel.appendChild(home);
  root.classList.add('phone-screen');
}

installPhonePreview();

document.addEventListener(
  'gesturestart',
  (event) => {
    if (!(event.target as HTMLElement | null)?.closest('.map')) event.preventDefault();
  },
  { passive: false },
);

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode><App /></React.StrictMode>,
);
