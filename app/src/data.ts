// Types and loaders for the JSON files written by the Python collectors.

export type Point = [string, number, ...unknown[]];

export interface Trade {
  producer: string;
  symbol: string;
  grade: string;
  price: number;
  min: number;
  max: number;
  tonnes: number;
}

export interface Card {
  id: string;
  title: string;
  group: 'world' | 'iran' | 'fx' | 'helper';
  unit: string;
  unit_fa: string;
  source: string;
  source_url: string;
  freq: 'daily' | 'intraday' | 'manual';
  fetched_at?: string;
  value: number | null;
  date?: string;
  time?: string;
  prev_date?: string;
  prev_value?: number;
  change_pct?: number;
  stale: boolean;
  stale_reason?: string | null;
  detail?: { date: string; trades: Trade[] };
}

export interface Gap {
  value_pct: number;
  world_toman_per_kg: number;
  iran_toman_per_kg: number;
  fx_id: string;
  fx_title: string;
  fx_value: number;
  dates: { iran: string; lme: string; fx: string };
  source: string;
  stale: boolean;
}

export interface Latest {
  generated_at: string;
  order: string[];
  cards: Record<string, Card>;
  gap: Gap | null;
}

export interface CollectorStatus {
  title: string;
  ok: boolean;
  last_attempt: string;
  last_success?: string;
  error?: string | null;
  note?: string | null;
}

export interface Status {
  updated_at: string;
  collectors: Record<string, CollectorStatus>;
}

export interface Series {
  id: string;
  title: string;
  unit: string;
  unit_fa: string;
  source: string;
  fetched_at?: string;
  points: Point[];
}

async function getJson<T>(path: string): Promise<T> {
  // relative URL: works under any base path; the service worker caches it for offline use
  const r = await fetch(`data/${path}`, { cache: 'no-cache' });
  if (!r.ok) throw new Error(`${path}: HTTP ${r.status}`);
  return r.json() as Promise<T>;
}

export const loadLatest = () => getJson<Latest>('latest.json');
export const loadStatus = () => getJson<Status>('status.json');

const seriesCache = new Map<string, Promise<Series>>();
export function loadSeries(id: string): Promise<Series> {
  let p = seriesCache.get(id);
  if (!p) {
    p = getJson<Series>(`series/${id}.json`);
    p.catch(() => seriesCache.delete(id));
    seriesCache.set(id, p);
  }
  return p;
}
