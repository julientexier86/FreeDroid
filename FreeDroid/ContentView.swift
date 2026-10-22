import SwiftUI
import FreeDroidUI
import FreeDroidDomain
import DeviceManagement
import FileBrowser
import Gallery
import Transfer
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.openSettings) private var openSettings
    @State private var tab: DetailTab = .files
    @State private var showingWifiPair = false
    @State private var wifiPairVM = WifiPairSheetViewModel()
    @State private var isImportingAPK = false
    @State private var actionError: String?
    @State private var diagnosticChecks: [DiagnosticCheck] = []
    @State private var showingDiagnostics = false
    @State private var isImportingMultiDevice = false

    enum DetailTab: Hashable { case files, gallery }

    private var theme: Theme {
        container.preferences.theme(for: systemColorScheme)
    }

    var body: some View {
        ZStack(alignment: .top) {
            AmbientGradientBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                appHeader
                Divider().overlay(theme.colors.line)
                HStack(spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        DeviceListView(
                            viewModel: container.deviceListViewModel,
                            deviceFractions: container.transfersViewModel.deviceFractions,
                            onRevealInFinder: { device in
                                FinderRevealer.revealTransferDestination(for: device.displayName)
                            },
                            onShowInFinder: { device in
                                Task { await ProviderRevealer.revealInFinder(deviceID: device.id) }
                            },
                            onAddWifi: {
                                wifiPairVM = WifiPairSheetViewModel()
                                showingWifiPair = true
                            }
                        )
                        appearanceMenu
                            .padding(Spacing.md)
                    }
                    .sheet(isPresented: $showingWifiPair) {
                        WifiPairSheet(
                            viewModel: wifiPairVM,
                            coordinator: container.wifiCoordinator,
                            onDismiss: { showingWifiPair = false }
                        )
                        .padding(Spacing.xl)
                    }
                    Divider().overlay(theme.colors.line)
                    detail
                }
            }
        }
        .frame(minWidth: 920, minHeight: 600)
        .freeDroidTheme(theme)
        .task { await container.start() }
        .overlay(alignment: .bottomTrailing) {
            if !container.transfersViewModel.states.isEmpty {
                TransfersPanel(
                    viewModel: container.transfersViewModel,
                    deviceNameByID: { deviceID in
                        container.deviceListViewModel.devices.first { $0.id == deviceID }?.displayName
                    }
                )
                .frame(width: 360)
                .padding(Spacing.lg)
            }
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: Spacing.sm) {
                ForEach(container.transferToastPresenter.toasts) { toast in
                    toast
                }
            }
            .padding(Spacing.lg)
        }
        .task {
            for await states in container.transferRepository.observe() {
                await MainActor.run {
                    container.transferToastPresenter.consume(states)
                }
            }
        }
        .fileImporter(
            isPresented: $isImportingAPK,
            allowedContentTypes: [UTType(filenameExtension: "apk") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first,
                  let selectedID = container.deviceListViewModel.selectedID else { return }
            Task {
                do {
                    try await container.installAPK(from: url, on: selectedID)
                } catch {
                    actionError = String(describing: error)
                }
            }
        }
        .alert("FreeDroid", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .fileImporter(
            isPresented: $isImportingMultiDevice,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task {
                do {
                    try await container.uploadFiles(urls, to: container.deviceListViewModel.selectedIDs)
                } catch {
                    actionError = String(describing: error)
                }
            }
        }
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticSheet(checks: diagnosticChecks)
                .padding(Spacing.xl)
                .frame(width: 520, height: 420)
        }
    }

    private var appHeader: some View {
        HStack(spacing: Spacing.sm) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
            }
            Text("FreeDroid")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.colors.text0)
            Spacer()
            if container.deviceListViewModel.selectedIDs.count > 1 {
                Button {
                    isImportingMultiDevice = true
                } label: {
                    Label("Send to \(container.deviceListViewModel.selectedIDs.count) Quests", systemImage: "square.and.arrow.down.on.square")
                }
                .buttonStyle(.bordered)
            }
            Text("v\(container.bundleVersion)")
                .font(Typography.caption)
                .foregroundStyle(theme.colors.text2)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
    }

    private var appearanceMenu: some View {
        @Bindable var preferences = container.preferences
        return Menu {
            Picker("Appearance", selection: $preferences.appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            Divider()
            Button("Settings\u{2026}") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14))
                .foregroundStyle(theme.colors.text2)
                .padding(8)
                .background(Circle().fill(.ultraThinMaterial))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var detail: some View {
        ZStack {
            if let selectedID = container.deviceListViewModel.selectedID {
                deviceDetail(for: selectedID)
                    .id(selectedID)
            } else {
                placeholderDetail
            }
        }
        .animation(.easeInOut(duration: 0.12), value: container.deviceListViewModel.selectedID)
    }

    private func deviceDetail(for selectedID: DeviceID) -> some View {
        VStack(spacing: 0) {
            HStack {
                PillTabs(
                    selection: $tab,
                    tabs: [("Files", DetailTab.files), ("Gallery", DetailTab.gallery)]
                )
                Spacer()
                Button {
                    isImportingAPK = true
                } label: {
                    Label("Install APK", systemImage: "shippingbox")
                }
                .buttonStyle(.bordered)
                Button {
                    Task {
                        diagnosticChecks = await container.diagnose(selectedID)
                        showingDiagnostics = true
                    }
                } label: {
                    Label("Diagnose", systemImage: "stethoscope")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            Divider().overlay(theme.colors.line)
            SidebarFlow(selection: tab) { selectedTab in
                switch selectedTab {
                case .files:
                    FileBrowserView(viewModel: container.fileBrowserViewModel(for: selectedID))
                case .gallery:
                    GalleryView(
                        viewModel: container.galleryViewModel(for: selectedID),
                        onCopySelectionToMac: { items in
                            Task {
                                guard let device = await container.registry.device(selectedID) else { return }
                                let stream = container.startTransferUseCase()(
                                    deviceID: selectedID,
                                    deviceName: device.displayName,
                                    items: items.map { $0.path }
                                )
                                do {
                                    for try await progress in stream {
                                        await MainActor.run {
                                            container.transfersViewModel.register(jobID: progress.jobID, on: selectedID)
                                        }
                                    }
                                } catch {}
                            }
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var placeholderDetail: some View {
        ZStack {
            Color.clear
            VStack(spacing: Spacing.md) {
                Text("Select a device").font(Typography.title)
                Text("Plug in a phone or pick one from the sidebar to start browsing.")
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DiagnosticSheet: View {
    @Environment(\.dismiss) private var dismiss
    let checks: [DiagnosticCheck]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Quest diagnostic")
                .font(.title2.weight(.semibold))
            List(checks) { check in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: icon(for: check.status))
                        .foregroundStyle(color(for: check.status))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.title).font(.headline)
                        Text(check.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 3)
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func icon(for status: DiagnosticCheck.Status) -> String {
        switch status {
        case .passed: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private func color(for status: DiagnosticCheck.Status) -> Color {
        switch status {
        case .passed: .green
        case .warning: .orange
        case .failed: .red
        }
    }
}
