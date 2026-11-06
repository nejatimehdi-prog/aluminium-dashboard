"""Metadata for every price series. Units are normalised:
world prices in USD per tonne, Iran prices in toman per kg, FX in toman per USD."""

SERIES: dict[str, dict] = {
    "lme_cash": {
        "title": "LME نقدی", "group": "world", "collector": "westmetall",
        "unit": "USD/t", "unit_fa": "دلار بر تن", "freq": "daily",
        "source": "Westmetall (LME Cash-Settlement)",
        "source_url": "https://www.westmetall.com/en/markdaten.php?action=table&field=LME_Al_cash",
    },
    "lme_3m": {
        "title": "LME سه‌ماهه", "group": "world", "collector": "westmetall",
        "unit": "USD/t", "unit_fa": "دلار بر تن", "freq": "daily",
        "source": "Westmetall (LME 3-month)",
        "source_url": "https://www.westmetall.com/en/markdaten.php?action=table&field=LME_Al_cash",
    },
    "comex": {
        "title": "COMEX (تأخیری)", "group": "world", "collector": "yahoo",
        "unit": "USD/t", "unit_fa": "دلار بر تن", "freq": "intraday",
        "source": "Yahoo Finance — COMEX ALI=F (حدود ۱۵ دقیقه تأخیر)",
        "source_url": "https://finance.yahoo.com/quote/ALI=F",
    },
    "usdcny": {
        "title": "یوان بر دلار", "group": "helper", "collector": "yahoo",
        "unit": "CNY/USD", "unit_fa": "یوان بر دلار", "freq": "daily",
        "source": "Yahoo Finance — CNY=X",
        "source_url": "https://finance.yahoo.com/quote/CNY=X",
    },
    "shfe": {
        "title": "شانگهای SHFE", "group": "world", "collector": "sina",
        "unit": "USD/t", "unit_fa": "دلار بر تن", "freq": "daily",
        "source": "Sina Finance — SHFE AL0، تبدیل با CNY=X",
        "source_url": "https://finance.sina.com.cn/futures/quotes/AL0.shtml",
    },
    "ime_ingot": {
        "title": "بورس کالا — شمش خالص", "group": "iran", "collector": "ime",
        "unit": "toman/kg", "unit_fa": "تومان بر کیلوگرم", "freq": "daily",
        "source": "بورس کالای ایران — میانگین وزنی معاملات شمش خالص",
        "source_url": "https://www.ime.co.ir/",
    },
    "fx_ime": {
        "title": "دلار بورس کالا", "group": "fx", "collector": "ime_fx",
        "unit": "toman/USD", "unit_fa": "تومان بر دلار", "freq": "daily",
        "source": "بورس کالای ایران — نرخ تسویه",
        "source_url": "https://www.ime.co.ir/",
    },
    "fx_free": {
        "title": "دلار بازار آزاد", "group": "fx", "collector": "manual",
        "unit": "toman/USD", "unit_fa": "تومان بر دلار", "freq": "manual",
        "source": "ورود دستی (data/manual/fx_free_market.csv)",
        "source_url": "",
    },
    "iran_free_market": {
        "title": "شمش — بازار آزاد", "group": "iran", "collector": "manual",
        "unit": "toman/kg", "unit_fa": "تومان بر کیلوگرم", "freq": "manual",
        "source": "ورود دستی (data/manual/iran_free_market.csv)",
        "source_url": "",
    },
}

# Days without a new point after which a card is labelled «به‌روز نشده».
MAX_AGE_DAYS = {"intraday": 4, "daily": 5, "manual": 10}
