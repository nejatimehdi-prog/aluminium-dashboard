import { useEffect, useState } from 'react';
import { loadLatest, loadStatus, type Card, type Gap, type Latest, type Status } from '../data';
import { faAgo, faDate, faDateTime, faNum, faPct } from '../format';

const SECTIONS: { title: string; ids: string[] }[] = [
  { title: 'قیمت جهانی', ids: ['lme_cash', 'comex', 'shfe'] },
  { title: 'بازار ایران', ids: ['ime_ingot', 'iran_free_market'] },
  { title: 'نرخ ارز', ids: ['fx_free', 'fx_ime'] },
];

const MANUAL_FILE: Record<string, string> = {
  iran_free_market: 'data/manual/iran_free_market.csv',
  fx_free: 'data/manual/fx_free_market.csv',
};

export default function Home() {
  const [latest, setLatest] = useState<Latest | null>(null);
  const [status, setStatus] = useState<Status | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    const load = () => {
      loadLatest()
        .then((l) => alive && (setLatest(l), setError(null)))
        .catch((e) => alive && setError(String(e)));
      loadStatus().then((s) => alive && setStatus(s)).catch(() => {});
    };
    load();
    const t = setInterval(load, 5 * 60 * 1000); // pick up new data while the app stays open
    return () => {
      alive = false;
      clearInterval(t);
    };
  }, []);

  if (error && !latest) return <p className="rounded-lg bg-warn-bg p-3 text-sm text-warn-ink">داده بارگیری نشد: {error}</p>;
  if (!latest) return <p className="text-sm text-muted">در حال بارگیری…</p>;

  return (
    <div className="space-y-6">
      <p className="text-xs text-muted">
        آخرین پردازش داده‌ها: {faDateTime(latest.generated_at)} ({faAgo(latest.generated_at)})
      </p>
      {SECTIONS.map((s) => (
        <section key={s.title}>
          <h2 className="mb-2 text-sm font-semibold text-ink-2">{s.title}</h2>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {s.ids.map((id) => latest.cards[id] && <PriceCard key={id} c={latest.cards[id]} />)}
            {s.title === 'بازار ایران' && <GapCard g={latest.gap} />}
          </div>
        </section>
      ))}
      {latest.cards.ime_ingot?.detail && <ImeTable c={latest.cards.ime_ingot} />}
      {status && <StatusList s={status} />}
    </div>
  );
}

function Badge({ reason }: { reason?: string | null }) {
  return (
    <span className="rounded-md bg-warn-bg px-1.5 py-0.5 text-[11px] font-medium text-warn-ink" title={reason ?? ''}>
      به‌روز نشده
    </span>
  );
}

function Change({ c }: { c: Card }) {
  if (c.change_pct == null) return null;
  const up = c.change_pct > 0;
  const down = c.change_pct < 0;
  return (
    <p className="text-xs text-muted">
      <span className={`font-semibold ${up ? 'text-up' : down ? 'text-down' : 'text-ink-2'}`}>
        {up ? '▲' : down ? '▼' : '•'} {faPct(c.change_pct, 2)}
      </span>{' '}
      نسبت به {c.freq === 'daily' && c.group === 'iran' ? 'معاملهٔ قبلی' : 'روز قبل'} ({faDate(c.prev_date, false)})
    </p>
  );
}

function PriceCard({ c }: { c: Card }) {
  const empty = c.value == null;
  return (
    <article className="flex flex-col gap-2 rounded-xl border border-line bg-surface p-4">
      <header className="flex items-start justify-between gap-2">
        <h3 className="text-sm font-semibold">{c.title}</h3>
        {c.stale && !empty && <Badge reason={c.stale_reason} />}
      </header>
      {empty ? (
        <p className="text-sm leading-6 text-muted">
          هنوز داده‌ای ثبت نشده.
          {MANUAL_FILE[c.id] && (
            <>
              {' '}
              برای نمایش، فایل <code className="text-[11px]" dir="ltr">{MANUAL_FILE[c.id]}</code> را پر کنید.
            </>
          )}
        </p>
      ) : (
        <>
          <p className="text-2xl font-bold">
            {faNum(c.value)} <span className="text-xs font-normal text-muted">{c.unit_fa}</span>
          </p>
          <Change c={c} />
        </>
      )}
      <dl className="mt-auto space-y-0.5 border-t border-line pt-2 text-[11px] leading-5 text-muted">
        {!empty && (
          <div>
            <dt className="inline">تاریخ داده: </dt>
            <dd className="inline">{c.time ? faDateTime(c.time) : faDate(c.date)}</dd>
          </div>
        )}
        <div>
          <dt className="inline">منبع: </dt>
          <dd className="inline">
            {c.source_url ? (
              <a href={c.source_url} target="_blank" rel="noopener noreferrer" className="underline decoration-dotted">
                {c.source}
              </a>
            ) : (
              c.source
            )}
          </dd>
        </div>
        {c.fetched_at && (
          <div>
            <dt className="inline">دریافت: </dt>
            <dd className="inline">{faAgo(c.fetched_at)}</dd>
          </div>
        )}
        {c.stale && c.stale_reason && !empty && <div className="text-warn-ink">{c.stale_reason}</div>}
      </dl>
    </article>
  );
}

