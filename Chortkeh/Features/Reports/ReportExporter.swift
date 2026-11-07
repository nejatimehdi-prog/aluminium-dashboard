import Foundation
import SwiftUI
import UIKit

/// CSV and PDF exports. Files are written to a temporary folder and only leave the device through the
/// Share Sheet when the user chooses to.
enum ReportExporter {
    /// UTF-8 with BOM so Excel shows Persian text correctly; amounts are plain integers in the chosen unit.
    static func transactionsCSV(_ ledger: LedgerSnapshot, unit: CurrencyUnit) -> String {
        let reversed = FinancialCalculator.reversedTransactionIds(ledger)
        var rows: [[String]] = [[
            "تاریخ", "نوع", "مبلغ (\(unit.title))", "از حساب", "به حساب", "طرف حساب", "دسته", "توضیح", "وضعیت"
        ]]
        let sorted = ledger.transactions.sorted { $0.date == $1.date ? $0.createdAt < $1.createdAt : $0.date < $1.date }
        for tx in sorted {
            rows.append([
                PersianFormat.date(tx.date, style: .numeric),
                tx.kind.title,
                String(tx.amount.rials / unit.rialsPerUnit),
                ledger.account(tx.fromAccountId)?.name ?? "",
                ledger.account(tx.toAccountId)?.name ?? "",
                ledger.contact(tx.contactId)?.name ?? "",
                ledger.category(tx.categoryId)?.name ?? "",
                tx.note,
                reversed.contains(tx.id) ? "برگشت‌خورده" : ""
            ])
        }
        return "\u{FEFF}" + rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    static func commitmentsCSV(_ ledger: LedgerSnapshot, today: CivilDate, unit: CurrencyUnit) -> String {
        var rows: [[String]] = [["نوع", "طرف حساب", "مانده (\(unit.title))", "سررسید", "روز تا سررسید"]]
        for c in (try? CommitmentResolver.commitments(ledger, today: today)) ?? [] {
            rows.append([
                c.kind.title,
                ledger.contact(c.contactId)?.name ?? "",
                String(c.amount.rials / unit.rialsPerUnit),
                c.dueDate.map { PersianFormat.date($0, style: .numeric) } ?? "بدون سررسید",
                c.dueDate.map { String(today.days(until: $0)) } ?? ""
            ])
        }
        return "\u{FEFF}" + rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    static func escape(_ field: String) -> String {
        var f = field
        // Neutralize spreadsheet formula injection.
        if let first = f.first, "=+-@".contains(first) { f = "'" + f }
        if f.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return f
    }

    static func writeTemporary(_ data: Data, name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// Renders an RTL Persian report page to PDF.
    @MainActor
    static func pdf(data: DashboardData, ledger: LedgerSnapshot, unit: CurrencyUnit) throws -> Data {
        let page = ReportPDFPage(data: data, ledger: ledger, unit: unit)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "fa_IR"))
            .frame(width: 595, alignment: .topLeading)
        let renderer = ImageRenderer(content: page)
        renderer.proposedSize = ProposedViewSize(width: 595, height: nil)
        let output = NSMutableData()
        var failed = true
        renderer.render { size, draw in
            var box = CGRect(x: 0, y: 0, width: 595, height: max(842, size.height))
            guard let consumer = CGDataConsumer(data: output as CFMutableData),
                  let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            failed = false
        }
        if failed { throw DomainError.backupCorrupted }
        return output as Data
    }
}

private struct ReportPDFPage: View {
    let data: DashboardData
    let ledger: LedgerSnapshot
    let unit: CurrencyUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("گزارش چُرتکه").font(.title.bold())
            Text(PersianFormat.date(data.today, style: .withWeekday)).foregroundStyle(.secondary)
            Divider()
            row("موجودی واقعی", data.position.cash)
            row("طلب‌های باز", data.position.receivables)
            row("بدهی‌های باز", data.position.payables)
            row("خالص موقعیت ثبت‌شده (قابل خرج نیست)", data.position.netPosition)
            row("قابل خرج با خیال راحت (\(PersianFormat.number(data.safeToSpend.horizonDays)) روز)", data.safeToSpend.amount)
            Divider()
            Text("\(data.month.title)").font(.headline)
            row("خرج ماه", data.month.expense)
            row("درآمد ماه", data.month.income)
            Divider()
            Text("پیش‌بینی \(PersianFormat.number(data.forecast.horizonDays)) روز (\(data.forecast.scenario.title))").font(.headline)
            if let s = data.forecast.firstShortfall {
                Text("نخستین روز کسری: \(PersianFormat.date(s.date)) — حداکثر کسری \(PersianFormat.money(data.forecast.requiredFunds, unit: unit))")
            } else {
                Text("کسری پیش‌بینی نمی‌شود.")
            }
            row("مانده پایان بازه", data.forecast.endBalance)
            Divider()
            Text("سررسیدهای نزدیک").font(.headline)
            ForEach(data.upcoming.prefix(25)) { item in
                HStack {
                    Text("\(PersianFormat.date(item.dueDate, style: .numeric)) · \(item.kind.title) · \(item.contactName ?? "")")
                    Spacer()
                    Text(PersianFormat.money(item.amount, unit: unit))
                }
                .font(.caption)
            }
            Divider()
            ForEach(data.forecast.assumptions, id: \.self) { Text("• " + $0).font(.caption2) }
        }
        .padding(32)
        .foregroundStyle(.black)
        .background(.white)
    }

    private func row(_ title: String, _ money: Money) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(PersianFormat.money(money, unit: unit)).monospacedDigit()
        }
    }
}
