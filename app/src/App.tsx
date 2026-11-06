import { lazy, Suspense, useEffect, useState } from 'react';
import Home from './pages/Home';
import Soon from './pages/Soon';
import { useTheme } from './theme';

const Charts = lazy(() => import('./pages/Charts')); // keeps ECharts out of the first load

const TABS = [
  { id: 'home', label: 'خانه' },
  { id: 'charts', label: 'نمودارها' },
  { id: 'forecast', label: 'پیش‌بینی' },
  { id: 'production', label: 'تولید' },
  { id: 'trade', label: 'تجارت خارجی' },
] as const;
type TabId = (typeof TABS)[number]['id'];

const readHash = (): TabId => {
  const h = location.hash.replace('#', '');
  return (TABS.find((t) => t.id === h)?.id ?? 'home') as TabId;
};

export default function App() {
  const [tab, setTab] = useState<TabId>(readHash);
  const [theme, cycleTheme] = useTheme();
  const online = useOnline();

  useEffect(() => {
    const on = () => setTab(readHash());
    addEventListener('hashchange', on);
    return () => removeEventListener('hashchange', on);
  }, []);

  return (
    <div className="mx-auto min-h-dvh max-w-5xl px-4 pb-10">
      <header className="flex items-center justify-between gap-3 pt-[max(1rem,env(safe-area-inset-top))] pb-3">
        <div className="flex items-center gap-2.5 min-w-0">
          <img src="icon.svg" alt="" className="size-9 shrink-0 rounded-lg" />
          <div className="min-w-0">
            <h1 className="truncate text-lg font-bold leading-tight">داشبورد شمش آلومینیوم</h1>
            <p className="text-xs text-muted">قیمت جهانی و ایران، به‌روزرسانی خودکار</p>
          </div>
        </div>
        <button
          onClick={cycleTheme}
          className="shrink-0 rounded-lg border border-line bg-surface px-3 py-1.5 text-sm text-ink-2 hover:bg-surface-2"
          aria-label="تغییر حالت روشن و تیره"
        >
          {theme === 'system' ? 'خودکار' : theme === 'dark' ? 'تیره' : 'روشن'}
        </button>
      </header>

      <nav className="sticky top-0 z-10 -mx-4 mb-4 border-b border-line bg-page/95 px-4 backdrop-blur">
        <ul className="flex gap-1 overflow-x-auto py-2 [scrollbar-width:none]">
          {TABS.map((t) => (
            <li key={t.id}>
              <a
                href={`#${t.id}`}
                aria-current={tab === t.id ? 'page' : undefined}
                className={`block whitespace-nowrap rounded-lg px-3 py-1.5 text-sm ${
                  tab === t.id ? 'bg-accent font-semibold text-accent-ink' : 'text-ink-2 hover:bg-surface-2'
                }`}
              >
                {t.label}
              </a>
            </li>
          ))}
        </ul>
      </nav>

      {!online && (
        <p className="mb-4 rounded-lg bg-warn-bg px-3 py-2 text-sm text-warn-ink">
          آفلاین هستید — آخرین داده‌های ذخیره‌شده نمایش داده می‌شود.
        </p>
      )}

      <main>
        {tab === 'home' && <Home />}
        {tab === 'charts' && (
          <Suspense fallback={<p className="text-sm text-muted">در حال بارگیری نمودار…</p>}>
            <Charts />
          </Suspense>
        )}
        {tab === 'forecast' && <Soon title="پیش‌بینی" phase="۳" />}
        {tab === 'production' && <Soon title="تولید شمش ایران" phase="۲" />}
        {tab === 'trade' && <Soon title="صادرات و واردات" phase="۲" />}
      </main>

      <footer className="mt-10 border-t border-line pt-4 text-xs leading-6 text-muted">
        این تحلیل آماری است و توصیهٔ معاملاتی نیست. کنار هر عدد منبع و زمان دریافت آن آمده است؛ اگر منبعی
        به‌روز نشود، آخرین مقدار معتبر با برچسب «به‌روز نشده» نمایش داده می‌شود.
      </footer>
    </div>
  );
}

function useOnline() {
  const [online, setOnline] = useState(() => navigator.onLine);
  useEffect(() => {
    const on = () => setOnline(navigator.onLine);
    addEventListener('online', on);
    addEventListener('offline', on);
    return () => {
      removeEventListener('online', on);
      removeEventListener('offline', on);
    };
  }, []);
  return online;
}