function GapCard({ g }: { g: Gap | null }) {
  return (
    <article className="flex flex-col gap-2 rounded-xl border border-line bg-surface p-4">
      <header className="flex items-start justify-between gap-2">
        <h3 className="text-sm font-semibold">شکاف قیمت ایران و جهان</h3>
        {g?.stale && <Badge />}
      </header>
      {!g ? (
        <p className="text-sm text-muted">برای محاسبه، قیمت بورس کالا، LME و نرخ دلار لازم است.</p>
      ) : (
        <>
          <p className="text-2xl font-bold">{faPct(g.value_pct)}</p>
          <p className="text-xs leading-5 text-muted">
            بورس کالا {faNum(g.iran_toman_per_kg)} در برابر معادل جهانی {faNum(g.world_toman_per_kg)} تومان بر کیلوگرم
            (LME × {g.fx_title}: {faNum(g.fx_value)} تومان)
          </p>
          <dl className="mt-auto border-t border-line pt-2 text-[11px] leading-5 text-muted">
            <dt className="inline">منبع: </dt>
            <dd className="inline">{g.source}</dd>
            <div>
              تاریخ‌ها: بورس {faDate(g.dates.iran, false)}، LME {faDate(g.dates.lme, false)}، دلار {faDate(g.dates.fx, false)}
            </div>
          </dl>
        </>
      )}
    </article>
  );
}

function ImeTable({ c }: { c: Card }) {
  const d = c.detail!;
  const rows = [...d.trades].sort((a, b) => a.producer.localeCompare(b.producer, 'fa') || a.price - b.price);
  return (
    <section>
      <h2 className="mb-2 text-sm font-semibold text-ink-2">معاملات شمش خالص در بورس کالا — {faDate(d.date)}</h2>
      <div className="overflow-x-auto rounded-xl border border-line bg-surface">
        <table className="tnum w-full min-w-[30rem] text-sm">
          <thead className="bg-surface-2 text-xs text-ink-2">
            <tr>
              <th className="px-3 py-2 text-right font-medium">تولیدکننده</th>
              <th className="px-3 py-2 text-right font-medium">عیار</th>
              <th className="px-3 py-2 text-left font-medium">میانگین (تومان/کیلوگرم)</th>
              <th className="px-3 py-2 text-left font-medium">حجم (تن)</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((t, i) => (
              <tr key={i} className="border-t border-line">
                <td className="px-3 py-2">{t.producer}</td>
                <td className="px-3 py-2 text-ink-2" dir="ltr">{t.grade}</td>
                <td className="px-3 py-2 text-left">{faNum(t.price)}</td>
                <td className="px-3 py-2 text-left">{faNum(t.tonnes)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="mt-1 text-[11px] text-muted">
        فقط معاملات نقدی با تسویهٔ نقدی در تالار اصلی. میانگین کارت «بورس کالا» بر اساس حجم وزن‌دهی شده است. منبع: ime.co.ir
      </p>
    </section>
  );
}

function StatusList({ s }: { s: Status }) {
  const items = Object.entries(s.collectors).filter(([k]) => k !== 'summary');
  return (
    <section>
      <h2 className="mb-2 text-sm font-semibold text-ink-2">وضعیت جمع‌آوری داده</h2>
      <ul className="divide-y divide-line rounded-xl border border-line bg-surface text-xs">
        {items.map(([k, c]) => (
          <li key={k} className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1 px-3 py-2">
            <span className="font-medium">
              <span aria-hidden className={c.ok ? 'text-up' : 'text-down'}>
                {c.ok ? '✓' : '✕'}
              </span>{' '}
              {c.title} <span className="sr-only">{c.ok ? 'موفق' : 'ناموفق'}</span>
            </span>
            <span className="text-muted">
              {c.ok ? `موفق ${faAgo(c.last_success)}` : `خطا ${faAgo(c.last_attempt)} — آخرین موفق: ${c.last_success ? faAgo(c.last_success) : 'هرگز'}`}
            </span>
            {!c.ok && c.error && (
              <span className="w-full break-words text-[11px] text-down" dir="ltr">
                {c.error}
              </span>
            )}
          </li>
        ))}
      </ul>
    </section>
  );
}
