import SwiftUI
import AVKit
import UniformTypeIdentifiers

@main
struct MediaVaultApp: App {
    var body: some Scene {
        WindowGroup { FileBrowserView() }
    }
}

class BookmarkManager: ObservableObject {
    @Published var currentFolderURL: URL?
    private let bookmarkKey = "saved_folder_bookmark"
    init() { restoreBookmark() }
    func saveFolder(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        do {
            let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            currentFolderURL = url
        } catch { print(error) }
    }
    private func restoreBookmark() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            guard url.startAccessingSecurityScopedResource() else { return }
            currentFolderURL = url
            if stale { saveFolder(url: url) }
        } catch { print(error) }
    }
    func clearFolder() {
        currentFolderURL?.stopAccessingSecurityScopedResource()
        currentFolderURL = nil
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }
}

struct FileItem: Identifiable {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    var name: String { url.lastPathComponent }
    var isImage: Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }
    var isVideo: Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .video)
    }
    var icon: String {
        if isDirectory { return "folder" }
        if isImage { return "photo" }
        if isVideo { return "film" }
        return "doc"
    }
}

struct FileBrowserView: View {
    @StateObject private var bookmarkManager = BookmarkManager()
    @State private var files: [FileItem] = []
    @State private var selectedImage: FileItem?
    @State private var selectedVideo: FileItem?
    @State private var showFolderPicker = false

    var body: some View {
        NavigationStack {
            Group {
                if bookmarkManager.currentFolderURL == nil { emptyView } else { fileList }
            }
            .navigationTitle(bookmarkManager.currentFolderURL?.lastPathComponent ?? "MediaVault")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { showFolderPicker = true } label: { Image(systemName: "folder.badge.plus") } }
                if bookmarkManager.currentFolderURL != nil {
                    ToolbarItem(placement: .topBarLeading) { Button("更换文件夹") { bookmarkManager.clearFolder(); files = [] } }
                }
            }
        }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                bookmarkManager.saveFolder(url: url)
                loadFiles(from: url)
            }
        }
        .fullScreenCover(item: $selectedImage) { ImageViewerView(url: $0.url) }
        .fullScreenCover(item: $selectedVideo) { VideoPlayerView(url: $0.url) }
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.questionmark").font(.system(size: 60)).foregroundStyle(.secondary)
            Text("选择一个文件夹开始浏览").font(.headline)
            Button("选择文件夹") { showFolderPicker = true }.buttonStyle(.borderedProminent)
        }
    }

    private var fileList: some View {
        List(files) { item in
            Button {
                if item.isDirectory {
                    if let url = bookmarkManager.currentFolderURL {
                        let subURL = url.appendingPathComponent(item.name)
                        guard subURL.startAccessingSecurityScopedResource() else { return }
                        loadFiles(from: subURL)
                    }
                } else if item.isImage { selectedImage = item }
                else if item.isVideo { selectedVideo = item }
            } label: {
                HStack { Image(systemName: item.icon).foregroundStyle(item.isDirectory ? .blue : .secondary); Text(item.name).lineLimit(1) }
            }
        }
    }

    private func loadFiles(from url: URL) {
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            files = contents.compactMap { fileURL in
                let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return FileItem(url: fileURL, isDirectory: isDir)
            }.filter { $0.isDirectory || $0.isImage || $0.isVideo }
             .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch { print(error) }
    }
}

struct ImageViewerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let uiImage = UIImage(contentsOfFile: url.path) {
                Image(uiImage: uiImage).resizable().scaledToFit()
                    .scaleEffect(scale).offset(offset)
                    .gesture(MagnifyGesture().onChanged { scale = max(1.0, lastScale * $0.magnification) }.onEnded { _ in lastScale = scale; if scale <= 1.0 { withAnimation(.spring) { offset = .zero; lastOffset = .zero } } })
                    .simultaneousGesture(DragGesture().onChanged { guard scale > 1.0 else { return }; offset = CGSize(width: lastOffset.width + $0.translation.width, height: lastOffset.height + $0.translation.height) }.onEnded { _ in lastOffset = offset })
                    .onTapGesture(count: 2) { withAnimation(.spring) { scale = scale > 1.0 ? 1.0 : 2.5; if scale == 1.0 { offset = .zero; lastOffset = .zero }; lastScale = scale } }
            } else { Text("无法加载图片").foregroundStyle(.white) }
            VStack { HStack { Button { dismiss() } label: { Image(systemName: "xmark").font(.title2).foregroundStyle(.white).padding().background(.ultraThinMaterial, in: Circle()) }; Spacer() }; Spacer() }.padding()
        }.statusBarHidden()
    }
}

struct VideoPlayerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player { VideoPlayer(player: player).ignoresSafeArea().onAppear { player.play() }.onDisappear { player.pause() } }
            else { ProgressView().tint(.white) }
            VStack { HStack { Button { dismiss() } label: { Image(systemName: "xmark").font(.title2).foregroundStyle(.white).padding().background(.ultraThinMaterial, in: Circle()) }; Spacer() }; Spacer() }.padding()
        }.statusBarHidden().onAppear { player = AVPlayer(url: url) }
    }
}
