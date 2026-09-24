import SwiftUI
import AVKit
import UniformTypeIdentifiers
import AMSMB2

@main
struct MediaVaultApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}

// MARK: - 根 Tab 切换
struct RootTabView: View {
    var body: some View {
        TabView {
            SMBLoginView()
                .tabItem { Label("SMB", systemImage: "network") }
            LocalFileBrowserView()
                .tabItem { Label("本地", systemImage: "folder") }
        }
    }
}

// MARK: - SMB 登录界面
struct SMBLoginView: View {
    @State private var host = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var connectedClient: SMB2Manager?
    @State private var showBrowser = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("服务器地址 (例如 192.168.1.100)")) {
                    TextField("IP 或主机名", text: $host)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                Section(header: Text("认证信息")) {
                    TextField("用户名", text: $username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    SecureField("密码", text: $password)
                }
                if let error = errorMessage {
                    Section { Text(error).foregroundColor(.red) }
                }
                Button(action: connect) {
                    if isLoading { ProgressView() } else { Text("连接") }
                }
                .disabled(host.isEmpty || username.isEmpty || password.isEmpty || isLoading)
            }
            .navigationTitle("连接局域网共享")
            .navigationDestination(isPresented: $showBrowser) {
                if let client = connectedClient {
                    SMBFileBrowserView(client: client, path: "/")
                }
            }
        }
    }

    private func connect() {
        isLoading = true
        errorMessage = nil

        guard let url = URL(string: "smb://\(host)") else {
            isLoading = false
            errorMessage = "服务器地址无效"
            return
        }
        let credential = URLCredential(user: username, password: password, persistence: .forSession)

        guard let client = SMB2Manager(url: url, credential: credential) else {
            isLoading = false
            errorMessage = "无法创建 SMB 客户端，请检查地址格式"
            return
        }

        connectedClient = client

        Task {
            do {
                do {
                    _ = try await client.listShares()
                } catch {
                    _ = try await client.contentsOfDirectory(atPath: "/")
                }
                await MainActor.run {
                    isLoading = false
                    showBrowser = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "连接失败: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - 媒体项包装类型
struct MediaItem: Identifiable {
    let id = UUID()
    let url: URL
    let isVideo: Bool
}

// MARK: - 媒体工具
enum MediaHelper {
    static func isVideo(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "avi", "mkv"].contains(ext)
    }
    static func isImage(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "bmp", "tiff"].contains(ext)
    }
    static func isMedia(_ name: String) -> Bool {
        return isVideo(name) || isImage(name)
    }
}

// MARK: - 本地文件浏览
struct LocalFileBrowserView: View {
    let path: URL
    @State private var entries: [URL] = []
    @State private var isLoading = true
    @State private var selectedMedia: MediaItem?

    init(path: URL? = nil) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.path = path ?? docs
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("正在读取...")
                } else if entries.isEmpty {
                    ContentUnavailableView(
                        "此文件夹为空",
                        systemImage: "folder",
                        description: Text("在「文件」App 的“我的 iPhone → MediaVault”里放入图片或视频")
                    )
                } else {
                    List(entries, id: \.self) { url in
                        row(for: url)
                    }
                }
            }
            .navigationTitle(title)
            .onAppear(perform: load)
            .fullScreenCover(item: $selectedMedia) { item in
                if item.isVideo {
                    SMBVideoPlayer(url: item.url)
                } else {
                    ImagePreview(url: item.url)
                }
            }
        }
    }

    private var title: String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return path == docs ? "我的文件" : path.lastPathComponent
    }

    @ViewBuilder
    private func row(for url: URL) -> some View {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if isDir {
            NavigationLink(destination: LocalFileBrowserView(path: url)) {
                Label(url.lastPathComponent, systemImage: "folder")
            }
        } else {
            Button {
                selectedMedia = MediaItem(url: url, isVideo: MediaHelper.isVideo(url.lastPathComponent))
            } label: {
                HStack {
                    Image(systemName: MediaHelper.isVideo(url.lastPathComponent) ? "film" : "photo")
                        .foregroundStyle(.blue)
                    Text(url.lastPathComponent)
                        .foregroundStyle(.primary)
                    Spacer()
                }
            }
        }
    }

    private func load() {
        isLoading = true
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(
            at: path,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let sorted = urls.sorted { a, b in
            let aDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let bDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if aDir != bDir { return aDir }
            return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }
        entries = sorted
        isLoading = false
    }
}

// MARK: - SMB 文件浏览界面
struct SMBFileBrowserView: View {
    let client: SMB2Manager
    let path: String
    @State private var files: [Any] = []
    @State private var isLoading = true
    @State private var selectedMedia: MediaItem?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("正在读取...")
            } else if files.isEmpty {
                VStack { Text("此文件夹为空") }
            } else {
                List(0..<files.count, id: \.self) { index in
                    let file = files[index]
                    let name = (file as AnyObject).value(forKey: "name") as? String ?? "未知文件"
                    let isDir = (file as AnyObject).value(forKey: "isDirectory") as? Bool ?? false

                    if isDir {
                        NavigationLink(destination: SMBFileBrowserView(client: client, path: "\(path)/\(name)")) {
                            Label(name, systemImage: "folder")
                        }
                    } else {
                        Button {
                            downloadAndOpen(name: name)
                        } label: {
                            Label(name, systemImage: MediaHelper.isVideo(name) ? "film" : "photo")
                        }
                    }
                }
            }
        }
        .navigationTitle(path == "/" ? "共享根目录" : (path as NSString).lastPathComponent)
        .onAppear(perform: loadFiles)
        .fullScreenCover(item: $selectedMedia) { item in
            if item.isVideo {
                SMBVideoPlayer(url: item.url)
            } else {
                ImagePreview(url: item.url)
            }
        }
    }

    private func loadFiles() {
        isLoading = true
        Task {
            do {
                let smbFiles = try await client.contentsOfDirectory(atPath: path)
                let filtered = smbFiles.filter { !(($0.name ?? "").hasPrefix(".")) }
                await MainActor.run {
                    self.files = filtered
                    self.isLoading = false
                }
            } catch {
                await MainActor.run { self.isLoading = false }
            }
        }
    }

    private func downloadAndOpen(name: String) {
        // 改成保存到 Documents（而不是 tmp），这样在「文件」App 里也能看到
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destURL = docs.appendingPathComponent(name)
        let fullPath = "\(path)/\(name)"
        isLoading = true

        Task {
            do {
                if !FileManager.default.fileExists(atPath: destURL.path) {
                    try await client.downloadItem(atPath: fullPath, to: destURL, progress: { _, _ in return true })
                }
                await MainActor.run {
                    isLoading = false
                    selectedMedia = MediaItem(url: destURL, isVideo: MediaHelper.isVideo(name))
                }
            } catch {
                await MainActor.run { isLoading = false }
            }
        }
    }
}

// MARK: - 图片查看器
struct ImagePreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                Text("无法加载图片").foregroundStyle(.white)
            }
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").foregroundStyle(.white).padding()
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - 视频播放器
struct SMBVideoPlayer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            }
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").foregroundStyle(.white).padding()
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding()
        }
        .onAppear { player = AVPlayer(url: url) }
    }
}
