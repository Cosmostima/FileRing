//
//  DoubleRingSectionRingView.swift
//  FileRing
//
//  Created by Cosmos on 30/10/2025.
//

import SwiftUI

struct DoubleRingSectionRingView: View {
    let selectedSection: PanelSection
    let hoveredSection: PanelSection?
    let center: CGPoint
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    var body: some View {
        let size = CGSize(width: outerRadius * 2, height: outerRadius * 2)

        ZStack {
            // Base ultraThinMaterial ring at the bottom
            backgroundRing(size: size)

            // Color segments on top
            ForEach(PanelSection.allCases) { section in
                segment(for: section, size: size)
            }

            // Icons at the top
            ForEach(PanelSection.allCases) { section in
                sectionIcon(for: section)
            }
        }
        .allowsHitTesting(false)
    }

    private func backgroundRing(size: CGSize) -> some View {
        // Create a full ring shape (360 degrees)
        let fullRing = DoubleRingSegment(
            startAngle: 0,
            angleSpan: 360,
            innerRadius: innerRadius,
            outerRadius: outerRadius
        )

        return fullRing
            .fill(.ultraThinMaterial)
            .frame(width: size.width, height: size.height)
            .position(center)
    }

    private func segment(for section: PanelSection, size: CGSize) -> some View {
        let isSelected = section == selectedSection
        let isHovered = section == hoveredSection
        let baseColor = section.baseColor

        let fillOpacity: Double = isSelected ? 0.55 : (isHovered ? 0.32 : 0.2)

        let segment = DoubleRingSegment(
            startAngle: section.startAngle,
            angleSpan: PanelSection.angleSpan,
            innerRadius: innerRadius,
            outerRadius: outerRadius
        )

        return segment
            .fill(baseColor.opacity(fillOpacity))
            .frame(width: size.width, height: size.height)
            .position(center)
    }

    private func sectionIcon(for section: PanelSection) -> some View {
        let isSelected = section == selectedSection
        let isHovered = section == hoveredSection
        let midRadius = (innerRadius + outerRadius) / 2
        let angleRadians = section.midAngle * .pi / 180.0
        let iconX = center.x + CGFloat(cos(angleRadians)) * midRadius
        let iconY = center.y + CGFloat(sin(angleRadians)) * midRadius

        let iconSize: CGFloat = isSelected ? 14 : 11
        let opacity: Double = isSelected ? 1.0 : (isHovered ? 0.8 : 0.6)

        return Image(systemName: section.symbolName)
            .font(.system(size: iconSize, weight: .medium))
            .foregroundStyle(.white)
            .opacity(opacity)
            .position(x: iconX, y: iconY)
            .animation(.easeOut(duration: 0.2), value: isSelected)
    }
}

struct DoubleRingSegment: Shape {
    let startAngle: Double
    let angleSpan: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)

        let start = Angle(degrees: startAngle)
        let end = Angle(degrees: startAngle + angleSpan)

        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: start,
            endAngle: end,
            clockwise: false
        )

        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: end,
            endAngle: start,
            clockwise: true
        )

        path.closeSubpath()
        return path
    }
}
