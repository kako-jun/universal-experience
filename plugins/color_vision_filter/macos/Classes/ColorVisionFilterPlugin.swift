import FlutterMacOS

public class ColorVisionFilterPlugin: NSObject, FlutterPlugin {
    private var currentType = "none"
    private var currentIntensity: Float = 1.0
    private var isActive = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "color_vision_filter",
            binaryMessenger: registrar.messenger
        )
        let instance = ColorVisionFilterPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "apply":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
                return
            }
            if let type = args["type"] as? String {
                currentType = type
            }
            if let intensity = args["intensity"] as? Double {
                currentIntensity = Float(intensity)
            }
            isActive = currentType != "none"
            result(true)

        case "setIntensity":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
                return
            }
            if let intensity = args["intensity"] as? Double {
                currentIntensity = Float(intensity)
            }
            result(true)

        case "remove":
            isActive = false
            currentType = "none"
            result(true)

        case "getState":
            result([
                "type": currentType,
                "intensity": Double(currentIntensity),
                "isActive": isActive,
            ] as [String: Any])

        case "hasPermission":
            result(true)

        case "requestPermission":
            result(true)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
