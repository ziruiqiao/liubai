import AppKit
import CoreImage.CIFilterBuiltins
import LiuBaiCore
import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var favorites: FavoritesController
    @State private var selectedFolder: FavoriteFolder?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                SectionTitle(title: "B 站收藏夹")
                Spacer()
                if favorites.isConnected {
                    QuietButton(title: "刷新", icon: "arrow.clockwise") { favorites.refresh() }.disabled(favorites.isLoading)
                    Button("退出登录") { favorites.disconnect() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
            }
            if let error = favorites.error {
                Label(error, systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(Palette.warm).fixedSize(horizontal: false, vertical: true)
            }
            if let notice = favorites.storageNotice {
                Label(notice, systemImage: "key").font(.system(size: 10)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !favorites.isConnected {
                Spacer()
                EmptyNote(icon: "folder.badge.person.crop", title: "尚未连接", detail: "用哔哩哔哩 App 扫码登录。")
                PrimaryButton(title: "扫码连接收藏夹", icon: "qrcode") { favorites.showLogin = true }.frame(maxWidth: .infinity).padding(.top, 5)
                Spacer()
            } else if favorites.isLoading {
                Spacer(); ProgressView("正在读取收藏夹…").font(.system(size: 12)).frame(maxWidth: .infinity); Spacer()
            } else if favorites.folders.isEmpty {
                Spacer(); EmptyNote(icon: "folder", title: "还没有创建收藏夹", detail: "在 B 站收藏音乐后，回来刷新这里。") ; Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(favorites.folders) { folder in
                            Button { selectedFolder = folder } label: {
                                HStack(spacing: 15) {
                                    Image(systemName: "folder").font(.system(size: 23, weight: .light)).foregroundStyle(Palette.accent)
                                        .frame(width: 53, height: 53).background(Palette.softAccent, in: RoundedRectangle(cornerRadius: 13))
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(folder.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text).lineLimit(1)
                                        Text("\(folder.count) 个条目\(folder.isPrivate ? " · 私密收藏夹" : "")").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                                    }
                                    Spacer()
                                    Text("浏览收藏夹").font(.system(size: 11)).foregroundStyle(Palette.accent)
                                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                                }.padding(15).background(Palette.surface, in: RoundedRectangle(cornerRadius: 15)).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }.scrollIndicators(.hidden)
            }
        }.onAppear { favorites.restoreAndLoad() }
            .sheet(isPresented: $favorites.showLogin) { FavoritesLoginView() }
            .sheet(item: $selectedFolder) { folder in FavoriteFolderImportView(folder: folder) }
    }
}

struct FavoritesLoginView: View {
    @EnvironmentObject private var favorites: FavoritesController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 21) {
            HStack { Spacer(); IconButton(icon: "xmark", title: "取消连接收藏夹") { dismiss() } }
            SectionTitle(title: "扫码连接收藏夹")
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(.white).frame(width: 218, height: 218)
                if let challenge = favorites.challenge, let image = qrImage(challenge.url), !favorites.loginExpired {
                    Image(nsImage: image).interpolation(.none).resizable().scaledToFit().frame(width: 186, height: 186).accessibilityLabel("B 站登录二维码")
                } else if favorites.loginWorking { ProgressView().controlSize(.regular) }
                else { Image(systemName: "qrcode").font(.system(size: 65, weight: .ultraLight)).foregroundStyle(Palette.secondary.opacity(0.5)) }
            }.overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line)).frame(width: 218, height: 218)
            Text(favorites.loginStatus).font(.system(size: 12)).foregroundStyle(favorites.loginExpired ? Palette.warm : Palette.secondary).multilineTextAlignment(.center).lineLimit(3)
            if favorites.loginExpired { QuietButton(title: "刷新二维码", icon: "arrow.clockwise") { favorites.beginLogin() } }
            Toggle("记住登录，保存在 macOS 钥匙串", isOn: $favorites.rememberLogin).toggleStyle(.checkbox).font(.system(size: 11))
            Text("登录建立普通网页会话；留白仅用它读取收藏夹，凭据不随备份导出。")
                .font(.system(size: 10)).foregroundStyle(Palette.secondary).lineSpacing(5).multilineTextAlignment(.center)
        }.padding(28).frame(width: 410).background(Palette.background).foregroundStyle(Palette.text).tint(Palette.accent).preferredColorScheme(.light)
            .onAppear { favorites.beginLogin() }.onDisappear { favorites.cancelLogin() }
    }
    private func qrImage(_ value: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let image = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = CIContext().createCGImage(image, from: image.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: image.extent.width, height: image.extent.height))
    }
}

private struct FavoriteFolderImportView: View {
    @EnvironmentObject private var favorites: FavoritesController
    @Environment(\.dismiss) private var dismiss
    let folder: FavoriteFolder
    @State private var preview: LibraryPreview?
    @State private var error: String?
    @State private var progress = "正在读取收藏夹…"
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("收藏夹").font(.system(size: 22, weight: .medium))
                Spacer()
                IconButton(icon: "xmark", title: "关闭收藏夹") { dismiss() }
            }
            if let preview { LibraryPreviewView(preview: preview) { dismiss() }.frame(height: 435) }
            else if let error {
                Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(Palette.warm).fixedSize(horizontal: false, vertical: true)
                Button("关闭") { dismiss() }.buttonStyle(.plain).foregroundStyle(Palette.accent)
            } else { ProgressView(progress).frame(maxWidth: .infinity).padding(.vertical, 55).font(.system(size: 12)) }
        }.padding(30).frame(width: 650).background(Palette.background).foregroundStyle(Palette.text).tint(Palette.accent).preferredColorScheme(.light)
            .task {
                do {
                    let result = try await favorites.client.contents(of: folder) { count, total in
                        await MainActor.run { progress = "已读取 \(count) / \(total) 段声音" }
                    }
                    guard !Task.isCancelled else { return }
                    preview = result
                } catch {
                    guard !Task.isCancelled else { return }
                    self.error = error.localizedDescription; favorites.handle(error)
                }
            }
    }
}
