//
//  HostPostEditorView.swift
//  Lurelia
//
//  Full sheet for authoring a host post or an announcement.
//
//  Layout, top to bottom:
//    • Header row (title + pin toggle) with an xmarkwavy dismiss on the
//      right and a Publish pill next to it.
//    • Formatting toolbar — its own row, visually distinct, floating on
//      the background (NOT inside the editor card).
//    • Editor GlassCard — fixed height, WKWebView with bounce disabled.
//
//  Sheet is `.interactiveDismissDisabled(true)` so tapping/pulling inside
//  the editor never accidentally dismisses.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

enum HostPostEditorKind: Equatable {
    case post
    case announcement
}

struct HostPostDraft: Equatable {
    var title: String
    var bodyMarkdown: String
    var bodyHTML: String
    var isPinned: Bool
}

struct HostPostEditorView: View {
    // Inputs
    let kind: HostPostEditorKind
    let sharedEventID: String
    let currentUserID: String
    let tint: Color
    var initialTitle: String = ""
    let initialMarkdown: String
    var initialIsPinned: Bool = false
    var isEditing: Bool = false
    let mediaUploader: TiptapMediaUploader
    let onSave: (HostPostDraft) -> Void
    let onCancel: () -> Void

    @Environment(\.appTheme) private var theme

    // State
    @StateObject private var controller = TiptapEditorController()
    @State private var postTitle: String = ""
    @State private var isPinned: Bool = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var linkDraft: String = ""
    @State private var showingLinkPrompt = false
    @State private var isUploading = false
    @State private var uploadError: String?

    // Icon picker (for callouts).
    @State private var showingIconPicker: Bool = false
    @State private var pickedIcon: String = "starcal"
    @State private var iconPickerPurpose: IconPickerPurpose = .insert
    @FocusState private var focusedField: FocusedField?

    private enum IconPickerPurpose: Equatable {
        case insert
        case update(calloutId: String)
    }

    private enum FocusedField: Hashable {
        case title
    }

    // MARK: Body

