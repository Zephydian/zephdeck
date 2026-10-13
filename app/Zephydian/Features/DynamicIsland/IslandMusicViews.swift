// Copied into Zephydian from boring.notch (github.com/TheBoredTeam/boring.notch, GPL-3.0, commit e2654ee):
// - AudioSpectrum (components/Music/MusicVisualizer.swift, created by Harsh Vardhan Goswami)
// - MarqueeText (components/Live activities/MarqueeTextView.swift, created by Richard Kunkli)
// - HoverButton (components/HoverButton.swift, created by Kraigo)
// - MusicLiveActivity (ContentView.swift), MusicPlayerView, AlbumArtView, MusicControlsView,
//   MusicSliderView and CustomSlider (components/Notch/NotchHomeView.swift, created by Hugo Persson,
//   modified by Harsh Vardhan Goswami, Richard Kunkli and Mustafa Ramadan)
// Zephydian changes: renamed with an Island prefix; read IslandMusic instead of MusicManager and
// Defaults (tinting, glow and the colored bars always on, boring.notch's defaults); the control slots
// are fixed to previous / play-pause / next and follow what the player supports; no lyrics, volume,
// shuffle, repeat or favorite; a placeholder instead of boring.notch's default artwork; the bars
// timer runs only while playing and on screen, never in Settings' preview; Reduce Motion stops the
// marquee and the bars.

import AppKit
import SwiftUI

// MARK: - Bars

final class IslandAudioSpectrum: NSView {
    private var barLayers: [CAShapeLayer] = []
    private var barScales: [CGFloat] = []
    private var isPlaying: Bool = true
    private var animationTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupBars()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupBars()
    }

    private func setupBars() {
        let barWidth: CGFloat = 2
        let barCount = 4
        let spacing: CGFloat = barWidth
        let totalWidth = CGFloat(barCount) * (barWidth + spacing)
        let totalHeight: CGFloat = 14
        frame.size = CGSize(width: totalWidth, height: totalHeight)

        for i in 0 ..< barCount {
            let xPosition = CGFloat(i) * (barWidth + spacing)
            let barLayer = CAShapeLayer()
            barLayer.frame = CGRect(x: xPosition, y: 0, width: barWidth, height: totalHeight)
            barLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            barLayer.position = CGPoint(x: xPosition + barWidth / 2, y: totalHeight / 2)
            barLayer.fillColor = NSColor.white.cgColor
            barLayer.backgroundColor = NSColor.white.cgColor
            barLayer.allowsGroupOpacity = false
            barLayer.masksToBounds = true
            let path = NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: barWidth, height: totalHeight),
                                    xRadius: barWidth / 2,
                                    yRadius: barWidth / 2)
            barLayer.path = path.cgPath
            barLayers.append(barLayer)
            barScales.append(0.35)
            layer?.addSublayer(barLayer)
        }
    }

    private func startAnimating() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateBars() }
        }
    }

    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        resetBars()
    }

    private func updateBars() {
        for (i, barLayer) in barLayers.enumerated() {
            let currentScale = barScales[i]
            let targetScale = CGFloat.random(in: 0.35 ... 1.0)
            barScales[i] = targetScale
            let animation = CABasicAnimation(keyPath: "transform.scale.y")
            animation.fromValue = currentScale
            animation.toValue = targetScale
            animation.duration = 0.3
            animation.autoreverses = true
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 24, preferred: 24)
            barLayer.add(animation, forKey: "scaleY")
        }
    }

    private func resetBars() {
        for (i, barLayer) in barLayers.enumerated() {
            barLayer.removeAllAnimations()
            barLayer.transform = CATransform3DMakeScale(1, 0.35, 1)
            barScales[i] = 0.35
        }
    }

    func setPlaying(_ playing: Bool) {
        isPlaying = playing
        if isPlaying && window != nil {
            startAnimating()
        } else {
            stopAnimating()
        }
    }

    // No timer while the view is off screen.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setPlaying(isPlaying)
    }
}

struct IslandAudioSpectrumView: NSViewRepresentable {
    let isPlaying: Bool

    func makeNSView(context: Context) -> IslandAudioSpectrum {
        let spectrum = IslandAudioSpectrum()
        spectrum.setPlaying(isPlaying)
        return spectrum
    }

    func updateNSView(_ nsView: IslandAudioSpectrum, context: Context) {
        nsView.setPlaying(isPlaying)
    }

