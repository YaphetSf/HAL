import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Candidate-window colors and the switch-animation artwork: one colour-scheme card whose
/// dashed Custom tile opens the pickers, live previews, and the D26 artwork row.
struct AppearanceSettingsView: View {
    @Binding var scheme: CandidateColorScheme

    @State private var customSchemes = SettingsStore.load().customColorSchemes
    @State private var editingEntryID: UUID?
    @State private var choice = SettingsStore.load().switchAnimation
    @State private var artwork = SwitchAnimationArtwork.image(for: SettingsStore.load().switchAnimation)
    @State private var customNames = SwitchAnimationArtwork.installedNames
    @State private var replayID: UInt = 1
    @State private var isChoosingFile = false
    @State private var isTargeted = false
    @State private var importError: String?
    /// Draft page size; `Apply & Restart` writes it into Settings.json + the yaml patch.
    @State private var pageSize = SettingsStore.load().candidatePageSize
    /// Max window width. Unlike the page size this applies to the next candidate window
    /// without a restart, so it persists live as the slider moves.
    @State private var maxWidth = SettingsStore.load().candidateWindowMaxWidth
    @State private var applyState = ApplyState.idle
    /// Measured natural size of the preview row: what the panel would take before the cap,
    /// mirroring `CandidatePanel`'s own min(fittingSize, maxWidth).
    @State private var previewNaturalSize = CGSize.zero
    /// Width the card has to spend on the preview; a wider window is scaled down to fit.
    @State private var previewSpace: CGFloat = 0

    private enum ApplyState {
        case idle
        case applying
        case applied
        case failed
    }

    /// What rime-ice really answers "paopao" with, in its own order, so the preview is a
    /// page the user could have typed rather than a mock-up of one.
    private var previewCandidates: [Candidate] {
        let pool = ["泡泡", "🫧", "跑跑", "刨刨", "炮炮", "抛抛", "袍袍", "咆咆", "庖庖"]
        return pool.prefix(pageSize).map { Candidate(text: $0, comment: nil) }
    }

    private var previewWindowWidth: CGFloat { min(previewNaturalSize.width, maxWidth) }

    private var previewScale: CGFloat {
        guard previewSpace > 0, previewWindowWidth > previewSpace else { return 1 }
        return previewSpace / previewWindowWidth
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                colourScheme
                candidateWindow
                switchAnimation
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .scrollIndicators(.never)
    }

    // MARK: Candidate window (D21)

