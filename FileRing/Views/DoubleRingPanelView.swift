//
//  DoubleRingPanelView.swift
//  FileRing
//
//  Created by Cosmos on 30/10/2025.
//

import SwiftUI
import AppKit

struct DoubleRingPanelView: View {
    @StateObject private var viewModel: DoubleRingViewModel
    @State private var hoverState = HoverState()
    @State private var hoveredSection: PanelSection?
    @State private var lastHoveredPath: String?
    @State private var ringOpacity: Double = 0
    @State private var ringScale: CGFloat = 0.9
    @State private var hasTriggeredInitialRefresh = false

    private enum Layout {
        static let panelSize: CGFloat = 900
        static let deadZoneRadius: CGFloat = 20
        static let sectionHitInnerRadius: CGFloat = 20
        static let sectionHitOuterRadius: CGFloat = 60
        static let sectionVisualInnerRadius: CGFloat = 40
        static let sectionVisualOuterRadius: CGFloat = 60
        static let itemAnchorRadius: CGFloat = 105
        static let itemList = DoubleRingItemListLayout(
            columnWidth: 320,
            rowHeight: 52,
            rowSpacing: 6,
            columnGap: 12,
            verticalPadding: 10,
            iconSize: 52,
            hitPadding: 3
        )
    }

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: DoubleRingViewModel())
    }

    var body: some View {
        content
            .frame(width: Layout.panelSize, height: Layout.panelSize)
            .onAppear {
                guard !hasTriggeredInitialRefresh else { return }
                hasTriggeredInitialRefresh = true
                Task { await refreshWithEntranceAnimation() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .triggerHoveredItem)) { _ in
                performCurrentHoverAction()
            }
            .onReceive(NotificationCenter.default.publisher(for: .refreshPanel)) { _ in
                Task { await refreshWithEntranceAnimation() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .hidePanel)) { _ in
                hoverState.clear()
                hoveredSection = nil
                lastHoveredPath = nil
                viewModel.handlePanelHide()
            }
    }
}

// MARK: - Content
private extension DoubleRingPanelView {
    @ViewBuilder
    var content: some View {
        ZStack {
            ringLayout

            if viewModel.isInitialLoading {
                loadingIndicator
            }

            if let error = viewModel.error {
                errorState(message: error)
            }

            if viewModel.isLoadingSection && !viewModel.isInitialLoading {
                loadingIndicator
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    var loadingIndicator: some View {
        if #available(macOS 26.0, *) {
            ProgressView()
                .controlSize(.large)
                .padding(10)
                .glassEffect()
        } else {
            ProgressView()
                .controlSize(.large)
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Text("Error")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await viewModel.refresh() }
            }
        }
    }

    var ringLayout: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                DoubleRingSectionRingView(
                    selectedSection: viewModel.selectedSection,
                    hoveredSection: hoveredSection,
                    center: center,
                    innerRadius: Layout.sectionVisualInnerRadius,
                    outerRadius: Layout.sectionVisualOuterRadius
                )
                .opacity(ringOpacity)
                .scaleEffect(ringScale, anchor: .center)

                if !viewModel.isInitialLoading {
                    DoubleRingItemsListView(
                        items: viewModel.displayItems,
                        layout: Layout.itemList,
                        side: viewModel.selectedSection.side,
                        center: center,
                        radius: Layout.sectionVisualOuterRadius,
                        tint: viewModel.selectedSection.baseColor,
                        hoveredPath: hoverState.openFilePath ?? hoverState.copyFilePath,
                        onHoverChange: handleHoverChange
                    )
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    updateSectionHover(at: location, center: center)
                case .ended:
                    hoveredSection = nil
                    hoverState.clear()
                    lastHoveredPath = nil
                }
            }
        }
    }
}

// MARK: - Hover Target
extension DoubleRingPanelView {
    enum HoverTarget {
        case row(path: String)
        case copyFile(path: String)
        case copyPath(path: String)
    }
}

// MARK: - Hover handling
private extension DoubleRingPanelView {
    @MainActor
    func refreshWithEntranceAnimation() async {
        triggerRingEntranceAnimation()
        await viewModel.refresh()
    }

    func triggerRingEntranceAnimation() {
        ringOpacity = 0
        ringScale = 0.9
        withAnimation(.easeOut(duration: 0.05)) {
            ringOpacity = 1
            ringScale = 1
        }
    }

    func updateSectionHover(at location: CGPoint, center: CGPoint) {
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        let angle = normalizedDegrees(Double(atan2(dy, dx)) * 180 / .pi)

        guard distance >= Layout.deadZoneRadius else {
            hoverState.clear()
            hoveredSection = nil
            return
        }

        guard distance >= Layout.sectionHitInnerRadius,
              distance <= Layout.sectionHitOuterRadius else {
            hoveredSection = nil
            return
        }

        let section = PanelSection.section(for: angle) ?? viewModel.selectedSection
        if hoveredSection != section {
            hoveredSection = section
        }
        if viewModel.selectedSection != section {
            viewModel.switchToSection(section)
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        hoverState.clear()
    }

    func handleHoverChange(target: HoverTarget?, isHovering: Bool) {
        guard let target = target else {
            hoverState.clear()
            lastHoveredPath = nil
            return
        }

        if isHovering {
            switch target {
            case .row(let path):
                // Trigger haptic feedback only on first hover or when changing rows
                if lastHoveredPath != path {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    lastHoveredPath = path
                }
                hoveredSection = nil
                hoverState.setOpen(path)

            case .copyFile(let path):
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                hoveredSection = nil
                hoverState.setCopy(path, mode: .file)

            case .copyPath(let path):
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                hoveredSection = nil
                hoverState.setCopy(path, mode: .path)
            }
        } else {
            // When leaving a button but still on row, restore open state
            switch target {
            case .row(let path):
                // Leaving row entirely
                if hoverState.openFilePath == path || hoverState.copyFilePath == path {
                    hoverState.clear()
                    lastHoveredPath = nil
                }

            case .copyFile(let path), .copyPath(let path):
                // Leaving button - restore to open state if still hovering row
                if hoverState.copyFilePath == path {
                    hoverState.setOpen(path)
                }
            }
        }
    }

    func performCurrentHoverAction() {
        // Priority: copy > open
        if let copyPath = hoverState.copyFilePath, let mode = hoverState.copyMode {
            Task {
                await viewModel.copyToClipboard(path: copyPath, mode: mode)
            }
        } else if let openPath = hoverState.openFilePath {
            Task {
                await viewModel.open(path: openPath)
            }
        }
        // If neither is set, do nothing
    }
}

