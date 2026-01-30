# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude-Utils is a cross-platform Rust toolkit providing clipboard integration for Claude Code CLI via the Model Context Protocol (MCP). It enables seamless pasting of text and images into Claude Code without leaving the keyboard-centric workflow.

## Build & Development Commands

```bash
# Build
cargo build                      # Debug build
cargo build --release            # Optimized release build

# Run
cargo run -- start               # Start MCP daemon
cargo run -- start --watch       # Start with watch mode (auto image-to-path)
cargo run -- token               # Display auth token
cargo run -- clip get            # Get clipboard content

# Test
cargo test                       # Run all tests
cargo test <test_name>           # Run specific test
cargo test -- --nocapture        # Show test output

# Lint & Format
cargo clippy -- -D warnings      # Lint (warnings treated as errors)
cargo fmt                        # Format code
cargo fmt -- --check             # Check formatting without changes
```

## Architecture

```
Claude Code CLI
    ↓ (HTTP + Token Auth)
MCP Server (127.0.0.1:3830)
    ├── /health, /rpc, /sse endpoints
    └── Core Components
        ├── ClipboardManager → System clipboard access
        ├── FileManager → Image staging + SHA-256 dedup
        ├── AuthManager → Token-based auth
        └── ClipboardProcessor → Watch mode
```

### Key Modules

| Module | Location | Purpose |
|--------|----------|---------|
| CLI | `src/bin/claude-utils.rs` | Entry point, clap-based command parsing |
| Clipboard | `src/clipboard/mod.rs` | Cross-platform clipboard abstraction via `arboard` |
| Watch Mode | `src/clipboard/watcher.rs` + `processor.rs` | 500ms polling, image-to-path conversion |
| File Manager | `src/file_manager/mod.rs` | `/tmp/claude-utils/` staging, 15-min auto-cleanup |
| MCP Server | `src/mcp/server.rs` | Axum HTTP + SSE, JSON-RPC 2.0 |
| Protocol | `src/mcp/protocol.rs` | MCP message types and serialization |
| Auth | `src/mcp/auth.rs` | Token generation/validation, stored in `~/.claude-utils/auth.token` |

### MCP Tools Implemented

- `clipboard.get` - Read clipboard (format: auto|text|image)
- `clipboard.set` - Write to clipboard (requires `--write` flag)

### Platform-Specific Code

- **macOS**: `objc`/`cocoa` for NSPasteboard, dual clipboard format (path + image)
- **Linux**: `x11-clipboard` for X11, `arboard` fallback for Wayland
- **Windows**: `winapi` for native clipboard, WSL2 support via `deploy.sh`

## Code Conventions

- Async/await with Tokio runtime throughout
- Error handling: `thiserror` for custom errors, `anyhow` for propagation
- Shared state: `Arc<Mutex<T>>` pattern for thread-safe state
- Conventional commits for commit messages

## Testing

- Unit tests: inline in modules (e.g., `src/main_test.rs`)
- Integration tests: `tests/integration_test.rs`
- All tests use `#[tokio::test]` for async support

## Security Model

- Local-only: binds to 127.0.0.1
- Token auth: 32-char hex tokens with 0600 file permissions
- Read-only by default: writes require `--write` flag

## Fork-Specific Changes

This fork includes critical fixes for MCP protocol compatibility:

| Fix | File | Issue | Solution |
|-----|------|-------|----------|
| Protocol version | `src/mcp/server.rs:~173` | `"1.0"` rejected | Changed to `"2024-11-05"` |
| JSON serialization | `src/mcp/protocol.rs` | snake_case keys | Added `#[serde(rename_all = "camelCase")]` |
| Image clipboard.set | `src/mcp/server.rs` | arboard expects RGBA, not PNG | Auto-convert PNG → RGBA with `image` crate |

**Image format note:** `arboard` requires raw RGBA bytes (4 bytes/pixel), not compressed PNG. The fix auto-converts PNG input or accepts raw RGBA with explicit `width`/`height` parameters.

## Windows/WSL Deployment

```bash
# Deploy from WSL to Windows
./deploy.sh                  # Full deployment (build + install)
./deploy.sh --skip-build     # Install only (no recompile)
./deploy.sh --uninstall      # Remove from Windows

# Verify server from WSL
curl http://172.22.32.1:3830/health
```

**Installation paths (Windows):**
- Binary: `%LOCALAPPDATA%\claude-utils\claude-utils.exe`
- Startup shortcut: `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\`

**MCP configuration from WSL:**
```bash
claude mcp add --transport http claude-utils http://172.22.32.1:3830/
```

## WSL Path Conversion

The `--wsl` flag converts Windows paths to WSL format when running on Windows but pasting in WSL terminals:

```bash
claude-utils start --watch --wsl
# C:\Users\name\Desktop\file.png → /mnt/c/Users/name/Desktop/file.png
```

Implementation: `convert_to_wsl_path()` in `src/clipboard/processor.rs`

## Pending Work

- **Hidden startup:** Server currently shows terminal window on Windows startup
