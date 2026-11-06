# داشبورد شمش آلومینیوم

وب‌اپ فارسی و قابل نصب (PWA) برای قیمت جهانی و داخلی شمش آلومینیوم. هزینهٔ اجرا صفر است: داده‌ها را GitHub Actions جمع می‌کند، در پوشهٔ `data/` به‌صورت JSON ذخیره می‌کند، و اپ ایستا روی GitHub Pages فقط همین فایل‌ها را می‌خواند.

```
GitHub Actions (هر ۳۰ دقیقه) → اسکریپت‌های Python → data/*.json → ساخت اپ → GitHub Pages
کامپیوتر ویندوز شما (اختیاری) → collect_iran.py → push ↗
```

جزئیات منابع: [docs/sources.md](docs/sources.md)

## ساختار پوشه‌ها

| مسیر | کار |
|---|---|
| `collect_global.py` | قیمت جهانی: LME (Westmetall)، COMEX و یوان (Yahoo)، شانگهای (Sina) |
| `collect_iran.py` | بورس کالا: معاملات شمش و نرخ دلار. روی ویندوز، بعد از جمع‌آوری push هم می‌کند |
| `backfill.py` | پر کردن یک‌بارهٔ تاریخچه (پیش‌فرض: ۵ سال جهانی، ۱۲ ماه بورس کالا) |
| `collect_weekly.py` | تولید ماهانه (کدال + ورود دستی) و تجارت خارجی (UN Comtrade + گمرک) → `data/production.json`، `data/trade.json` |
| `run_forecast.py` | پیش‌بینی، بک‌تست و سناریوها → `data/forecast.json` و `docs/model.md` (نیاز به `requirements-model.txt`) |
| `collector/` | کد مشترک: parserها، ذخیره، وضعیت، همگام‌سازی git |
| `data/series/*.json` | تاریخچهٔ هر سری. هر فایل `source`، `unit` و `fetched_at` دارد |
| `data/latest.json` | کارت‌های صفحهٔ خانه |
| `data/status.json` | وضعیت آخرین اجرای هر منبع (موفق یا خطا) |
| `data/manual/*.csv` | ورود دستی (پایین‌تر) |
| `app/` | اپ React + Vite + Tailwind + ECharts |
| `tests/` | تست parserها با پاسخ‌های واقعی ذخیره‌شده در `tests/fixtures/` |

واحدها همه‌جا یکسان‌اند:
- قیمت جهانی: **دلار بر تن**
- قیمت ایران: **تومان بر کیلوگرم**
- نرخ ارز: **تومان بر دلار**

## نصب محلی (ویندوز)

