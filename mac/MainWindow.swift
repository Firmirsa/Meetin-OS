import SwiftUI

enum MainRoute: Hashable {
    case home, meetings, meetingDetail, settings, account
}

struct MainWindow: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var session: MeetingSession
    @AppStorage("detectZoomMeetings") private var detectZoomMeetings = false
    @AppStorage("webWorkspaceURL") private var webWorkspaceURL = MeetinSite.defaultAddress

    // Ouverture à environ 80 % de la zone visible de l'écran.
    static func placement(in context: WindowPlacementContext) -> WindowPlacement {
        let visible = context.defaultDisplay.visibleRect
        return WindowPlacement(.center, size: CGSize(width: visible.width * 0.8, height: visible.height * 0.8))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            Sidebar(session: session)
                .frame(minWidth: 240, idealWidth: 250, maxWidth: 290)
                .navigationSplitViewColumnWidth(min: 240, ideal: 250, max: 290)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MTMist().ignoresSafeArea())
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 940, minHeight: 620)
        .meetinNight()
        .onAppear {
            session.notebookCount += 1
            session.openWindowAction = openWindow
        }
        .onDisappear { session.notebookCount -= 1 }
        .task { session.refreshNotificationPermission() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.refreshNotificationPermission() }
        }
        .onOpenURL { url in
            guard session.integrationsRequest == nil, let request = IntegrationsRequest.fromLink(url) else { return }
            session.integrationsRequest = request
        }
        .sheet(item: $session.integrationsRequest) { request in
            IntegrationsView(session: session, workspaceURL: $webWorkspaceURL, request: request, transcribe: {})
        }
        .task(id: detectZoomMeetings) {
            session.zoomDetector = ZoomMeetingDetector()
            guard detectZoomMeetings else { return }
            while !Task.isCancelled {
                if session.zoomDetector.observe(ZoomMeetingDetector.windowTitles()) {
                    openWindow(id: "meeting")
                }
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
            }
        }
    }

    @ViewBuilder private var page: some View {
        switch session.route {
        case .home: HomeView(session: session)
        case .meetings: MeetingsView(session: session)
        case .meetingDetail: MeetingDetailView(session: session)
        case .settings: SettingsPage(session: session)
        case .account: AccountPage(session: session)
        }
    }
}