    static func dismantleNSView(_ nsView: IslandAudioSpectrum, coordinator: ()) {
        nsView.setPlaying(false)
    }
}

/// The four bars in the art's color, still when paused, in Reduce Motion and in Settings' preview.
struct IslandBars: View {
    let isPlaying: Bool
    let color: NSColor
    @Environment(\.islandPreview) private var preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: color).gradient)
            .mask {
                IslandAudioSpectrumView(isPlaying: isPlaying && !preview && !reduceMotion)
                    .frame(width: 16, height: 12)
            }
    }
}

// MARK: - Scrolling text

private struct IslandSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct IslandMeasureSizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(GeometryReader { geometry in
            Color.clear.preference(key: IslandSizePreferenceKey.self, value: geometry.size)
        })
    }
}

struct IslandMarqueeText: View {
    let text: String
    let font: Font
    let nsFont: NSFont.TextStyle
    let textColor: Color
    let minDuration: Double
    let frameWidth: CGFloat

    @State private var animate = false
    @State private var textSize: CGSize = .zero
    @State private var offset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandPreview) private var preview

    init(_ text: String, font: Font = .body, nsFont: NSFont.TextStyle = .body, textColor: Color = .primary,
         minDuration: Double = 3.0, frameWidth: CGFloat = 200) {
        self.text = text
        self.font = font
        self.nsFont = nsFont
        self.textColor = textColor
        self.minDuration = minDuration
        self.frameWidth = frameWidth
    }

    private var needsScrolling: Bool {
        textSize.width > frameWidth && !reduceMotion && !preview
    }

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .leading) {
                HStack(spacing: 20) {
                    Text(text)
                    Text(text)
                        .opacity(needsScrolling ? 1 : 0)
                }
                .id(text)
                .font(font)
                .foregroundColor(textColor)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: self.animate ? offset : 0)
                .animation(
                    self.animate ?
                        .linear(duration: Double(textSize.width / 30))
                        .delay(minDuration)
                        .repeatForever(autoreverses: false) : .none,
                    value: self.animate
                )
                .modifier(IslandMeasureSizeModifier())
                .onPreferenceChange(IslandSizePreferenceKey.self) { size in
                    self.textSize = CGSize(width: size.width / 2, height: NSFont.preferredFont(forTextStyle: nsFont).pointSize)
                    self.animate = false
                    self.offset = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                        if needsScrolling {
                            self.animate = true
                            self.offset = -(textSize.width + 10)
                        }
                    }
                }
            }
            .frame(width: frameWidth, alignment: .leading)
            .clipped()
        }
        .frame(height: textSize.height * 1.3)
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

// MARK: - Buttons

struct IslandHoverButton: View {
    var icon: String
    var label: String
    var iconColor: Color = .primary
    var scale: Image.Scale = .medium
    var action: () -> Void
    var contentTransition: ContentTransition = .symbolEffect

    @State private var isHovering = false

    var body: some View {
        let size = CGFloat(scale == .large ? 40 : 30)

        Button(action: action) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .frame(width: size, height: size)
                .overlay {
                    Capsule()
                        .fill(isHovering ? Color.gray.opacity(0.2) : .clear)
                        .frame(width: size, height: size)
                        .overlay {
                            Image(systemName: icon)
                                .foregroundColor(iconColor)
                                .contentTransition(contentTransition)
                                .font(scale == .large ? .largeTitle : .body)
                        }
                }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(label)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.3)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Closed island

/// While music plays: the artwork on the left of the notch, the bars on the right.
struct IslandMusicLiveActivity: View {
    let model: IslandModel
    let namespace: Namespace.ID
    private var music: IslandMusic { IslandMusic.shared }

    static func extraWidth(height: CGFloat) -> CGFloat {
        2 * max(0, height - 12) + 20
    }

    var body: some View {
        let height = model.effectiveClosedHeight
        let side = max(0, height - 12)
        HStack {
            IslandArtwork(image: music.artwork, cornerRadius: 4)
                .matchedGeometryEffect(id: "albumArt", in: namespace)
                .frame(width: side, height: side)

            Rectangle()
                .fill(.black)
                .frame(width: model.closedSize.width - IslandSizing.cornerRadiusInsets.closed.top)

            IslandBars(isPlaying: music.isPlaying, color: music.color)
                .frame(width: side, height: side, alignment: .center)
        }
        .frame(height: height, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(music.isPlaying ? "Playing \(music.title), \(music.artist)" : "Paused: \(music.title)")
    }
}

/// The artwork, or a note on grey while the player gives none.
struct IslandArtwork: View {
    let image: NSImage?
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
            } else {
                ZStack {
                    Color(white: 0.18)
                    Image(systemName: "music.note")
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                        .frame(maxWidth: 40, maxHeight: 40)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
    }
}

// MARK: - Open island

/// The player: artwork, title and artist, scrubber, controls.
struct IslandMusicPlayer: View {
    var namespace: Namespace.ID?

