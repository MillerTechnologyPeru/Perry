import CPerryGeometry
import Glibc
import PerryObjCInterop

// Properties of SceneKit's cameras, lights and views that nothing draws or
// uses yet (bloom, depth of field, shadow settings...): they are kept, so
// that what an app sets it reads back, and default to what SceneKit's do.

/// Numbers and flags set by name.
final class SCNExtrasState: ObjectState {
    var values: [String: Double] = [:]
    var objects: [String: NSObject] = [:]
}

enum SCNExtras {
    static let cameras = StateTable<SCNExtrasState>()
    static let lights = StateTable<SCNExtrasState>()
    static let views = StateTable<SCNExtrasState>()
    static let materials = StateTable<SCNExtrasState>()
    static let nodes = StateTable<SCNExtrasState>()
    static let scenes = StateTable<SCNExtrasState>()
}

@ObjCCategory("SCNCameraSettings")
extension SCNCamera {
    @ObjCMethod("bloomIntensity") func bloomIntensityValue() -> CGFloat { CGFloat(SCNExtras.cameras[objcObject].values["bloomIntensity"] ?? 0) }
    @ObjCMethod("setBloomIntensity:") func setBloomIntensity(_ value: CGFloat) { SCNExtras.cameras[objcObject].values["bloomIntensity"] = Double(value) }
    @ObjCMethod("bloomThreshold") func bloomThresholdValue() -> CGFloat { CGFloat(SCNExtras.cameras[objcObject].values["bloomThreshold"] ?? 0.5) }
    @ObjCMethod("setBloomThreshold:") func setBloomThreshold(_ value: CGFloat) { SCNExtras.cameras[objcObject].values["bloomThreshold"] = Double(value) }
    @ObjCMethod("bloomBlurRadius") func bloomBlurRadiusValue() -> CGFloat { CGFloat(SCNExtras.cameras[objcObject].values["bloomBlurRadius"] ?? 16) }
    @ObjCMethod("setBloomBlurRadius:") func setBloomBlurRadius(_ value: CGFloat) { SCNExtras.cameras[objcObject].values["bloomBlurRadius"] = Double(value) }
    @ObjCMethod("vignettingIntensity") func vignettingIntensityValue() -> CGFloat { CGFloat(SCNExtras.cameras[objcObject].values["vignettingIntensity"] ?? 0) }
    @ObjCMethod("setVignettingIntensity:") func setVignettingIntensity(_ value: CGFloat) { SCNExtras.cameras[objcObject].values["vignettingIntensity"] = Double(value) }
    @ObjCMethod("vignettingPower") func vignettingPowerValue() -> CGFloat { CGFloat(SCNExtras.cameras[objcObject].values["vignettingPower"] ?? 0) }
    @ObjCMethod("setVignettingPower:") func setVignettingPower(_ value: CGFloat) { SCNExtras.cameras[objcObject].values["vignettingPower"] = Double(value) }
    @ObjCMethod("fStop") func fStopValue() -> CGFloat { CGFloat(SCNExtras.cameras[objcObject].values["fStop"] ?? 2.8) }
    @ObjCMethod("setFStop:") func setFStop(_ value: CGFloat) { SCNExtras.cameras[objcObject].values["fStop"] = Double(value) }
    @ObjCMethod("focusDistance") func focusDistanceValue() -> CGFloat { CGFloat(SCNExtras.cameras[objcObject].values["focusDistance"] ?? 2.5) }
    @ObjCMethod("setFocusDistance:") func setFocusDistance(_ value: CGFloat) { SCNExtras.cameras[objcObject].values["focusDistance"] = Double(value) }
    @ObjCMethod("sensorHeight") func sensorHeightValue() -> CGFloat { CGFloat(SCNExtras.cameras[objcObject].values["sensorHeight"] ?? 24) }
    @ObjCMethod("setSensorHeight:") func setSensorHeight(_ value: CGFloat) { SCNExtras.cameras[objcObject].values["sensorHeight"] = Double(value) }
    @ObjCMethod("motionBlurIntensity") func motionBlurIntensityValue() -> CGFloat { CGFloat(SCNExtras.cameras[objcObject].values["motionBlurIntensity"] ?? 0) }
    @ObjCMethod("setMotionBlurIntensity:") func setMotionBlurIntensity(_ value: CGFloat) { SCNExtras.cameras[objcObject].values["motionBlurIntensity"] = Double(value) }
    @ObjCMethod("saturation") func saturationValue() -> CGFloat { CGFloat(SCNExtras.cameras[objcObject].values["saturation"] ?? 1) }
    @ObjCMethod("setSaturation:") func setSaturation(_ value: CGFloat) { SCNExtras.cameras[objcObject].values["saturation"] = Double(value) }
    @ObjCMethod("contrast") func contrastValue() -> CGFloat { CGFloat(SCNExtras.cameras[objcObject].values["contrast"] ?? 0) }
    @ObjCMethod("setContrast:") func setContrast(_ value: CGFloat) { SCNExtras.cameras[objcObject].values["contrast"] = Double(value) }
    @ObjCMethod("whitePoint") func whitePointValue() -> CGFloat { CGFloat(SCNExtras.cameras[objcObject].values["whitePoint"] ?? 1) }
    @ObjCMethod("setWhitePoint:") func setWhitePoint(_ value: CGFloat) { SCNExtras.cameras[objcObject].values["whitePoint"] = Double(value) }
    @ObjCMethod("averageGray") func averageGrayValue() -> CGFloat { CGFloat(SCNExtras.cameras[objcObject].values["averageGray"] ?? 0.18) }
    @ObjCMethod("setAverageGray:") func setAverageGray(_ value: CGFloat) { SCNExtras.cameras[objcObject].values["averageGray"] = Double(value) }
    @ObjCMethod("minimumExposure") func minimumExposureValue() -> CGFloat { CGFloat(SCNExtras.cameras[objcObject].values["minimumExposure"] ?? -15) }
    @ObjCMethod("setMinimumExposure:") func setMinimumExposure(_ value: CGFloat) { SCNExtras.cameras[objcObject].values["minimumExposure"] = Double(value) }
    @ObjCMethod("maximumExposure") func maximumExposureValue() -> CGFloat { CGFloat(SCNExtras.cameras[objcObject].values["maximumExposure"] ?? 15) }
    @ObjCMethod("setMaximumExposure:") func setMaximumExposure(_ value: CGFloat) { SCNExtras.cameras[objcObject].values["maximumExposure"] = Double(value) }
    @ObjCMethod("exposureOffset") func exposureOffsetValue() -> CGFloat { CGFloat(SCNExtras.cameras[objcObject].values["exposureOffset"] ?? -1) }
    @ObjCMethod("setExposureOffset:") func setExposureOffset(_ value: CGFloat) { SCNExtras.cameras[objcObject].values["exposureOffset"] = Double(value) }
    @ObjCMethod("grainIntensity") func grainIntensityValue() -> CGFloat { CGFloat(SCNExtras.cameras[objcObject].values["grainIntensity"] ?? 0) }
    @ObjCMethod("setGrainIntensity:") func setGrainIntensity(_ value: CGFloat) { SCNExtras.cameras[objcObject].values["grainIntensity"] = Double(value) }
    @ObjCMethod("colorFringeIntensity") func colorFringeIntensityValue() -> CGFloat { CGFloat(SCNExtras.cameras[objcObject].values["colorFringeIntensity"] ?? 1) }
    @ObjCMethod("setColorFringeIntensity:") func setColorFringeIntensity(_ value: CGFloat) { SCNExtras.cameras[objcObject].values["colorFringeIntensity"] = Double(value) }
    @ObjCMethod("colorFringeStrength") func colorFringeStrengthValue() -> CGFloat { CGFloat(SCNExtras.cameras[objcObject].values["colorFringeStrength"] ?? 0) }
    @ObjCMethod("setColorFringeStrength:") func setColorFringeStrength(_ value: CGFloat) { SCNExtras.cameras[objcObject].values["colorFringeStrength"] = Double(value) }
    @ObjCMethod("focalLength") func focalLengthValue() -> CGFloat { CGFloat(SCNExtras.cameras[objcObject].values["focalLength"] ?? 50) }
    @ObjCMethod("setFocalLength:") func setFocalLength(_ value: CGFloat) { SCNExtras.cameras[objcObject].values["focalLength"] = Double(value) }
    @ObjCMethod("wantsHDR") func wantsHDRFlag() -> Bool { (SCNExtras.cameras[objcObject].values["wantsHDR"] ?? 0) != 0 }
    @ObjCMethod("setWantsHDR:") func setWantsHDR(_ value: Bool) { SCNExtras.cameras[objcObject].values["wantsHDR"] = value ? 1 : 0 }
    @ObjCMethod("wantsDepthOfField") func wantsDepthOfFieldFlag() -> Bool { (SCNExtras.cameras[objcObject].values["wantsDepthOfField"] ?? 0) != 0 }
    @ObjCMethod("setWantsDepthOfField:") func setWantsDepthOfField(_ value: Bool) { SCNExtras.cameras[objcObject].values["wantsDepthOfField"] = value ? 1 : 0 }
    @ObjCMethod("wantsExposureAdaptation") func wantsExposureAdaptationFlag() -> Bool { (SCNExtras.cameras[objcObject].values["wantsExposureAdaptation"] ?? 1) != 0 }
    @ObjCMethod("setWantsExposureAdaptation:") func setWantsExposureAdaptation(_ value: Bool) { SCNExtras.cameras[objcObject].values["wantsExposureAdaptation"] = value ? 1 : 0 }
    @ObjCMethod("automaticallyAdjustsZRange") func automaticallyAdjustsZRangeFlag() -> Bool { (SCNExtras.cameras[objcObject].values["automaticallyAdjustsZRange"] ?? 0) != 0 }
    @ObjCMethod("setAutomaticallyAdjustsZRange:") func setAutomaticallyAdjustsZRange(_ value: Bool) { SCNExtras.cameras[objcObject].values["automaticallyAdjustsZRange"] = value ? 1 : 0 }
}

