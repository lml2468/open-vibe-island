import SwiftUI
@preconcurrency import MarkdownUI
import OpenIslandCore

private struct NotificationContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Row Height Estimation

extension AgentSession {
    /// Estimated row height matching `IslandSessionRow` layout for viewport sizing.
    func estimatedIslandRowHeight(at date: Date) -> CGFloat {
        let presence = islandPresence(at: date)
        // v8 list rows are full-width scan rows, not rounded cards.
        // Base: vertical padding (22) + headline (~17) + divider rounding.
        var height: CGFloat = 40
        guard presence != .inactive else { return height }
        if spotlightPromptLineText != nil { height += 17 }
        if spotlightActivityLineText != nil { height += 20 }
        if let subagents = claudeMetadata?.activeSubagents, !subagents.isEmpty {
            height += 18
            height += CGFloat(subagents.count) * 18  // each subagent row (spacing 4 + text 14)
        }
        if let tasks = claudeMetadata?.activeTasks, !tasks.isEmpty {
            height += 17
            height += CGFloat(tasks.count) * 16  // each task row (spacing 3 + text 13)
        }
        return height
    }
}

// MARK: - Animations

private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
private let closeAnimation = Animation.smooth(duration: 0.3)
private let popAnimation = Animation.spring(response: 0.3, dampingFraction: 0.5)
private let openedSurfaceUnmountDelay: TimeInterval = 0.36

// MARK: - Main island view

struct IslandPanelView: View {
    private static let headerControlButtonSize: CGFloat = 22
    private static let headerControlSpacing: CGFloat = 8
    private static let headerHorizontalPadding: CGFloat = 18
    private static let headerTopPadding: CGFloat = 2
    private static let notchHeaderHorizontalPadding: CGFloat = 46
    private static let notchLaneSafetyInset: CGFloat = 12
    private static let minimumRightUsageLaneWidth: CGFloat = 58

    var model: AppModel
    private var lang: LanguageManager { model.lang }

    @State private var isHovering = false
    @State private var showingQuitConfirmation = false
    @State private var keepsOpenedSurfaceMounted = false
    @State private var openedSurfaceMountGeneration: UInt64 = 0

    private var isOpened: Bool {
        model.notchStatus == .opened
    }

    private var usesOpenedVisualState: Bool {
        isOpened
    }

    private var shouldRenderOpenedSurface: Bool {
        usesOpenedVisualState || keepsOpenedSurfaceMounted
    }

    private var isPopping: Bool {
        model.notchStatus == .popping
    }

    /// Single animation selection based on the current notch status.
    private var notchTransitionAnimation: Animation {
        switch model.notchStatus {
        case .opened:  return openAnimation
        case .closed:  return closeAnimation
        case .popping: return popAnimation
        }
    }

