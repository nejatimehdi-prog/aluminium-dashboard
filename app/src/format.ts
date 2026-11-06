import { format, formatDistanceToNowStrict } from 'date-fns-jalali';
import { faIR } from 'date-fns-jalali/locale';

const nf = new Map<string, Intl.NumberFormat>();
function fmt(digits: number) {
  const k = String(digits);
  if (!nf.has(k)) nf.set(k, new Intl.NumberFormat('fa-IR', { maximumFractionDigits: digits, minimumFractionDigits: 0 }));
  return nf.get(k)!;
}

/** 3160 → «۳٬۱۶۰» */
export const faNum = (v: number | null | undefined, digits = 0) => (v == null || Number.isNaN(v) ? '—' : fmt(digits).format(v));

/** 1.2 → «+۱٫۲٪» (sign shown explicitly, LTR-isolated so it stays on the left of the digits) */
export function faPct(v: number | null | undefined, digits = 1) {
  if (v == null) return '—';
  const s = v > 0 ? '+' : v < 0 ? '−' : '';
  return `⁦${s}${fmt(digits).format(Math.abs(v))}٪⁩`;
}

/** Latin digits → Persian digits (date-fns formats numbers with Latin digits). */
export const faDigits = (s: string) => s.replace(/\d/g, (d) => '۰۱۲۳۴۵۶۷۸۹'[+d]);

/** "2026-11-05" → «۱۴ آبان ۱۴۰۵» (a date-only string is a calendar day, so parse it as local) */
export function faDate(iso: string | undefined, withYear = true) {
  if (!iso) return '—';
  const d = iso.length === 10 ? new Date(`${iso}T12:00:00`) : new Date(iso);
  return faDigits(format(d, withYear ? 'd MMMM yyyy' : 'd MMMM', { locale: faIR }));
}

/** ISO timestamp → «۱۴ آبان، ۲۱:۳۰» in the viewer's local time */
export function faDateTime(iso: string | undefined) {
  if (!iso) return '—';
  return faDigits(format(new Date(iso), 'd MMMM، HH:mm', { locale: faIR }));
}

/** ISO timestamp → «۲۰ دقیقه پیش» */
export function faAgo(iso: string | undefined) {
  if (!iso) return '—';
  return faDigits(formatDistanceToNowStrict(new Date(iso), { locale: faIR, addSuffix: true }));
}

export const faShortDate = (iso: string) => faDigits(format(new Date(`${iso}T12:00:00`), 'd MMMM', { locale: faIR }));