@ObjCCategory("SCNLightSettings")
extension SCNLight {
    @ObjCMethod("shadowRadius") func shadowRadiusValue() -> CGFloat { CGFloat(SCNExtras.lights[objcObject].values["shadowRadius"] ?? 3) }
    @ObjCMethod("setShadowRadius:") func setShadowRadius(_ value: CGFloat) { SCNExtras.lights[objcObject].values["shadowRadius"] = Double(value) }
    @ObjCMethod("shadowBias") func shadowBiasValue() -> CGFloat { CGFloat(SCNExtras.lights[objcObject].values["shadowBias"] ?? 1) }
    @ObjCMethod("setShadowBias:") func setShadowBias(_ value: CGFloat) { SCNExtras.lights[objcObject].values["shadowBias"] = Double(value) }
    @ObjCMethod("maximumShadowDistance") func maximumShadowDistanceValue() -> CGFloat { CGFloat(SCNExtras.lights[objcObject].values["maximumShadowDistance"] ?? 100) }
    @ObjCMethod("setMaximumShadowDistance:") func setMaximumShadowDistance(_ value: CGFloat) { SCNExtras.lights[objcObject].values["maximumShadowDistance"] = Double(value) }
    @ObjCMethod("shadowCascadeSplittingFactor") func shadowCascadeSplittingFactorValue() -> CGFloat { CGFloat(SCNExtras.lights[objcObject].values["shadowCascadeSplittingFactor"] ?? 0.15) }
    @ObjCMethod("setShadowCascadeSplittingFactor:") func setShadowCascadeSplittingFactor(_ value: CGFloat) { SCNExtras.lights[objcObject].values["shadowCascadeSplittingFactor"] = Double(value) }
    @ObjCMethod("zNear") func zNearValue() -> CGFloat { CGFloat(SCNExtras.lights[objcObject].values["zNear"] ?? 1) }
    @ObjCMethod("setZNear:") func setZNear(_ value: CGFloat) { SCNExtras.lights[objcObject].values["zNear"] = Double(value) }
    @ObjCMethod("zFar") func zFarValue() -> CGFloat { CGFloat(SCNExtras.lights[objcObject].values["zFar"] ?? 100) }
    @ObjCMethod("setZFar:") func setZFar(_ value: CGFloat) { SCNExtras.lights[objcObject].values["zFar"] = Double(value) }
    @ObjCMethod("orthographicScale") func orthographicScaleValue() -> CGFloat { CGFloat(SCNExtras.lights[objcObject].values["orthographicScale"] ?? 1) }
    @ObjCMethod("setOrthographicScale:") func setOrthographicScale(_ value: CGFloat) { SCNExtras.lights[objcObject].values["orthographicScale"] = Double(value) }
    @ObjCMethod("automaticallyAdjustsShadowProjection") func automaticallyAdjustsShadowProjectionFlag() -> Bool { (SCNExtras.lights[objcObject].values["automaticallyAdjustsShadowProjection"] ?? 1) != 0 }
    @ObjCMethod("setAutomaticallyAdjustsShadowProjection:") func setAutomaticallyAdjustsShadowProjection(_ value: Bool) { SCNExtras.lights[objcObject].values["automaticallyAdjustsShadowProjection"] = value ? 1 : 0 }
    @ObjCMethod("shadowCascadeCount") func shadowCascadeCountCount() -> Int { Int(SCNExtras.lights[objcObject].values["shadowCascadeCount"] ?? 1) }
    @ObjCMethod("setShadowCascadeCount:") func setShadowCascadeCount(_ value: Int) { SCNExtras.lights[objcObject].values["shadowCascadeCount"] = Double(value) }
    @ObjCMethod("shadowSampleCount") func shadowSampleCountCount() -> Int { Int(SCNExtras.lights[objcObject].values["shadowSampleCount"] ?? 8) }
    @ObjCMethod("setShadowSampleCount:") func setShadowSampleCount(_ value: Int) { SCNExtras.lights[objcObject].values["shadowSampleCount"] = Double(value) }
}

