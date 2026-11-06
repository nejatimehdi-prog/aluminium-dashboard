import { useEffect, useMemo, useState } from 'react';
import type { EChartsCoreOption } from 'echarts/core';
import EChart from '../EChart';
import { loadSeries, type Series } from '../data';
import { faDate, faNum, faPct, faShortDate } from '../format';
import { cssVar, useIsDark } from '../theme';

const RANGES = [
  { id: '1w', label: '۱ هفته', days: 7 },
  { id: '1m', label: '۱ ماه', days: 31 },
  { id: '3m', label: '۳ ماه', days: 92 },
  { id: '6m', label: '۶ ماه', days: 183 },
  { id: '1y', label: '۱ سال', days: 366 },
] as const;

const MODES = [
  { id: 'world', label: 'جهانی' },
  { id: 'iran', label: 'ایران' },
  { id: 'both', label: 'هر دو' },
] as const;

type RangeId = (typeof RANGES)[number]['id'];
type ModeId = (typeof MODES)[number]['id'];

// colour follows the series, never its position
const COLOR: Record<string, string> = {
  lme_cash: '--s-lme',
  comex: '--s-comex',
  shfe: '--s-shfe',
  ime_ingot: '--s-ime',
  iran_free_market: '--s-free',
};
const IDS: Record<ModeId, string[]> = {
  world: ['lme_cash', 'comex', 'shfe'],
  iran: ['ime_ingot', 'iran_free_market'],
  both: ['lme_cash', 'ime_ingot'],
};

function remember<T extends string>(key: string, fallback: T, allowed: readonly { id: string }[]): [T, (v: T) => void] {
  const [v, setV] = useState<T>(() => {
    try {
      const s = localStorage.getItem(key);
      return (allowed.some((a) => a.id === s) ? s : fallback) as T;
    } catch {
      return fallback;
    }
  });
  return [
    v,
    (n: T) => {
      setV(n);
      try {
        localStorage.setItem(key, n);
      } catch {
        /* ignore */
      }
    },
  ];
}

function Seg<T extends string>({ items, value, onChange, label }: {
  items: readonly { id: T; label: string }[];
  value: T;
  onChange: (v: T) => void;
  label: string;
}) {
  return (
    <div role="radiogroup" aria-label={label} className="inline-flex rounded-lg border border-line bg-surface p-0.5">
      {items.map((it) => (
        <button
          key={it.id}
          role="radio"
          aria-checked={value === it.id}
          onClick={() => onChange(it.id)}
          className={`rounded-md px-2.5 py-1 text-sm ${value === it.id ? 'bg-accent font-semibold text-accent-ink' : 'text-ink-2 hover:bg-surface-2'}`}
        >
          {it.label}
        </button>
      ))}
    </div>
  );
}