۱. این‌ها را نصب کنید (همه رایگان):
- [Python 3.12](https://www.python.org/downloads/): در نصب، گزینهٔ «Add python.exe to PATH» را تیک بزنید.
- [Git for Windows](https://git-scm.com/download/win)
- [Node.js LTS](https://nodejs.org/) (فقط برای ساخت یا اجرای اپ روی کامپیوتر خودتان)

۲. در پوشهٔ پروژه، PowerShell را باز کنید:

```powershell
py -3.12 -m venv .venv
.venv\Scripts\pip install -r requirements.txt
```

۳. اجرای اسکریپت‌ها:

```powershell
.venv\Scripts\python -m pytest              # تست parserها
.venv\Scripts\python collect_global.py      # قیمت جهانی
.venv\Scripts\python collect_iran.py        # بورس کالا، بعد push
.venv\Scripts\python collect_iran.py --no-push
.venv\Scripts\python backfill.py            # فقط یک‌بار
```

اگر منبعی خطا بدهد، اسکریپت متوقف نمی‌شود. خطا در `data/status.json` ثبت و در پایین صفحهٔ خانه نشان داده می‌شود. آخرین دادهٔ معتبر سر جایش می‌ماند و برچسب «به‌روز نشده» می‌گیرد.

۴. اجرای اپ روی کامپیوتر:

```powershell
cd app
npm install
npm run dev        # http://localhost:5173
npm run build      # خروجی در app/dist
```

## ورود دستی

برای داده‌هایی که منبع خودکار مجاز ندارند، فایل CSV را ویرایش و commit کنید:

| فایل | داده | واحدهای مجاز |
|---|---|---|
| `data/manual/iran_free_market.csv` | قیمت شمش در بازار آزاد | `تومان/کیلوگرم` یا `ریال/کیلوگرم` |
| `data/manual/fx_free_market.csv` | دلار بازار آزاد | `تومان/دلار` یا `ریال/دلار` |
| `data/manual/production_national.csv` | تولید ماهانهٔ کل کشور و تولیدکنندگان غیر بورسی | ستون‌ها: `month_jalali,producer,tonnes,source,note` (ماه مثل `1405/07`، برای جمع کشور producer=«کل کشور») |
| `data/manual/customs_trade.csv` | آمار گمرک | ستون‌ها: `period_jalali,flow,category,tonnes,value_usd,source,note` (flow: صادرات/واردات، category: شمش/ضایعات/محصولات) |
| `data/manual/scenario_assumptions.json` | فرض‌ها و متن سناریوهای پیش‌بینی | صدک‌ها، ضریب پهنای ارز، تعداد مسیرها |

**تاریخچهٔ دلار آزاد مدل پیش‌بینی را دقیق‌تر می‌کند:** اگر چند ماه نرخ روزانه را در `fx_free_market.csv` وارد کنید (حداقل ۳۰ روزِ هم‌زمان با معاملات بورس کالا)، مدل خودکار از حالت «نسبت ضمنی» به رگرسیون کامل (ضریب و پرمیوم) می‌رود.

ستون‌ها: `date_jalali,date,value,unit,source,note`
- یکی از دو تاریخ کافی است.
- ستون `source` اجباری است.

مثال:

```csv
date_jalali,date,value,unit,source,note
1405/08/14,,266900,تومان/دلار,صرافی X,نرخ فروش
```

اگر خطی خطا داشته باشد (واحد ناشناخته، عدد غیرعادی، منبع خالی)، شمارهٔ همان خط در بخش «وضعیت جمع‌آوری» اپ نمایش داده می‌شود.

تا وقتی دلار بازار آزاد وارد نشده، «شکاف قیمت» با دلار بورس کالا حساب می‌شود و این در کارت نوشته شده است.

## راه‌اندازی روی GitHub Pages

۱. در GitHub یک ریپوی **Public** بسازید، مثلاً `aluminium-dashboard`. در ریپوی عمومی، دقیقه‌های Actions رایگان و نامحدود است.

۲. پروژه را push کنید:

```powershell
git init -b main
git add .
git commit -m "phase 1"
git remote add origin https://github.com/<نام-کاربری>/aluminium-dashboard.git
git push -u origin main
```

۳. در ریپو:
- **Settings → Pages → Build and deployment → Source** را روی **GitHub Actions** بگذارید.
- **Settings → Actions → General → Workflow permissions** را روی **Read and write permissions** بگذارید.

۴. در تب **Actions**:
- workflow «deploy to GitHub Pages» را با **Run workflow** یک‌بار اجرا کنید.
- بعد «collect prices» را یک‌بار دستی اجرا کنید، تا ببینید منابع از سرور GitHub جواب می‌دهند.

آدرس اپ: `https://<نام-کاربری>.github.io/aluminium-dashboard/`

workflowهای زمان‌بندی‌شده:

| workflow | زمان | کار |
|---|---|---|
| collect prices | هر ۳۰ دقیقه | قیمت‌ها و نرخ ارز |
| daily forecast | هر روز ۲۱:۰۰ تهران | پیش‌بینی، بک‌تست، `docs/model.md` |
| weekly production and trade | دوشنبه‌ها ۸:۳۰ تهران | تولید (کدال) و تجارت (Comtrade، حدود ۴ دقیقه به‌خاطر محدودیت نرخ) |
| tests | با هر push کد | تست‌ها |

هر کدام را می‌توانید از تب Actions با **Run workflow** دستی هم اجرا کنید.

از آن به بعد، «collect prices» هر ۳۰ دقیقه خودکار اجرا می‌شود. اگر داده عوض شده باشد، commit می‌کند و اپ را دوباره منتشر می‌کند. نتیجهٔ هر منبع در بخش «وضعیت جمع‌آوری داده» در صفحهٔ خانه دیده می‌شود.

نکته‌ها:
- زمان‌بندی GitHub دقیق نیست و ممکن است ۵ تا ۲۰ دقیقه دیر اجرا شود.
- GitHub زمان‌بندی ریپوهایی را که ۶۰ روز هیچ فعالیتی ندارند غیرفعال می‌کند. commitهای خودکار داده فعالیت حساب می‌شوند. اگر غیرفعال شد، در تب Actions دکمهٔ Enable را بزنید.

### جایگزین: Cloudflare Pages
- در داشبورد Cloudflare: **Workers & Pages → Create → Pages → Connect to Git**، و ریپو را انتخاب کنید.
- Build command: `cd app && npm ci && npm run build`
- Output directory: `app/dist`
- ⚠️ طرح رایگان Cloudflare **۵۰۰ build در ماه** دارد. commitهای هر ۳۰ دقیقه بیشتر از این می‌شوند. پس Cloudflare را فقط وقتی جایگزین کنید که GitHub Pages از ایران باز نشود. در آن صورت، بازهٔ cron در `.github/workflows/collect.yml` را به هر ۲ ساعت تغییر دهید.

### تست دسترسی از داخل ایران
بعد از راه‌اندازی، آدرس `github.io` را از چند اینترنت داخلی (همراه اول، ایرانسل، ثابت) و بدون VPN باز کنید. اگر باز نشد، Cloudflare Pages (`*.pages.dev`) را امتحان کنید. وضعیت فیلترینگ هر دو ممکن است تغییر کند.

## جمع‌کنندهٔ محلی ویندوز (برای بورس کالا)

سایت بورس کالا ممکن است درخواست‌های سرورهای GitHub (آمریکا) را رد کند. بعد از اولین اجرای «collect prices»، در اپ ببینید وضعیت «بورس کالا» موفق است یا نه:
- **موفق:** همین کافی است. جمع‌کنندهٔ محلی لازم نیست.
- **ناموفق:** روی ویندوز خودتان، `collect_iran.py` را زمان‌بندی کنید.

مراحل:

۱. نصب محلی بالا را انجام دهید. Git باید بتواند بدون پرسیدن رمز push کند. Git for Windows با Git Credential Manager یک‌بار ورود به GitHub را می‌پرسد و بعد به خاطر می‌سپارد. یک‌بار دستی اجرا کنید:

```powershell
.venv\Scripts\python collect_iran.py
```

۲. **Task Scheduler** را باز کنید (Win+R ← `taskschd.msc`) و **Create Task** را بزنید:
- **General:** نام را «Aluminium IME collector» بگذارید و «Run only when user is logged on» را انتخاب کنید، تا Git به رمز ذخیره‌شده دسترسی داشته باشد.
- **Triggers → New:**
  - Daily، ساعت ۰۹:۰۰.
  - Repeat task every: **30 minutes**، for a duration of: **8 hours**.
  - Enabled.
- **Actions → New:**
  - Program: مسیر کامل `run_iran_collector.bat`.
  - Start in: پوشهٔ پروژه.
- **Conditions:** تیک «Start the task only if the computer is on AC power» را بردارید، تا روی لپ‌تاپ هم اجرا شود.
- **Settings:** «If the task is already running: Do not start a new instance».

۳. خروجی هر اجرا در `collect_iran.log` ذخیره می‌شود.

اگر هم GitHub و هم کامپیوتر شما داده بنویسند، `collector/gitsync.py` تداخل‌های معمول را خودکار ادغام می‌کند:
- `status.json`: از هر منبع، اجرای جدیدتر می‌ماند.
- سری‌ها: نقطه‌ها بر اساس تاریخ ادغام می‌شوند.

## هشدار قیمت روی گوشی (ntfy)

بعد از هر اجرای «collect prices»، قانون‌های `data/manual/alerts.json` بررسی می‌شوند. هر قانونی که برقرار شود، از طریق [ntfy.sh](https://ntfy.sh) (رایگان، بدون حساب) پیام می‌فرستد.

۱. **یک topic محرمانه انتخاب کنید.** نام topic مثل رمز است: هر کس آن را بداند، پیام‌ها را می‌بیند. یک رشتهٔ طولانی و تصادفی بسازید، مثل `alu-k3v9x2m7q8w1z5r4`. آن را **در ریپو ننویسید**.
۲. در GitHub بروید به **Settings → Secrets and variables → Actions → New repository secret**:
   - Name: `NTFY_TOPIC`
   - Secret: همان topic
۳. اپ **ntfy** را نصب کنید ([iOS](https://apps.apple.com/app/ntfy/id1625396347)، [Android](https://play.google.com/store/apps/details?id=io.heckel.ntfy)). **+** را بزنید و همان topic را با سرور پیش‌فرض `ntfy.sh` اضافه کنید.
۴. برای آزمایش، در PowerShell:

```powershell
$env:NTFY_TOPIC = "<topic>"; .venv\Scripts\python check_alerts.py --test
```

قانون‌ها:

| op | معنی |
|---|---|
| `above` / `below` | عبور از یک سطح. با هر عبور یک بار پیام می‌آید، نه هر ۳۰ دقیقه. |
| `change_above` | تغییر بیش از X درصد نسبت به دادهٔ قبلی. برای هر دادهٔ جدید یک بار. |
| `stale` | منبع به‌روز نشده. روزی یک بار. |

وضعیت هر قانون در پایین صفحهٔ خانهٔ اپ نمایش داده می‌شود.

## نصب اپ

**ویندوز (Chrome یا Edge):**
- آدرس اپ را باز کنید.
- در نوار آدرس، آیکون **Install** را بزنید (یا منوی ⋮ ← «Install داشبورد شمش آلومینیوم» / «Apps → Install this site as an app»).
- اپ در منوی Start و پنجرهٔ جدا باز می‌شود.

**iOS (Safari):**
- آدرس را در **Safari** باز کنید.
- دکمهٔ **Share** (مربع با فلش) را بزنید.
- **Add to Home Screen** و بعد **Add** را بزنید.
- نصب در iOS فقط از Safari ممکن است.

اپ آخرین داده‌ها را ذخیره می‌کند و بدون اینترنت هم آخرین وضعیت را نشان می‌دهد.

## پیش‌بینی
توضیح کامل روش، ضریب‌ها و نتایج بک‌تست در [docs/model.md](docs/model.md) است و هر روز خودکار به‌روز می‌شود.

خلاصه:
- قیمت ایران مستقیم پیش‌بینی نمی‌شود. از LME × نرخ ارز ساخته می‌شود.
- LME با گام تصادفی، ETS و ARIMA پیش‌بینی می‌شود، و مدل با بک‌تست انتخاب می‌شود.
- سناریوها صدک ۱۰، ۵۰ و ۹۰ مونت‌کارلو هستند.
- خطای بک‌تست هر افق در اپ کنار پیش‌بینی نمایش داده می‌شود.

## قواعد داده
- هیچ عددی ساخته یا حدس زده نمی‌شود. اگر منبعی شکست بخورد، آخرین مقدار معتبر با برچسب «به‌روز نشده» می‌ماند.
- کنار هر عدد، منبع، تاریخ داده و زمان دریافت آمده است.
- بورس کالا: فقط معاملات **نقدی با تسویهٔ نقدی** شمش خالص در تالار اصلی حساب می‌شوند. معاملات «نقدی / اعتباری» حدود ۹٪ گران‌ترند و قابل مقایسه نیستند. عدد کارت، میانگین وزنی بر اساس حجم است.
- شمش در بورس کالا معمولاً هفته‌ای یک تا دو بار عرضه می‌شود. «درصد تغییر» این کارت نسبت به معاملهٔ قبلی است.
- COMEX (`ALI=F`) حجم معاملات کمی دارد و با LME متفاوت است. برچسب «COMEX (تأخیری)» دارد، نه LME.
- هیچ کلید، رمز یا توکنی در ریپو نیست و لازم هم نیست.

این تحلیل آماری است و توصیهٔ معاملاتی نیست.
