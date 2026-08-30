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
  { days: 7, label: '7 天' },
  { days: 30, label: '30 天' },
  { days: 90, label: '90 天' },
];

function humanMinutes(minutes: number) {
  if (minutes < 60) return `${Math.round(minutes)} 分钟`;
  const hours = minutes / 60;
  if (hours < 24) return `${hours.toFixed(hours < 10 ? 1 : 0)} 小时`;
  return `${(hours / 24).toFixed(1)} 天`;
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
        setError(e instanceof Error ? e.message : '足迹加载失败');
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
          <b>{heatVisible ? '正在显示热力图' : '显示热力图'}</b>
          <small>你待得越久的地方颜色越深，只有你自己能看到</small>
        </div>
      </button>

      {loading && (
        <p className="muted empty-hint">
          <Loader2 size={14} className="spin" /> 正在整理你的足迹…
        </p>
      )}

      {error && <p className="muted empty-hint">{error}</p>}

      {!loading && !error && places.length === 0 && (
        <div className="empty-state">
          <p className="muted empty-hint">这段时间还没有足迹。带着 Pinpop 出门走走就会有了。</p>
        </div>
      )}

      {places.length > 0 && (
        <>
          <div className="footprint-stats">
            <div><b>{totals.spots}</b><small>常去地点</small></div>
            <div><b>{totals.visits}</b><small>到访次数</small></div>
            <div><b>{humanMinutes(totals.minutes)}</b><small>累计停留</small></div>
          </div>

          <div className="eyebrow">待得最久的地方</div>
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
                    <Clock size={11} /> {humanMinutes(Number(place.minutes))} · 去过 {place.visits} 次
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
