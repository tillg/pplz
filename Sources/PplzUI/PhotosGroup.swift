import PhotosUI
import PplzCore
import SwiftUI
import UniformTypeIdentifiers

/// The "Photos" group of a person's card: the pictures of their face that pplz keeps, to recognise
/// them in new photos. Pictures come in by + (photo library on iPhone and iPad, a file or the
/// clipboard on the Mac) or by drag and drop.
struct PhotosGroup: View {
    let photos: [PhotoSnapshot]
    let onAdd: ([Data]) -> Void
    /// Set on the Mac. ⌘V stays "capture a profile", so pasting a photo is a menu item.
    let onPaste: (() -> Void)?
    /// Set when the person has a contact that may get a picture.
    let onUse: ((UUID) -> Void)?
    let onDelete: (UUID) -> Void

    @State private var isDropTarget = false
    @State private var deleting: UUID?
    #if os(macOS)
    @State private var isChoosingFile = false
    #else
    @State private var picked: [PhotosPickerItem] = []
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionTitle("Photos")
                Spacer()
                addButton
            }
            FieldGroup {
                if photos.isEmpty {
                    Text("No photos yet. Add one with +, or drop pictures here.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(photos, id: \.id) { photo in thumbnail(photo) }
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(.pink, lineWidth: isDropTarget ? 2 : 0) }
        }
        .onDrop(of: [.image], isTargeted: $isDropTarget) { providers in
            let loaded = DropLoader()
            let group = DispatchGroup()
            for provider in providers {
                group.enter()
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data { loaded.add(data) }
                    group.leave()
                }
            }
            group.notify(queue: .main) { let images = loaded.images; if !images.isEmpty { onAdd(images) } }
            return !providers.isEmpty
        }
        .confirmationDialog("Delete this photo?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Photo", role: .destructive) { if let id = deleting { onDelete(id) } }
        } message: {
            Text("It is removed from pplz on all your devices. Contacts is not changed.")
        }
        #if os(macOS)
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            guard let urls = try? result.get() else { return }
            onAdd(urls.compactMap { url in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return try? Data(contentsOf: url)
            })
        }
        #else
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task {
                var images: [Data] = []
                for item in items { if let data = try? await item.loadTransferable(type: Data.self) { images.append(data) } }
                if !images.isEmpty { onAdd(images) }
            }
        }
        #endif
    }

    private var addButton: some View {
        let symbol = Image(systemName: "plus.circle.fill").font(.title3)
        return Group {
            #if os(macOS)
            Menu {
                Button("Choose Files…", systemImage: "photo.on.rectangle") { isChoosingFile = true }
                if let onPaste { Button("Paste Photo", systemImage: "doc.on.clipboard", action: onPaste) }
            } label: { symbol }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            #else
            PhotosPicker(selection: $picked, matching: .images) { symbol }
            #endif
        }
        .foregroundStyle(.pink)
        .help("Add photos of this person")
        .accessibilityLabel("Add photos")
    }

    private func thumbnail(_ photo: PhotoSnapshot) -> some View {
        Menu {
            if let onUse { Button("Use as contact picture", systemImage: "person.crop.circle") { onUse(photo.id) } }
            Button("Delete…", systemImage: "trash", role: .destructive) { deleting = photo.id }
        } label: {
            Group {
                if let image = Image(data: photo.data) {
                    image.resizable().scaledToFill()
                } else {
                    Color.secondary.opacity(0.3)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())
            .overlay { Circle().stroke(.quaternary, lineWidth: 1) }
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .help(photo.createdAt.formatted(date: .abbreviated, time: .shortened))
        .accessibilityLabel("Photo of \(photo.createdAt.formatted(date: .abbreviated, time: .omitted))")
    }
}

/// Collects the pictures of a drop, whose providers answer on background threads.
private final class DropLoader: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [Data] = []
    func add(_ data: Data) { lock.lock(); collected.append(data); lock.unlock() }
    var images: [Data] { lock.lock(); defer { lock.unlock() }; return collected }
}

/// Which face is the person? Shown when a picture has several; tapping a crop stores it.
struct FaceChoiceSheet: View {
    let personName: String
    let crops: [Data]
    let onChoose: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 16) {
            Text("Which one is \(personName)?").font(.title3.weight(.semibold))
            faces
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .tint(.pink)
        #else
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                faces
                Spacer()
            }
            .padding()
            .navigationTitle("Which one is \(personName)?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .tint(.pink)
        #endif
    }

    private var faces: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(Array(crops.enumerated()), id: \.offset) { index, crop in
                    Button { onChoose(index) } label: {
                        Group {
                            if let image = Image(data: crop) { image.resizable().scaledToFill() } else { Color.secondary.opacity(0.3) }
                        }
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Face \(index + 1) of \(crops.count)")
                }
            }
            .padding(4)
        }
    }
}
