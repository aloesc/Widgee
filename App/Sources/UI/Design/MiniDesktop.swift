import AppKit
import ImageIO
import SwiftUI

/// Обои главного экрана (уменьшенная копия); при ошибке остаётся nil и рисуется градиент.
@MainActor
final class WallpaperProvider: ObservableObject {
    static let shared = WallpaperProvider()
    @Published private(set) var image: NSImage?
    private var started = false

    func loadIfNeeded() {
        guard !started else { return }
        started = true
        guard let screen = NSScreen.main ?? NSScreen.screens.first,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return }
        Task.detached(priority: .utility) {
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                         kCGImageSourceCreateThumbnailWithTransform: true,
                                         kCGImageSourceThumbnailMaxPixelSize: 1400]
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return }
            let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            await MainActor.run { WallpaperProvider.shared.image = img }
        }
    }
}

/// Мини-рабочий стол 16:10: обои, строка меню сверху, намёк на Dock снизу.
/// `content` получает масштаб (ширина мини-стола / `virtualWidth`) для размещения виджета в масштабе.
struct MiniDesktop<Content: View>: View {
    var virtualWidth: CGFloat = 1000
    @ViewBuilder var content: (CGFloat) -> Content
    @ObservedObject private var wallpaper = WallpaperProvider.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let scale = w / virtualWidth
            ZStack {
                backdrop
                VStack(spacing: 0) {
                    menuBar(width: w).frame(height: max(10, h * 0.055))
                    ZStack { content(scale) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    dock(width: w).frame(height: max(14, h * 0.1)).padding(.bottom, h * 0.02)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous).strokeBorder(.primary.opacity(0.15), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        }
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
        .onAppear { wallpaper.loadIfNeeded() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Desktop preview")
    }

    @ViewBuilder private var backdrop: some View {
        if let img = wallpaper.image {
            Color.clear.overlay { Image(nsImage: img).resizable().scaledToFill() }.clipped()
        } else {
            LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.95), Color(red: 0.62, green: 0.38, blue: 0.9),
                                    Color(red: 0.95, green: 0.55, blue: 0.62)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func menuBar(width: CGFloat) -> some View {
        HStack(spacing: width * 0.012) {
            Image(systemName: "apple.logo").font(.system(size: max(6, width * 0.017))).foregroundStyle(.white.opacity(0.95))
            ForEach(0..<4, id: \.self) { i in
                Capsule().fill(.white.opacity(0.7)).frame(width: width * (i == 0 ? 0.05 : 0.035), height: max(2, width * 0.006))
            }
            Spacer()
            ForEach(0..<3, id: \.self) { _ in Circle().fill(.white.opacity(0.7)).frame(width: max(3, width * 0.01)) }
        }
        .padding(.horizontal, width * 0.025)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(reduceTransparency ? AnyShapeStyle(Color.black.opacity(0.75)) : AnyShapeStyle(.black.opacity(0.28)))
        .accessibilityHidden(true)
    }

    private func dock(width: CGFloat) -> some View {
        let icon = max(8, width * 0.04)
        return HStack(spacing: icon * 0.35) {
            ForEach(0..<7, id: \.self) { i in
                RoundedRectangle(cornerRadius: icon * 0.26, style: .continuous)
                    .fill(Color(hue: Double(i) / 7, saturation: 0.45, brightness: 0.95).opacity(0.9))
                    .frame(width: icon, height: icon)
            }
        }
        .padding(.horizontal, icon * 0.4).padding(.vertical, icon * 0.28)
        .background(Capsule().fill(reduceTransparency ? AnyShapeStyle(Color.black.opacity(0.7)) : AnyShapeStyle(.ultraThinMaterial)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}
