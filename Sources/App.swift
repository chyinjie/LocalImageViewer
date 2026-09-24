import SwiftUI
import AVKit
import UniformTypeIdentifiers

@main
struct MediaVaultApp: App {
    var body: some Scene {
        WindowGroup { FileBrowserView() }
    }
}

struct FileBrowserView: View {
    @State private var files: [FileItem] = []
    @State private var selectedImage: FileItem?
    @State private var selectedVideo: FileItem?
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            Group {
                if files.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "folder.badge.questionmark").font(.system(size: 60)).foregroundStyle(.secondary)
                        Text("请选择文件夹").font(.headline)
                        Button("选择文件夹") { showPicker = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List(files) { item in
                        Button {
                            if item.isImage { selectedImage = item }
                            else if item.isVideo { selectedVideo = item }
                        } label: {
                            HStack { Image(systemName: item.icon); Text(item.name) }
                        }
                    }
                }
            }
            .navigationTitle("媒体浏览器")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("选文件夹") { showPicker = true }
                }
            }
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                loadFolder(url: url)
            }
        }
        .fullScreenCover(item: $selectedImage) { item in
            if let img = UIImage(contentsOfFile: item.url.path) {
                ImageViewerView(image: img)
            }
        }
        .fullScreenCover(item: $selectedVideo) { item in
            VideoPlayerView(url: item.url)
        }
    }

    private func loadFolder(url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        if let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) {
            files = contents.compactMap { fileURL in
                let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return FileItem(url: fileURL, isDirectory: isDir)
            }.filter { $0.isImage || $0.isVideo }
             .sorted { $0.name < $1.name }
        }
    }
}

struct ImageViewerView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image).resizable().scaledToFit()
            VStack { HStack { Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.white).padding() }; Spacer() }; Spacer() }.padding()
        }
    }
}

struct VideoPlayerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player { VideoPlayer(player: player).onAppear { player.play() }.onDisappear { player.pause() } }
            VStack { HStack { Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.white).padding() }; Spacer() }; Spacer() }.padding()
        }
        .onAppear { player = AVPlayer(url: url) }
    }
}

struct FileItem: Identifiable {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    var name: String { url.lastPathComponent }
    var isImage: Bool { let type = UTType(filenameExtension: url.pathExtension); return type?.conforms(to: .image) ?? false }
    var isVideo: Bool { let type = UTType(filenameExtension: url.pathExtension); return type?.conforms(to: .movie) ?? false }
    var icon: String { isImage ? "photo" : "film" }
}
