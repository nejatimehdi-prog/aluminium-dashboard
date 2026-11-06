import { loadAlerts, type AlertRule, type Latest } from '../data';
import { faAgo, faNum } from '../format';
import { useJson } from '../ui';

const OP_FA: Record<AlertRule['op'], string> = {
  above: 'بالاتر از',
  below: 'پایین‌تر از',
  change_above: 'تغییر بیشتر از',
  stale: 'به‌روز نشدن',
};
const STATUS_FA: Record<AlertRule['status'], string> = {
  met: 'برقرار',
  not_met: 'برقرار نیست',
  no_data: 'بدون داده',
  disabled: 'خاموش',
};

export default function AlertsSection({ latest }: { latest: Latest }) {
  const { data } = useJson(loadAlerts);
  if (!data) return null;
  const title = (sid: string) => (sid === 'gap' ? 'شکاف قیمت' : latest.cards[sid]?.title ?? sid);
  const unit = (r: AlertRule) =>
    r.op === 'change_above' || r.series === 'gap' ? '٪' : latest.cards[r.series]?.unit_fa ?? '';

  return (
    <section>
      <h2 className="mb-2 text-sm font-semibold text-ink-2">هشدار قیمت (ntfy)</h2>
      {!data.configured && (
        <p className="mb-2 rounded-lg bg-warn-bg px-3 py-2 text-xs leading-6 text-warn-ink">
          هنوز فعال نشده: Secret به نام <code dir="ltr">NTFY_TOPIC</code> در تنظیمات ریپو تعریف نشده است (راهنما در README).
          قانون‌ها بررسی می‌شوند ولی پیامی فرستاده نمی‌شود.
        </p>
      )}
      <ul className="divide-y divide-line rounded-xl border border-line bg-surface text-xs">
        {data.rules.map((r) => (
          <li key={r.id} className={`px-3 py-2 ${r.status === 'disabled' ? 'opacity-60' : ''}`}>
            <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
              <span className="font-medium">
                <span aria-hidden className={r.status === 'met' ? 'text-down' : 'text-muted'}>
                  {r.status === 'met' ? '●' : '○'}
                </span>{' '}
                {title(r.series)} — {OP_FA[r.op]}
                {r.value != null && r.op !== 'stale' && ` ${faNum(r.value, 2)} ${unit(r)}`}
              </span>
              <span className="text-muted">
                {STATUS_FA[r.status]}
                {r.current != null && r.op !== 'stale' && r.op !== 'change_above' && ` (اکنون ${faNum(r.current)})`}
              </span>
            </div>
            {r.last_message && (
              <p className="mt-0.5 text-[11px] text-muted">
                آخرین پیام{r.last_sent_at ? ` (${faAgo(r.last_sent_at)})` : ' (ارسال نشده)'}: {r.last_message}
              </p>
            )}
          </li>
        ))}
      </ul>
      <p className="mt-1 text-[11px] text-muted">
        قانون‌ها در <code dir="ltr">data/manual/alerts.json</code> قابل ویرایش‌اند؛ هر ۳۰ دقیقه بعد از جمع‌آوری قیمت بررسی می‌شوند.
      </p>
    </section>
  );
}
