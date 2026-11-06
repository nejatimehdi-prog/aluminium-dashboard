import { useEffect, useState, type ReactNode } from 'react';
import { cssVar } from './theme';

/** Loads one JSON file once; shows a message while loading or on error. */
export function useJson<T>(load: () => Promise<T>): { data: T | null; error: string | null } {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let alive = true;
    load()
      .then((d) => alive && setData(d))
      .catch((e) => alive && setError(String(e)));
    return () => {
      alive = false;
    };
  }, [load]);
  return { data, error };
}

export function Loading({ error }: { error: string | null }) {
  return error ? (
    <p className="rounded-lg bg-warn-bg p-3 text-sm text-warn-ink">داده بارگیری نشد: {error}</p>
  ) : (
    <p className="text-sm text-muted">در حال بارگیری…</p>
  );
}

export function Section({ title, children, note }: { title: string; children: ReactNode; note?: ReactNode }) {
  return (
    <section>
      <h2 className="mb-2 text-sm font-semibold text-ink-2">{title}</h2>
      {children}
      {note && <p className="mt-1 text-[11px] leading-5 text-muted">{note}</p>}
    </section>
  );
}

export function Panel({ children, className = '' }: { children: ReactNode; className?: string }) {
  return <div className={`rounded-xl border border-line bg-surface p-4 ${className}`}>{children}</div>;
}

export function StaleBadge() {
  return <span className="rounded-md bg-warn-bg px-1.5 py-0.5 text-[11px] font-medium text-warn-ink">به‌روز نشده</span>;
}

export function Seg<T extends string>({ items, value, onChange, label }: {
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

/** Common ECharts chrome read from the current theme's CSS variables. */
export function chartChrome() {
  const muted = cssVar('--muted');
  return {
    muted,
    ink: cssVar('--ink'),
    ink2: cssVar('--ink-2'),
    grid: cssVar('--grid'),
    axis: cssVar('--axis'),
    surface: cssVar('--surface'),
    tooltip: {
      backgroundColor: cssVar('--surface'),
      borderColor: cssVar('--axis'),
      textStyle: { color: cssVar('--ink'), fontFamily: 'Vazirmatn' },
    },
    label: { color: muted, fontFamily: 'Vazirmatn' },
  };
}
