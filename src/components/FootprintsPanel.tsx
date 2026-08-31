import { useEffect, useMemo, useState } from 'react';
import { Flame, Loader2, MapPin, Clock } from 'lucide-react';
import { loadFrequentPlaces, loadHeatmap } from '../services/footprints';
import type { FrequentPlace, HeatCell } from '../types';

interface Props {
  /** Kept in sync with the map so toggling the overlay is instant. */
  heatVisible: boolean;
  onToggleHeat: (visible: boolean) => void;
  onHeatLoaded: (cells: HeatCell[]) => void;
  onFocusPlace: (lat: number, lng: number) => void;
}

const RANGES = [
  { days: 7, label: '7 days' },
  { days: 30, label: '30 days' },
  { days: 90, label: '90 days' },
];

function humanMinutes(minutes: number) {
  if (minutes < 60) return `${Math.round(minutes)} min`;
  const hours = minutes / 60;
  if (hours < 24) return `${hours.toFixed(hours < 10 ? 1 : 0)} hr`;
  return `${(hours / 24).toFixed(1)} d`;
}

export function FootprintsPanel({ heatVisible, onToggleHeat, onHeatLoaded, onFocusPlace }: Props) {
  const [days, setDays] = useState(30);
  const [places, setPlaces] = useState<FrequentPlace[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let stale = false;
    setLoading(true);
    setError(null);
    Promise.all([loadFrequentPlaces(days), loadHeatmap(days)])
      .then(([frequent, cells]) => {
        if (stale) return;
        setPlaces(frequent);
        onHeatLoaded(cells);
      })
      .catch((e: unknown) => {
        if (stale) return;
        setError(e instanceof Error ? e.message : 'Failed to load footprints');
      })
      .finally(() => {
        if (!stale) setLoading(false);
      });
    return () => {
      stale = true;
    };
  }, [days, onHeatLoaded]);

  const totals = useMemo(() => {
    const minutes = places.reduce((sum, p) => sum + Number(p.minutes || 0), 0);
    const visits = places.reduce((sum, p) => sum + Number(p.visits || 0), 0);
    return { minutes, visits, spots: places.length };
  }, [places]);

  return (
    <div className="footprints-panel">
      <div className="chip-row">
        {RANGES.map((range) => (
          <button
            key={range.days}
            type="button"
            className={days === range.days ? 'chip selected' : 'chip'}
            onClick={() => setDays(range.days)}
          >
            {range.label}
          </button>
        ))}
      </div>

      <button
        type="button"
        className={`heat-toggle ${heatVisible ? 'on' : ''}`}
        onClick={() => onToggleHeat(!heatVisible)}
      >
        <Flame size={17} />
        <div>
          <b>{heatVisible ? 'Showing heatmap' : 'Show heatmap'}</b>
          <small>Darker means more time spent — only visible to you</small>
        </div>
      </button>

      {loading && (
        <p className="muted empty-hint">
          <Loader2 size={14} className="spin" /> Gathering your footprints…
        </p>
      )}

      {error && <p className="muted empty-hint">{error}</p>}

      {!loading && !error && places.length === 0 && (
        <div className="empty-state">
          <p className="muted empty-hint">No footprints in this period yet. Get out and about with Pinpop and they'll show up.</p>
        </div>
      )}

      {places.length > 0 && (
        <>
          <div className="footprint-stats">
            <div><b>{totals.spots}</b><small>Frequent spots</small></div>
            <div><b>{totals.visits}</b><small>Visits</small></div>
            <div><b>{humanMinutes(totals.minutes)}</b><small>Total time</small></div>
          </div>

          <div className="eyebrow">Where you spend the most time</div>
          <div className="friend-list">
            {places.slice(0, 12).map((place, index) => (
              <button
                className="friend-row"
                key={`${place.cell_lat}:${place.cell_lng}`}
                type="button"
                onClick={() => onFocusPlace(place.lat, place.lng)}
              >
                <span className="footprint-rank">{index + 1}</span>
                <div>
                  <b>{place.label || `${place.lat.toFixed(3)}, ${place.lng.toFixed(3)}`}</b>
                  <small>
                    <Clock size={11} /> {humanMinutes(Number(place.minutes))} · visited {place.visits}x
                  </small>
                </div>
                <MapPin size={16} className="muted-icon" />
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
