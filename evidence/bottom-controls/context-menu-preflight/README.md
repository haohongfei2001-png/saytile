# Isolated AppKit context-menu preflight

One local macOS run verified that a non-key, non-main NSTextView in a transparent nonactivating panel exposes AXShowMenu for its attached native menu. The helper matched only the exact fixture PID, nonce and transcript identifier. AXShowMenu and AXPress on the named NSMenuItem each returned success. The view received one menu(for:) request, and the native target/action ran exactly once. Both processes exited 0. The fixture reported zero key events, zero activation, stable foreground and no clipboard operation.

This bounded prerequisite uses an independent AppKit fixture. The production Saytile menu and its actions require their own packaged checks. The fallback branch was not used. Sources and hashes of the two executed binaries are in result.json. To reproduce, compile Fixture.swift and Probe.swift using swiftc -swift-version 6 -parse-as-library into a temporary directory as fixture and probe; copy run.py there and run python3 run.py.
