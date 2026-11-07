import Foundation

/// Errors raised by the financial core. Every case carries a short, plain Persian message.
enum DomainError: Error, Equatable, LocalizedError {
    case overflow
    case amountMustBePositive
    case amountOutOfRange
    case invalidAmountFormat
    case sameAccountTransfer
    case accountRequired
    case accountNotFound
    case accountInactive
    case contactRequired
    case dueDateRequired
    case exceedsOutstanding(remaining: Money)
    case nothingOutstanding
    case alreadyReversed
    case cannotReverseReversal
    case chequeNotActive
    case invalidOffset
    case hasDependencies(String)
    case notFound
    case invalidDate
    case nameRequired
    case passwordTooShort
    case backupWrongPassword
    case backupCorrupted
    case backupUnsupportedVersion(Int)
    case backupInvalid(String)

    var errorDescription: String? {
        switch self {
        case .overflow:
            return "مبلغ بیش از حد بزرگ است و قابل محاسبه نیست."
        case .amountMustBePositive:
            return "مبلغ باید بیشتر از صفر باشد."
        case .amountOutOfRange:
            return "مبلغ واردشده خارج از محدوده مجاز است."
        case .invalidAmountFormat:
            return "مبلغ را فقط با عدد وارد کن."
        case .sameAccountTransfer:
            return "حساب مبدأ و مقصد نباید یکی باشند."
        case .accountRequired:
            return "یک حساب انتخاب کن."
        case .accountNotFound:
            return "حساب پیدا نشد."
        case .accountInactive:
            return "این حساب غیرفعال است."
        case .contactRequired:
            return "طرف حساب را مشخص کن."
        case .dueDateRequired:
            return "تاریخ سررسید را مشخص کن."
        case .exceedsOutstanding(let remaining):
            return "مبلغ بیشتر از مانده است. مانده فعلی: \(PersianFormat.money(remaining, unit: .toman))"
        case .nothingOutstanding:
            return "مانده‌ای برای تسویه باقی نمانده است."
        case .alreadyReversed:
            return "این رویداد قبلاً برگشت خورده است."
        case .cannotReverseReversal:
            return "رویداد برگشتی را نمی‌توان دوباره برگشت زد."
        case .chequeNotActive:
            return "این چک در وضعیت فعال نیست."
        case .invalidOffset:
            return "تهاتر فقط میان طلب و بدهی باز یک شخص ممکن است."
        case .hasDependencies(let what):
            return "این مورد به \(what) وابسته است و حذف آن مجاز نیست."
        case .notFound:
            return "مورد موردنظر پیدا نشد."
        case .invalidDate:
            return "تاریخ نامعتبر است."
        case .nameRequired:
            return "نام را وارد کن."
        case .passwordTooShort:
            return "گذرواژه باید دست‌کم ۸ نویسه باشد."
        case .backupWrongPassword:
            return "گذرواژه اشتباه است یا فایل پشتیبان آسیب دیده است."
        case .backupCorrupted:
            return "فایل پشتیبان معتبر نیست."
        case .backupUnsupportedVersion(let v):
            return "نسخه فایل پشتیبان (\(PersianFormat.digits(String(v)))) پشتیبانی نمی‌شود."
        case .backupInvalid(let reason):
            return "پشتیبان ناسازگار است: \(reason)"
        }
    }
}
