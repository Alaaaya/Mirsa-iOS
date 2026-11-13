import Foundation

/// Explicit, local inspector transport. No background capture and no remote I/O.
enum ForgeInspector {
    /// The trusted inspector (mirsa.inspector.v1, two-finger double-tap) is injected by the build server into every tweak.
    /// This inert scaffold only gives the build a valid hook; it never embeds the reserved inspector schema.
    static func code(tweakID: UUID) -> String {
        return "%hook UIWindow\n- (void)becomeKeyWindow { %orig; }\n%end"
    }
}
