import Foundation

private typealias ProgressFunction = @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void
@_silgen_name("mirsa_pb_progress_set")
private func setNativeProgress(_ callback: ProgressFunction?, _ context: UnsafeMutableRawPointer?)

/// The entire detached diagnostic body is synchronous on one worker thread.
/// Never cancel a cache swap or release this context while native code is active.
final class ProbeProgress {
    private let logger: (String) -> Void
    init(_ logger: @escaping (String) -> Void) {
        self.logger = logger
        setNativeProgress({ text, context in
            guard let text, let context else { return }
            let sink = Unmanaged<ProbeProgress>.fromOpaque(context).takeUnretainedValue()
            sink.logger(String(cString: text))
        }, Unmanaged.passUnretained(self).toOpaque())
    }
    func finish() { setNativeProgress(nil, nil) }
}
