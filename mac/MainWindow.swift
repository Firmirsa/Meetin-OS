import SwiftUI

enum MainRoute: Hashable {
    case home, meetings, meetingDetail, settings, account
}

struct MainWindow: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var session: MeetingSession
    @AppStorage("detectZoomMeetings") private var detectZoomMeetings = false
    @AppStorage("webWorkspaceURL") private var webWorkspaceURL = "http://localhost:3000"

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
            session.notebookIsOpen = true
            session.openWindowAction = openWindow
        }
        .onDisappear { session.notebookIsOpen = false }
        .onOpenURL { url in
            guard session.integrationsRequest == nil, let request = IntegrationsRequest.fromLink(url) else { return }
            session.integrationsRequest = request
        }
        .sheet(item: $session.integrationsRequest) { request in
            IntegrationsView(session: session, workspaceURL: $webWorkspaceURL, request: request, transcribe: {})
        }
        .onChange(of: detectZoomMeetings, initial: true) {
            session.setZoomDetection(detectZoomMeetings, openWindow: openWindow)
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
