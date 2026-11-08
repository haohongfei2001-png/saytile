// Minimal reproduction of the original optional trailing-closure API; no UI or external state.
func original(validation: (() -> Void)? = nil, interaction: (() -> Void)? = nil) {
    print("ORIGINAL validation=\(validation != nil) interaction=\(interaction != nil)")
}
func repaired(interaction: (() -> Void)? = nil) {
    print("REPAIRED interaction=\(interaction != nil)")
}
original { }
repaired { }
