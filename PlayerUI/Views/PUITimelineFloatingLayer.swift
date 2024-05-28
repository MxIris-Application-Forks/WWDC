import AppKit

final class PUITimelineFloatingLayer: PUIBoringLayer, CAAnimationDelegate {

    var attributedText: NSAttributedString? = nil {
        didSet {
            guard attributedText != oldValue else { return }

            updateSize()
            setNeedsLayout()
        }
    }

    var padding: CGSize = CGSize(width: 16, height: 10) {
        didSet {
            guard padding != oldValue else { return }

            updateSize()
            setNeedsLayout()
        }
    }

    func show() {
        guard model().isHidden else { return }

        isHidden = false

        removeAllAnimations()

        let scaleAnim = CASpringAnimation.springFrom(CATransform3DMakeScale(0.2, 0.2, 1), to: CATransform3DIdentity, keyPath: "sublayerTransform")
        transformLayer.add(scaleAnim, forKey: "show")
        transformLayer.sublayerTransform = CATransform3DIdentity

        let fadeAnim = CABasicAnimation.basicFrom(0, to: 1, keyPath: "opacity", duration: 0.25)
        transformLayer.add(fadeAnim, forKey: "fadeIn")
        transformLayer.opacity = 1
    }

    func hide(animated: Bool = true) {
        guard !model().isHidden else { return }

        removeAllAnimations()

        guard animated else {
            transformLayer.sublayerTransform = CATransform3DMakeScale(0.2, 0.2, 1)
            transformLayer.opacity = 0
            return
        }

        let scaleAnim = CASpringAnimation.springFrom(CATransform3DIdentity, to: CATransform3DMakeScale(0.2, 0.2, 1), keyPath: "sublayerTransform", delegate: self)
        transformLayer.add(scaleAnim, forKey: "hide")
        transformLayer.sublayerTransform = CATransform3DMakeScale(0.2, 0.2, 1)
        
        let fadeAnim = CABasicAnimation.basicFrom(1, to: 0, keyPath: "opacity", duration: 0.25)
        transformLayer.add(fadeAnim, forKey: "fadeOut")
        transformLayer.opacity = 0
    }

    private struct AssetError: LocalizedError, CustomStringConvertible {
        var errorDescription: String?
        var description: String { errorDescription ?? "" }
        init(_ message: String) { self.errorDescription = message }
    }

    private lazy var backgroundLayer: CALayer = {
        guard let asset = NSDataAsset(name: "TimeBubble", bundle: .playerUI) else {
            assertionFailure("Missing TimeBubble asset in PlayerUI.framework")
            return CALayer()
        }

        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: asset.data)
            unarchiver.requiresSecureCoding = false

            guard let dict = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? [String: Any] else {
                throw AssetError("Root object is not a dictionary")
            }
            unarchiver.finishDecoding()

            guard let rootLayer = dict["rootLayer"] as? CALayer else {
                throw AssetError("Missing or invalid rootLayer")
            }

            return rootLayer
        } catch {
            assertionFailure("TimeBubble asset corrupted: \(error)")
            return CALayer()
        }
    }()

    private lazy var textLayer: PUIBoringTextLayer = {
        let l = PUIBoringTextLayer()
        return l
    }()

    private lazy var transformLayer: CATransformLayer = {
        let l = CATransformLayer()
        return l
    }()

    private func updateSize() {
        guard let attributedText else { return }

        let textSize = attributedText.size()

        frame.size = CGSize(width: textSize.width + padding.width, height: textSize.height + padding.height)
    }

    override func layoutSublayers() {
        super.layoutSublayers()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        defer { CATransaction.commit() }

        guard let attributedText else {
            isHidden = true
            return
        }

        isHidden = false

        if backgroundLayer.superlayer == nil {
            transformLayer.addSublayer(backgroundLayer)
        }
        if textLayer.superlayer == nil {
            transformLayer.addSublayer(textLayer)
        }
        if transformLayer.superlayer == nil {
            addSublayer(transformLayer)
        }

        transformLayer.frame = bounds

        backgroundLayer.frame = bounds
        backgroundLayer.masksToBounds = true
        backgroundLayer.cornerCurve = .continuous
        backgroundLayer.cornerRadius = 12

        let textSize = attributedText.size()
        textLayer.string = attributedText
        textLayer.frame = CGRect(
            x: bounds.midX - textSize.width * 0.5,
            y: bounds.midY - textSize.height * 0.5,
            width: textSize.width,
            height: textSize.height
        )
        textLayer.contentsScale = NSApp.windows.first?.backingScaleFactor ?? 2
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        isHidden = true
    }

}

extension PUITimelineFloatingLayer {
    static func attributedString(for timestamp: Double, font: NSFont) -> NSAttributedString {
        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = .center

        let timeTextAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: pStyle
        ]

        let timeStr = String(timestamp: timestamp) ?? ""

        return NSAttributedString(string: timeStr, attributes: timeTextAttributes)
    }
}

extension CABasicAnimation {
    static func basicFrom<V>(_ fromValue: V, to toValue: V, keyPath: String, duration: TimeInterval = 0.4, delegate: CAAnimationDelegate? = nil) -> Self {
        let anim = Self()
        anim.duration = duration
        anim.keyPath = keyPath
        anim.fromValue = fromValue
        anim.toValue = toValue
        anim.isRemovedOnCompletion = true
        anim.fillMode = .both
        anim.delegate = delegate
        return anim
    }
}

extension CASpringAnimation {
    static func springFrom<V>(
        _ fromValue: V,
        to toValue: V,
        keyPath: String,
        mass: CGFloat = 1,
        stiffness: CGFloat = 140,
        damping: CGFloat = 18,
        initialVelocity: CGFloat = 10,
        delegate: CAAnimationDelegate? = nil) -> CASpringAnimation
    {
        let anim = CASpringAnimation()
        anim.mass = mass
        anim.stiffness = stiffness
        anim.damping = damping
        anim.initialVelocity = initialVelocity
        anim.keyPath = keyPath
        anim.fromValue = fromValue
        anim.toValue = toValue
        anim.isRemovedOnCompletion = true
        anim.fillMode = .both
        anim.delegate = delegate
        return anim
    }
}
