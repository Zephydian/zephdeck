//
//  NotchShape.swift
//  boringNotch
//
// Created by Kai Azim on 2023-08-24.
// Original source: https://github.com/MrKai77/DynamicNotchKit
// Modified by Alexander on 2025-05-18.
//
// Copied into Zephydian from boring.notch (github.com/TheBoredTeam/boring.notch, GPL-3.0,
// commit e2654ee). Zephydian changes: renamed to IslandShape, made insettable so it can carry
// glass, removed the preview; IslandSilhouetteShape adds Vorssaint's capsule.

import SwiftUI

/// The island's outline: square top corners curving out into the menu bar, rounded bottom corners.
nonisolated struct IslandShape: InsettableShape {
    private var topCornerRadius: CGFloat
    private var bottomCornerRadius: CGFloat
    private var insetAmount: CGFloat = 0

    init(
        topCornerRadius: CGFloat? = nil,
        bottomCornerRadius: CGFloat? = nil
    ) {
        self.topCornerRadius = topCornerRadius ?? 6
        self.bottomCornerRadius = bottomCornerRadius ?? 14
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get {
            .init(
                topCornerRadius,
                bottomCornerRadius
            )
        }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func inset(by amount: CGFloat) -> IslandShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: 0)
        var path = Path()

        path.move(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.minY + topCornerRadius
            ),
            control: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.minY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.maxY - bottomCornerRadius
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + topCornerRadius + bottomCornerRadius,
                y: rect.maxY
            ),
            control: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.maxY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.maxX - topCornerRadius - bottomCornerRadius,
                y: rect.maxY
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.maxY - bottomCornerRadius
            ),
            control: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.maxY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.minY + topCornerRadius
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX,
                y: rect.minY
            ),
            control: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.minY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY
            )
        )

        return path
    }
}

/// The island's shape: boring.notch's notch, or Vorssaint's capsule while the closed island floats
/// on a display without a notch.
nonisolated struct IslandSilhouetteShape: InsettableShape {
    var capsule: Bool
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    private var insetAmount: CGFloat = 0

    init(capsule: Bool, topCornerRadius: CGFloat, bottomCornerRadius: CGFloat) {
        self.capsule = capsule
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        if capsule {
            let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
            return RoundedRectangle(cornerRadius: min(r.width, r.height) / 2, style: .continuous).path(in: r)
        }
        return IslandShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius)
            .inset(by: insetAmount).path(in: rect)
    }

    func inset(by amount: CGFloat) -> IslandSilhouetteShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}