    private var candidateWindow: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("CANDIDATE WINDOW")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
                applyButton
            }
            Slider(value: pageSizeBinding, in: 3...9, step: 1) {
                Text("\(pageSize) candidates per page")
            } minimumValueLabel: {
                Text("3").font(.caption).foregroundStyle(.tertiary)
            } maximumValueLabel: {
                Text("9").font(.caption).foregroundStyle(.tertiary)
            }
            .disabled(applyState == .applying)
            Slider(value: $maxWidth, in: 200...900, step: 20) {
                Text("Max window width \(Int(maxWidth)) pt")
            } minimumValueLabel: {
                Text("200").font(.caption).foregroundStyle(.tertiary)
            } maximumValueLabel: {
                Text("900").font(.caption).foregroundStyle(.tertiary)
            }
            .onChange(of: maxWidth) { _, newWidth in
                SettingsStore.saveCandidateWindowMaxWidth(newWidth)
            }
            preview
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// The real window, at the width it would really take, scaled down only when that is
    /// wider than the card. Laying it out at the card's width instead would cut candidates
    /// off here that the panel shows on screen.
    private var preview: some View {
        // A GeometryReader so the row can never widen the card: it reports the room the card
        // has, and anything wider than that is scaled down instead of pushing the card out.
        GeometryReader { proxy in
            // Only cap the copy on screen when the cap really binds: at its natural width the
            // row is laid out exactly, and a fraction of a point of rounding is enough to
            // ellipsize a candidate the panel itself shows in full.
            previewWindow(maxWidth: previewNaturalSize.width > maxWidth ? maxWidth : nil)
                .frame(width: previewWindowWidth > 0 ? previewWindowWidth : nil, alignment: .leading)
                .scaleEffect(previewScale, anchor: .topLeading)
                .onChange(of: proxy.size.width, initial: true) { _, width in previewSpace = width }
        }
        .frame(height: previewNaturalSize.height * previewScale)
        // Uncapped, the same row reports the natural size the panel would fit to; it is
        // hidden but still measured, and never asked to shrink.
        .background(alignment: .topLeading) {
            previewWindow(maxWidth: nil)
                .hidden()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { previewNaturalSize = $0 }
        }
    }

    private func previewWindow(maxWidth: CGFloat?) -> some View {
        CandidateView(candidates: previewCandidates,
                      highlightedIndex: 0,
                      page: EngineState.Page(index: 0, hasPrev: false, hasNext: true),
                      justAppeared: true,
                      scheme: scheme,
                      maxWidth: maxWidth)
    }

    private var pageSizeBinding: Binding<Double> {
        Binding(get: { Double(pageSize) },
                set: { pageSize = Int($0.rounded()) })
    }

    private var applyButton: some View {
        Button {
            applyPageSize()
        } label: {
            HStack(spacing: 8) {
                switch applyState {
                case .idle, .failed:
                    Image(systemName: applyState == .failed ? "exclamationmark.triangle" : "arrow.clockwise")
                case .applying:
                    ProgressView()
                        .controlSize(.small)
                case .applied:
                    Image(systemName: "checkmark.circle.fill")
                }
                Text(applyState == .failed ? "Failed" : applyState == .applied ? "Applied" : "Apply & Restart")
            }
        }
        .buttonStyle(GlassButtonStyle())
        .disabled(applyState == .applying)
        .opacity(applyState == .applying ? 0.45 : 1)
    }

    private func applyPageSize() {
        applyState = .applying
        RimeApplyRestart.apply {
            let settings = SettingsStore.load()
            SettingsStore.saveCandidatePageSize(pageSize)
            RimeSpellerPatch.write(rules: settings.spellerRules,
                                   asciiPhrases: settings.asciiPhrases,
                                   pageSize: pageSize,
                                   in: RimeSpellerPatch.userDirectory)
        } completion: { success in
            applyState = success ? .applied : .failed
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                if applyState != .applying { applyState = .idle }
            }
        }
    }


    // MARK: Switch Animation (D26)

    private var switchAnimation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Switch Animation")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            stage
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                      spacing: 12) {
                tile(.miku, title: "Miku")
                tile(.serve, title: "Tennis", symbol: "tennisball.fill")
                ForEach(customNames, id: \.self) { name in
                    customTile(name)
                }
                addTile
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                importArtwork(from: url)
                return true
            } isTargeted: { targeted in
                withAnimation(.easeOut(duration: 0.15)) { isTargeted = targeted }
            }
            if let importError {
                Text(importError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .fileImporter(isPresented: $isChoosingFile,
                      allowedContentTypes: [.image, .pdf, .svg]) { result in
            if case .success(let url) = result { importArtwork(from: url) }
        }
    }

    /// The real skin, not a mock of it. It replays on its own, cycling 中 / EN / EN+ so the
    /// badge variants show themselves; tapping replays it now.
    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.42))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
            SwitchAnimationScene(
                presentation: SwitchAnimationPresentation(id: replayID, mode: previewMode,
                                                       scheme: scheme),
                artwork: artwork,
                placement: SwitchAnimationPlacement(origin: .zero,
                                                 horizontalDirection: .right,
                                                 verticalDirection: .below),
                style: SwitchAnimationStyle(choice)
            )
            .id(replayID)
        }
        .frame(height: 150)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { replay() }
        // The animation is a one-shot: without a loop the stage sits empty between taps.
        .onReceive(Timer.publish(every: 2.4, on: .main, in: .common).autoconnect()) { _ in
            replay()
        }
    }

    private var previewMode: SwitchAnimationMode {
        switch replayID % 3 {
        case 1: return .english
        case 2: return .englishAssist
        default: return .chinese
        }
    }

    private func tile(_ tileChoice: SwitchAnimationChoice, title: String,
                      symbol: String = "photo") -> some View {
        ArtworkTile(title: title,
                    image: SwitchAnimationArtwork.image(for: tileChoice),
                    symbol: symbol,
                    isSelected: choice == tileChoice,
                    isHighlighted: false,
                    scheme: scheme) {
            select(tileChoice)
        }
    }

    private func customTile(_ name: String) -> some View {
        ArtworkTile(title: SwitchAnimationArtwork.index(of: name).map { "Custom \($0)" } ?? "Custom",
                    image: SwitchAnimationArtwork.image(for: .custom(name)),
                    symbol: "photo",
                    isSelected: choice == .custom(name),
                    isHighlighted: false,
                    scheme: scheme) {
            select(.custom(name))
        }
        .contextMenu {
            Button("Remove", role: .destructive) { remove(name) }
        }
    }

    private var addTile: some View {
        Button {
            isChoosingFile = true
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(isTargeted ? 0.1 : 0.03))
                    Image(systemName: "plus")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(scheme.accentEnd.color)
                }
                .frame(height: 64)
                Text("Add")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(isTargeted
                                     ? AnyShapeStyle(scheme.accentEnd.color)
                                     : AnyShapeStyle(Color.white.opacity(0.18)))
            )
        }
        .buttonStyle(.plain)
        .hoverLift(glow: scheme.glow.color)
    }

    private func replay() {
        replayID &+= 1
    }

    private func select(_ newChoice: SwitchAnimationChoice) {
        choice = newChoice
        artwork = SwitchAnimationArtwork.image(for: newChoice)
        SettingsStore.saveSwitchAnimation(newChoice)
        importError = nil
        replay()
    }

    private func remove(_ name: String) {
        SwitchAnimationArtwork.remove(named: name)
        customNames = SwitchAnimationArtwork.installedNames
        if choice == .custom(name) { select(.miku) }
    }

    private func importArtwork(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let name = try SwitchAnimationArtwork.install(from: url)
            customNames = SwitchAnimationArtwork.installedNames
            select(.custom(name))
        } catch SwitchAnimationArtwork.ImportError.tooLarge {
            importError = "That file is over 4 MB."
        } catch {
            importError = "macOS cannot read that file as an image."
        }
    }

    // MARK: Colour scheme

    /// Presets and the user's own schemes live in one grid; the dashed Add tile is the
    /// entry into a new scheme, the same way the artwork row's Add tile is. A custom tile
    /// previews itself live; picking one again — or its sliders button — opens the editor.
    private var colourScheme: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("COLOUR SCHEME")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            schemeCells
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// One row of cells per pair, built eagerly: this many cards cost nothing to build and
    /// the editor needs to know which row its card sits in.
    private var schemeCells: some View {
        let cells = cellModels
        return VStack(spacing: 12) {
            ForEach(Array(stride(from: 0, to: cells.count, by: 2)), id: \.self) { start in
                let pair = Array(cells[start..<min(start + 2, cells.count)])
                HStack(alignment: .top, spacing: 12) {
                    ForEach(pair) { cell in
                        cell.view
                    }
                    if pair.count == 1 {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                // The editor opens in the flow, directly under the card it belongs to. It
                // used to float over the grid, which put it behind the card below it and
                // let the scroll view crop it — a panel this tall has nowhere to float to.
                if let editingEntryID, pair.contains(where: { $0.id == editingEntryID.uuidString }) {
                    colorEditor
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: editingEntryID)
    }

    private struct SchemeCell: Identifiable {
        let id: String
        let view: AnyView
    }

    private var cellModels: [SchemeCell] {
        var cells = CandidateColorPreset.allCases.map { preset in
            SchemeCell(id: "preset-\(preset.rawValue)",
                       view: AnyView(PresetCard(preset: preset,
                                                isSelected: scheme.preset == preset) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    scheme = .preset(preset)
                    editingEntryID = nil
                }
                SettingsStore.saveCandidateColorScheme(scheme)
            }))
        }
        cells.append(contentsOf: customSchemes.enumerated().map { index, entry in
            SchemeCell(id: entry.id.uuidString,
                       view: AnyView(CustomCard(name: "Custom \(index + 1)",
                                                colors: entry.colors,
                                                isSelected: isActive(entry),
                                                isEditing: editingEntryID == entry.id,
                                                showsEditButton: isActive(entry)) {
                if isActive(entry) {
                    toggleEditor(for: entry)
                } else {
                    select(entry)
                }
            } onEdit: {
                toggleEditor(for: entry)
            } onRemove: {
                remove(entry)
            }))
        })
        cells.append(SchemeCell(id: "add", view: AnyView(addCard)))
        return cells
    }

    private func toggleEditor(for entry: CustomColorScheme) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            editingEntryID = editingEntryID == entry.id ? nil : entry.id
        }
    }

    /// HAL's own palette, in the page rather than in a window of its own: pick Start / End
    /// / Glow, then drag the square and the spectrum. The card right above it is the live
    /// preview, so the editor does not repeat one.
    private var colorEditor: some View {
        PaletteEditor(colors: editedColors, onCommit: persist)
            // The palette carries HSB state of its own; re-key it so moving to another
            // entry never inherits the last one's hue.
            .id(editingEntryID)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.28)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1))
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
    }

    private func isActive(_ entry: CustomColorScheme) -> Bool {
        scheme.preset == nil && scheme.customID == entry.id
    }

    private func select(_ entry: CustomColorScheme) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            scheme = .custom(entry)
            editingEntryID = nil
        }
        SettingsStore.saveCandidateColorScheme(scheme)
    }

    /// A new scheme starts as a copy of whatever is on screen, and the editor opens right
    /// away — Add is "start drifting from here", not "here is a new tile to find".
    private func add() {
        let entry = CustomColorScheme(colors: .init(accentStart: scheme.accentStart,
                                                    accentEnd: scheme.accentEnd,
                                                    glow: scheme.glow))
        customSchemes.append(entry)
        SettingsStore.saveCustomColorSchemes(customSchemes)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            scheme = .custom(entry)
            editingEntryID = entry.id
        }
        SettingsStore.saveCandidateColorScheme(scheme)
    }

    private func remove(_ entry: CustomColorScheme) {
        customSchemes.removeAll { $0.id == entry.id }
        SettingsStore.saveCustomColorSchemes(customSchemes)
        if editingEntryID == entry.id { editingEntryID = nil }
        if isActive(entry) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                scheme = .mono
            }
            SettingsStore.saveCandidateColorScheme(scheme)
        }
    }

    private var addCard: some View {
        Button {
            add()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(gradient)
                Text("Add")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
            .glassCard(corner: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(Color.white.opacity(0.18))
            )
        }
        .buttonStyle(.plain)
        .hoverLift(glow: scheme.glow.color)
    }

    private var gradient: LinearGradient {
        LinearGradient(colors: [scheme.accentStart.color, scheme.accentEnd.color],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Editing the live scheme also writes the entry it came from, so the card preview and
    /// a later re-selection show the drifted colors, not the seeding ones. Both writes stay
    /// in memory; `persist` puts them on disk once the drag ends.
    private var editedColors: Binding<CandidateColorScheme.CustomColors> {
        Binding(get: { scheme.custom },
                set: { newColors in
                    scheme.custom = newColors
                    scheme.preset = nil
                    if let id = scheme.customID,
                       let index = customSchemes.firstIndex(where: { $0.id == id }) {
                        customSchemes[index].colors = newColors
                    }
                })
    }

    private func persist() {
        SettingsStore.saveCandidateColorScheme(scheme)
        SettingsStore.saveCustomColorSchemes(customSchemes)
    }
}

private struct PresetCard: View {
    let preset: CandidateColorPreset
    let isSelected: Bool
    let action: () -> Void

    private var gradient: LinearGradient {
        LinearGradient(colors: [preset.accentStart.color, preset.accentEnd.color],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                MiniCandidateBar(start: preset.accentStart, end: preset.accentEnd)
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected
                                     ? AnyShapeStyle(gradient)
                                     : AnyShapeStyle(Color.white.opacity(0.16)))
                    .scaleEffect(isSelected ? 1.1 : 1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .glassCard(corner: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(gradient, lineWidth: 1.5)
                    .opacity(isSelected ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .hoverLift(glow: preset.glow.color)
        .accessibilityLabel("(preset.displayName) color scheme")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct CustomCard: View {
    let name: String
    let colors: CandidateColorScheme.CustomColors
    let isSelected: Bool
    let isEditing: Bool
    let showsEditButton: Bool
    let action: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    private var gradient: LinearGradient {
        LinearGradient(colors: [colors.accentStart.color, colors.accentEnd.color],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                MiniCandidateBar(start: colors.accentStart, end: colors.accentEnd)
                Spacer(minLength: 0)
                if showsEditButton {
                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: isEditing ? "xmark" : "slider.horizontal.3")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(5)
                            .background(Circle().fill(.white.opacity(isEditing ? 0.16 : 0.09)))
                    }
                    .buttonStyle(.plain)
                    .help(isEditing ? "Close" : "Edit colors")
                }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected
                                     ? AnyShapeStyle(gradient)
                                     : AnyShapeStyle(Color.white.opacity(0.16)))
                    .scaleEffect(isSelected ? 1.1 : 1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .glassCard(corner: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(gradient, lineWidth: 1.5)
                    .opacity(isSelected ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .hoverLift(glow: colors.glow.color)
        .accessibilityLabel("(name) color scheme")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .contextMenu {
            Button("Remove", role: .destructive) { onRemove() }
        }
    }
}

private struct MiniCandidateBar: View {
    let start: RGB
    let end: RGB

    private var gradient: LinearGradient {
        LinearGradient(colors: [start.color, end.color],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        HStack(spacing: 5) {
            item("泡泡", highlighted: true)
            item("🫧", highlighted: false)
            item("跑跑", highlighted: false)
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 9).fill(.black.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.07), lineWidth: 1))
    }

    private func item(_ text: String, highlighted: Bool) -> some View {
        Text(text)
            .font(.system(size: 12, weight: highlighted ? .semibold : .regular))
            .foregroundStyle(highlighted ? .white : Color.white.opacity(0.55))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(highlighted ? AnyShapeStyle(gradient) : AnyShapeStyle(Color.white.opacity(0.06)))
            }
    }
}

private struct ArtworkTile: View {
    let title: String
    let image: NSImage?
    let symbol: String
    let isSelected: Bool
    let isHighlighted: Bool
    let scheme: CandidateColorScheme
    let action: () -> Void

    private var gradient: LinearGradient {
        LinearGradient(colors: [scheme.accentStart.color, scheme.accentEnd.color],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.black.opacity(0.34))
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .padding(11)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(gradient)
                    }
                }
                .frame(height: 64)
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected
                                         ? AnyShapeStyle(gradient)
                                         : AnyShapeStyle(Color.white.opacity(0.16)))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .glassCard(corner: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(gradient, lineWidth: 1.5)
                    .opacity(isSelected || isHighlighted ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .hoverLift(glow: scheme.glow.color)
    }
}
