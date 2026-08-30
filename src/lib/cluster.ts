export interface ClusterPoint<T> {
  x: number;
  y: number;
  data: T;
}

export interface ClusterGroup<T> {
  x: number;
  y: number;
  items: T[];
}

/**
 * Group points that sit on top of each other on screen. Radius is in the same
 * units as x/y (Leaflet layer pixels), so a zoomed-out city view collapses
 * nearby friends into one bubble while a street view keeps them separate.
 */
export function clusterByPixels<T>(points: ClusterPoint<T>[], radius: number): ClusterGroup<T>[] {
  const clusters: ClusterGroup<T>[] = [];
  for (const point of points) {
    let best = -1;
    let bestDist = radius;
    for (let i = 0; i < clusters.length; i++) {
      const dist = Math.hypot(clusters[i].x - point.x, clusters[i].y - point.y);
      if (dist <= bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    if (best === -1) {
      clusters.push({ x: point.x, y: point.y, items: [point.data] });
      continue;
    }
    const cluster = clusters[best];
    const n = cluster.items.length;
    cluster.x = (cluster.x * n + point.x) / (n + 1);
    cluster.y = (cluster.y * n + point.y) / (n + 1);
    cluster.items.push(point.data);
  }
  return clusters;
}