    var body: some View {
        HStack {
            IslandAlbumArt(namespace: namespace).padding(.all, 5)
            IslandMusicControls().drawingGroup().compositingGroup()
        }
    }
}

private struct IslandAlbumArt: View {
    var namespace: Namespace.ID?
    private var music: IslandMusic { IslandMusic.shared }
    private static let cornerRadius: CGFloat = 13

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            albumArtBackground
            albumArtButton
        }
    }

    private var albumArtBackground: some View {
        IslandArtwork(image: music.artwork, cornerRadius: Self.cornerRadius)
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(x: 1.3, y: 1.4)
            .rotationEffect(.degrees(92))
            .blur(radius: 40)
            .opacity(music.isPlaying ? 0.5 : 0)
    }

    private var albumArtButton: some View {
        ZStack {
            Button {
                music.openPlayer()
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    albumArtImage
                    appIconOverlay
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(music.isPlaying ? 1 : 0.85)
            .accessibilityLabel("Open the player")

            albumArtDarkOverlay
        }
    }

    private var albumArtDarkOverlay: some View {
        Rectangle()
            .aspectRatio(1, contentMode: .fit)
            .foregroundColor(Color.black)
            .opacity(music.isPlaying ? 0 : 0.8)
            .blur(radius: 50)
            .allowsHitTesting(false)
    }

    @ViewBuilder private var albumArtImage: some View {
        let art = IslandArtwork(image: music.artwork, cornerRadius: Self.cornerRadius)
            .aspectRatio(1, contentMode: .fit)
        if let namespace {
            art.matchedGeometryEffect(id: "albumArt", in: namespace)
        } else {
            art
        }
    }

    @ViewBuilder
    private var appIconOverlay: some View {
        if music.artwork != nil, let bundleID = music.bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 30, height: 30)
                .offset(x: 10, y: 10)
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
                .accessibilityHidden(true)
        }
    }
}

private struct IslandMusicControls: View {
    private var music: IslandMusic { IslandMusic.shared }
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast

    var body: some View {
        VStack(alignment: .leading) {
            songInfoAndSlider
            slotToolbar
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var songInfoAndSlider: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 4) {
                songInfo(width: geo.size.width)
                musicSlider
            }
        }
        .padding(.top, 10)
        .padding(.leading, 5)
    }

    private func songInfo(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            IslandMarqueeText(
                music.hasTrack ? music.title : "Nothing playing", font: .headline, nsFont: .headline,
                textColor: music.hasTrack ? .white : .gray, frameWidth: width)
            IslandMarqueeText(
                music.artist,
                font: .headline,
                nsFont: .headline,
                textColor: Color(nsColor: music.color).ensureMinimumBrightness(factor: 0.6),
                frameWidth: width
            )
            .fontWeight(.medium)
        }
    }

    private var musicSlider: some View {
        TimelineView(.animation(minimumInterval: music.rate > 0 && music.isPlaying ? 0.1 : nil, paused: !music.isPlaying)) { timeline in
            IslandMusicSlider(
                sliderValue: $sliderValue,
                duration: music.duration,
                lastDragged: $lastDragged,
                color: music.color,
                dragging: $dragging,
                enabled: music.canSeek,
                currentDate: timeline.date,
                timestampDate: music.timestamp
            ) { newValue in
                music.seek(to: newValue)
            }
            .padding(.top, 5)
            .frame(height: 36)
        }
        .onAppear { sliderValue = music.position() }
        .onChange(of: music.timestamp) { if !dragging { sliderValue = music.position() } }
    }

    private var slotToolbar: some View {
        HStack(spacing: 6) {
            IslandHoverButton(icon: "backward.fill", label: "Previous", scale: .medium) {
                music.previous()
            }
            .disabled(!music.hasTrack || !music.canSkipPrevious)
            .opacity(music.hasTrack && music.canSkipPrevious ? 1 : 0.35)
            IslandHoverButton(icon: music.isPlaying ? "pause.fill" : "play.fill", label: music.isPlaying ? "Pause" : "Play",
                              scale: .large) {
                music.togglePlay()
            }
            .disabled(!music.hasTrack)
            .opacity(music.hasTrack ? 1 : 0.35)
            IslandHoverButton(icon: "forward.fill", label: "Next", scale: .medium) {
                music.next()
            }
            .disabled(!music.hasTrack || !music.canSkipNext)
            .opacity(music.hasTrack && music.canSkipNext ? 1 : 0.35)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct IslandMusicSlider: View {
    @Binding var sliderValue: Double
    let duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    let enabled: Bool
    let currentDate: Date
    let timestampDate: Date
    var onValueChange: (Double) -> Void

    var body: some View {
        VStack {
            IslandSlider(
                value: $sliderValue,
                range: 0...max(duration, 0.001),
                color: Color(nsColor: color).ensureMinimumBrightness(factor: 0.8),
                dragging: $dragging,
                lastDragged: $lastDragged,
                onValueChange: onValueChange
            )
            .frame(height: 10, alignment: .center)
            .allowsHitTesting(enabled)
            .accessibilityLabel("Position")
            .accessibilityValue("\(timeString(from: sliderValue)) of \(timeString(from: duration))")

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(timeString(from: duration))
            }
            .fontWeight(.medium)
            .foregroundColor(Color(nsColor: color).ensureMinimumBrightness(factor: 0.6))
            .font(.caption)
            .monospacedDigit()
        }
        .onChange(of: currentDate) {
            guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            sliderValue = IslandMusic.shared.position(at: currentDate)
        }
    }

    func timeString(from seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
}

struct IslandSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var onDragChange: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(dragging ? 9 : 5)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: height)

                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)
            }
            .cornerRadius(height / 2)
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                        onDragChange?(value)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: dragging)
        }
    }
}

