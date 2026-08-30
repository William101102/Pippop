import { describe, expect, it } from 'vitest';
import { bearingDeg, haversineKm, usernameFromInviteUrl } from './geo';
import { compassLabel, fmtSpeed } from './format';

describe('bearingDeg', () => {
  it('points north when the destination is due north', () => {
    expect(bearingDeg(0, 0, 1, 0)).toBeCloseTo(0, 5);
  });

  it('points east when the destination is due east', () => {
    expect(bearingDeg(0, 0, 0, 1)).toBeCloseTo(90, 5);
  });
});

describe('haversineKm', () => {
  it('is ~111 km for one degree of latitude', () => {
    expect(haversineKm(0, 0, 1, 0)).toBeCloseTo(111.2, 0);
  });
});

describe('fmtSpeed', () => {
  it('hides walking jitter', () => {
    expect(fmtSpeed(0.3)).toBeNull();
  });

  it('renders cycling speed in km/h', () => {
    expect(fmtSpeed(5.5)).toBe('20 km/h');
  });
});

describe('compassLabel', () => {
  it('snaps to the eight Chinese points', () => {
    expect(compassLabel(0)).toBe('北');
    expect(compassLabel(90)).toBe('东');
    expect(compassLabel(180)).toBe('南');
    expect(compassLabel(270)).toBe('西');
  });
});

describe('usernameFromInviteUrl', () => {
  it('reads the web query param', () => {
    expect(usernameFromInviteUrl('https://example.com/zenly-app/?add=ada')).toBe('ada');
  });

  it('reads the native custom scheme', () => {
    expect(usernameFromInviteUrl('pinpop://add/ada')).toBe('ada');
    expect(usernameFromInviteUrl('pinpop://open?add=ada')).toBe('ada');
  });
});