export default function Charts() {
  const [range, setRange] = remember<RangeId>('chart.range', '3m', RANGES);
  const [mode, setMode] = remember<ModeId>('chart.mode', 'both', MODES);
  const [indexed, setIndexed] = useState(false);
  const [series, setSeries] = useState<Record<string, Series>>({});
  const [error, setError] = useState<string | null>(null);
  const dark = useIsDark();

  useEffect(() => {
    let alive = true;
    Promise.allSettled(IDS[mode].map(loadSeries)).then((rs) => {
      if (!alive) return;
      const ok: Record<string, Series> = {};
      rs.forEach((r) => r.status === 'fulfilled' && (ok[r.value.id] = r.value));
      setSeries((prev) => ({ ...prev, ...ok }));
      setError(rs.some((r) => r.status === 'rejected') ? 'بعضی سری‌ها بارگیری نشدند.' : null);
    });
    return () => {
      alive = false;
    };
  }, [mode]);

  const days = RANGES.find((r) => r.id === range)!.days;
  const from = useMemo(() => new Date(Date.now() - days * 864e5).toISOString().slice(0, 10), [days]);

  const visible = IDS[mode]
    .map((id) => series[id])
    .filter(Boolean)
    .map((s) => ({ s, pts: s.points.filter((p) => p[0] >= from) }));
  const withData = visible.filter((v) => v.pts.length > 0);
  const useIndex = mode === 'both' && indexed;

  const option = useMemo<EChartsCoreOption>(() => {
    const ink2 = cssVar('--ink-2');
    const muted = cssVar('--muted');
    const grid = cssVar('--grid');
    const axis = cssVar('--axis');
    const surface = cssVar('--surface');
    const dual = mode === 'both' && !useIndex;
    const unitOf = (id: string) => series[id]?.unit_fa ?? '';
    const yAxis = (name: string, i: number) => ({
      type: 'value',
      scale: true,
      name,
      position: i === 0 ? 'left' : 'right',
      nameTextStyle: { color: muted, fontFamily: 'Vazirmatn', align: i === 0 ? 'left' : 'right' },
      axisLabel: { color: muted, fontFamily: 'Vazirmatn', formatter: (v: number) => faNum(v) },
      splitLine: { show: i === 0, lineStyle: { color: grid } },
      axisLine: { show: false },
    });
    return {
      animation: false,
      textStyle: { fontFamily: 'Vazirmatn' },
      grid: { top: 40, bottom: 56, left: 8, right: 8, containLabel: true },
      legend: { bottom: 0, textStyle: { color: ink2, fontFamily: 'Vazirmatn' }, icon: 'roundRect', itemWidth: 14, itemHeight: 4 },
      tooltip: {
        trigger: 'axis',
        backgroundColor: surface,
        borderColor: axis,
        textStyle: { color: cssVar('--ink'), fontFamily: 'Vazirmatn' },
        axisPointer: { type: 'line', lineStyle: { color: axis } },
        formatter: (ps: { seriesName: string; value: [string, number, number?]; color: string; seriesId: string }[]) => {
          if (!ps.length) return '';
          const head = `<div style="margin-bottom:4px;color:${muted}">${faDate(ps[0].value[0])}</div>`;
          return (
            head +
            ps
              .map((p) => {
                const raw = p.value[2];
                const v = useIndex ? `${faNum(p.value[1], 1)} <span style="color:${muted}">(${faNum(raw ?? null)} ${unitOf(p.seriesId)})</span>` : `${faNum(p.value[1])} <span style="color:${muted}">${unitOf(p.seriesId)}</span>`;
                return `<div style="display:flex;gap:6px;align-items:center"><span style="width:10px;height:3px;border-radius:2px;background:${p.color}"></span>${p.seriesName}: <b>${v}</b></div>`;
              })
              .join('')
          );
        },
      },
      xAxis: {
        type: 'time',
        min: from,
        axisLabel: { color: muted, fontFamily: 'Vazirmatn', hideOverlap: true, formatter: (v: number) => faShortDate(new Date(v).toISOString().slice(0, 10)) },
        axisLine: { lineStyle: { color: axis } },
        splitLine: { show: false },
      },
      yAxis: dual
        ? [yAxis(unitOf('lme_cash'), 0), yAxis(unitOf('ime_ingot'), 1)]
        : [yAxis(useIndex ? 'شاخص (ابتدای بازه = ۱۰۰)' : unitOf(IDS[mode][0]), 0)],
      series: withData.map(({ s, pts }) => {
        const base = pts[0][1];
        const data = pts.map((p) => (useIndex ? [p[0], (p[1] / base) * 100, p[1]] : [p[0], p[1]]));
        const sparse = pts.length < 40 || s.id === 'ime_ingot';
        return {
          id: s.id,
          name: s.title,
          type: 'line',
          data,
          yAxisIndex: dual && s.id === 'ime_ingot' ? 1 : 0,
          showSymbol: sparse,
          symbolSize: 8,
          itemStyle: { color: cssVar(COLOR[s.id]), borderColor: surface, borderWidth: 2 },
          lineStyle: { width: 2 },
          connectNulls: true,
          emphasis: { focus: 'series' },
        };
      }),
    };
    // dark is a dependency so colours are re-read from CSS after a theme switch
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [withData.map((v) => `${v.s.id}:${v.pts.length}`).join(), from, mode, useIndex, dark]);

  const changes = withData.map(({ s, pts }) => ({
    s,
    first: pts[0],
    last: pts[pts.length - 1],
    pct: (pts[pts.length - 1][1] / pts[0][1] - 1) * 100,
  }));
  const missing = visible.filter((v) => v.pts.length === 0);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <Seg items={RANGES} value={range} onChange={setRange} label="بازهٔ زمانی" />
        <Seg items={MODES} value={mode} onChange={setMode} label="سری" />
        {mode === 'both' && (
          <label className="flex items-center gap-1.5 text-sm text-ink-2">
            <input type="checkbox" checked={indexed} onChange={(e) => setIndexed(e.target.checked)} />
            نمایش شاخص (۱۰۰ = ابتدای بازه)
          </label>
        )}
      </div>

      <section className="rounded-xl border border-line bg-surface p-3">
        {withData.length ? <EChart option={option} /> : <p className="p-6 text-center text-sm text-muted">در این بازه داده‌ای نیست.</p>}
        {mode === 'both' && !useIndex && (
          <p className="px-1 text-[11px] text-muted">
            محور چپ: LME به دلار بر تن. محور راست: بورس کالا به تومان بر کیلوگرم. برای مقایسهٔ درصد تغییر، «نمایش شاخص» را بزنید.
          </p>
        )}
      </section>

      {error && <p className="text-sm text-warn-ink">{error}</p>}
      {missing.map((v) => (
        <p key={v.s.id} className="text-xs text-muted">
          {v.s.title}: در این بازه داده‌ای ثبت نشده{v.s.id === 'ime_ingot' ? ' (شمش در بورس کالا معمولاً هفته‌ای یک تا دو بار عرضه می‌شود).' : '.'}
        </p>
      ))}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {changes.map(({ s, first, last, pct }) => (
          <div key={s.id} className="rounded-xl border border-line bg-surface p-3 text-sm">
            <div className="mb-1 flex items-center gap-2 font-semibold">
              <span className="h-1 w-3.5 rounded" style={{ background: `var(${COLOR[s.id]})` }} aria-hidden />
              {s.title}
            </div>
            <div className="text-ink-2">
              تغییر در بازه: <b className={pct > 0 ? 'text-up' : pct < 0 ? 'text-down' : ''}>{faPct(pct)}</b>
            </div>
            <div className="text-xs text-muted">
              از {faNum(first[1])} ({faDate(first[0], false)}) تا {faNum(last[1])} ({faDate(last[0], false)}) {s.unit_fa}
            </div>
            <div className="mt-1 text-[11px] text-muted">منبع: {s.source}</div>
          </div>
        ))}
      </div>

      {withData.length > 0 && (
        <details className="rounded-xl border border-line bg-surface text-sm">
          <summary className="cursor-pointer px-3 py-2 text-ink-2">نمایش جدول داده‌ها</summary>
          <DataTable rows={withData} />
        </details>
      )}
    </div>
  );
}

function DataTable({ rows }: { rows: { s: Series; pts: Series['points'] }[] }) {
  const dates = [...new Set(rows.flatMap((r) => r.pts.map((p) => p[0])))].sort().reverse();
  const maps = rows.map((r) => new Map(r.pts.map((p) => [p[0], p[1]])));
  return (
    <div className="max-h-96 overflow-auto border-t border-line">
      <table className="tnum w-full text-xs">
        <thead className="sticky top-0 bg-surface-2 text-ink-2">
          <tr>
            <th className="px-3 py-1.5 text-right font-medium">تاریخ</th>
            {rows.map((r) => (
              <th key={r.s.id} className="px-3 py-1.5 text-left font-medium">
                {r.s.title} <span className="font-normal text-muted">({r.s.unit_fa})</span>
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {dates.map((d) => (
            <tr key={d} className="border-t border-line">
              <td className="px-3 py-1.5">{faDate(d)}</td>
              {maps.map((m, i) => (
                <td key={i} className="px-3 py-1.5 text-left">
                  {m.has(d) ? faNum(m.get(d)!) : '—'}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
