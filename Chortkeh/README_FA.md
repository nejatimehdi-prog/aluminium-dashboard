# چُرتکه — پول من، حساب من

اپلیکیشن بومی iOS برای حساب‌وکتاب شخصی: موجودی واقعی، طلب، بدهی، چک‌های صادره و دریافتی، و پیش‌بینی روزانه نقدینگی — کاملاً آفلاین، بدون حساب کاربری، سرور، تبلیغات یا ردیاب.

> وضعیت فعلی: کد کامل فاز ۱ و بخشی از فاز ۲ نوشته شده است. **ساخت و آزمون روی macOS/Xcode هنوز انجام نشده** (جزئیات در [`docs/TEST_REPORT_FA.md`](docs/TEST_REPORT_FA.md)). تا وقتی CI سبز نشده، این نسخه را «نهایی» ندانید.

## پیش‌نیازها

| مورد | نسخه |
|---|---|
| macOS | 14.5 یا جدیدتر |
| Xcode | 16 یا جدیدتر (Swift 5 language mode) |
| XcodeGen | 2.40+ (`brew install xcodegen`) |
| iOS هدف | 17.0+ (آزمون‌شده برای iPhone 13 و جدیدتر) |

بدون Mac هم می‌توان با GitHub Actions ساخت و آزمون را اجرا کرد (پایین‌تر)، اما **نصب روی آیفون واقعی همیشه به امضای اپل نیاز دارد.**

## ساخت و اجرا

```bash
cd Chortkeh
xcodegen generate            # Chortkeh.xcodeproj را از project.yml می‌سازد
open Chortkeh.xcodeproj      # در Xcode: Scheme «Chortkeh» → iPhone 13 → Run
```

آزمون‌ها از خط فرمان:

```bash
xcodebuild test -project Chortkeh.xcodeproj -scheme Chortkeh \
  -destination 'platform=iOS Simulator,name=iPhone 13' CODE_SIGNING_ALLOWED=NO
```

- `ChortkehTests`: آزمون‌های واحد هسته مالی/تقویم/پیش‌بینی/پشتیبان + آزمون‌های یکپارچه با SwiftData درون‌حافظه.
- `ChortkehUITests`: حالت خالی، ثبت سریع هزینه و بازگشت به داشبورد، و تهیه اسکرین‌شات واقعی (متغیر محیطی `SCREENSHOT_DIR`).

## CI (GitHub Actions)

فایل [`.github/workflows/chortkeh-ios.yml`](../.github/workflows/chortkeh-ios.yml) روی runner مک:
1. XcodeGen را نصب و پروژه را تولید می‌کند،
2. شبیه‌ساز iPhone 13 می‌سازد (اگر روی runner نبود، iPhone 16 و در خلاصه اعلام می‌کند)،
3. build-for-testing، سپس آزمون‌های واحد/یکپارچه و آزمون‌های UI را اجرا می‌کند،
4. اسکرین‌شات‌ها (`chortkeh-screenshots`) و نتایج xcresult و لاگ‌ها را به‌صورت Artifact بارگذاری می‌کند.

آزمون شکست‌خورده مخفی یا حذف نمی‌شود؛ هر شکست، Job را قرمز می‌کند.

## امضا و نصب روی آیفون

1. در Xcode → Target «Chortkeh» → Signing & Capabilities: Team خود را انتخاب کنید (یا `DEVELOPMENT_TEAM` را در `project.yml` بگذارید). Bundle ID پیش‌فرض: `app.chortkeh.ios` (در صورت تداخل تغییر دهید).
2. **Apple ID رایگان**: نصب مستقیم از Xcode روی گوشی متصل؛ اعتبار امضا ۷ روز است و باید دوباره نصب شود.
3. **Apple Developer Program (سالانه)**: Archive → Distribute → TestFlight یا Ad Hoc برای نصب پایدار.
4. CI فعلی عمداً بدون امضا (`CODE_SIGNING_ALLOWED=NO`) فقط برای شبیه‌ساز می‌سازد؛ **هیچ IPA قابل نصبی تولید نمی‌کند**. برای IPA امضاشده در CI باید گواهی و Provisioning Profile را به‌صورت Secret اضافه کنید.

