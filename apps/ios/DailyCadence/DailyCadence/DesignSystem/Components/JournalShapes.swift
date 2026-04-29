import SwiftUI

// MARK: - Journal-pen illustration primitives
//
// Hand-drawn-feeling motifs used by onboarding, sign-in, and future
// empty/marketing surfaces. See `feedback_journal_illustration_style.md`
// in memory for the full vocabulary + when to use each.
//
// All shapes are stroke-only (no fills) and drawn with quadratic
// Bézier curves where possible so they read as organic rather than
// geometric. Compose them in per-surface illustration files
// (`WelcomeIllustration`, `RemindersIllustration`, etc.) at low
// opacity in the user's current theme color.

/// Simple sun: a small circle with rays radiating outward at fixed
/// angles. Rays are short line segments rather than triangles so the
/// whole mark reads as a single pen drawing.
struct SunMark: Shape {
    var rayCount: Int = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let coreRadius = min(rect.width, rect.height) * 0.24
        let rayInner = coreRadius * 1.45
        let rayOuter = coreRadius * 2.05

        path.addEllipse(in: CGRect(
            x: center.x - coreRadius,
            y: center.y - coreRadius,
            width: coreRadius * 2,
            height: coreRadius * 2
        ))

        for i in 0..<rayCount {
            let angle = Double(i) * (2 * .pi / Double(rayCount)) - .pi / 2
            let from = CGPoint(
                x: center.x + CGFloat(cos(angle)) * rayInner,
                y: center.y + CGFloat(sin(angle)) * rayInner
            )
            let to = CGPoint(
                x: center.x + CGFloat(cos(angle)) * rayOuter,
                y: center.y + CGFloat(sin(angle)) * rayOuter
            )
            path.move(to: from)
            path.addLine(to: to)
        }
        return path
    }
}

/// Stem-with-two-leaves growing from the bottom. Slightly asymmetric
/// curve so it doesn't read as geometric. Both leaves are closed
/// quad-curve teardrops. Optional bloom at the tip for the "Done"
/// state.
struct PlantSprout: Shape {
    var bloom: Bool = false

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let stemBottom = CGPoint(x: rect.midX, y: rect.maxY)
        let stemTop = CGPoint(x: rect.midX + rect.width * 0.06, y: rect.minY + rect.height * 0.12)
        let stemCtrl = CGPoint(x: rect.midX + rect.width * 0.20, y: rect.midY)
        path.move(to: stemBottom)
        path.addQuadCurve(to: stemTop, control: stemCtrl)

        addLeaf(
            to: &path,
            base: CGPoint(x: rect.midX, y: rect.maxY * 0.62),
            tip: CGPoint(x: rect.midX - rect.width * 0.34, y: rect.maxY * 0.48),
            outerCtrl: CGPoint(x: rect.midX - rect.width * 0.20, y: rect.maxY * 0.42),
            innerCtrl: CGPoint(x: rect.midX - rect.width * 0.10, y: rect.maxY * 0.62)
        )

        addLeaf(
            to: &path,
            base: CGPoint(x: rect.midX + rect.width * 0.05, y: rect.maxY * 0.36),
            tip: CGPoint(x: rect.midX + rect.width * 0.32, y: rect.maxY * 0.22),
            outerCtrl: CGPoint(x: rect.midX + rect.width * 0.24, y: rect.maxY * 0.18),
            innerCtrl: CGPoint(x: rect.midX + rect.width * 0.16, y: rect.maxY * 0.36)
        )

