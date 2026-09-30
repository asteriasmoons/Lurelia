//
//  CommentAttachmentSupport.swift
//  Lurelia
//
//  Small reusable pieces for putting attachments on comments:
//    • `CommentAttachmentDraft` — @Observable state used while composing
//    • `CommentAttachmentComposer` — the "+" picker + thumbnail strip
//    • `CommentAttachmentStrip` — the display strip under a submitted comment
//    • `CommentAttachmentCache` — resolves attachmentID → URL/thumbnail
//      for comments loaded from the server. Uses the existing
//      `/api/lurelia/media/batch` endpoint added in Prompt 1B.
//
//  Uploading reuses the existing `TiptapMediaUploader` so there is no
//  parallel networking or storage layer.
//

import SwiftUI
import Combine
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

// MARK: - Draft

@MainActor
final class CommentAttachmentDraft: ObservableObject {
    /// Uploaded assets, keyed to the order in which the user added them.
    @Published var uploaded: [TiptapUploadedAsset] = []
    @Published var isUploading: Bool = false
    @Published var errorMessage: String?

    var attachmentIDs: [String] {
        uploaded.compactMap { $0.id }
    }

    func reset() {
        uploaded.removeAll()
        errorMessage = nil
    }
}

// MARK: - Composer

struct CommentAttachmentComposer: View {
    @ObservedObject var draft: CommentAttachmentDraft
    let eventID: String
    let uploaderUserID: String
    let tint: Color

    @Environment(\.appTheme) private var theme

    @State private var photoItem: PhotosPickerItem?
    @State private var showingFileImporter = false

    private var uploader: TiptapMediaUploader {
        TiptapMediaUploader(baseURL: LureliaAPIConfig.baseURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PhotosPicker(
                    selection: $photoItem,
                    matching: .images,
                    photoLibrary: .shared(),
                ) {
                    label("Photo")
                }

                Button {
                    showingFileImporter = true
                } label: {
                    label("File")
                }
                .buttonStyle(.plain)

                if draft.isUploading {
                    ProgressView().tint(LColors.accent).scaleEffect(0.8)
                }
                Spacer()
            }

            if !draft.uploaded.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(draft.uploaded.enumerated()), id: \.offset) { pair in
                            thumbnail(for: pair.element, at: pair.offset)
                        }
                    }
                }
            }

            if let err = draft.errorMessage {
                Text(err)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(LColors.danger)
                    .lineLimit(2)
            }
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task { await handlePhoto(newItem) }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.pdf, .data, .plainText, .image],
            allowsMultipleSelection: false,
        ) { result in
            handleFileImport(result)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                BubblyIconMaterial(tint: tint)
                    .clipShape(Capsule())
            }
            .overlay(Capsule().strokeBorder(tint, lineWidth: 1))
    }

    @ViewBuilder
    private func thumbnail(for asset: TiptapUploadedAsset, at index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let thumb = asset.thumbnailURL, let url = URL(string: thumb) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            LColors.glassSurface2
                        }
                    }
                } else {
                    filePlaceholder(asset)
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(tint, lineWidth: 1),
            )

            Button {
                if draft.uploaded.indices.contains(index) {
                    draft.uploaded.remove(at: index)
                }
            } label: {
                Image("xmarkwavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Circle().fill(Color.black.opacity(0.7)))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
        }
    }

    private func filePlaceholder(_ asset: TiptapUploadedAsset) -> some View {
        VStack(spacing: 2) {
            Text("FILE")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(LColors.textSecondary)
            Text(asset.filename ?? "attachment")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(LColors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(2)
        .frame(width: 60, height: 60)
        .background(theme.palette.surface)
    }

    private func handlePhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            draft.isUploading = true
            defer { draft.isUploading = false }
            let asset = try await uploader.uploadImage(
                image,
                target: .event(sharedEventID: eventID),
                uploaderUserID: uploaderUserID,
                filename: "comment-image.jpg",
                isInline: false,
            )
            draft.uploaded.append(asset)
            draft.errorMessage = nil
        } catch {
            draft.errorMessage = String(describing: error)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let e):
            draft.errorMessage = e.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await uploadFile(at: url) }
        }
    }

    private func uploadFile(at url: URL) async {
        do {
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let mimeType = (UTType(filenameExtension: url.pathExtension)?
                .preferredMIMEType) ?? "application/octet-stream"
            draft.isUploading = true
            defer { draft.isUploading = false }
            let asset = try await uploader.uploadFile(
                data,
                filename: url.lastPathComponent,
                mimeType: mimeType,
                target: .event(sharedEventID: eventID),
                uploaderUserID: uploaderUserID,
            )
            draft.uploaded.append(asset)
            draft.errorMessage = nil
        } catch {
            draft.errorMessage = String(describing: error)
        }
    }
}

// MARK: - Display strip

struct CommentAttachmentStrip: View {
    let attachmentIDs: [String]

    @StateObject private var cache = CommentAttachmentCache.shared
    @State private var previewSelection: CommentAttachmentPreviewSelection?

    var body: some View {
        if attachmentIDs.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachmentIDs, id: \.self) { id in
                        chip(for: id)
                    }
                }
            }
            .task { await cache.hydrate(ids: attachmentIDs) }
            .sheet(item: $previewSelection) { selection in
                CommentAttachmentPreviewSheet(asset: selection.asset)
            }
        }
    }

    @ViewBuilder
    private func chip(for id: String) -> some View {
        if let asset = cache.byID[id] {
            Button {
                previewSelection = CommentAttachmentPreviewSelection(asset: asset)
            } label: {
                if let thumb = asset.thumbnailURL, let url = URL(string: thumb) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            LColors.glassSurface2
                        }
                    }
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(LColors.glassBorder, lineWidth: 1),
                    )
                } else {
                    Text(asset.filename ?? "File")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(LColors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(LColors.glassSurface2, in: Capsule())
                        .overlay(Capsule().strokeBorder(LColors.glassBorder, lineWidth: 1))
                }
            }
            .buttonStyle(.plain)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LColors.glassSurface2)
                .frame(width: 54, height: 54)
        }
    }
}

