import { useMemo, useState } from 'react';
import type { EChartsCoreOption } from 'echarts/core';
import EChart from '../EChart';
import { loadTrade, type Trade as TradeData, type TradeTotals } from '../data';
import { faAgo, faDigits, faNum, faUsd } from '../format';
import { cssVar, useIsDark } from '../theme';
import { chartChrome, Loading, Panel, Section, Seg, StaleBadge, useJson } from '../ui';

const CATS = ['ingot', 'scrap', 'products'] as const;
const CAT_FA: Record<(typeof CATS)[number], string> = { ingot: 'شمش', scrap: 'ضایعات', products: 'محصولات' };
const VIEWS = [
  { id: 'mirror', label: 'آینه‌ای (کشورهای طرف تجاری)' },
  { id: 'reported', label: 'گزارش خود ایران' },
] as const;
type View = (typeof VIEWS)[number]['id'];
const FLOW_FA = { export: 'صادرات', import: 'واردات' } as const;

function latestYear(d: TradeData, view: View) {
  return [...d.comtrade].reverse().find((y) => y[view].export || y[view].import);
}

export default function Trade() {
  const { data, error } = useJson(loadTrade);
  const [view, setView] = useState<View>('mirror');
  const dark = useIsDark();

  const option = useMemo<EChartsCoreOption | null>(() => {
    if (!data) return null;
    const c = chartChrome();
    const years = data.comtrade.map((y) => y.year);
    const s = (name: string, color: string, get: (y: TradeData['comtrade'][number]) => number | undefined) => ({
      name, type: 'bar', barMaxWidth: 26, barGap: '10%',
      itemStyle: { color: cssVar(color), borderRadius: [4, 4, 0, 0] },
      data: data.comtrade.map((y) => get(y) ?? null),
    });
    return {
      animation: false,
      textStyle: { fontFamily: 'Vazirmatn' },
      grid: { top: 30, bottom: 50, left: 8, right: 8, containLabel: true },
      legend: { bottom: 0, textStyle: { color: c.ink2, fontFamily: 'Vazirmatn' } },
      tooltip: { trigger: 'axis', ...c.tooltip, valueFormatter: (v: number | null) => (v == null ? 'گزارش نشده' : `${faNum(v)} تن`) },
      xAxis: { type: 'category', data: years.map(faDigits), axisLabel: c.label, axisLine: { lineStyle: { color: c.axis } } },
      yAxis: { type: 'value', name: 'تن', nameTextStyle: c.label, axisLabel: { ...c.label, formatter: (v: number) => faNum(v) }, splitLine: { lineStyle: { color: c.grid } } },
      series: [
        s('صادرات شمش — گزارش ایران', '--s-lme', (y) => y.reported.export?.ingot.tonnes),
        s('صادرات شمش — آینه‌ای', '--s-comex', (y) => y.mirror.export?.ingot.tonnes),
      ],
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data, dark]);

  if (!data) return <Loading error={error} />;
  const ly = latestYear(data, view);

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center gap-2">
        <Seg items={VIEWS} value={view} onChange={setView} label="نوع آمار" />
        {data.stale && <StaleBadge />}
      </div>

      {ly ? (
        <Section
          title={`سال ${faDigits(ly.year)} — ${VIEWS.find((v) => v.id === view)!.label}`}
          note={`منبع: ${data.source} — دریافت ${faAgo(ly.fetched_at)}.`}
        >
          <div className="grid gap-3 sm:grid-cols-2">
            {(['export', 'import'] as const).map((f) => (
              <Panel key={f}>
                <h3 className="mb-2 text-sm font-semibold">{FLOW_FA[f]}</h3>
                {ly[view][f] ? (
                  <>
                    {CATS.map((cat) => (
                      <Row key={cat} label={data.categories[cat]} t={ly[view][f]![cat]} />
                    ))}
                    {view === 'mirror' && <Partners t={ly[view][f]!.ingot} flow={f} />}
                  </>
                ) : (
                  <p className="text-sm text-muted">برای این سال گزارش نشده.</p>
                )}
              </Panel>
            ))}
          </div>
        </Section>
      ) : (
        <p className="text-sm text-muted">داده‌ای برای این نوع آمار نیست.</p>
      )}

      {option && (
        <Section title="صادرات شمش ایران در سال‌های اخیر (تن)" note="ستون خالی یعنی آن سال گزارش نشده؛ دادهٔ آینه‌ای سال جاری ناقص است.">
          <Panel className="p-3">
            <EChart option={option} height={300} />
          </Panel>
        </Section>
      )}

      <details className="rounded-xl border border-line bg-surface text-sm">
        <summary className="cursor-pointer px-3 py-2 text-ink-2">جدول همهٔ سال‌ها ({VIEWS.find((v) => v.id === view)!.label})</summary>
        <div className="overflow-x-auto border-t border-line">
          <table className="tnum w-full min-w-[36rem] text-xs">
            <thead className="bg-surface-2 text-ink-2">
              <tr>
                <th className="px-3 py-1.5 text-right font-medium">سال</th>
                {(['export', 'import'] as const).flatMap((f) =>
                  CATS.map((c) => (
                    <th key={f + c} className="px-3 py-1.5 text-left font-medium">{FLOW_FA[f]} {CAT_FA[c]}</th>
                  )),
                )}
              </tr>
            </thead>
            <tbody>
              {[...data.comtrade].reverse().map((y) => (
                <tr key={y.year} className="border-t border-line">
                  <td className="px-3 py-1.5">{faDigits(y.year)}</td>
                  {(['export', 'import'] as const).flatMap((f) =>
                    CATS.map((c) => (
                      <td key={f + c} className="px-3 py-1.5 text-left">{y[view][f] ? faNum(y[view][f]![c].tonnes) : '—'}</td>
                    )),
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="border-t border-line px-3 py-2 text-[11px] text-muted">اعداد به تن. منبع: {data.source}</p>
      </details>

      <Section title="آمار گمرک ایران (ورود دستی)">
        {data.customs.length ? (
          <div className="overflow-x-auto rounded-xl border border-line bg-surface">
            <table className="tnum w-full min-w-[30rem] text-sm">
              <thead className="bg-surface-2 text-xs text-ink-2">
                <tr>
                  <th className="px-3 py-2 text-right font-medium">دوره</th>
                  <th className="px-3 py-2 text-right font-medium">جریان</th>
                  <th className="px-3 py-2 text-right font-medium">گروه</th>
                  <th className="px-3 py-2 text-left font-medium">تن</th>
                  <th className="px-3 py-2 text-left font-medium">ارزش</th>
                  <th className="px-3 py-2 text-right font-medium">منبع</th>
                </tr>
              </thead>
              <tbody>
                {data.customs.map((r, i) => (
                  <tr key={i} className="border-t border-line">
                    <td className="px-3 py-2">{faDigits(r.period)}</td>
                    <td className="px-3 py-2">{FLOW_FA[r.flow]}</td>
                    <td className="px-3 py-2">{CAT_FA[r.category]}</td>
                    <td className="px-3 py-2 text-left">{faNum(r.tonnes)}</td>
                    <td className="px-3 py-2 text-left">{faUsd(r.usd)}</td>
                    <td className="px-3 py-2 text-[11px] text-muted">{r.source}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="text-xs leading-6 text-muted">
            هنوز ثبت نشده. برای افزودن، فایل <code dir="ltr">data/manual/customs_trade.csv</code> را پر کنید.
          </p>
        )}
      </Section>

      <ul className="list-disc space-y-1 ps-5 text-[11px] leading-5 text-muted">
        {data.notes.map((n) => (
          <li key={n}>{n}</li>
        ))}
      </ul>
    </div>
  );
}

function Row({ label, t }: { label: string; t: TradeTotals }) {
  return (
    <div className="flex items-baseline justify-between gap-2 border-t border-line py-1.5 text-sm first:border-t-0">
      <span className="text-ink-2">{label}</span>
      <span className="tnum text-left">
        <b>{faNum(t.tonnes)}</b> <span className="text-xs text-muted">تن</span>
        <span className="block text-[11px] text-muted">
          {faUsd(t.usd)}
          {t.reporters > 1 && ` — ${faNum(t.reporters)} کشور گزارش‌دهنده`}
          {t.weight_missing > 0 && ` — وزن ${faNum(t.weight_missing)} ردیف نامعلوم`}
        </span>
      </span>
    </div>
  );
}

function Partners({ t, flow }: { t: TradeTotals; flow: 'export' | 'import' }) {
  if (!t.top_partners?.length) return null;
  return (
    <p className="mt-2 text-[11px] leading-5 text-muted">
      {flow === 'export' ? 'بزرگ‌ترین خریداران شمش: ' : 'بزرگ‌ترین فروشندگان شمش: '}
      {t.top_partners.slice(0, 4).map((p) => `${p.name} (${faNum(p.tonnes)} تن)`).join('، ')}
    </p>
  );
}