/// The player in a third of the island (Home with three items): smaller artwork beside the title,
/// then the scrubber and the controls. Zephydian's own, built from the pieces above.
struct IslandCompactPlayer: View {
    private var music: IslandMusic { IslandMusic.shared }
    @State private var sliderValue: Double = 0
    @State private var dragging = false
    @State private var lastDragged: Date = .distantPast

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { music.openPlayer() } label: {
                    IslandArtwork(image: music.artwork, cornerRadius: 8)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open the player")
                GeometryReader { geo in
                    VStack(alignment: .leading, spacing: 0) {
                        IslandMarqueeText(music.hasTrack ? music.title : "Nothing playing", font: .subheadline.weight(.semibold),
                                          nsFont: .subheadline, textColor: music.hasTrack ? .white : .gray, frameWidth: geo.size.width)
                        IslandMarqueeText(music.artist, font: .subheadline, nsFont: .subheadline,
                                          textColor: Color(nsColor: music.color).ensureMinimumBrightness(factor: 0.6),
                                          frameWidth: geo.size.width)
                    }
                }
                .frame(height: 44)
            }
            TimelineView(.animation(minimumInterval: music.isPlaying ? 0.25 : nil, paused: !music.isPlaying)) { timeline in
                IslandSlider(value: $sliderValue, range: 0...max(music.duration, 0.001),
                             color: Color(nsColor: music.color).ensureMinimumBrightness(factor: 0.8),
                             dragging: $dragging, lastDragged: $lastDragged) { music.seek(to: $0) }
                    .frame(height: 10)
                    .allowsHitTesting(music.canSeek)
                    .onChange(of: timeline.date) {
                        guard !dragging, Date().timeIntervalSince(lastDragged) > 1 else { return }
                        sliderValue = music.position(at: timeline.date)
                    }
            }
            .onAppear { sliderValue = music.position() }
            .accessibilityLabel("Position")
            HStack(spacing: 2) {
                IslandHoverButton(icon: "backward.fill", label: "Previous") { music.previous() }
                    .disabled(!music.hasTrack || !music.canSkipPrevious)
                    .opacity(music.hasTrack && music.canSkipPrevious ? 1 : 0.35)
                IslandHoverButton(icon: music.isPlaying ? "pause.fill" : "play.fill", label: music.isPlaying ? "Pause" : "Play") {
                    music.togglePlay()
                }
                .disabled(!music.hasTrack)
                .opacity(music.hasTrack ? 1 : 0.35)
                IslandHoverButton(icon: "forward.fill", label: "Next") { music.next() }
                    .disabled(!music.hasTrack || !music.canSkipNext)
                    .opacity(music.hasTrack && music.canSkipNext ? 1 : 0.35)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}