@ObjCCategory("SCNLightShadowSize")
extension SCNLight {
    @ObjCMethod("shadowMapSize") func shadowMapSize() -> CGSize {
        let values = SCNExtras.lights[objcObject].values
        return CGSize(width: values["shadowMapWidth"] ?? 0, height: values["shadowMapHeight"] ?? 0)
    }
    @ObjCMethod("setShadowMapSize:") func setShadowMapSize(_ size: CGSize) {
        SCNExtras.lights[objcObject].values["shadowMapWidth"] = Double(size.width)
        SCNExtras.lights[objcObject].values["shadowMapHeight"] = Double(size.height)
    }
    @ObjCMethod("categoryBitMask") func lightCategoryBitMask() -> Int { Int(SCNExtras.lights[objcObject].values["categoryBitMask"] ?? -1) }
    @ObjCMethod("setCategoryBitMask:") func setLightCategoryBitMask(_ mask: Int) { SCNExtras.lights[objcObject].values["categoryBitMask"] = Double(mask) }
}

@ObjCCategory("SCNViewSettings")
extension SCNView {
    @ObjCMethod("isJitteringEnabled") func jitteringEnabledFlag() -> Bool { (SCNExtras.views[objcObject].values["jitteringEnabled"] ?? 0) != 0 }
    @ObjCMethod("setJitteringEnabled:") func setJitteringEnabled(_ value: Bool) { SCNExtras.views[objcObject].values["jitteringEnabled"] = value ? 1 : 0 }
    @ObjCMethod("isTemporalAntialiasingEnabled") func temporalAntialiasingEnabledFlag() -> Bool { (SCNExtras.views[objcObject].values["temporalAntialiasingEnabled"] ?? 0) != 0 }
    @ObjCMethod("setTemporalAntialiasingEnabled:") func setTemporalAntialiasingEnabled(_ value: Bool) { SCNExtras.views[objcObject].values["temporalAntialiasingEnabled"] = value ? 1 : 0 }
    @ObjCMethod("usesReverseZ") func usesReverseZFlag() -> Bool { (SCNExtras.views[objcObject].values["usesReverseZ"] ?? 0) != 0 }
    @ObjCMethod("setUsesReverseZ:") func setUsesReverseZ(_ value: Bool) { SCNExtras.views[objcObject].values["usesReverseZ"] = value ? 1 : 0 }
    @ObjCMethod("debugOptions") func debugOptionsCount() -> Int { Int(SCNExtras.views[objcObject].values["debugOptions"] ?? 0) }
    @ObjCMethod("setDebugOptions:") func setDebugOptions(_ value: Int) { SCNExtras.views[objcObject].values["debugOptions"] = Double(value) }
}
