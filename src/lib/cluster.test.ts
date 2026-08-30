import { describe, expect, it } from 'vitest';
import { clusterByPixels } from './cluster';

describe('clusterByPixels', () => {
  it('keeps far-apart points as their own pins', () => {
    const groups = clusterByPixels([
      { x: 0, y: 0, data: 'a' },
      { x: 200, y: 0, data: 'b' },
    ], 56);
    expect(groups).toHaveLength(2);
    expect(groups.map(g => g.items.join('')).sort()).toEqual(['a', 'b']);
  });

  it('merges points that would overlap on screen', () => {
    const groups = clusterByPixels([
      { x: 10, y: 10, data: 'a' },
      { x: 30, y: 18, data: 'b' },
    ], 56);
    expect(groups).toHaveLength(1);
    expect(groups[0].items).toEqual(['a', 'b']);
  });

  it('keeps adding a third point that still overlaps the bubble', () => {
    const groups = clusterByPixels([
      { x: 0, y: 0, data: 'a' },
      { x: 20, y: 0, data: 'b' },
      { x: 40, y: 0, data: 'c' },
    ], 56);
    expect(groups).toHaveLength(1);
    expect(groups[0].items).toEqual(['a', 'b', 'c']);
  });
});
