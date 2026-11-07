# گزارش آزمون، امکانات و محدودیت‌ها

تاریخ: ۱۶ آبان ۱۴۰۵

## وضعیت اجرای واقعی — صادقانه

| مرحله | وضعیت |
|---|---|
| نوشتن کد و آزمون‌ها | انجام شد |
| کامپایل و اجرای آزمون‌ها | **هنوز اجرا نشده.** محیط توسعه این نسخه لینوکسی و بدون Xcode بود؛ اجرای toolchain سوئیفت هم مجاز نشد. |
| CI روی macOS | Workflow آماده است اما push به GitHub در این نشست با خطای دسترسی (403) رد شد، پس CI اجرا نشد. |
| اسکرین‌شات شبیه‌ساز | توسط آزمون UI در CI تولید می‌شود (Artifact `chortkeh-screenshots`)؛ هنوز تولید نشده. |
| IPA امضاشده | تولید نشده و ادعا نمی‌شود. |

تا وقتی Job «chortkeh-ios» سبز نشده، هیچ‌یک از آزمون‌های زیر «گذرانده‌شده» محسوب نمی‌شود.

## نگاشت سناریوهای پذیرش به آزمون‌ها

| # | سناریو | آزمون |
|---|---|---|
| 1 | ۲۰۰م − هزینه ۱۰م = ۱۹۰م | `FinancialEngineTests.testExpenseReducesBalance`، `LedgerServiceIntegrationTests.testScenario1And2…` |
| 2 | انتقال ۵۰م، جمع ثابت | `testTransferKeepsTotal`، `testScenario1And2…` |
| 3 | چک صادره ۸۰م، نقد ثابت | `testIssuedChequeDoesNotChangeCash`، `testScenario3To5…` |
| 4 | چک دریافتی ۴۰م، یک بار افزایش در وصول | `testReceivedChequeCollectedOnce`، `testScenario3To5…` |
| 5 | بدهی ۸۰م + چک ۸۰م = یک خروجی | `testLinkedChequeIsNotDoubleCounted`، `testScenario3To5…` |
| 6 | طلب ۱۰۰م − وصول ۳۰م = ۷۰م | `testPartialReceivableSettlement`، `testScenario6And7…` |
| 7 | تسویه چندمرحله‌ای، رد تسویه اضافه | `testChequeMultiPartAndOverSettlementRejected`، `testScenario6And7…` |
| 8 | برگشت چک | `testVoidedSettlementAndBouncedCheque`، `testScenario8BounceReverses…` |
| 9 | تهاتر فقط با تأیید | `testOffsetValidation`، `testScenario9Offset…` |
| 10 | درآمد ثابت + وقوع واقعی | `testRecurringIncomeConfirmedOccurrenceNotDoubleCounted`، `testScenario10…` |
| 11 | روز ۳۱ در ماه کوتاه | `JalaliCalendarTests.testDay31InShortMonthPolicies`، `ForecastEngineTests.testMonthlyRuleOnDay31` |
| 12 | اسفند و کبیسه | `testLeapYears`، `testCrossingEsfandAndNewYear`، `testRoundTripAndAgreementWithFoundation` |
| 13 | منطقه زمانی | `testTimeZoneKeepsCalendarMeaning` |
| 14 | منفی‌شدن میانه دوره | `testMidPeriodNegativeIsDetected` |
| 15 | نبود ثبت ≠ صفر | `testMissingRecordsAreNoDataNotZero` |
| 16 | حذف/اصلاح و مانده‌ها | `testReversalRestoresBalanceAndTotals`، `testScenario16ReverseAndCorrect`، `testReversingASettlementReopensTheDebt` |
| 17 | یادآوری و تغییر سررسید | `ReminderPlannerTests.*`، `ReminderSchedulerTests.testRescheduleReplacesAndRemoves` |
| 18 | پشتیبان/بازیابی/گذرواژه اشتباه/سلامت داده | `BackupCryptoTests.*`، `BackupRestoreIntegrationTests.*` |
| 19 | اعداد بزرگ و ارقام سه خط | `AmountInputParserTests.*`، `MoneyTests.*` |
| 20 | آفلاین | هیچ کدی شبکه استفاده نمی‌کند؛ `testDataSurvivesContainerReopen` |
| 21 | حالت خالی، بدون مجوز اعلان | `ChortkehUITests.testEmptyStateAndOnboardingSkip`، `testDeniedPermissionSchedulesNothing` |
| 22 | ثبت سریع روی iPhone 13 | `ChortkehUITests.testQuickExpenseFlow` |
| طلایی | کسری موقت پیش از روز ۲۵ | `ForecastEngineTests.testGoldenScenarioTemporaryShortfall` |

حالت «ردکردن Face ID» (۲۱): صفحه قفل باقی می‌ماند و دکمه تلاش دوباره دارد (`LockView`)؛ آزمون خودکار ندارد چون شبیه‌سازی LocalAuthentication در XCUITest پشتیبانی رسمی ندارد — باید دستی روی دستگاه بررسی شود.

## امکانات پیاده‌شده

فاز ۱: پروژه XcodeGen؛ مدل داده SwiftData با Schema نسخه‌دار؛ Money دقیق؛ تقویم جلالی محاسباتی؛ حساب‌ها، انتقال، تعدیل موجودی؛ هزینه/درآمد؛ اشخاص؛ طلب/بدهی با تسویه جزئی/کامل و تهاتر؛ چک صادره/دریافتی، اتصال به تعهد، وصول/پرداخت جزئی، برگشت، باطل/عودت، تمدید؛ برگشت/اصلاح قابل ممیزی؛ سابقه عملیات؛ داشبورد کامل (موجودی، طلب و بدهی، قابل خرج، پیش‌بینی با نمودار و سناریو، امروز چه خبر، سررسیدها، ماه جاری، آخرین رویدادها)؛ جست‌وجو و فیلتر؛ اعلان محلی با شناسه پایدار؛ Face ID؛ پوشش App Switcher؛ پشتیبان رمزگذاری‌شده و بازیابی اتمیک؛ پیش‌بینی ۷ تا ۹۰ روزه.

فاز ۲ (بخشی): ورود جمله فارسی با تجزیه محلی و پیش‌نمایش؛ بودجه ماهانه؛ CSV (UTF-8 BOM، ضد Formula Injection) و PDF راست‌چین؛ قواعد تکرار با سیاست پایان ماه؛ تصویر چک رمزگذاری‌شده.

## انجام‌نشده / ریسک‌ها

- **کامپایل نشده**: احتمال خطاهای کامپایل جزئی وجود دارد؛ نخستین اجرای CI باید رفع شوند.
- ورود گفتاری، OCR چک، ویجت و Siri Shortcuts (فاز ۳) پیاده نشده‌اند.
- بودجه به تفکیک دسته در مدل وجود دارد ولی رابط آن فقط بودجه کل را تنظیم می‌کند.
- چیدمان PDF برای گزارش‌های بسیار طولانی صفحه‌بندی چندصفحه‌ای ندارد (یک صفحه بلند).
- مقایسه الگوریتم جلالی با `Calendar(.persian)` اپل برای ۲۰ سال (۲۰۱۶–۲۰۳۶) در آزمون است؛ در صورت اختلاف ICU در سال‌های دور، تقویم رسمی ایران مرجع است.
- قفل برنامه دسترسی را می‌بندد ولی رمزگذاری در حالت سکون بر Data Protection iOS متکی است (کد عبور دستگاه لازم است).
- ابعاد دقیق UI روی iPhone 13 و Dynamic Type بزرگ فقط پس از اجرای واقعی قابل تأیید است.
