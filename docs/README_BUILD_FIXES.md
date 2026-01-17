# Xcode Build Error Fixes for Bitchat

This directory contains documentation and scripts to help resolve common Xcode build errors when working with Bitchat.

## Quick Start

If you're experiencing Xcode build errors, start here:

### 1. Run the Cleanup Script

```bash
cd /path/to/bitchat
./scripts/clean-xcode.sh
```

This will clean all Xcode derived data and package caches.

### 2. Check the Build Fix Guide

If you're seeing specific errors, consult:

- **[XCODE_BUILD_FIX.md](../XCODE_BUILD_FIX.md)** - Solutions for specific error messages

### 3. Review P256K Examples

If you need to understand how to use the cryptographic APIs correctly:

- **[P256K_EXAMPLES.md](P256K_EXAMPLES.md)** - Complete examples and patterns

## Common Error Categories

### Cryptographic Errors
- P256K API usage errors
- SHA256Digest conformance issues
- Key format issues (compressed vs x-only)

**Solution**: See [XCODE_BUILD_FIX.md](../XCODE_BUILD_FIX.md#common-errors-and-solutions)

### Type Mismatch Errors
- Delegate type issues
- Optional vs non-optional mismatches
- UUID method errors

**Solution**: See specific error sections in [XCODE_BUILD_FIX.md](../XCODE_BUILD_FIX.md)

### Build Cache Issues
- Stale derived data
- Package resolution problems
- Module cache corruption

**Solution**: Run `./scripts/clean-xcode.sh`

## Files in This Guide

```
bitchat/
├── XCODE_BUILD_FIX.md           # Main troubleshooting guide
├── scripts/
│   └── clean-xcode.sh           # Build cleanup script
└── docs/
    ├── README_BUILD_FIXES.md    # This file
    └── P256K_EXAMPLES.md        # Crypto API examples
```

## Working Code Examples

The following files in the codebase contain working examples of P256K usage:

- `bitchat/Nostr/NostrIdentity.swift` - Key generation and management
- `bitchat/Nostr/NostrProtocol.swift` - Signing, ECDH, encryption
- `bitchat/Noise/NoiseProtocol.swift` - Key agreement patterns

## Still Need Help?

If you're still experiencing build errors after:
1. Running the cleanup script
2. Consulting the error-specific solutions
3. Reviewing the working examples

Then the issue might be:
- Missing file target membership in Xcode
- Incorrect build settings or deployment target
- Incompatible Xcode version (requires Xcode 15.0+)
- Platform-specific issues (macOS vs iOS targets)

Check the Xcode Issue Navigator for detailed error messages and file locations.

## Contributing Fixes

If you discover a new build error and solution, please add it to XCODE_BUILD_FIX.md with:
- Clear error message
- Root cause explanation
- Working solution with code example
