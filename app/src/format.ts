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
  const r = Number(v.toFixed(digits)); // no sign on a value that rounds to zero («−۰٪»)
  const s = r > 0 ? '+' : r < 0 ? '−' : '';
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

const J_MONTHS = ['فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور', 'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'];
/** "1405/07" → «مهر ۱۴۰۵» */
export function faJMonth(m: string, withYear = true) {
  const [y, mm] = m.split('/');
  return `${J_MONTHS[+mm - 1]}${withYear ? ` ${faDigits(y)}` : ''}`;
}

/** 12345678 → «۱۲٫۳ میلیون» */
export function faUsd(v: number | null | undefined) {
  if (v == null) return '—';
  if (v >= 1e9) return `${faNum(v / 1e9, 2)} میلیارد دلار`;
  if (v >= 1e6) return `${faNum(v / 1e6, 1)} میلیون دلار`;
  return `${faNum(v)} دلار`;
}

export const faShortDate = (iso: string) => faDigits(format(new Date(`${iso}T12:00:00`), 'd MMMM', { locale: faIR }));
