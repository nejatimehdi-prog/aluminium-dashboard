import { useCallback, useEffect, useState } from 'react';

export type ThemeChoice = 'system' | 'light' | 'dark';

function read(): ThemeChoice {
  try {
    const t = localStorage.getItem('theme');
    return t === 'light' || t === 'dark' ? t : 'system';
  } catch {
    return 'system';
  }
}

function apply(t: ThemeChoice) {
  const el = document.documentElement;
  if (t === 'system') delete el.dataset.theme;
  else el.dataset.theme = t;
  try {
    if (t === 'system') localStorage.removeItem('theme');
    else localStorage.setItem('theme', t);
  } catch {
    /* storage may be blocked; the choice just won't persist */
  }
  window.dispatchEvent(new Event('themechange'));
}

/** Cycles system → light → dark. */
export function useTheme(): [ThemeChoice, () => void] {
  const [t, setT] = useState<ThemeChoice>(read);
  const cycle = useCallback(() => {
    setT((cur) => {
      const next: ThemeChoice = cur === 'system' ? 'light' : cur === 'light' ? 'dark' : 'system';
      apply(next);
      return next;
    });
  }, []);
  return [t, cycle];
}

/** True when the page currently renders dark (resolved from the choice + OS setting). */
export function useIsDark() {
  const get = () => {
    const t = document.documentElement.dataset.theme;
    if (t) return t === 'dark';
    return matchMedia('(prefers-color-scheme: dark)').matches;
  };
  const [dark, setDark] = useState(get);
  useEffect(() => {
    const mq = matchMedia('(prefers-color-scheme: dark)');
    const on = () => setDark(get());
    mq.addEventListener('change', on);
    addEventListener('themechange', on);
    return () => {
      mq.removeEventListener('change', on);
      removeEventListener('themechange', on);
    };
  }, []);
  return dark;
}

/** Reads a CSS custom property from :root (resolved for the current theme). */
export const cssVar = (name: string) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();
