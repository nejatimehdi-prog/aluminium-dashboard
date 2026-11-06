import { useMemo, useState } from 'react';
import type { EChartsCoreOption } from 'echarts/core';
import EChart from '../EChart';
import { loadForecast, type Forecast as F } from '../data';
import { faAgo, faDate, faNum, faPct, faShortDate } from '../format';
import { cssVar, useIsDark } from '../theme';
import { chartChrome, Loading, Panel, Section, Seg, useJson } from '../ui';

const SCEN = ['pessimistic', 'base', 'optimistic'] as const;
const TARGETS = [
  { id: 'iran', label: 'قیمت ایران' },
  { id: 'lme', label: 'LME' },
] as const;
type Target = (typeof TARGETS)[number]['id'];

export default function Forecast() {
  const { data, error } = useJson(loadForecast);
  const [target, setTarget] = useState<Target>('iran');
  const dark = useIsDark();

  const option = useMemo<EChartsCoreOption | null>(() => {
    if (!data) return null;
    const c = chartChrome();
    const t = data[target];
    const hist = target === 'iran' ? data.history.iran : data.history.lme;
    const color = cssVar(target === 'iran' ? '--s-ime' : '--s-lme');
    const fan = t.fan;
    const digits = target === 'iran' ? 0 : 1;
    return {
      animation: false,
      textStyle: { fontFamily: 'Vazirmatn' },
      grid: { top: 30, bottom: 50, left: 8, right: 8, containLabel: true },
      legend: { bottom: 0, textStyle: { color: c.ink2, fontFamily: 'Vazirmatn' }, data: ['واقعی', 'مبنا', `باند صدک ${faNum(data.percentiles[0])} تا ${faNum(data.percentiles[2])}`] },
      tooltip: {
        trigger: 'axis', ...c.tooltip,
        formatter: (ps: { seriesName: string; value: [string, number]; seriesId: string }[]) => {
          const d = ps[0]?.value[0];
          const f = fan.find((r) => r[0] === d);
          const h = hist.find((r) => r[0] === d);
          let s = `<div style="color:${c.muted};margin-bottom:4px">${faDate(d)}</div>`;
          if (h) s += `واقعی: <b>${faNum(h[1], digits)}</b><br/>`;
          if (f) s += `بدبینانه: ${faNum(f[1], digits)}<br/>مبنا: <b>${faNum(f[2], digits)}</b><br/>خوشبینانه: ${faNum(f[3], digits)}`;
          return s + `<div style="color:${c.muted}">${t.unit}</div>`;
        },
      },
      xAxis: {
        type: 'time',
        axisLabel: { ...c.label, hideOverlap: true, formatter: (v: number) => faShortDate(new Date(v).toISOString().slice(0, 10)) },
        axisLine: { lineStyle: { color: c.axis } },
      },
      yAxis: { type: 'value', scale: true, name: t.unit, nameTextStyle: c.label, axisLabel: { ...c.label, formatter: (v: number) => faNum(v) }, splitLine: { lineStyle: { color: c.grid } } },
      series: [
        { id: 'hist', name: 'واقعی', type: 'line', data: hist, showSymbol: target === 'iran', symbolSize: 6, lineStyle: { width: 2 }, itemStyle: { color } },
        // band = invisible lower edge + stacked (upper − lower) area
        { id: 'lo', name: 'lo', type: 'line', stack: 'band', data: fan.map((r) => [r[0], r[1]]), lineStyle: { opacity: 0 }, symbol: 'none', silent: true },
        {
          id: 'band', name: `باند صدک ${faNum(data.percentiles[0])} تا ${faNum(data.percentiles[2])}`, type: 'line', stack: 'band',
          data: fan.map((r) => [r[0], r[3] - r[1]]), lineStyle: { opacity: 0 }, symbol: 'none',
          areaStyle: { color, opacity: 0.18 }, itemStyle: { color }, silent: true,
        },
        { id: 'p50', name: 'مبنا', type: 'line', data: fan.map((r) => [r[0], r[2]]), symbol: 'none', lineStyle: { width: 2, type: 'dashed' }, itemStyle: { color } },
      ],
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data, target, dark]);

  if (!data) return <Loading error={error} />;
  const A = data.assumptions;

  return (
    <div className="space-y-6">
      <p className="rounded-lg border border-line bg-surface-2 px-3 py-2 text-sm font-semibold">{A.disclaimer}</p>
      <p className="text-xs leading-6 text-muted">
        محاسبه: {faAgo(data.generated_at)} — دادهٔ LME تا {faDate(data.as_of.lme)}، بورس کالا تا {faDate(data.as_of.iran)}.
        <br />
        روش: <b className="text-ink-2">{data.mode_fa}</b>
        {data.mode === 'implied_ratio' && (
          <>
            {' '}— برای رگرسیون {faNum(data.min_pairs)} روز معاملاتی با نرخ ارز معلوم لازم است؛ الان {faNum(data.fx_pairs)} روز.
            با پر کردن <code dir="ltr">fx_free_market.csv</code> یا گذشت زمان، خودکار به رگرسیون می‌رود.
          </>
        )}
      </p>

      <ScenarioTable f={data} which="iran" digits={0} />

      <Section title="نمودار سناریوها">
        <div className="mb-2">
          <Seg items={TARGETS} value={target} onChange={setTarget} label="سری" />
        </div>
        <Panel className="p-3">{option && <EChart option={option} height={340} />}</Panel>
      </Section>

      <ScenarioTable f={data} which="lme" digits={0} />

      <Section title={data.side.title} note={`باند این جزء ${faNum(data.side.vol_multiplier, 2)} برابر پهن‌تر از نوسان تاریخی گرفته شده است.`}>
        <SimpleTable f={data} />
      </Section>

      <Section title="دقت مدل LME در بک‌تست (MAPE)" note={`${faNum(data.lme.backtest.origins)} مبدأ از ${faDate(data.lme.backtest.from)} تا ${faDate(data.lme.backtest.to)}؛ هرچه کمتر بهتر. مدل منتخب: ${data.lme.model_fa}.`}>
        <div className="overflow-x-auto rounded-xl border border-line bg-surface">
          <table className="tnum w-full min-w-[26rem] text-sm">
            <thead className="bg-surface-2 text-xs text-ink-2">
              <tr>
                <th className="px-3 py-2 text-right font-medium">مدل</th>
                {data.horizons.map((h) => (
                  <th key={h.bdays} className="px-3 py-2 text-left font-medium">{h.label}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {Object.entries(data.lme.backtest.mape).map(([m, v]) => (
                <tr key={m} className={`border-t border-line ${m === data.lme.model ? 'font-semibold' : ''}`}>
                  <td className="px-3 py-2">{MODEL_FA[m] ?? m}{m === data.lme.model && ' ✓'}</td>
                  {data.horizons.map((h) => (
                    <td key={h.bdays} className="px-3 py-2 text-left">{faNum(v[h.bdays], 2)}٪</td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Section>

      {data.regression && (
        <Section title="ضریب و پرمیوم (رگرسیون)">
          <Panel className="text-sm leading-7">
            قیمت ایران = <b>{faNum(data.regression.a, 3)}</b> × (LME × ارز ÷ ۱۰۰۰) {data.regression.b >= 0 ? '+' : '−'} <b>{faNum(Math.abs(data.regression.b))}</b> تومان
            <div className="text-xs text-muted">
              R² = {faNum(data.regression.r2, 3)} — {faNum(data.regression.n)} روز معاملاتی ({faDate(data.regression.from)} تا {faDate(data.regression.to)})
            </div>
          </Panel>
        </Section>
      )}

      <Section title="فرض‌های سناریوها" note={<>این متن از فایل <code dir="ltr">data/manual/scenario_assumptions.json</code> می‌آید و قابل ویرایش است.</>}>
        <Panel className="space-y-3 text-sm leading-6">
          {SCEN.map((k) => (
            <p key={k}>
              <b>{A.scenarios[k].label}</b> (صدک {faNum(A.scenarios[k].percentile)}): {A.scenarios[k].description}
            </p>
          ))}
          <ul className="list-disc space-y-1 border-t border-line pt-3 ps-5 text-ink-2">
            {A.assumptions.map((a) => (
              <li key={a}>{a}</li>
            ))}
            <li>
              {faNum(A.n_paths)} مسیر شبیه‌سازی، پنجرهٔ بوت‌استرپ {faNum(A.bootstrap_window_days)} روز، ضریب پهنای ارز {faNum(A.fx_vol_multiplier, 2)}.
            </li>
          </ul>
        </Panel>
      </Section>
    </div>
  );
}

const MODEL_FA: Record<string, string> = {
  rw: 'گام تصادفی',
  ets: 'ETS (روند میرا)',
  arima: 'ARIMA(1,1,1)',
  ensemble: 'میانگین سه مدل',
};

function ScenarioTable({ f, which, digits }: { f: F; which: 'iran' | 'lme'; digits: number }) {
  const t = f[which];
  const bt = which === 'iran' ? f.iran.backtest : null;
  return (
    <Section
      title={`${t.title} — ${t.unit}`}
      note={`آخرین مقدار: ${faNum(t.last, digits)} (${faDate(t.last_date)}). ${which === 'lme' ? `مدل: ${f.lme.model_fa}.` : 'خطای بک‌تست: میانگین درصد خطای مطلق «مبنا» در گذشته؛ پوشش: درصد مواردی که قیمت واقعی داخل باند بدبینانه–خوشبینانه افتاد (ایده‌آل حدود ۸۰٪).'}`}
    >
      <div className="overflow-x-auto rounded-xl border border-line bg-surface">
        <table className="tnum w-full min-w-[30rem] text-sm">
          <thead className="bg-surface-2 text-xs text-ink-2">
            <tr>
              <th className="px-3 py-2 text-right font-medium">افق</th>
              {SCEN.map((s) => (
                <th key={s} className="px-3 py-2 text-left font-medium">{f.assumptions.scenarios[s].label}</th>
              ))}
              {bt && <th className="px-3 py-2 text-left font-medium">خطای بک‌تست</th>}
              {bt && <th className="px-3 py-2 text-left font-medium">پوشش</th>}
              {which === 'lme' && <th className="px-3 py-2 text-left font-medium">MAPE</th>}
            </tr>
          </thead>
          <tbody>
            {f.horizons.map((h, i) => {
              const b = bt?.[String(h.bdays)];
              const base = t.scenarios.base[i];
              return (
                <tr key={h.bdays} className="border-t border-line">
                  <td className="px-3 py-2">
                    {h.label}
                    <span className="block text-[11px] text-muted">{faDate(h.target)}</span>
                  </td>
                  {SCEN.map((s) => (
                    <td key={s} className={`px-3 py-2 text-left ${s === 'base' ? 'font-bold' : ''}`}>
                      {faNum(t.scenarios[s][i], digits)}
                      {s === 'base' && <span className="block text-[11px] font-normal text-muted">{faPct((base / t.last - 1) * 100)}</span>}
                    </td>
                  ))}
                  {bt && <td className="px-3 py-2 text-left">{b?.mape != null ? `${faNum(b.mape, 1)}٪` : '—'}<span className="block text-[11px] text-muted">n={faNum(b?.n ?? 0)}</span></td>}
                  {bt && <td className="px-3 py-2 text-left">{b?.coverage != null ? `${faNum(b.coverage)}٪` : '—'}</td>}
                  {which === 'lme' && <td className="px-3 py-2 text-left">{faNum(f.lme.backtest.mape[f.lme.model][h.bdays], 2)}٪</td>}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </Section>
  );
}

function SimpleTable({ f }: { f: F }) {
  return (
    <div className="overflow-x-auto rounded-xl border border-line bg-surface">
      <table className="tnum w-full min-w-[24rem] text-sm">
        <thead className="bg-surface-2 text-xs text-ink-2">
          <tr>
            <th className="px-3 py-2 text-right font-medium">افق</th>
            {SCEN.map((s) => (
              <th key={s} className="px-3 py-2 text-left font-medium">{f.assumptions.scenarios[s].label}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {f.horizons.map((h, i) => (
            <tr key={h.bdays} className="border-t border-line">
              <td className="px-3 py-2">{h.label}</td>
              {SCEN.map((s) => (
                <td key={s} className="px-3 py-2 text-left">{faNum(f.side.scenarios[s][i])}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
      <p className="border-t border-line px-3 py-1.5 text-[11px] text-muted">
        واحد: {f.side.unit} — آخرین: {faNum(f.side.last)}
      </p>
    </div>
  );
}
