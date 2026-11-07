# مدل داده، روابط و فرمول‌های مالی

## اصول

- **مبلغ**: `Money` = عدد صحیح Int64 به ریال. همه عملیات با کنترل سرریز (`addingReportingOverflow`) و در صورت سرریز خطای `overflow`؛ هیچ Float/Double در محاسبه پول نیست.
- **تاریخ مالی**: `CivilDate` = شماره روز ژولینی (JDN). تبدیل شمسی/میلادی با الگوریتم محاسباتی (جدول سال‌های شکست، مانند jalaali-js) و در آزمون با `Calendar(identifier: .persian)` مقایسه می‌شود. موعدها به منطقه زمانی وابسته نیستند؛ اعلان‌ها با DateComponents شناور زمان‌بندی می‌شوند.
- **یک منبع حقیقت**: «مانده باز» هر تعهد و چک ذخیره نمی‌شود؛ همیشه = مبلغ اصلی − جمع تسویه‌های ابطال‌نشده. وضعیت‌های «نزدیک سررسید/معوق/تسویه جزئی/تسویه‌شده» هم محاسباتی‌اند؛ فقط وضعیت ثبتی چک (فعال/برگشتی/باطل/عودت) ذخیره می‌شود.
- **ارجاع‌ها**: UUID ساده، بدون Relationship؛ بنابراین حذف آبشاری وجود ندارد و حذف رکورد وابسته رد می‌شود.

## موجودیت‌ها (SwiftData، Schema V1)

| مدل | فیلدهای اصلی |
|---|---|
| FinancialAccount | id، name، kind (bank/cash)، openingBalanceRials، isActive، sortOrder |
| Contact | id، name، phone، note |
| MoneyTransaction | id، kind، amountRials (>0)، dayNumber، fromAccountId?، toAccountId?، contactId?، categoryId?، note، reversesTransactionId?، recurrenceKey?، eventGroupId، chequeId?، obligationId? |
| Obligation | id، direction (receivable/payable)، contactId، principalRials، dueDayNumber? (nil = بی‌موعد)، isCancelled، confidence (confirmed/expected/uncertain) |
| Cheque | id، direction (issued/received)، amountRials، dueDayNumber، contactId، bankName، accountId?، chequeNumber، sayadId، lifecycle، obligationId?، confidence، attachmentId? |
| Settlement | id، obligationId? یا chequeId?، amountRials، dayNumber، method (cash/offset)، transactionId?، groupId، isVoided |
| RecurringRule | id، title، kind (income/expense)، amountRials، accountId?، startDay، endDay?، frequency، interval، monthEndPolicy، confidence |
| Budget | categoryId? (nil = بودجه کل هزینه‌های متغیر)، monthlyLimitRials |
| ExpenseCategory | name، symbol، sortOrder، isArchived |
| Attachment | ownerId، fileName (فایل AES-GCM با کلید Keychain) |
| AuditEvent | timestamp، action، entityType، entityId، summary |

همه مدل‌ها `createdAt` و `updatedAt` دارند. `ChortkehMigrationPlan` برای نسخه‌های بعدی schema آماده است.

## قاعده حرکت پول

هر تراکنش مبلغ را از `fromAccountId` کم و به `toAccountId` اضافه می‌کند:

| نوع | from | to |
|---|---|---|
| expense / settlementOut / adjustmentOut | حساب | — |
| income / settlementIn / adjustmentIn | — | حساب |
| transfer | مبدأ | مقصد (جمع کل ثابت) |
| reversal | `to` تراکنش اصلی | `from` تراکنش اصلی |

ثبت طلب، بدهی یا چک **هیچ تراکنشی نمی‌سازد**؛ فقط پرداخت/وصول واقعی تراکنش می‌سازد.

