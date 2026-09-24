import SwiftUI
import AVKit
import UniformTypeIdentifiers
import AMSMB2

@main
struct MediaVaultApp: App {
    var body: some Scene {
        WindowGroup {
            SMBLoginView()
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
        let url = URL(string: "smb://\(host)")!
        let credential = URLCredential(user: username, password: password, persistence: .forSession)
        let client = SMB2Manager(url: url, credential: credential)
        connectedClient = client
        
        // 关键修改：用 Task 代替 DispatchQueue.global().async
        Task {
            do {
                try await client.connect()
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

// MARK: - SMB 文件浏览界面
struct SMBFileBrowserView: View {
    let client: SMB2Manager
    let path: String
    @State private var files: [Any] = []
    @State private var isLoading = true
    @State private var selectedMediaURL: URL?
    @State private var isVideo = false
    @Environment(\.dismiss) private var dismiss
    
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
                            Label(name, systemImage: isVideo(name) ? "film" : "photo")
                        }
                    }
                }
            }
        }
        .navigationTitle(path == "/" ? "共享根目录" : (path as NSString).lastPathComponent)
        .onAppear(perform: loadFiles)
        .fullScreenCover(item: $selectedMediaURL) { url in
            if isVideo {
                SMBVideoPlayer(url: url)
            } else {
                ImagePreview(url: url)
            }
        }
    }
    
    private func loadFiles() {
        isLoading = true
        Task {
            do {
                // 关键修改：用 await 调用 async 方法
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
    
    private func isVideo(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "avi", "mkv"].contains(ext)
    }
    
    private func downloadAndOpen(name: String) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let fullPath = "\(path)/\(name)"
        isLoading = true
        
        Task {
            do {
                // 关键修改：用 await 调用 async 下载方法
                try await client.downloadItem(atPath: fullPath, to: tempURL)
                await MainActor.run {
                    isLoading = false
                    isVideo = isVideo(name)
                    selectedMediaURL = tempURL
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
            }
            VStack { HStack { Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.white).padding() }; Spacer() }; Spacer() }.padding()
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
            if let player { VideoPlayer(player: player).onAppear { player.play() }.onDisappear { player.pause() } }
            VStack { HStack { Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.white).padding() }; Spacer() }; Spacer() }.padding()
        }
        .onAppear { player = AVPlayer(url: url) }
    }
}

// 让 URL 支持 Identifiable，用于全屏弹窗
// 修复警告：加 @retroactive
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
