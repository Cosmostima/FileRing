//
//  DoubleRingItemsListView.swift
//  PopUp
//
//  Created by Cosmos on 30/10/2025.
//

import SwiftUI
import AppKit

struct DoubleRingItemListLayout {
    let columnWidth: CGFloat
    let rowHeight: CGFloat
    let rowSpacing: CGFloat
    let columnGap: CGFloat
    let verticalPadding: CGFloat
    let iconSize: CGFloat
    let hitPadding: CGFloat
}

struct DoubleRingItemsListView: View {
    let items: [DoubleRingDisplayItem]
    let layout: DoubleRingItemListLayout
    let side: PanelSection.Side
    let center: CGPoint
    let radius: CGFloat
    let tint: Color
    let hoveredPath: String?
    let onHoverChange: (DoubleRingPanelView.HoverTarget?, Bool) -> Void

    var body: some View {
        ZStack {
            if items.isEmpty {
                placeholder
                    .frame(width: layout.columnWidth)
                    .position(listPosition)
            } else {
                VStack(
                    alignment: side == .right ? .leading : .trailing,
                    spacing: 0  // No spacing - rows push apart via their own padding
                ) {
                    ForEach(items) { item in
                        DoubleRingItemRow(
                            item: item,
                            layout: layout,
                            tint: tint,
                            side: side,
                            isHovered: hoveredPath == item.path,
                            onHoverChange: onHoverChange
                        )
                    }
                }
                .frame(width: layout.columnWidth, alignment: side == .right ? .leading : .trailing)
                .position(listPosition)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: items.count)
    }

    private var listPosition: CGPoint {
        let offset = radius +  layout.columnWidth / 2 + 20
        let x = center.x + (side == .right ? offset : -offset)
        return CGPoint(x: x, y: center.y)
    }

    private var placeholder: some View {
        Text("No items")
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.gray.opacity(0.08))
            )
    }
}

private struct DoubleRingItemRow: View {
    let item: DoubleRingDisplayItem
    let layout: DoubleRingItemListLayout
    let tint: Color
    let side: PanelSection.Side
    let isHovered: Bool
    let onHoverChange: (DoubleRingPanelView.HoverTarget?, Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            if side == .left && isHovered {
                actionButtons
                    .padding(.trailing, 12)
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }

            // Main row content
            HStack(spacing: 16) {
                if side == .right {
                    icon
                    details(alignment: .leading)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    details(alignment: .trailing)
                    icon
                }
            }
            .frame(maxWidth: .infinity, minHeight: layout.rowHeight, alignment: side == .right ? .leading : .trailing)
            .padding(.horizontal, 22)
            .padding(.vertical, layout.verticalPadding)
            .background {
                if #available(macOS 26.0, *) {
                    Color.clear
                        .glassEffect(in: .rect(cornerRadius: 20))
                } else {
                    Color.clear
                        .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
                }
            }
            .overlay(selectionOverlay)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)

            if side == .right && isHovered {
                actionButtons
                    .padding(.leading, 12)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        // Add padding to create space for extended hover region
        .padding(EdgeInsets(
            top: layout.rowSpacing / 2,
            leading: 10,
            bottom: layout.rowSpacing / 2,
            trailing: 10
        ))
        // Wrap entire HStack with extended hover region that extends into the padding
        .contentShape(Rectangle())
        .onHover { hovering in
            onHoverChange(.row(path: item.path), hovering)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
    }

    private var selectionOverlay: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(isHovered ? tint.opacity(0.22) : .clear)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isHovered ? tint.opacity(0.45) : .clear, lineWidth: 1.5)
            )
    }

    private var icon: some View {
        FileIconView(path: item.path, isFolder: item.isFolder)
            .frame(width: layout.iconSize, height: layout.iconSize)
            .shadow(radius: isHovered ? 6 : 0)
            .scaleEffect(isHovered ? 1.08 : 1.0)
            .animation(.easeOut(duration: 0.2), value: isHovered)
    }

    private func details(alignment: HorizontalAlignment) -> some View {
        let timeText = relativeTimeText  // Compute once

        return VStack(alignment: alignment, spacing: 3) {
            // Relative time - shown above when hovering, always reserves space
            Text(timeText)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .opacity(isHovered && timeText != " " ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isHovered)

            // File name - always centered
            Text(item.name)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)

            // Parent path - shown below when hovering, always reserves space
            Text(item.parentPath.isEmpty ? " " : item.parentPath)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .opacity(isHovered && !item.parentPath.isEmpty ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }

    private var relativeTimeText: String {
        guard let lastModified = item.lastModified,
              let timeString = lastModified.relativeTimeString() else {
            return " "
        }
        return timeString
    }

    @ViewBuilder
    private var actionButtons: some View {
        if isHovered {
            HStack(spacing: 10) {
                // For applications, show no action buttons (only open on click)
                // For files, show copy file button
                // For folders, show copy path button only
                if !item.isApplication {
                    if !item.isFolder {
                        CircularActionButton(
                            icon: "doc.on.doc",
                            tint: tint,
                            onHover: { hovering in
                                onHoverChange(.copyFile(path: item.path), hovering)
                            }
                        )
                    }

                    CircularActionButton(
                        icon: "link",
                        tint: tint,
                        onHover: { hovering in
                            onHoverChange(.copyPath(path: item.path), hovering)
                        }
                    )
                }
            }
            .transition(.asymmetric(
                insertion: .scale.combined(with: .opacity),
                removal: .scale.combined(with: .opacity)
            ))
        }
    }
}

private struct CircularActionButton: View {
    let icon: String
    let tint: Color
    let onHover: (Bool) -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            // Button action is handled by hover state in parent
            // The actual action is triggered by keyboard shortcut
        }) {
            ZStack {
                // Background circle with subtle shadow (no glow)
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 38, height: 38)
                    .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)

                // Icon with color change on hover
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isHovered ? tint : .primary.opacity(0.8))
                    .scaleEffect(isPressed ? 0.85 : (isHovered ? 1.1 : 1.0))
            }
            .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .scaleEffect(isPressed ? 0.92 : (isHovered ? 1.05 : 1.0))
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isHovered)
        .animation(.spring(response: 0.15, dampingFraction: 0.5), value: isPressed)
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)

            // Trigger haptic feedback on hover
            if hovering {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        // Trigger haptic feedback on press
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}