- **وصول/پرداخت چک**: یک تراکنش settlementIn/Out + یک Settlement برای چک + (اگر به تعهد متصل است) یک Settlement برای تعهد با همان transactionId.
- **برگشت چک**: تراکنش‌های تسویه آن با reversal جبران، Settlementها ابطال (isVoided) و چک «برگشتی» می‌شود؛ تعهد مرتبط خودکار دوباره باز می‌شود.
- **تهاتر**: دو Settlement با method=offset و groupId مشترک، بدون تراکنش نقدی؛ فقط با تأیید صریح کاربر؛ قابل لغو گروهی.
- **اصلاح تراکنش**: reversal تراکنش قبلی + تراکنش جدید در یک ذخیره اتمیک.

## فرمول‌ها

```
موجودی حساب      = موجودی اولیه + Σ ورودی‌ها − Σ خروجی‌ها
موجودی نقد        = Σ موجودی حساب‌های فعال
مانده تعهد/چک     = مبلغ اصلی − Σ تسویه‌های ابطال‌نشده   (چک غیرفعال یا تعهد لغوشده = ۰)
مطالبات باز       = Σ مانده طلب‌ها + Σ مانده چک‌های دریافتیِ بدون تعهد
بدهی‌های باز      = Σ مانده بدهی‌ها + Σ مانده چک‌های صادره‌ی بدون تعهد
خالص موقعیت       = موجودی نقد + مطالبات باز − بدهی‌های باز      (قابل خرج نیست)
پول آزاد احتیاطی  = موجودی نقد − خروجی‌های قطعی موعددار تا پایان بازه − ذخیره احتیاطی
                   (خروجی قطعی = چک صادره، بدهی، هزینه تکراری؛ دریافتی‌ها لحاظ نمی‌شوند؛ می‌تواند منفی شود)
```

### جلوگیری از دوباره‌شماری (CommitmentResolver)

هر واحد پول آینده فقط یک «مالک پیش‌بینی» (`forecastOwnerId`) دارد:
- چک فعال مالک مانده خودش در تاریخ سررسید خودش است: `cheque:<id>`
- تعهد فقط مالک بخشِ پوشش‌داده‌نشده توسط چک‌های فعال مرتبط است: `obligation:<id>`
  `باقی = max(0, مانده تعهد − Σ مانده چک‌های فعال مرتبط)`
- وقوع تکراری: `recurring:<ruleId>#<index>`؛ تراکنش واقعیِ تأییدکننده همان `recurrenceKey` را دارد و آن وقوع حذف می‌شود.

نمونه: بدهی ۸۰ + چک ۸۰ بابت آن → یک خروجی ۸۰. بدهی ۱۰۰ + چک ۸۰ → چک ۸۰ در سررسید چک + ۲۰ در سررسید بدهی.

### موتور پیش‌بینی (ForecastEngine)

1. شروع از موجودی نقد فعلی (شامل ثبت‌های امروز).
2. تعهدات تاریخ‌دار؛ موارد معوقِ هنوز باز در «امروز» قرار می‌گیرند؛ موارد بی‌موعد کنار گذاشته و جداگانه گزارش می‌شوند.
3. خروجی‌ها در همه سناریوها؛ ورودی‌ها بر اساس اطمینان:
   - محتاطانه: فقط confirmed و غیرمعوق
   - معمولی: confirmed (حتی معوق) + expected غیرمعوق
   - خوش‌بینانه: همه
4. وقوع‌های تکراری تأییدنشده در بازه.
5. هزینه روزمره برآوردی از فردا تا پایان بازه (بودجه یا میانگین تاریخی هزینه‌های غیرتکراری) × ضریب سناریو.
6. `مانده روز t = مانده روز t−1 + ورود t − خروج t`
7. خروجی: نخستین روز منفی، نخستین روز زیر ذخیره، کمینه مانده و تاریخ آن، وجه موردنیاز `max(0, −کمینه)`، مانده پایان، فهرست فرض‌ها.

### آمار هزینه

میانگین روزانه = جمع هزینه‌های متغیر بازه ÷ تعداد روزهای تقویمیِ پوشش‌داده‌شده (از اولین ثبت یا ابتدای بازه). کمتر از ۷ روز سابقه → میانگین گزارش نمی‌شود. تعداد روزهای دارای ثبت جداگانه نمایش داده می‌شود؛ روز بدون ثبت «بدون داده» است، نه «هزینه صفر».
