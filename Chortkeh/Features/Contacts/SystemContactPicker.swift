import ContactsUI
import SwiftUI

struct PickedContact {
    let name: String
    let phone: String
}

/// iOS system contact picker. It runs out of process, so the app only receives the single contact the
/// user taps — no address-book permission and nothing leaves the device.
struct SystemContactPicker: UIViewControllerRepresentable {
    let onPick: (PickedContact) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (PickedContact) -> Void

        init(onPick: @escaping (PickedContact) -> Void) {
            self.onPick = onPick
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? contact.givenName
            let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
            onPick(PickedContact(name: name, phone: phone))
        }
    }
}
