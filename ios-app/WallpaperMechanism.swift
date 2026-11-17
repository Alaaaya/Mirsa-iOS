import Foundation

/// Structural catalogue studied at CAPlayground/wallpapers@799fcf81d51dd04b9b8248830959eb1f7fe24d57.
/// These are classes and properties, not 70 distinct motion types. No reference artwork is used.
/// Supported means a bounded exporter recipe exists, NOT verified device compatibility.
enum WallpaperMechanism: String, CaseIterable, Identifiable {
    case classCABackdropLayer = "class:CABackdropLayer"
    case classCAEmitterBehavior = "class:CAEmitterBehavior"
    case classCAEmitterCell = "class:CAEmitterCell"
    case classCAEmitterLayer = "class:CAEmitterLayer"
    case classCAGradientLayer = "class:CAGradientLayer"
    case classCAReplicatorLayer = "class:CAReplicatorLayer"
    case classCASDFElementLayer = "class:CASDFElementLayer"
    case classCASDFLayer = "class:CASDFLayer"
    case classCATextLayer = "class:CATextLayer"
    case classCATransformLayer = "class:CATransformLayer"
    case classLKState = "class:LKState"
    case classLKStateAddAnimation = "class:LKStateAddAnimation"
    case classscriptObject = "class:scriptObject"
    case classwallpaperParallaxGroups = "class:wallpaperParallaxGroups"
    case classwallpaperPropertyGroups = "class:wallpaperPropertyGroups"
    case emitterModeoutline = "emitterMode:outline"
    case emitterModevolume = "emitterMode:volume"
    case emitterShapeline = "emitterShape:line"
    case emitterShapepoint = "emitterShape:point"
    case emitterShaperectangle = "emitterShape:rectangle"
    case filterContrast1 = "filter:Contrast 1"
    case filterGaussianBlur1 = "filter:Gaussian Blur 1"
    case filterHueRotate1 = "filter:Hue Rotate 1"
    case filterSaturate1 = "filter:Saturate 1"
    case filterSepia1 = "filter:Sepia 1"
    case filterciboxBlur = "filter:ciboxBlur"
    case filtercicolorControls = "filter:cicolorControls"
    case filtercigaussianBlur = "filter:cigaussianBlur"
    case filtercolorSaturate = "filter:colorSaturate"
    case filterdisplacementMap = "filter:displacementMap"
    case propertyanchorPoint = "property:anchorPoint"
    case propertyanimation = "property:animation"
    case propertyautoreverses = "property:autoreverses"
    case propertybackgroundColor = "property:backgroundColor"
    case propertybounds = "property:bounds"
    case propertyboundssizeheight = "property:bounds.size.height"
    case propertyboundssizewidth = "property:bounds.size.width"
    case propertycompositingFilter = "property:compositingFilter"
    case propertycontents = "property:contents"
    case propertycontinuousCorners = "property:continuousCorners"
    case propertycornerRadius = "property:cornerRadius"
    case propertyfilterscolorMatrixinputColorMatrix = "property:filters.colorMatrix.inputColorMatrix"
    case propertyhidden = "property:hidden"
    case propertylocked = "property:locked"
    case propertymasksToBounds = "property:masksToBounds"
    case propertyopacity = "property:opacity"
    case propertyposition = "property:position"
    case propertypositionx = "property:position.x"
    case propertypositiony = "property:position.y"
    case propertyshadowOpacity = "property:shadowOpacity"
    case propertyspeed = "property:speed"
    case propertysublayers = "property:sublayers"
    case propertytransformrotationx = "property:transform.rotation.x"
    case propertytransformrotationy = "property:transform.rotation.y"
    case propertytransformrotationz = "property:transform.rotation.z"
    case propertytransformscale = "property:transform.scale"
    case propertytransformscalex = "property:transform.scale.x"
    case propertytransformscalexy = "property:transform.scale.xy"
    case propertytransformtranslationx = "property:transform.translation.x"
    case propertytransformtranslationy = "property:transform.translation.y"
    case propertyzPosition = "property:zPosition"
    case renderModeadditive = "renderMode:additive"
    case renderModeunordered = "renderMode:unordered"
    case typeCABasicAnimation = "type:CABasicAnimation"
    case typeCAFilter = "type:CAFilter"
    case typeCAKeyframeAnimation = "type:CAKeyframeAnimation"
    case typeCAMatchMoveAnimation = "type:CAMatchMoveAnimation"
    case typeCASDFGlassDisplacementEffect = "type:CASDFGlassDisplacementEffect"
    case typeCASpringAnimation = "type:CASpringAnimation"
    case typeCATransition = "type:CATransition"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .classLKState: return "Lock, home and sleep states"
        case .classLKStateAddAnimation: return "State-triggered animation"
        case .classwallpaperParallaxGroups: return "Device-tilt parallax"
        case .classwallpaperPropertyGroups: return "Parameterized scene changes"
        case .classscriptObject: return "Script object (unavailable)"
        default: return String(rawValue.split(separator: ":", maxSplits: 1).last ?? "")
        }
    }
    var isSupported: Bool { unsupportedReason == nil }
    var isExperimental: Bool { true }
    var limitation: String? {
        unsupportedReason ?? "Experimental export recipe. Device playback has not been verified."
    }
    private var unsupportedReason: String? {
        switch self {
        case .classCAEmitterBehavior: return "The only surveyed attractor is disabled. An active behavior has not been validated, so no enabled behavior is emitted."
        case .classscriptObject: return "Arbitrary script execution is not supported."
        case .typeCAMatchMoveAnimation: return "The surveyed match-move animation has no source target. No valid independent source-follow schema is available."
        case .typeCATransition: return "The surveyed transition is disabled and has no transition subtype. A valid active transition schema is not available."
        case .propertyanimation: return "The surveyed animation key path is a placeholder, not an animatable layer property."
        case .propertyautoreverses: return "autoreverses belongs to an animation, not the targeted layer in the surveyed state assignment."
        case .propertylocked: return "The surveyed locked key path targets a layer without a verified lock-property schema."
        case .propertysublayers: return "Replacing a layer hierarchy in a state is not safe for stable photo identities."
        case .propertyfilterscolorMatrixinputColorMatrix: return "The surveyed state references a missing colorMatrix filter. No valid matching filter object schema is available."
        default: return nil
        }
    }
    /// Exact CAML substrings, asserted against actual generated XML rather than a manifest claim.
    var structuralMarkers: [String] {
        switch self {
        case .classCABackdropLayer: return ["<CABackdropLayer", "inputAmount=\"-24\""]
        case .classCAEmitterBehavior: return []
        case .classCAEmitterCell: return ["<CAEmitterCell", "lifetime=\"3\"", "scale=\"0.14\""]
        case .classCAEmitterLayer: return ["<CAEmitterLayer", "lifetime=\"5\"", "birthRate=\"10\""]
        case .classCAGradientLayer: return ["<CAGradientLayer", "opacity=\"0.28\""]
        case .classCAReplicatorLayer: return ["<CAReplicatorLayer"]
        case .classCASDFElementLayer: return ["<CASDFElementLayer", "cornerRadius=\"28\""]
        case .classCASDFLayer: return ["<CASDFLayer", "height=\"20\""]
        case .classCATextLayer: return ["<CATextLayer"]
        case .classCATransformLayer: return ["<CATransformLayer"]
        case .classLKState: return ["<LKState"]
        case .classLKStateAddAnimation: return ["<LKStateAddAnimation"]
        case .classscriptObject: return []
        case .classwallpaperParallaxGroups: return ["<wallpaperParallaxGroups type=\"NSArray\""]
        case .classwallpaperPropertyGroups: return ["<wallpaperPropertyGroups type=\"NSArray\""]
        case .emitterModeoutline: return ["emitterMode=\"outline\"", "emitterSize=\"300 500\""]
        case .emitterModevolume: return ["emitterMode=\"volume\"", "emitterSize=\"260 420\""]
        case .emitterShapeline: return ["emitterShape=\"line\"", "emitterSize=\"300 0\""]
        case .emitterShapepoint: return ["emitterShape=\"point\"", "emitterPosition=\"195 160\""]
        case .emitterShaperectangle: return ["emitterShape=\"rectangle\"", "emitterSize=\"300 120\""]
        case .filterContrast1: return ["name=\"Contrast 1\""]
        case .filterGaussianBlur1: return ["name=\"Gaussian Blur 1\""]
        case .filterHueRotate1: return ["name=\"Hue Rotate 1\""]
        case .filterSaturate1: return ["name=\"Saturate 1\""]
        case .filterSepia1: return ["name=\"Sepia 1\""]
        case .filterciboxBlur: return ["name=\"ciboxBlur\""]
        case .filtercicolorControls: return ["name=\"cicolorControls\""]
        case .filtercigaussianBlur: return ["name=\"cigaussianBlur\""]
        case .filtercolorSaturate: return ["name=\"colorSaturate\""]
        case .filterdisplacementMap: return ["filter=\"displacementMap\"", "inputAmount=\"-56\""]
        case .propertyanchorPoint: return ["keyPath=\"anchorPoint\""]
        case .propertyanimation: return []
        case .propertyautoreverses: return []
        case .propertybackgroundColor: return ["keyPath=\"backgroundColor\""]
        case .propertybounds: return ["keyPath=\"bounds\""]
        case .propertyboundssizeheight: return ["keyPath=\"bounds.size.height\""]
        case .propertyboundssizewidth: return ["keyPath=\"bounds.size.width\""]
        case .propertycompositingFilter: return ["keyPath=\"compositingFilter\"", "filter=\"screenBlendMode\""]
        case .propertycontents: return ["keyPath=\"contents\"", "calculationMode=\"discrete\""]
        case .propertycontinuousCorners: return ["keyPath=\"continuousCorners\""]
        case .propertycornerRadius: return ["keyPath=\"cornerRadius\""]
        case .propertyfilterscolorMatrixinputColorMatrix: return []
        case .propertyhidden: return ["keyPath=\"hidden\""]
        case .propertylocked: return []
        case .propertymasksToBounds: return ["keyPath=\"masksToBounds\""]
        case .propertyopacity: return ["keyPath=\"opacity\""]
        case .propertyposition: return ["keyPath=\"position\""]
        case .propertypositionx: return ["keyPath=\"position.x\""]
        case .propertypositiony: return ["keyPath=\"position.y\""]
        case .propertyshadowOpacity: return ["keyPath=\"shadowOpacity\""]
        case .propertyspeed: return ["keyPath=\"speed\""]
        case .propertysublayers: return []
        case .propertytransformrotationx: return ["keyPath=\"transform.rotation.x\""]
        case .propertytransformrotationy: return ["keyPath=\"transform.rotation.y\""]
        case .propertytransformrotationz: return ["keyPath=\"transform.rotation.z\""]
        case .propertytransformscale: return ["keyPath=\"transform.scale\""]
        case .propertytransformscalex: return ["keyPath=\"transform.scale.x\""]
        case .propertytransformscalexy: return ["keyPath=\"transform.scale.xy\""]
        case .propertytransformtranslationx: return ["keyPath=\"transform.translation.x\""]
        case .propertytransformtranslationy: return ["keyPath=\"transform.translation.y\""]
        case .propertyzPosition: return ["keyPath=\"zPosition\""]
        case .renderModeadditive: return ["renderMode=\"additive\""]
        case .renderModeunordered: return ["renderMode=\"unordered\"", "birthRate=\"16\""]
        case .typeCABasicAnimation: return ["type=\"CABasicAnimation\""]
        case .typeCAFilter: return ["type=\"CAFilter\"", "filter=\"overlayBlendMode\""]
        case .typeCAKeyframeAnimation: return ["type=\"CAKeyframeAnimation\""]
        case .typeCAMatchMoveAnimation: return []
        case .typeCASDFGlassDisplacementEffect: return ["type=\"CASDFGlassDisplacementEffect\"", "height=\"40\"", "inputAmount=\"-80\""]
        case .typeCASpringAnimation: return ["type=\"CASpringAnimation\""]
        case .typeCATransition: return []
        }
    }
}