        if bloom {
            // Four-petal flower at the stem tip. Each petal is a
            // closed teardrop, rotated 90 degrees from the next.
            let bloomCenter = stemTop
            let petalReach = rect.width * 0.10
            let petalWidth = rect.width * 0.05
            for i in 0..<4 {
                let angle = Double(i) * (.pi / 2) - .pi / 2
                let dirX = CGFloat(cos(angle))
                let dirY = CGFloat(sin(angle))
                let perpX = -dirY
                let perpY = dirX
                let tip = CGPoint(
                    x: bloomCenter.x + dirX * petalReach,
                    y: bloomCenter.y + dirY * petalReach
                )
                let leftCtrl = CGPoint(
                    x: bloomCenter.x + dirX * (petalReach * 0.5) + perpX * petalWidth,
                    y: bloomCenter.y + dirY * (petalReach * 0.5) + perpY * petalWidth
                )
                let rightCtrl = CGPoint(
                    x: bloomCenter.x + dirX * (petalReach * 0.5) - perpX * petalWidth,
                    y: bloomCenter.y + dirY * (petalReach * 0.5) - perpY * petalWidth
                )
                path.move(to: bloomCenter)
                path.addQuadCurve(to: tip, control: leftCtrl)
                path.addQuadCurve(to: bloomCenter, control: rightCtrl)
            }
        }

        return path
    }

    private func addLeaf(
        to path: inout Path,
        base: CGPoint,
        tip: CGPoint,
        outerCtrl: CGPoint,
        innerCtrl: CGPoint
    ) {
        path.move(to: base)
        path.addQuadCurve(to: tip, control: outerCtrl)
        path.addQuadCurve(to: base, control: innerCtrl)
    }
}

/// A loose horizontal squiggle: smooth waves. Used as negative-space
/// ornament; helps a composition feel like a margin doodle rather than
/// a logo.
struct LooseSquiggle: Shape {
    var waveCount: Int = 3

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        let waveWidth = rect.width / CGFloat(waveCount)
        for i in 0..<waveCount {
            let x = rect.minX + CGFloat(i) * waveWidth
            let nextX = x + waveWidth
            let amplitude = rect.height * 0.45
            let dir: CGFloat = i.isMultiple(of: 2) ? -1 : 1
            path.addQuadCurve(
                to: CGPoint(x: nextX, y: rect.midY),
                control: CGPoint(x: x + waveWidth / 2, y: rect.midY + amplitude * dir)
            )
        }
        return path
    }
}

/// Four-pointed sparkle / star outline. Two crossing curves that taper
/// at the tips. Used for completion / delight states (the Done page).
struct SparkleMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        let armLong = min(rect.width, rect.height) * 0.5
        let armShort = armLong * 0.16

        // Vertical arm — ends taper toward center via control points.
        path.move(to: CGPoint(x: cx, y: cy - armLong))
        path.addQuadCurve(
            to: CGPoint(x: cx, y: cy + armLong),
            control: CGPoint(x: cx + armShort, y: cy)
        )
        path.addQuadCurve(
            to: CGPoint(x: cx, y: cy - armLong),
            control: CGPoint(x: cx - armShort, y: cy)
        )

        // Horizontal arm — same shape, rotated.
        path.move(to: CGPoint(x: cx - armLong, y: cy))
        path.addQuadCurve(
            to: CGPoint(x: cx + armLong, y: cy),
            control: CGPoint(x: cx, y: cy + armShort)
        )
        path.addQuadCurve(
            to: CGPoint(x: cx - armLong, y: cy),
            control: CGPoint(x: cx, y: cy - armShort)
        )
        return path
    }
}

/// Continuous inward-curling spiral. Single unbroken line, drawn as
/// many short segments along an Archimedean curve (radius shrinks
/// linearly with angle). Used for the "Spiral" app-icon family.
struct SpiralMark: Shape {
    var turns: CGFloat = 2.6
    var steps: Int = 220

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxR = min(rect.width, rect.height) / 2
        let totalAngle = turns * 2 * .pi
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let angle = t * totalAngle - .pi / 2
            let r = maxR * (1 - t * 0.95)
            let p = CGPoint(
                x: center.x + CGFloat(cos(angle)) * r,
                y: center.y + CGFloat(sin(angle)) * r
            )
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }
}