    private var targetOverlayScreen: NSScreen? {
        if let targetScreenID = model.overlayPlacementDiagnostics?.targetScreenID,
           let screen = NSScreen.screens.first(where: { screenID(for: $0) == targetScreenID }) {
            return screen
        }

        return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    private var usesNotchAwareOpenedHeader: Bool {
        model.overlayPlacementDiagnostics?.mode == .notch
            || targetOverlayScreen?.safeAreaInsets.top ?? 0 > 0
    }

    /// True when the closed island sits on an external (non-notched) display.
    /// The central black rectangle is otherwise aligned with the physical
    /// notch, so center content is only useful here.
    private var isExternalDisplayPlacement: Bool {
        if let mode = model.overlayPlacementDiagnostics?.mode {
            return mode == .topBar
        }
        // Fallback when diagnostics haven't been populated yet.
        return (targetOverlayScreen?.safeAreaInsets.top ?? 0) == 0
    }

    private var openedHeaderButtonsWidth: CGFloat {
        (Self.headerControlButtonSize * 3) + (Self.headerControlSpacing * 2)
    }

    private var openedHeaderHorizontalPadding: CGFloat {
        usesNotchAwareOpenedHeader ? Self.notchHeaderHorizontalPadding : Self.headerHorizontalPadding
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.clear

                notchContent(availableSize: geometry.size)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .alert(model.lang.t("island.quit.confirmTitle"), isPresented: $showingQuitConfirmation) {
            Button(model.lang.t("island.quit.confirmAction"), role: .destructive) {
                model.quitApplication()
            }
            Button(model.lang.t("settings.general.cancel"), role: .cancel) {}
        } message: {
            Text(model.lang.t("island.quit.confirmMessage"))
        }
        .onAppear {
            syncOpenedSurfaceMount(with: model.notchStatus, immediate: true)
        }
        .onChange(of: model.notchStatus) { _, status in
            syncOpenedSurfaceMount(with: status)
        }
    }

    @ViewBuilder
    private func notchContent(availableSize: CGSize) -> some View {
        // Window is always at opened size — use opened insets unconditionally.
        let panelShadowHorizontalInset = IslandChromeMetrics.openedShadowHorizontalInset
        let panelShadowBottomInset = IslandChromeMetrics.openedShadowBottomInset
        let layoutWidth = max(0, availableSize.width - (panelShadowHorizontalInset * 2))
        let layoutHeight = max(0, availableSize.height - panelShadowBottomInset)

        let outerHorizontalPadding: CGFloat = 0
        let outerBottomPadding: CGFloat = 0
        let openedWidth = max(0, layoutWidth - outerHorizontalPadding)
        let openedHeight = max(closedNotchHeight, layoutHeight - outerBottomPadding)

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if shouldRenderOpenedSurface {
                    openedSurface(width: openedWidth, height: openedHeight)
                        .opacity(usesOpenedVisualState ? 1 : 0)
                        .allowsHitTesting(usesOpenedVisualState)
                }

                v6ClosedSurface()
                    .opacity(usesOpenedVisualState ? 0 : 1)
                    .allowsHitTesting(!usesOpenedVisualState)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scaleEffect(usesOpenedVisualState ? 1 : (isHovering ? IslandChromeMetrics.closedHoverScale : 1), anchor: .top)
        .padding(.horizontal, panelShadowHorizontalInset)
        .padding(.bottom, panelShadowBottomInset)
        .animation(notchTransitionAnimation, value: model.notchStatus)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            if model.notchStatus != .opened {
                model.notchOpen(reason: .click)
            }
        }
    }

    private func syncOpenedSurfaceMount(with status: NotchStatus, immediate: Bool = false) {
        openedSurfaceMountGeneration &+= 1
        let generation = openedSurfaceMountGeneration

        switch status {
        case .opened:
            keepsOpenedSurfaceMounted = true
        case .closed, .popping:
            guard !immediate else {
                keepsOpenedSurfaceMounted = false
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + openedSurfaceUnmountDelay) {
                guard openedSurfaceMountGeneration == generation,
                      model.notchStatus != .opened else {
                    return
                }
                keepsOpenedSurfaceMounted = false
            }
        }
    }

    // MARK: - v6 closed surface

    /// Closed island per v6 spec. Renders the flat-top pill with the
    /// UnifiedBars glyph, respecting the user's right-slot / center-label
    /// preferences. AppModel is @Observable so any change to sessions /
    /// preferences re-renders this automatically; UnifiedBars runs its own
    /// TimelineView internally for bar animation.
    @ViewBuilder
    private func v6ClosedSurface() -> some View {
        let layout: V6ClosedLayout = isExternalDisplayPlacement ? .external : .macbook
        let physicalNotchWidth: CGFloat = targetOverlayScreen?.notchSize.width ?? 180
        V6ClosedPill(
            mode: model.islandClosedMode,
            label: layout == .external ? model.islandClosedLabel() : nil,
            rightSlot: model.islandClosedRightSlotContent(),
            layout: layout,
            height: closedNotchHeight,
            physicalNotchWidth: layout == .macbook ? physicalNotchWidth : 0,
            minWidth: 70
        )
        .scaleEffect(isPopping ? 1.04 : 1, anchor: .top)
        .shadow(color: .black.opacity(isHovering ? 0.25 : 0.0), radius: 4, x: 0, y: 2)
        .animation(.easeInOut(duration: 0.18), value: isHovering)
        .animation(popAnimation, value: isPopping)
    }

    // MARK: - Opened surface

