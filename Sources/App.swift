import SwiftUI
import AVKit
import PhotosUI
import UniformTypeIdentifiers

@main
struct MediaVaultApp: App {
    var body: some Scene {
        WindowGroup { FileBrowserView() }
    }
}

// MARK: - 主视图 (相册 + 文件夹双模式)
struct FileBrowserView: View {
    enum ViewMode { case photos, folder }
    @State private var viewMode: ViewMode = .photos
    @State private var photoAssets: [PHAsset] = []
    @State private var folderFiles: [FileItem] = []
    @State private var selectedImage: UIImage?
    @State private var selectedVideo: URL?
    @State private var showFolderPicker = false
    
    var body: some View {
        NavigationStack {
            Group {
                if viewMode == .photos {
                    if photoAssets.isEmpty { emptyView } else { photoGrid }
                } else {
                    if folderFiles.isEmpty { emptyView } else { fileList }
                }
            }
            .navigationTitle(viewMode == .photos ? "系统相册" : "文件夹浏览")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("选择文件夹") { showFolderPicker = true }
                }
                if viewMode == .folder {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("看相册") { viewMode = .photos }
                    }
                }
            }
        }
        .onAppear(perform: requestAndLoadPhotos)
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                // 开始安全作用域访问
                guard url.startAccessingSecurityScopedResource() else { return }
                loadFolder(from: url)
                viewMode = .folder // 切换到文件夹模式
            }
        }
        .fullScreenCover(item: $selectedImage) { img in ImageViewerView(image: img) }
        .fullScreenCover(item: $selectedVideo) { url in VideoPlayerView(url: url) }
    }
    
    // 相册网格
    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 4) {
                ForEach(photoAssets, id: \.localIdentifier) { asset in
                    PhotoThumbnailView(asset: asset)
                        .onTapGesture {
                            if asset.mediaType == .video {
                                let options = PHVideoRequestOptions()
                                options.isNetworkAccessAllowed = true
                                PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                                    if let urlAsset = avAsset as? AVURLAsset {
                                        DispatchQueue.main.async { selectedVideo = urlAsset.url }
                                    }
                                }
                            } else {
                                let options = PHImageRequestOptions()
                                options.isNetworkAccessAllowed = true
                                options.deliveryMode = .highQualityFormat
                                PHImageManager.default().requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options) { image, _ in
                                    DispatchQueue.main.async { selectedImage = image }
                                }
                            }
                        }
                }
            }
            .padding(2)
        }
    }
    
    // 文件夹列表
    private var fileList: some View {
        List(folderFiles) { item in
            Button {
                if item.isDirectory {
                    // 子文件夹处理：简单起见直接重新弹窗选，或者自己构建递归
                } else if item.isImage {
                    if let img = UIImage(contentsOfFile: item.url.path) { selectedImage = img }
                } else if item.isVideo {
                    selectedVideo = item.url
                }
            } label: {
                HStack {
                    Image(systemName: item.icon).foregroundStyle(item.isDirectory ? .blue : .secondary)
                    Text(item.name).lineLimit(1)
                }
            }
        }
    }
    
    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 60)).foregroundStyle(.secondary)
            Text(viewMode == .photos ? "正在请求相册权限..." : "文件夹为空或未授权").font(.headline)
            Button("选择文件夹") { showFolderPicker = true }.buttonStyle(.borderedProminent)
        }
    }
    
    // 请求并加载相册
    private func requestAndLoadPhotos() {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else { return }
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let result = PHAsset.fetchAssets(with: options)
            var newAssets: [PHAsset] = []
            result.enumerateObjects { asset, _, _ in newAssets.append(asset) }
            DispatchQueue.main.async { self.photoAssets = newAssets }
        }
    }
    
    // 加载文件夹
    private func loadFolder(from url: URL) {
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            var files: [FileItem] = []
            for fileURL in contents {
                let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let item = FileItem(url: fileURL, isDirectory: isDir)
                if isDir || item.isImage || item.isVideo { files.append(item) }
            }
            self.folderFiles = files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch { print(error) }
    }
}

// MARK: - 相册缩略图
struct PhotoThumbnailView: View {
    let asset: PHAsset
    @State private var image: UIImage?
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(.gray.opacity(0.2))
                ProgressView()
            }
            if asset.mediaType == .video {
                Image(systemName: "play.circle.fill").font(.title).foregroundStyle(.white).shadow(radius: 2)
            }
        }
        .frame(width: 100, height: 100).clipped()
        .onAppear {
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .opportunistic
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 200, height: 200), contentMode: .aspectFill, options: options) { img, _ in
                DispatchQueue.main.async { self.image = img }
            }
        }
    }
}

// MARK: - 图片查看器
struct ImageViewerView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image).resizable().scaledToFit()
                .scaleEffect(scale).offset(offset)
                .gesture(MagnifyGesture().onChanged { scale = max(1.0, lastScale * $0.magnification) }.onEnded { _ in lastScale = scale })
                .simultaneousGesture(DragGesture().onChanged { guard scale > 1.0 else { return }; offset = CGSize(width: lastOffset.width + $0.translation.width, height: lastOffset.height + $0.translation.height) }.onEnded { _ in lastOffset = offset })
            VStack { HStack { Button { dismiss() } label: { Image(systemName: "xmark").font(.title2).foregroundStyle(.white).padding().background(.ultraThinMaterial, in: Circle()) }; Spacer() }; Spacer() }.padding()
        }.statusBarHidden()
    }
}

// MARK: - 视频播放器
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

// MARK: - 文件模型
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