    var body: some View {
        ZStack {
            theme.palette.background
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                            .padding(.horizontal, LSpacing.pageHorizontal)
                            .padding(.top, 18)
                            .padding(.bottom, 6)

                        titleField
                            .id(FocusedField.title)
                            .padding(.horizontal, LSpacing.pageHorizontal)
                            .padding(.bottom, 10)

                        toolbarBand
                            .padding(.horizontal, LSpacing.pageHorizontal)
                            .padding(.bottom, 10)

                        editorArea
                            .padding(.horizontal, LSpacing.pageHorizontal)
                            .padding(.bottom, 16)

                        Spacer().frame(height: 120)
                    }
                }
                .safeAreaPadding(.top, 8)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focusedField) { _, field in
                    guard field == .title else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(FocusedField.title, anchor: .center)
                    }
                }
            }
        }
        .presentationBackground(theme.palette.background)
        .interactiveDismissDisabled(true)
        .photosPicker(
            isPresented: Binding(
                get: { photoPickerItem == nil && controller.pendingImageRequest != nil },
                set: { newValue in
                    if !newValue { controller.pendingImageRequest = nil }
                },
            ),
            selection: $photoPickerItem,
            matching: .images,
        )
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.data, .pdf, .image, .plainText],
            allowsMultipleSelection: false,
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView(
                selectedIcon: $pickedIcon,
                dismissesOnSelection: true,
                allowedSources: [.asset],
                onSelection: { iconName in
                    handleIconPicked(iconName)
                },
            )
        }
        .onChange(of: photoPickerItem) { _, newValue in
            guard let newValue else { return }
            Task { await handlePhotoSelection(newValue) }
        }
        .onChange(of: controller.pendingFileRequest) { _, newValue in
            guard newValue != nil else { return }
            showingFileImporter = true
        }
        .onChange(of: controller.pendingLinkRequest) { _, newValue in
            guard let req = newValue else { return }
            linkDraft = req.currentHref
            showingLinkPrompt = true
        }
        .onChange(of: controller.pendingIconPickerRequest) { _, newValue in
            guard let req = newValue else { return }
            let currentIcon = req.currentIcon.isEmpty ? "starcal" : req.currentIcon
            pickedIcon = currentIcon
            iconPickerPurpose = .update(calloutId: req.calloutId)
            showingIconPicker = true
        }
        .alert("Link", isPresented: $showingLinkPrompt) {
            TextField("https://…", text: $linkDraft)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            Button("Remove", role: .destructive) {
                controller.unsetLink()
                controller.pendingLinkRequest = nil
            }
            Button("Apply") {
                let trimmed = linkDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    controller.unsetLink()
                } else {
                    controller.setLink(trimmed)
                }
                controller.pendingLinkRequest = nil
            }
            Button("Cancel", role: .cancel) {
                controller.pendingLinkRequest = nil
            }
        } message: {
            Text("Paste a URL")
        }
        .alert(
            "Upload failed",
            isPresented: Binding(
                get: { uploadError != nil },
                set: { if !$0 { uploadError = nil } },
            ),
        ) {
            Button("OK", role: .cancel) { uploadError = nil }
        } message: {
            Text(uploadError ?? "")
        }
        .onAppear {
            isPinned = initialIsPinned
            postTitle = initialTitle
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(LColors.textPrimary)

                Spacer()

                Button {
                    onSave(
                        HostPostDraft(
                            title: trimmedPostTitle,
                            bodyMarkdown: controller.markdown,
                            bodyHTML: controller.html,
                            isPinned: isPinned,
                        ),
                    )
                } label: {
                    Text(saveLabel)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            BubblyIconMaterial(tint: tint)
                                .clipShape(Capsule())
                        }
                        .opacity(canSave ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)

                Button {
                    onCancel()
                } label: {
                    Image("xmarkwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(.white)
                        .bubblyIconMaterial(tint: .white)
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            if kind == .post {
                HStack(spacing: 12) {
                    Text("Pin to the top of the timeline")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(theme.palette.textSecondary)

                    Spacer()

                    LureliaSlidingIconToggle(
                        isOn: $isPinned,
                        iconName: "pin",
                        accentColor: tint,
                        accessibilityLabel: "Pin to the top of the timeline",
                        usesIconMaterial: true
                    )
                }
            }
        }
    }

    private var title: String {
        if isEditing {
            switch kind {
            case .post: return "Edit host post"
            case .announcement: return "Edit announcement"
            }
        }
        switch kind {
        case .post: return "New host post"
        case .announcement: return "New announcement"
        }
    }

    private var saveLabel: String {
        if isEditing { return "Save" }
        switch kind {
        case .post: return isPinned ? "Publish & pin" : "Publish"
        case .announcement: return "Announce"
        }
    }

    private var trimmedPostTitle: String {
        postTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedPostTitle.isEmpty && !controller.isEmpty
    }

    // MARK: Title field

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kind == .post ? "Post title" : "Announcement title")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(LColors.textSecondary)

            TextField(
                kind == .post ? "Give this post a title" : "Give this announcement a title",
                text: $postTitle,
            )
            .textInputAutocapitalization(.words)
            .focused($focusedField, equals: .title)
            .font(.system(size: 16, weight: .black, design: .rounded))
            .foregroundStyle(LColors.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.palette.surface),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(tint, lineWidth: 1),
            )
        }
    }

    // MARK: Toolbar (compact strip outside the editor card)

    private var toolbarBand: some View {
        toolbarButtons
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.palette.surface),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(tint, lineWidth: 1),
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var toolbarButtons: some View {
        LazyVGrid(columns: toolbarColumns, alignment: .leading, spacing: 6) {
            toolButton("B", isActive: controller.toolbar.isBold) {
                controller.toggleBold()
            }
            toolButton("I", isActive: controller.toolbar.isItalic) {
                controller.toggleItalic()
            }
            toolButton("U", isActive: controller.toolbar.isUnderline) {
                controller.toggleUnderline()
            }
            toolButton("S", isActive: controller.toolbar.isStrike) {
                controller.toggleStrike()
            }

            toolButton("H1", isActive: controller.toolbar.isH1) { controller.setHeading(1) }
            toolButton("H2", isActive: controller.toolbar.isH2) { controller.setHeading(2) }
            toolButton("H3", isActive: controller.toolbar.isH3) { controller.setHeading(3) }

            toolButton("• List", isActive: controller.toolbar.isBulletList) {
                controller.toggleBulletList()
            }
            toolButton("1. List", isActive: controller.toolbar.isOrderedList) {
                controller.toggleOrderedList()
            }
            toolButton("Quote", isActive: controller.toolbar.isBlockquote) {
                controller.toggleBlockquote()
            }
            toolButton("Callout", isActive: false) {
                controller.insertCallout(icon: "starcal", text: "Callout text")
            }
            toolButton("Code", isActive: controller.toolbar.isCodeBlock) {
                controller.toggleCodeBlock()
            }

            toolButton("Link", isActive: controller.toolbar.isLink) {
                linkDraft = ""
                showingLinkPrompt = true
            }
            toolButton("Photo", isActive: false) {
                photoPickerItem = nil
                controller.pendingImageRequest = UUID()
            }
            toolButton("File", isActive: false) {
                controller.pendingFileRequest = UUID()
            }

            toolButton("Undo", isActive: false, disabled: !controller.toolbar.canUndo) {
                controller.undo()
            }
            toolButton("Redo", isActive: false, disabled: !controller.toolbar.canRedo) {
                controller.redo()
            }
        }
        .padding(8)
    }

    private var toolbarColumns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: 54, maximum: 88),
                spacing: 6,
                alignment: .leading,
            ),
        ]
    }

    @ViewBuilder
    private func toolButton(
        _ label: String,
        isActive: Bool,
        disabled: Bool = false,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 30)
                .padding(.horizontal, 6)
                .padding(.vertical, 7)
                .background {
                    BubblyIconMaterial(tint: tint)
                        .clipShape(
                            RoundedRectangle(cornerRadius: LSpacing.buttonRadius, style: .continuous)
                        )
                }
                .overlay(
                    RoundedRectangle(cornerRadius: LSpacing.buttonRadius, style: .continuous)
                        .strokeBorder(tint, lineWidth: isActive ? 2 : 1),
                )
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.35 : (isUploading ? 0.6 : 1))
        .disabled(disabled || isUploading)
    }

    // MARK: Editor area

    private var editorArea: some View {
        ZStack {
            TiptapEditorWebView(
                controller: controller,
                initialMarkdown: initialMarkdown,
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: 320, idealHeight: 460, maxHeight: 560)

            if !controller.isReady {
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(tint)
                    Text("Preparing editor…")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }

            if isUploading {
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(tint)
                    Text("Uploading…")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(theme.palette.textPrimary)
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.55)),
                )
            }
        }
        .padding(4)
        .background(
            theme.palette.surface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(tint, lineWidth: 1)
        }
    }

    // MARK: Icon picker handoff

    private func handleIconPicked(_ iconName: String) {
        guard !iconName.isEmpty else { return }
        switch iconPickerPurpose {
        case .insert:
            controller.insertCallout(icon: iconName, text: "")
        case .update(let calloutId):
            controller.updateCalloutIcon(calloutId: calloutId, icon: iconName)
        }
        controller.pendingIconPickerRequest = nil
    }

    // MARK: Photo / File flows

    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        defer { photoPickerItem = nil; controller.pendingImageRequest = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            isUploading = true
            defer { isUploading = false }
            let asset = try await mediaUploader.uploadImage(
                image,
                target: mediaTarget,
                uploaderUserID: currentUserID,
                filename: "post-image.jpg",
                isInline: true,
            )
            controller.insertImage(url: asset.url, alt: asset.filename ?? "")
        } catch {
            uploadError = String(describing: error)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        controller.pendingFileRequest = nil
        switch result {
        case .failure(let err):
            uploadError = err.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await uploadFileAtURL(url) }
        }
    }

    private func uploadFileAtURL(_ url: URL) async {
        do {
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            let mimeType = (UTType(filenameExtension: url.pathExtension)?.preferredMIMEType)
                ?? "application/octet-stream"
            isUploading = true
            defer { isUploading = false }
            let asset = try await mediaUploader.uploadFile(
                data,
                filename: url.lastPathComponent,
                mimeType: mimeType,
                target: mediaTarget,
                uploaderUserID: currentUserID,
            )
            controller.insertFileLink(url: asset.url, filename: url.lastPathComponent)
        } catch {
            uploadError = String(describing: error)
        }
    }

    private var mediaTarget: TiptapMediaTarget {
        .event(sharedEventID: sharedEventID)
    }
}