    @ViewBuilder
    private func openedSurface(width openedWidth: CGFloat, height openedHeight: CGFloat) -> some View {
        let horizontalInset = 0.0
        let bottomInset = 0.0
        let surfaceWidth = openedWidth + (horizontalInset * 2)
        let surfaceHeight = openedHeight + bottomInset
        let surfaceShape = OpenedIslandSurfaceShape(
            topProfile: usesNotchAwareOpenedHeader ? .notch : .topBar
        )

        ZStack(alignment: .top) {
            surfaceShape
                .fill(V6Palette.ink)
                .frame(width: surfaceWidth, height: surfaceHeight)

            VStack(spacing: 0) {
                openedHeaderContent
                    .frame(height: closedNotchHeight)

                openedContent
                    .frame(width: openedWidth)
                    .frame(maxHeight: max(0, openedHeight - closedNotchHeight), alignment: .top)
                    .clipped()
            }
            .frame(width: openedWidth, height: openedHeight, alignment: .top)
            .padding(.horizontal, horizontalInset)
            .padding(.bottom, bottomInset)
            .clipShape(surfaceShape)
            .overlay {
                surfaceShape
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
        }
        .frame(width: surfaceWidth, height: surfaceHeight, alignment: .top)
    }

    // MARK: - Closed state

    private var closedNotchWidth: CGFloat {
        (targetOverlayScreen ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }))?.notchSize.width ?? NSScreen.externalDisplayNotchWidth
    }

    private var closedNotchHeight: CGFloat {
        (targetOverlayScreen ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }))?.islandClosedHeight ?? 24
    }

    @ViewBuilder
    private var openedHeaderContent: some View {
        if usesNotchAwareOpenedHeader {
            GeometryReader { geometry in
                let providers = openedUsageProviders
                let providerGroups = splitUsageProviders(providers)
                let metrics = openedHeaderMetrics(for: geometry.size.width)

                HStack(spacing: 0) {
                    usageLaneView(providerGroups.left, alignment: .leading)
                        .frame(width: metrics.leftUsageWidth, alignment: .leading)

                    Color.clear
                        .frame(width: metrics.centerGapWidth)

                    HStack(spacing: Self.headerControlSpacing) {
                        if metrics.rightUsageWidth > 0, !providerGroups.right.isEmpty {
                            usageLaneView(providerGroups.right, alignment: .trailing)
                                .frame(width: metrics.rightUsageWidth, alignment: .trailing)
                        }
                        openedHeaderButtons
                    }
                    .frame(width: metrics.rightLaneWidth, alignment: .trailing)
                }
                .padding(.horizontal, openedHeaderHorizontalPadding)
                .padding(.top, Self.headerTopPadding)
            }
        } else {
            HStack(spacing: 12) {
                openedUsageSummary
                    .frame(maxWidth: .infinity, alignment: .leading)

                openedHeaderButtons
            }
            .padding(.leading, openedHeaderHorizontalPadding)
            .padding(.trailing, openedHeaderHorizontalPadding)
            .padding(.top, Self.headerTopPadding)
        }
    }

    private var openedHeaderButtons: some View {
        HStack(spacing: Self.headerControlSpacing) {
            headerIconButton(
                systemName: model.isSoundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                isMuted: model.isSoundMuted
            ) {
                model.toggleSoundMuted()
            }

            headerIconButton(systemName: "gearshape.fill") {
                model.showSettings()
            }

            headerIconButton(
                systemName: "power",
                accessibilityLabel: model.lang.t("island.quit.confirmTitle")
            ) {
                showingQuitConfirmation = true
            }
        }
    }

    private func headerIconButton(
        systemName: String,
        isMuted: Bool = false,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(IslandHeaderIconButtonStyle(isMuted: isMuted))
        .accessibilityLabel(accessibilityLabel ?? systemName)
    }

    private var openedContent: some View {
        VStack(spacing: 8) {
            if !model.hasAnyInstalledAgent {
                installHooksHint
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
            }

            if model.shouldShowSessionBootstrapPlaceholder {
                sessionBootstrapPlaceholder
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
            } else if model.islandListSessions.isEmpty {
                emptyState
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
            } else {
                sessionList
            }
        }
        .padding(.bottom, 0)
    }

    /// Persistent hint at the top of the expanded island while no agent
    /// hooks are installed. Decoupled from session presence — process
    /// discovery routinely surfaces sessions even on a freshly cleaned
    /// install, so the empty-state branch alone never reaches users who
    /// already run an agent.
    private var installHooksHint: some View {
        Button {
            model.showOnboarding()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(model.lang.t("island.hint.installHooks"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.35), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var sessionBootstrapPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white.opacity(0.7))
                .scaleEffect(0.8)
            Text(model.lang.t("island.checkingTerminals"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
            Text(model.lang.t("island.terminalOwnership"))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.28))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(model.lang.t("island.noTerminals"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Text(model.recentSessions.isEmpty
                ? model.lang.t("island.startAgent")
                : model.lang.t("island.recentSessions"))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.25))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var actionableSessionID: String? {
        model.islandSurface.sessionID
    }

    /// Whether the panel was opened by a notification (show only actionable session + footer).
    private var isNotificationMode: Bool {
        model.notchOpenReason == .notification && actionableSessionID != nil
    }

    private static let maxSessionListHeight: CGFloat = 560

    private var sessionListSideInset: CGFloat {
        usesNotchAwareOpenedHeader ? 46 : 16
    }

    private var sessionList: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let referenceDate = context.date

            if isNotificationMode {
                // Notification mode: NO ScrollView — content sizes naturally
                sessionListContent(referenceDate: referenceDate)
                    .padding(.vertical, 2)
                    .onHover { hovering in
                        if hovering {
                            model.notePointerInsideIslandSurface()
                        } else {
                            model.handlePointerExitedIslandSurface()
                        }
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: NotificationContentHeightKey.self,
                                value: geo.size.height
                            )
                        }
                    )
                    .onPreferenceChange(NotificationContentHeightKey.self) { height in
                        if height > 0 {
                            model.measuredNotificationContentHeight = height
                        }
                    }
            } else {
                VStack(spacing: 0) {
                    sessionPanelHeader(referenceDate: referenceDate)

                    ScrollView(.vertical) {
                        sessionRowsContent(referenceDate: referenceDate)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)

                    sessionPanelFooter
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func sessionListContent(referenceDate: Date) -> some View {
        VStack(spacing: 0) {
            if !isNotificationMode {
                sessionPanelHeader(referenceDate: referenceDate)
            }

            if isNotificationMode, let session = model.activeIslandCardSession {
                IslandSessionRow(
                    session: session,
                    referenceDate: referenceDate,
                    stateIndicator: model.islandSessionStateIndicator,
                    completedStaleThreshold: model.completedStaleThreshold.seconds,
                    isActionable: true,
                    useDrawingGroup: model.notchStatus == .opened,
                    isInteractive: model.notchStatus == .opened,
                    presentation: .notification,
                    sideInset: sessionListSideInset,
                    lang: model.lang,
                    onApprove: { model.approvePermission(for: session.id, action: $0) },
                    onAnswer: { model.answerQuestion(for: session.id, answer: $0) },
                    onReply: TerminalTextSender.canReply(to: session, enabled: model.completionReplyEnabled)
                        ? { model.replyToSession(session, text: $0) } : nil,
                    onJump: { model.jumpToSession(session) }
                )
                .id(notificationCardIdentity(for: session))

                if model.allSessions.count > 1 {
                    Button {
                        let isCompletion = session.phase == .completed
                        model.expandNotificationToSessionList(clearExpansion: isCompletion)
                    } label: {
                        Text(model.lang.t("island.showAll", model.allSessions.count))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.36))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, sessionListSideInset)
                            .padding(.top, 6)
                            .padding(.bottom, 2)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ForEach(model.islandSessionSections) { section in
                    VStack(alignment: .leading, spacing: 0) {
                        if model.islandSessionGroup != .none {
                            sessionSectionHeader(section)
                        }

                        ForEach(section.sessions) { session in
                            IslandSessionRow(
                                session: session,
                                referenceDate: referenceDate,
                                stateIndicator: model.islandSessionStateIndicator,
                                completedStaleThreshold: model.completedStaleThreshold.seconds,
                                isActionable: session.phase.requiresAttention || session.id == actionableSessionID,
                                useDrawingGroup: model.notchStatus == .opened,
                                isInteractive: model.notchStatus == .opened,
                                sideInset: sessionListSideInset,
                                lang: model.lang,
                                onApprove: { model.approvePermission(for: session.id, action: $0) },
                                onAnswer: { model.answerQuestion(for: session.id, answer: $0) },
                                onReply: TerminalTextSender.canReply(to: session, enabled: model.completionReplyEnabled)
                                    ? { model.replyToSession(session, text: $0) } : nil,
                                onJump: { model.jumpToSession(session) },
                                onDismiss: session.isRemote ? { model.dismissSession(session.id) } : nil
                            )
                        }
                    }
                }
            }

            if !isNotificationMode {
                sessionPanelFooter
            }
        }
    }

    private func notificationCardIdentity(for session: AgentSession) -> String {
        switch session.phase {
        case .waitingForApproval:
            return "\(session.id)|approval|\(session.permissionRequest?.id.uuidString ?? "none")"
        case .waitingForAnswer:
            return "\(session.id)|question|\(session.questionPrompt?.id.uuidString ?? "none")"
        case .completed:
            return "\(session.id)|completed|\(session.updatedAt.timeIntervalSinceReferenceDate)"
        case .running:
            return "\(session.id)|running"
        }
    }

    @ViewBuilder
    private func sessionRowsContent(referenceDate: Date) -> some View {
        ForEach(model.islandSessionSections) { section in
            VStack(alignment: .leading, spacing: 0) {
                if model.islandSessionGroup != .none {
                    sessionSectionHeader(section)
                }

                ForEach(section.sessions) { session in
                    IslandSessionRow(
                        session: session,
                        referenceDate: referenceDate,
                        stateIndicator: model.islandSessionStateIndicator,
                        completedStaleThreshold: model.completedStaleThreshold.seconds,
                        isActionable: session.phase.requiresAttention || session.id == actionableSessionID,
                        useDrawingGroup: model.notchStatus == .opened,
                        isInteractive: model.notchStatus == .opened,
                        sideInset: sessionListSideInset,
                        lang: model.lang,
                        onApprove: { model.approvePermission(for: session.id, action: $0) },
                        onAnswer: { model.answerQuestion(for: session.id, answer: $0) },
                        onReply: TerminalTextSender.canReply(to: session, enabled: model.completionReplyEnabled)
                            ? { model.replyToSession(session, text: $0) } : nil,
                        onJump: { model.jumpToSession(session) },
                        onDismiss: session.isRemote ? { model.dismissSession(session.id) } : nil
                    )
                }
            }
        }
    }

    private func sessionPanelHeader(referenceDate: Date) -> some View {
        let overview = sessionOverviewItems(referenceDate: referenceDate)

        return HStack(spacing: 8) {
            Text(lang.t("island.sessionList.title").uppercased())
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(V6Palette.paper.opacity(0.55))

            ViewThatFits(in: .horizontal) {
                sessionOverviewView(overview, compact: false)
                sessionOverviewView(overview, compact: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, sessionListSideInset)
        .padding(.trailing, sessionListSideInset)
        .frame(height: 36)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.055))
                .frame(height: 1)
        }
    }

    private var sessionPanelFooter: some View {
        Color.clear
            .frame(height: 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.055))
                .frame(height: 1)
        }
    }

    private func sessionOverviewItems(referenceDate: Date) -> [SessionOverviewItem] {
        let sessions = model.islandListSessions
        guard !sessions.isEmpty else { return [] }

        let threshold = model.completedStaleThreshold.seconds
        let waiting = sessions.filter(\.phase.requiresAttention).count
        let running = sessions.filter { $0.phase == .running }.count
        let done = sessions.filter {
            $0.phase == .completed
                && !isIdleSessionOverviewItem($0, referenceDate: referenceDate, threshold: threshold)
        }.count
        let idle = sessions.filter {
            isIdleSessionOverviewItem($0, referenceDate: referenceDate, threshold: threshold)
        }.count

        return [
            SessionOverviewItem(id: "total", title: lang.t("island.sessionOverview.total"), compactTitle: "", count: sessions.count, tint: nil),
            SessionOverviewItem(id: "waiting", title: lang.t("island.sessionOverview.waiting"), compactTitle: lang.t("island.sessionOverview.waitingCompact"), count: waiting, tint: IslandDesignPalette.Status.waitingAggregate),
            SessionOverviewItem(id: "running", title: lang.t("island.sessionOverview.running"), compactTitle: lang.t("island.sessionOverview.runningCompact"), count: running, tint: IslandDesignPalette.Status.running),
            SessionOverviewItem(id: "done", title: lang.t("island.sessionOverview.done"), compactTitle: lang.t("island.sessionOverview.done"), count: done, tint: IslandDesignPalette.Status.completed),
            SessionOverviewItem(id: "idle", title: lang.t("island.sessionOverview.idle"), compactTitle: lang.t("island.sessionOverview.idle"), count: idle, tint: IslandDesignPalette.Status.idle),
        ].filter { $0.id == "total" || $0.count > 0 }
    }

    private func isIdleSessionOverviewItem(
        _ session: AgentSession,
        referenceDate: Date,
        threshold: TimeInterval
    ) -> Bool {
        guard session.phase == .completed else { return false }
        return session.isStaleCompletedForIsland(at: referenceDate, threshold: threshold)
            || session.islandPresence(at: referenceDate) == .inactive
    }

    private func sessionOverviewView(_ items: [SessionOverviewItem], compact: Bool) -> some View {
        HStack(spacing: compact ? 7 : 9) {
            ForEach(items) { item in
                sessionOverviewMetric(item, compact: compact)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func sessionOverviewMetric(_ item: SessionOverviewItem, compact: Bool) -> some View {
        HStack(spacing: 4) {
            if let tint = item.tint {
                Circle()
                    .fill(tint)
                    .frame(width: 5.5, height: 5.5)
            }

            Text(sessionOverviewMetricTitle(item, compact: compact))
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(item.tint == nil ? V6Palette.paper.opacity(0.34) : V6Palette.paper.opacity(0.48))
        }
    }

    private func sessionOverviewMetricTitle(_ item: SessionOverviewItem, compact: Bool) -> String {
        if item.id == "total" {
            return compact ? "\(item.count)" : "\(item.count) \(item.title)"
        }

        return "\(item.count) \(compact ? item.compactTitle : item.title)"
    }

    private func sessionSectionHeader(_ section: IslandSessionSection) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(sectionTint(for: section))
                .frame(width: 7, height: 7)
            Text(sessionSectionTitle(for: section).uppercased())
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(sectionLabelColor(for: section))
            Text("\(section.sessions.count)")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(V6Palette.paper.opacity(0.4))
            Spacer(minLength: 0)
        }
        .padding(.leading, sessionListSideInset)
        .padding(.trailing, sessionListSideInset)
        .padding(.top, 10)
        .padding(.bottom, 7)
        .background(Color.white.opacity(0.008))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.055))
                .frame(height: 1)
        }
    }

    private func sectionTint(for section: IslandSessionSection) -> Color {
        guard let first = section.sessions.first else { return IslandDesignPalette.Status.idle }
        if section.id == "state-idle" { return IslandDesignPalette.Status.idle }
        return IslandDesignPalette.Status.tint(for: first.phase)
    }

    private func sessionSectionTitle(for section: IslandSessionSection) -> String {
        if section.title.hasPrefix("island.") {
            return lang.t(section.title)
        }
        return section.title
    }

    private func sectionLabelColor(for section: IslandSessionSection) -> Color {
        switch section.id {
        case "state-approval":
            return IslandDesignPalette.Status.waitingForApproval.opacity(0.86)
        case "state-answer":
            return IslandDesignPalette.Status.waitingForAnswer.opacity(0.86)
        default:
            return V6Palette.paper.opacity(0.7)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var openedUsageSummary: some View {
        let providers = openedUsageProviders

        if providers.isEmpty == false {
            ViewThatFits(in: .horizontal) {
                compactUsageSummaryView(providers, usesShortTitles: false)
                compactUsageSummaryView(providers, usesShortTitles: true)
            }
        } else {
            Color.clear
        }
    }

    private var openedUsageProviders: [UsageProviderPresentation] {
        guard model.islandUsageDisplay == .compact else {
            return []
        }

        var providers: [UsageProviderPresentation] = []

        if let snapshot = model.claudeUsageSnapshot,
           snapshot.isEmpty == false {
            var windows: [UsageWindowPresentation] = []

            if let fiveHour = snapshot.fiveHour {
                windows.append(
                    UsageWindowPresentation(
                        id: "claude-5h",
                        label: "5h",
                        usedPercentage: fiveHour.usedPercentage,
                        resetsAt: fiveHour.resetsAt
                    )
                )
            }

            if let sevenDay = snapshot.sevenDay {
                windows.append(
                    UsageWindowPresentation(
                        id: "claude-7d",
                        label: "7d",
                        usedPercentage: sevenDay.usedPercentage,
                        resetsAt: sevenDay.resetsAt
                    )
                )
            }

            if windows.isEmpty == false {
                providers.append(
                    UsageProviderPresentation(
                        id: "claude",
                        title: "Claude",
                        windows: windows
                    )
                )
            }
        }

        if model.showCodexUsage,
           let snapshot = model.codexUsageSnapshot,
           snapshot.isEmpty == false {
            let windows = snapshot.windows.map { window in
                UsageWindowPresentation(
                    id: "codex-\(window.key)",
                    label: window.label,
                    usedPercentage: window.usedPercentage,
                    resetsAt: window.resetsAt
                )
            }

            if windows.isEmpty == false {
                providers.append(
                    UsageProviderPresentation(
                        id: "codex",
                        title: "Codex",
                        windows: windows
                    )
                )
            }
        }

        return providers
    }

    private func splitUsageProviders(
        _ providers: [UsageProviderPresentation]
    ) -> (left: [UsageProviderPresentation], right: [UsageProviderPresentation]) {
        switch providers.count {
        case 0:
            return ([], [])
        case 1:
            return ([providers[0]], [])
        case 2:
            return ([providers[0]], [providers[1]])
        default:
            let splitIndex = Int(ceil(Double(providers.count) / 2.0))
            return (
                Array(providers.prefix(splitIndex)),
                Array(providers.dropFirst(splitIndex))
            )
        }
    }

    @ViewBuilder
    private func usageLaneView(
        _ providers: [UsageProviderPresentation],
        alignment: Alignment
    ) -> some View {
        if providers.isEmpty {
            Color.clear
                .frame(maxWidth: .infinity)
        } else {
            ViewThatFits(in: .horizontal) {
                compactUsageSummaryView(providers, usesShortTitles: false)
                compactUsageSummaryView(providers, usesShortTitles: true)
            }
            .frame(maxWidth: .infinity, alignment: alignment)
        }
    }

    private func openedHeaderMetrics(for totalWidth: CGFloat) -> OpenedHeaderMetrics {
        let horizontalPadding = openedHeaderHorizontalPadding
        let contentWidth = max(0, totalWidth - (horizontalPadding * 2))
        guard usesNotchAwareOpenedHeader,
              let screen = targetOverlayScreen else {
            let rightLaneWidth = min(contentWidth, openedHeaderButtonsWidth + (contentWidth / 2))
            let leftUsageWidth = max(0, contentWidth - rightLaneWidth)
            return OpenedHeaderMetrics(
                leftUsageWidth: leftUsageWidth,
                centerGapWidth: 0,
                rightUsageWidth: max(0, rightLaneWidth - openedHeaderButtonsWidth - Self.headerControlSpacing),
                rightLaneWidth: rightLaneWidth
            )
        }

        let panelMinX = screen.frame.midX - (totalWidth / 2)
        let panelMaxX = panelMinX + totalWidth
        let contentMinX = panelMinX + horizontalPadding
        let contentMaxX = panelMaxX - horizontalPadding

        let fallbackNotchHalfWidth = screen.notchSize.width / 2
        let notchLeftEdge = screen.frame.midX - fallbackNotchHalfWidth
        let notchRightEdge = screen.frame.midX + fallbackNotchHalfWidth
        let leftVisibleMaxX = screen.auxiliaryTopLeftArea?.maxX ?? notchLeftEdge
        let rightVisibleMinX = screen.auxiliaryTopRightArea?.minX ?? notchRightEdge

        let rawLeftWidth = max(0, min(contentMaxX, leftVisibleMaxX) - contentMinX)
        let rawRightWidth = max(0, contentMaxX - max(contentMinX, rightVisibleMinX))

        let leftUsageWidth = max(0, rawLeftWidth - Self.notchLaneSafetyInset)
        let rightAvailableWidth = max(0, rawRightWidth - Self.notchLaneSafetyInset)
        let proposedRightUsageWidth = max(
            0,
            rightAvailableWidth - openedHeaderButtonsWidth - Self.headerControlSpacing
        )
        let rightUsageWidth = proposedRightUsageWidth >= Self.minimumRightUsageLaneWidth
            ? proposedRightUsageWidth
            : 0
        let rightLaneWidth = min(
            contentWidth,
            openedHeaderButtonsWidth
                + (rightUsageWidth > 0 ? Self.headerControlSpacing + rightUsageWidth : 0)
        )
        let centerGapWidth = max(0, contentWidth - leftUsageWidth - rightLaneWidth)

        return OpenedHeaderMetrics(
            leftUsageWidth: leftUsageWidth,
            centerGapWidth: centerGapWidth,
            rightUsageWidth: rightUsageWidth,
            rightLaneWidth: rightLaneWidth
        )
    }

    private func compactUsageSummaryView(
        _ providers: [UsageProviderPresentation],
        usesShortTitles: Bool
    ) -> some View {
        HStack(spacing: 7) {
            ForEach(providers) { provider in
                compactUsageChip(provider, usesShortTitle: usesShortTitles)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func screenID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return "display-\(number.uint32Value)"
        }

        return screen.localizedName
    }

    private func compactUsageChip(_ provider: UsageProviderPresentation, usesShortTitle: Bool) -> some View {
        HStack(spacing: 5) {
            Text(usesShortTitle ? provider.shortTitle : provider.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.74))

            Text(provider.peakWindowLabel)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.42))

            Text("\(provider.peakUsagePercentage)%")
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(usageColor(for: provider.peakUsedPercentage))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.055), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
        .help(usageHelpText(for: provider))
    }

    private func usageHelpText(for provider: UsageProviderPresentation) -> String {
        provider.windows.map { window in
            var parts = ["\(window.label) \(window.roundedUsedPercentage)%"]
            if let resetsAt = window.resetsAt,
               let remaining = remainingDurationString(until: resetsAt) {
                parts.append(remaining)
            }
            return parts.joined(separator: " ")
        }
        .joined(separator: " · ")
    }

    private func headerPill(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.08), in: Capsule())
    }

    private func usageColor(for percentage: Double) -> Color {
        switch percentage {
        case 90...:
            .red.opacity(0.95)
        case 70..<90:
            .orange.opacity(0.95)
        default:
            .green.opacity(0.95)
        }
    }

    private func remainingDurationString(until date: Date) -> String? {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else {
            return nil
        }

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated

        if interval >= 86_400 {
            formatter.allowedUnits = [.day]
            formatter.maximumUnitCount = 1
        } else if interval >= 3_600 {
            formatter.allowedUnits = [.hour, .minute]
            formatter.maximumUnitCount = 2
        } else {
            formatter.allowedUnits = [.minute]
            formatter.maximumUnitCount = 1
        }

        return formatter.string(from: interval)
    }
}

