/**
 * Day / night / auto theming.
 *
 * The stored value is the user's *preference* (`auto` | `light` | `dark`).
 * What lands on `<html data-theme>` is always the *resolved* value — only ever
 * `light` or `dark`. Resolving in one place keeps styles.css free of a
 * duplicated `prefers-color-scheme` copy of the entire dark palette: the CSS
 * only ever has to match `[data-theme='dark']`.
 */
export type ThemePreference = 'auto' | 'light' | 'dark';
export type ResolvedTheme = 'light' | 'dark';

const STORAGE_KEY = 'pinpop-theme';

export function readThemePreference(): ThemePreference {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored === 'light' || stored === 'dark' || stored === 'auto') return stored;
  } catch {
    // Private mode / storage disabled — fall through to auto.
  }
  return 'auto';
}

export function storeThemePreference(preference: ThemePreference) {
  try {
    localStorage.setItem(STORAGE_KEY, preference);
  } catch {
    // Not being able to remember the choice must never break the toggle.
  }
}

function systemPrefersDark() {
  return typeof window !== 'undefined'
    && window.matchMedia?.('(prefers-color-scheme: dark)').matches === true;
}

export function resolveTheme(preference: ThemePreference): ResolvedTheme {
  if (preference === 'auto') return systemPrefersDark() ? 'dark' : 'light';
  return preference;
}

/** Writes the resolved theme to `<html>`, where the CSS can see it. */
export function applyTheme(preference: ThemePreference): ResolvedTheme {
  const resolved = resolveTheme(preference);
  document.documentElement.dataset.theme = resolved;
  // Keeps form controls, scrollbars and the browser chrome in step.
  document.documentElement.style.colorScheme = resolved;
  const meta = document.querySelector('meta[name="theme-color"]');
  meta?.setAttribute('content', resolved === 'dark' ? '#14111c' : '#fff8ef');
  return resolved;
}

/**
 * Re-resolves when the OS flips appearance, but only while the preference is
 * `auto` — an explicit choice must not be overridden by the system.
 * Returns an unsubscribe function.
 */
export function watchSystemTheme(onChange: () => void) {
  if (typeof window === 'undefined' || !window.matchMedia) return () => undefined;
  const query = window.matchMedia('(prefers-color-scheme: dark)');
  query.addEventListener('change', onChange);
  return () => query.removeEventListener('change', onChange);
}

export const THEME_CYCLE: ThemePreference[] = ['auto', 'light', 'dark'];

export const THEME_LABEL: Record<ThemePreference, string> = {
  auto: 'Auto',
  light: 'Day',
  dark: 'Night',
};