/// Cursive lowercase "d" — single continuous stroke. Top of the
/// ascender → down → loop around the bowl (counter-clockwise) → close
/// at the top of the bowl back to the ascender. Brand-leaning option;
/// reads as a soft handwritten initial without spelling out the word.
struct CursiveDMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let x = rect.minX
        let y = rect.minY

        // Top of ascender — sits to the right.
        path.move(to: CGPoint(x: x + w * 0.72, y: y + h * 0.10))
        // Down the ascender to the top-right of the bowl.
        path.addLine(to: CGPoint(x: x + w * 0.72, y: y + h * 0.55))
        // Right side of bowl — curve down to bottom-right.
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.50, y: y + h * 0.92),
            control: CGPoint(x: x + w * 0.86, y: y + h * 0.78)
        )
        // Bottom of bowl — curve left.
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.18, y: y + h * 0.72),
            control: CGPoint(x: x + w * 0.20, y: y + h * 0.94)
        )
        // Left side of bowl — curve up to top-left.
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.42, y: y + h * 0.50),
            control: CGPoint(x: x + w * 0.16, y: y + h * 0.50)
        )
        // Close back to the ascender (slight rightward sweep).
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.72, y: y + h * 0.55),
            control: CGPoint(x: x + w * 0.58, y: y + h * 0.48)
        )
        return path
    }
}

/// Right-facing crescent moon. Outer arc traces the left half of a
/// circle (top → bottom around the left side); a quad curve closes
/// back through the interior, with `phase` controlling how thick the
/// crescent is (0 = full circle, 1 = a sliver). Used for the
/// Reminders page; suggests "calm, end-of-day, gentle" without the
/// literalness of a bell or clock.
struct CrescentMoon: Shape {
    /// 0.0 = full moon, 1.0 = thin crescent. Default reads as a clear
    /// crescent shape without being a tiny sliver.
    var phase: CGFloat = 0.65

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)

        // Outer arc — left half of the circle, top to bottom going
        // counter-clockwise (sweep through the left side).
        path.addArc(
            center: center,
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(90),
            clockwise: true
        )

        // Inner concave curve from bottom back up to top, with the
        // control point determining how deep the bite is.
        let bite = r * phase
        path.addQuadCurve(
            to: CGPoint(x: center.x, y: center.y - r),
            control: CGPoint(x: center.x - r + bite, y: center.y)
        )
        return path
    }
}

/// Bell shape with a small clapper. Used for the Reminders page.
/// Drawn as a single open path so the line has the felt-tip-pen feel.
struct JournalBell: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Bell body — wide at the bottom, narrow rounded crown.
        let bottomLeft = CGPoint(x: rect.minX + rect.width * 0.08, y: rect.maxY * 0.78)
        let bottomRight = CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.maxY * 0.78)
        let crownLeft = CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.18)
        let crownRight = CGPoint(x: rect.maxX - rect.width * 0.32, y: rect.minY + rect.height * 0.18)
        let crownTop = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.10)

        path.move(to: bottomLeft)
        path.addQuadCurve(
            to: crownLeft,
            control: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.midY * 0.75)
        )
        path.addQuadCurve(
            to: crownTop,
            control: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.minY + rect.height * 0.06)
        )
        path.addQuadCurve(
            to: crownRight,
            control: CGPoint(x: rect.maxX - rect.width * 0.30, y: rect.minY + rect.height * 0.06)
        )
        path.addQuadCurve(
            to: bottomRight,
            control: CGPoint(x: rect.maxX - rect.width * 0.05, y: rect.midY * 0.75)
        )

        // Bell rim (a separate horizontal line).
        path.move(to: CGPoint(x: bottomLeft.x - rect.width * 0.05, y: bottomLeft.y + rect.height * 0.02))
        path.addLine(to: CGPoint(x: bottomRight.x + rect.width * 0.05, y: bottomRight.y + rect.height * 0.02))

        // Clapper — a small loop hanging just below the rim.
        let clapperCenter = CGPoint(x: rect.midX, y: rect.maxY * 0.92)
        path.addEllipse(in: CGRect(
            x: clapperCenter.x - rect.width * 0.05,
            y: clapperCenter.y - rect.height * 0.04,
            width: rect.width * 0.10,
            height: rect.height * 0.08
        ))

        return path
    }
}