private struct UsageProviderPresentation: Identifiable {
    let id: String
    let title: String
    let windows: [UsageWindowPresentation]

    var peakWindow: UsageWindowPresentation? {
        windows.max { lhs, rhs in
            lhs.usedPercentage < rhs.usedPercentage
        }
    }

    var peakWindowLabel: String {
        peakWindow?.label ?? ""
    }

    var peakUsedPercentage: Double {
        peakWindow?.usedPercentage ?? 0
    }

    var peakUsagePercentage: Int {
        peakWindow?.roundedUsedPercentage ?? 0
    }

    var shortTitle: String {
        switch id {
        case "claude":
            "Cl"
        case "codex":
            "Cx"
        default:
            String(title.prefix(2))
        }
    }
}

private struct UsageWindowPresentation: Identifiable {
    let id: String
    let label: String
    let usedPercentage: Double
    let resetsAt: Date?

    var roundedUsedPercentage: Int {
        Int(usedPercentage.rounded())
    }
}

private struct OpenedHeaderMetrics {
    let leftUsageWidth: CGFloat
    let centerGapWidth: CGFloat
    let rightUsageWidth: CGFloat
    let rightLaneWidth: CGFloat
}

private struct SessionOverviewItem: Identifiable {
    let id: String
    let title: String
    let compactTitle: String
    let count: Int
    let tint: Color?
}
