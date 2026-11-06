import { useMemo } from 'react';
import type { EChartsCoreOption } from 'echarts/core';
import EChart from '../EChart';
import { loadProduction } from '../data';
import { faAgo, faJMonth, faNum } from '../format';
import { useIsDark, cssVar } from '../theme';
import { chartChrome, Loading, Panel, Section, StaleBadge, useJson } from '../ui';

const NATIONAL = 'کل کشور';
const PRODUCER_COLORS = ['--s-lme', '--s-comex', '--s-shfe', '--s-ime', '--s-free'];

export default function Production() {
  const { data, error } = useJson(loadProduction);
  const dark = useIsDark();

  const producers = useMemo(() => {
    if (!data) return [];
    const set = new Set<string>();
    data.months.forEach((m) => Object.keys(m.producers).forEach((p) => p !== NATIONAL && set.add(p)));
    return [...set];
  }, [data]);

  const option = useMemo<EChartsCoreOption | null>(() => {
    if (!data || !data.months.length) return null;
    const c = chartChrome();
    const months = data.months.slice(-15);
    const hasNational = months.some((m) => m.producers[NATIONAL]);
    const series: object[] = producers.map((p, i) => ({
      name: p,
      type: 'bar',
      stack: 'producers',
      barMaxWidth: 28,
      itemStyle: { color: cssVar(PRODUCER_COLORS[i % PRODUCER_COLORS.length]), borderRadius: [4, 4, 0, 0], borderColor: c.surface, borderWidth: 1 },
      data: months.map((m) => m.producers[p]?.tonnes ?? null),
    }));
    if (hasNational)
      series.push({
        name: NATIONAL, type: 'line', symbolSize: 8, lineStyle: { width: 2 },
        itemStyle: { color: c.ink2 }, data: months.map((m) => m.producers[NATIONAL]?.tonnes ?? null),
      });
    return {
      animation: false,
      textStyle: { fontFamily: 'Vazirmatn' },
      grid: { top: 30, bottom: 50, left: 8, right: 8, containLabel: true },
      legend: { bottom: 0, textStyle: { color: c.ink2, fontFamily: 'Vazirmatn' } },
      tooltip: {
        trigger: 'axis', ...c.tooltip,
        valueFormatter: (v: number | null) => (v == null ? '—' : `${faNum(v)} تن`),
      },
      xAxis: {
        // with the year: a 15-month window shows the same month name twice
        type: 'category', data: months.map((m) => faJMonth(m.month)),
        axisLabel: { ...c.label, interval: 0, rotate: months.length > 8 ? 45 : 0 }, axisLine: { lineStyle: { color: c.axis } },
      },
      yAxis: {
        type: 'value', name: 'تن', nameTextStyle: c.label,
        axisLabel: { ...c.label, formatter: (v: number) => faNum(v) }, splitLine: { lineStyle: { color: c.grid } },
      },
      series,
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data, producers, dark]);

  if (!data) return <Loading error={error} />;
  const s = data.summary;
  const lastMonth = s ? data.months.find((m) => m.month === s.last_month) : undefined;

  return (
    <div className="space-y-6">
      <p className="text-xs leading-5 text-muted">
        {data.note} آخرین پردازش: {faAgo(data.generated_at)}. {data.stale && <StaleBadge />}
      </p>

      {s && (
        <div className="grid gap-3 sm:grid-cols-2">
          <Panel>
            <h3 className="text-sm font-semibold">تولید ماه گذشته — {faJMonth(s.last_month)}</h3>
            <Total v={s.national?.last_month ?? null} label="کل کشور" />
            {producers.map((p) => (
              <Line key={p} name={p} v={s.producers[p]?.last_month ?? null} />
            ))}
          </Panel>
          <Panel>
            <h3 className="text-sm font-semibold">
              جمع سه ماه گذشته — {faJMonth(s.months_3[0], false)} تا {faJMonth(s.months_3[2])}
            </h3>
            <Total v={s.national && s.national.months_with_data === 3 ? s.national.sum_3m : null} label="کل کشور" />
            {producers.map((p) => {
              const r = s.producers[p];
              return <Line key={p} name={p} v={r?.sum_3m ?? null} partial={r && r.months_with_data < 3 ? r.months_with_data : undefined} />;
            })}
          </Panel>
        </div>
      )}
      {!s?.national && (
        <p className="rounded-lg bg-warn-bg px-3 py-2 text-xs leading-6 text-warn-ink">
          آمار کل کشور هنوز وارد نشده. فقط ایرالکو در کدال گزارش ماهانه دارد؛ برای کل کشور و سایر تولیدکنندگان (سالکو، المهدی، ...) فایل{' '}
          <code dir="ltr">data/manual/production_national.csv</code> را از گزارش‌های ایمیدرو پر کنید.
        </p>
      )}

      {option && (
        <Section title="تولید ماهانه (تن)" note="هر ستون: مجموع شمش خالص، آلیاژی، بیلت و اسلب یک ماه جلالی.">
          <Panel className="p-3">
            <EChart option={option} height={320} />
          </Panel>
        </Section>
      )}

      {lastMonth && (
        <Section title={`جزئیات ${faJMonth(lastMonth.month)}`}>
          <div className="overflow-x-auto rounded-xl border border-line bg-surface">
            <table className="tnum w-full min-w-[28rem] text-sm">
              <thead className="bg-surface-2 text-xs text-ink-2">
                <tr>
                  <th className="px-3 py-2 text-right font-medium">تولیدکننده</th>
                  <th className="px-3 py-2 text-right font-medium">محصول</th>
                  <th className="px-3 py-2 text-left font-medium">تن</th>
                  <th className="px-3 py-2 text-right font-medium">منبع</th>
                </tr>
              </thead>
              <tbody>
                {Object.entries(lastMonth.producers).flatMap(([p, r]) =>
                  (r.products ? Object.entries(r.products).filter(([, v]) => v > 0) : [['کل', r.tonnes] as [string, number]]).map(([prod, v], i) => (
                    <tr key={p + prod} className="border-t border-line">
                      <td className="px-3 py-2">{i === 0 ? p : ''}</td>
                      <td className="px-3 py-2 text-ink-2">{prod}</td>
                      <td className="px-3 py-2 text-left">{faNum(v)}</td>
                      <td className="px-3 py-2 text-[11px] text-muted">
                        {i === 0 &&
                          (r.source_url ? (
                            <a href={r.source_url} target="_blank" rel="noopener noreferrer" className="underline decoration-dotted">
                              {r.source}
                            </a>
                          ) : (
                            r.source
                          ))}
                        {i === 0 && r.published_at && <> — انتشار {r.published_at}</>}
                        {i === 0 && r.corrected && <> (اصلاحیه)</>}
                      </td>
                    </tr>
                  )),
                )}
              </tbody>
            </table>
          </div>
        </Section>
      )}

      <details className="rounded-xl border border-line bg-surface text-sm">
        <summary className="cursor-pointer px-3 py-2 text-ink-2">جدول همهٔ ماه‌ها</summary>
        <div className="max-h-96 overflow-auto border-t border-line">
          <table className="tnum w-full text-xs">
            <thead className="sticky top-0 bg-surface-2 text-ink-2">
              <tr>
                <th className="px-3 py-1.5 text-right font-medium">ماه</th>
                {[...producers, NATIONAL].map((p) => (
                  <th key={p} className="px-3 py-1.5 text-left font-medium">{p}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {[...data.months].reverse().map((m) => (
                <tr key={m.month} className="border-t border-line">
                  <td className="px-3 py-1.5">{faJMonth(m.month)}</td>
                  {[...producers, NATIONAL].map((p) => (
                    <td key={p} className="px-3 py-1.5 text-left">{m.producers[p] ? faNum(m.producers[p].tonnes) : '—'}</td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </details>
    </div>
  );
}

function Total({ v, label }: { v: number | null; label: string }) {
  return (
    <p className="mt-2 text-2xl font-bold">
      {v == null ? <span className="text-base font-normal text-muted">{label}: ثبت نشده</span> : <>{faNum(v)} <span className="text-xs font-normal text-muted">تن ({label})</span></>}
    </p>
  );
}

function Line({ name, v, partial }: { name: string; v: number | null; partial?: number }) {
  return (
    <p className="mt-1 flex justify-between gap-2 border-t border-line pt-1 text-sm">
      <span className="text-ink-2">{name}</span>
      <span className="tnum font-semibold">
        {v == null ? '—' : `${faNum(v)} تن`}
        {partial != null && <span className="font-normal text-[11px] text-muted"> (فقط {faNum(partial)} ماه)</span>}
      </span>
    </p>
  );
}