## ساختار

```
Chortkeh/
  project.yml            تعریف XcodeGen
  App/                   ورود برنامه، AppState، تم، قفل و پوشش حریم خصوصی
  Features/              داشبورد، ثبت سریع، حساب‌ها، اشخاص، تعهدات، چک‌ها، گزارش‌ها، تنظیمات، شروع
  Domain/                هسته خالص (بدون SwiftUI/SwiftData)
    Models/              Money، CivilDate و تقویم جلالی، Snapshotها، تنظیمات
    FinancialEngine/     مانده‌ها، موقعیت، «قابل خرج»، داشبورد، پیام‌های «امروز چه خبر»
    ForecastEngine/      تفکیک تعهدات بدون دوباره‌شماری، تکرارها، برآورد هزینه، پیش‌بینی روزانه
    Validation/          قواعد یکپارچگی، تجزیه مبلغ، تجزیه جمله فارسی
    Formatting/          ارقام، مبلغ و تاریخ فارسی
  Infrastructure/
    Persistence/         مدل‌های SwiftData (Schema V1 + Migration Plan)، LedgerService اتمیک
    Notifications/       برنامه‌ریز یادآوری (خالص) و همگام‌ساز UNUserNotificationCenter
    Backups/             رمزنگاری (PBKDF2 + AES-GCM) و پشتیبان/بازیابی اعتبارسنجی‌شده
    Security/            Keychain و قفل Face ID/رمز دستگاه
    Attachments/         ذخیره رمزگذاری‌شده تصویر چک
  Resources/             Assets و رشته‌های فارسی
  Tests/Unit|Integration|UI
  docs/                  مدل داده و فرمول‌ها، پشتیبان، گزارش آزمون
```

## تصمیم‌های پیش‌فرض (قابل تنظیم)

| موضوع | تصمیم |
|---|---|
| واحد | تومان؛ ذخیره همیشه Int64 ریال، تبدیل دقیق ×۱۰، کنترل سرریز |
| سقف یک مبلغ | ۱۰^۱۶ ریال (۱۰^۱۵ تومان) |
| تاریخ موعد | روز تقویمی بدون منطقه زمانی (Julian Day Number) |
| روز ۲۹/۳۰/۳۱ در ماه کوتاه | آخرین روز معتبر همان ماه (قابل تغییر به «اول ماه بعد») |
| یادآوری | ۷، ۳، ۱ روز قبل و روز سررسید ساعت ۹؛ یادآوری روزانه ثبت هزینه ۲۱:۰۰ |
| متن اعلان | بدون مبلغ و نام، مگر با فعال‌سازی جداگانه |
| سناریوها | محتاطانه: فقط دریافتی قطعی و هزینه روزمره ×۱٫۲؛ معمولی: قطعی + احتمالی؛ خوش‌بینانه: همه، هزینه ×۰٫۸۵ |
| هزینه روزمره در پیش‌بینی | بودجه ماهانه ÷ ۳۰؛ در نبود بودجه، میانگین ۳۰ روز (حداقل ۷ روز داده)؛ در غیر این صورت لحاظ نمی‌شود و اعلام می‌شود |
| حذف/اصلاح تراکنش | همیشه با رویداد «برگشت» (قابل ممیزی)؛ هیچ حذف آبشاری مخفی |
| قفل | اختیاری؛ Face ID با جایگزین رمز دستگاه |
| ذخیره‌سازی | فقط محلی، Data Protection، خارج از iCloud Backup؛ پشتیبان فقط دستی و رمزگذاری‌شده |

مستندات بیشتر:
- [مدل داده و فرمول‌ها](docs/DATA_MODEL_FA.md)
- [پشتیبان‌گیری و بازیابی](docs/BACKUP_FA.md)
- [گزارش آزمون و محدودیت‌ها](docs/TEST_REPORT_FA.md)
