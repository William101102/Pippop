import React from 'react';
import ReactDOM from 'react-dom/client';
import 'leaflet/dist/leaflet.css';
import './styles.css';
import App from './App';
import { initNativeShell, isNative } from './lib/native';

if (isNative) {
  document.body.classList.add('native');
  void initNativeShell();
}

// Pinch-zooming the chrome around the map looks broken in a native shell; the
// map keeps its own gesture handling.
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
