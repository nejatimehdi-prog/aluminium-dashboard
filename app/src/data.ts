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

// ---- phase 2/3 files

export interface ProducerMonth {
  tonnes: number;
  pure?: number;
  products?: Record<string, number>;
  source: string;
  source_url?: string;
  published_at?: string;
  corrected?: boolean;
  note?: string | null;
  auto: boolean;
}
export interface Production {
  generated_at: string;
  unit: string;
  note: string;
  stale?: boolean;
  months: { month: string; producers: Record<string, ProducerMonth> }[];
  summary: null | {
    last_month: string;
    months_3: string[];
    producers: Record<string, { last_month: number | null; sum_3m: number; months_with_data: number }>;
    national: { last_month: number | null; sum_3m: number; months_with_data: number } | null;
  };
}

export interface TradeTotals {
  tonnes: number;
  usd: number;
  reporters: number;
  weight_missing: number;
  top_partners: { code: number; name: string; tonnes: number; usd: number }[] | null;
}
type FlowCats = Record<'ingot' | 'scrap' | 'products', TradeTotals>;
export interface Trade {
  generated_at: string;
  categories: Record<string, string>;
  source: string;
  source_url: string;
  notes: string[];
  stale?: boolean;
  comtrade: { year: string; fetched_at: string; reported: Partial<Record<'export' | 'import', FlowCats>>; mirror: Partial<Record<'export' | 'import', FlowCats>> }[];
  customs: { period: string; flow: 'export' | 'import'; category: 'ingot' | 'scrap' | 'products'; tonnes: number; usd: number | null; source: string; note: string | null }[];
}

type Scen = Record<'pessimistic' | 'base' | 'optimistic', number[]>;
export interface Forecast {
  generated_at: string;
  as_of: { lme: string; iran: string; fx: string | null };
  mode: 'regression' | 'implied_ratio';
  mode_fa: string;
  fx_points: number;
  fx_id: string;
  fx_pairs: number;
  min_pairs: number;
  horizons: { bdays: number; label: string; target: string }[];
  percentiles: number[];
  iran: {
    title: string; unit: string; last: number; last_date: string; scenarios: Scen;
    fan: [string, number, number, number][];
    backtest: Record<string, { mape: number | null; coverage: number | null; n: number }>;
  };
  lme: {
    title: string; unit: string; last: number; last_date: string; model: string; model_fa: string; scenarios: Scen;
    fan: [string, number, number, number][];
    backtest: { mape: Record<string, Record<string, number>>; origins: number; from: string; to: string };
    mean_mape: Record<string, number>;
  };
  side: { title: string; unit: string; last: number; scenarios: Scen; vol_multiplier: number };
  regression: null | { a: number; b: number; r2: number; n: number; resid_std: number; fx_id: string; from: string; to: string };
  assumptions: {
    disclaimer: string;
    scenarios: Record<'pessimistic' | 'base' | 'optimistic', { label: string; percentile: number; description: string }>;
    assumptions: string[];
    fx_vol_multiplier: number;
    bootstrap_window_days: number;
    n_paths: number;
  };
  history: { iran: [string, number][]; lme: [string, number][] };
}

export interface AlertRule {
  id: string;
  series: string;
  op: 'above' | 'below' | 'change_above' | 'stale';
  value?: number;
  enabled: boolean;
  status: 'met' | 'not_met' | 'no_data' | 'disabled';
  current?: number | null;
  last_sent_at?: string | null;
  last_message?: string | null;
}
export interface Alerts {
  generated_at: string;
  configured: boolean;
  rules: AlertRule[];
}
export const loadAlerts = () => getJson<Alerts>('alerts.json');

export const loadProduction =() => getJson<Production>('production.json');
export const loadTrade = () => getJson<Trade>('trade.json');
export const loadForecast = () => getJson<Forecast>('forecast.json');

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