private struct CommentAttachmentPreviewSelection: Identifiable {
    let asset: TiptapUploadedAsset

    var id: String {
        asset.id ?? asset.url
    }
}

private struct CommentAttachmentPreviewSheet: View {
    let asset: TiptapUploadedAsset

    @Environment(\.dismiss) private var dismiss
    @State private var localPreviewURL: URL?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var title: String {
        asset.filename ?? "Attachment"
    }

    private var remoteURL: URL? {
        URL(string: asset.url)
    }

    private var isImage: Bool {
        if asset.kind?.lowercased() == "image" { return true }
        if asset.mimeType?.lowercased().hasPrefix("image/") == true { return true }
        let lower = asset.url.lowercased()
        return lower.hasSuffix(".jpg")
            || lower.hasSuffix(".jpeg")
            || lower.hasSuffix(".png")
            || lower.hasSuffix(".gif")
            || lower.hasSuffix(".heic")
            || lower.hasSuffix(".webp")
    }

    var body: some View {
        ZStack {
            LureliaBackgroundAlt()

            VStack(spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Attachment preview")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(LColors.textPrimary)
                        Text(title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(LColors.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image("xmarkwavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundStyle(LGradients.header)
                            .frame(width: 42, height: 42)
                            .background(LColors.glassSurface, in: Circle())
                            .overlay(Circle().strokeBorder(LColors.glassBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close preview")
                }

                GlassCard(cornerRadius: 22) {
                    Group {
                        if isImage, let url = remoteURL {
                            imagePreview(url)
                        } else if let localPreviewURL {
                            QuickLookAttachmentPreview(url: localPreviewURL)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        } else if isLoading {
                            VStack(spacing: 10) {
                                ProgressView()
                                    .tint(LColors.accent)
                                Text("Loading preview")
                                    .font(.system(size: 12, weight: .black, design: .rounded))
                                    .foregroundStyle(LColors.textSecondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 360)
                        } else {
                            VStack(spacing: 8) {
                                Image("notespen")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                    .foregroundStyle(LGradients.header)
                                Text(errorMessage ?? "Preview is not available for this attachment.")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(LColors.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, minHeight: 360)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 360)
                }
            }
            .padding(.top, 18)
            .padding(.horizontal, LSpacing.pageHorizontal)
            .padding(.bottom, 22)
        }
        .task(id: asset.url) {
            await preparePreviewIfNeeded()
        }
    }

    @ViewBuilder
    private func imagePreview(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
            case .failure:
                Text("Image preview could not load.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LColors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 360)
            default:
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(LColors.accent)
                    Text("Loading image")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(LColors.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 360)
            }
        }
    }

    private func preparePreviewIfNeeded() async {
        guard !isImage else { return }
        guard let remoteURL else {
            await MainActor.run { errorMessage = "Attachment URL is invalid." }
            return
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
            localPreviewURL = nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }

            let filename = sanitizedFilename(from: remoteURL)
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("lurelia-comment-preview-\(asset.id ?? UUID().uuidString)-\(filename)")
            try data.write(to: fileURL, options: .atomic)

            await MainActor.run {
                localPreviewURL = fileURL
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Preview could not load."
                isLoading = false
            }
        }
    }

    private func sanitizedFilename(from url: URL) -> String {
        let raw = asset.filename?.isEmpty == false
            ? asset.filename!
            : (url.lastPathComponent.isEmpty ? "attachment" : url.lastPathComponent)
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return raw.components(separatedBy: invalid).joined(separator: "-")
    }
}

private struct QuickLookAttachmentPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int,
        ) -> QLPreviewItem {
            url as NSURL
        }
    }
}

// MARK: - Cache

@MainActor
final class CommentAttachmentCache: ObservableObject {
    static let shared = CommentAttachmentCache()

    @Published private(set) var byID: [String: TiptapUploadedAsset] = [:]
    private var inflight: Set<String> = []

    private init() {}

    /// Registers assets known locally (e.g. just uploaded in the composer).
    func register(_ assets: [TiptapUploadedAsset]) {
        for a in assets {
            if let id = a.id { byID[id] = a }
        }
    }

    /// Fetches any IDs we don't already know about via `/media/batch`.
    func hydrate(ids: [String]) async {
        let missing = ids.filter { byID[$0] == nil && !inflight.contains($0) }
        guard !missing.isEmpty else { return }
        missing.forEach { inflight.insert($0) }
        defer { missing.forEach { inflight.remove($0) } }

        var comps = URLComponents(
            url: LureliaAPIConfig.route("/media/batch"),
            resolvingAgainstBaseURL: false,
        )!
        comps.queryItems = [URLQueryItem(name: "ids", value: missing.joined(separator: ","))]
        var request = URLRequest(url: comps.url!)
        request.httpMethod = "GET"
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return }
            struct Wrap: Decodable { let attachments: [TiptapUploadedAsset] }
            let dec = JSONDecoder()
            let wrap = try dec.decode(Wrap.self, from: data)
            register(wrap.attachments)
        } catch {
            #if DEBUG
            print("[CommentAttachmentCache] hydrate failed:", error)
            #endif
        }
    }
}
