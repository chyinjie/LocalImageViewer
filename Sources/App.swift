import SwiftUI
import AVKit
import UniformTypeIdentifiers
import AMSMB2

@main
struct MediaVaultApp: App {
    var body: some Scene {
        WindowGroup { SMBLoginView() }
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
        let client = SMB2Manager(url: url, user: username, password: password)
        connectedClient = client
        
        DispatchQueue.global(qos: .userInitiated).async {
            client.connect { error in
                DispatchQueue.main.async {
                    isLoading = false
                    if let error = error {
                        errorMessage = "连接失败: \(error.localizedDescription)"
                    } else {
                        showBrowser = true
                    }
                }
            }
        }
    }
}

// MARK: - SMB 文件浏览界面
struct SMBFileBrowserView: View {
    let client: SMB2Manager
    let path: String
    @State private var files: [SMB2File] = []
    @State private var isLoading = true
    @State private var selectedImageURL: URL?
    @State private var selectedVideoURL: URL?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("正在读取...")
            } else if files.isEmpty {
                VStack { Text("此文件夹为空") }
            } else {
                List(files) { file in
                    if file.isDirectory {
                        NavigationLink(destination: SMBFileBrowserView(client: client, path: "\(path)/\(file.name)")) {
                            Label(file.name, systemImage: "folder")
                        }
                    } else {
                        Button {
                            downloadAndOpen(file: file)
                        } label: {
                            Label(file.name, systemImage: isVideo(file.name) ? "film" : "photo")
                        }
                    }
                }
            }
        }
        .navigationTitle(path == "/" ? "共享根目录" : (path as NSString).lastPathComponent)
        .onAppear(perform: loadFiles)
        .fullScreenCover(item: $selectedImageURL) { url in
            ImagePreview(url: url)
        }
        .fullScreenCover(item: $selectedVideoURL) { url in
            SMBVideoPlayer(url: url)
        }
    }
    
    private func loadFiles() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let smbFiles = (try? client.contentsOfDirectory(atPath: path)) ?? []
            DispatchQueue.main.async {
                self.files = smbFiles.filter { !$0.name.hasPrefix(".") }
                self.isLoading = false
            }
        }
    }
    
    private func isVideo(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "avi", "mkv"].contains(ext)
    }
    
    private func downloadAndOpen(file: SMB2File) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
        let fullPath = "\(path)/\(file.name)"
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try client.downloadItem(atPath: fullPath, to: tempURL) { _, _ in }
                DispatchQueue.main.async {
                    isLoading = false
                    if isVideo(file.name) {
                        selectedVideoURL = tempURL
                    } else {
                        selectedImageURL = tempURL
                    }
                }
            } catch {
                DispatchQueue.main.async { isLoading = false }
            }
        }
    }
}

// MARK: - 辅助视图 (图片和视频播放)
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

// 让 URL 支持 Identifiable 用于 fullScreenCover
extension URL: Identifiable {
    public var id: String { absoluteString }
}
