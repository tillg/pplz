#if os(iOS)
import Contacts
import ContactsUI
import SwiftUI

/// The system's own contact card, shown inside cardXchange. iOS offers no way to open a given person
/// in the Contacts app, so this is the phone's counterpart to "Open in Contacts" on the Mac:
/// the same card, with Edit, call, message and so on.
struct ContactCardSheet: View {
    let identifier: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let contact = try? CNContactStore().unifiedContact(
            withIdentifier: identifier, keysToFetch: [CNContactViewController.descriptorForRequiredKeys()]) {
            Card(contact: contact, onDone: { dismiss() }).ignoresSafeArea()
        } else {
            ContentUnavailableView("Contact not found", systemImage: "person.crop.circle.badge.questionmark",
                                   description: Text("It may have been deleted from Contacts."))
        }
    }

    private struct Card: UIViewControllerRepresentable {
        let contact: CNContact
        let onDone: () -> Void

        func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

        func makeUIViewController(context: Context) -> UINavigationController {
            let card = CNContactViewController(for: contact)
            card.contactStore = CNContactStore()
            card.navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .done, target: context.coordinator, action: #selector(Coordinator.done))
            let navigation = UINavigationController(rootViewController: card)
            navigation.view.tintColor = .systemPink
            return navigation
        }

        func updateUIViewController(_ controller: UINavigationController, context: Context) {}

        final class Coordinator: NSObject {
            let onDone: () -> Void
            init(onDone: @escaping () -> Void) { self.onDone = onDone }
            @objc func done() { onDone() }
        }
    }
}
#endif
