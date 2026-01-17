#!/bin/bash

# Xcode Build Cleanup Script for Bitchat
# This script cleans Xcode derived data and package caches
# to fix common build errors

set -e

echo "🧹 Cleaning Xcode Build Artifacts for Bitchat..."
echo ""

# Get the project directory (parent of scripts directory)
PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$PROJECT_DIR"

echo "📁 Project directory: $PROJECT_DIR"
echo ""

# Clean Xcode DerivedData
echo "🗑️  Cleaning DerivedData..."
rm -rf ~/Library/Developer/Xcode/DerivedData/bitchat-* 2>/dev/null || true
echo "✅ DerivedData cleaned"
echo ""

# Clean local .build directory
if [ -d "$PROJECT_DIR/.build" ]; then
    echo "🗑️  Cleaning local .build directory..."
    rm -rf "$PROJECT_DIR/.build"
    echo "✅ .build directory cleaned"
    echo ""
fi

# Clean Swift Package Manager caches
echo "🗑️  Cleaning SPM caches..."
rm -rf ~/Library/Caches/org.swift.swiftpm 2>/dev/null || true
echo "✅ SPM caches cleaned"
echo ""

# Clean Package.resolved to force fresh resolution
if [ -f "$PROJECT_DIR/Package.resolved" ]; then
    echo "🗑️  Removing Package.resolved..."
    rm "$PROJECT_DIR/Package.resolved"
    echo "✅ Package.resolved removed"
    echo ""
fi

# Clean Xcode build products
if [ -d "$PROJECT_DIR/build" ]; then
    echo "🗑️  Cleaning build directory..."
    rm -rf "$PROJECT_DIR/build"
    echo "✅ build directory cleaned"
    echo ""
fi

# Clean module cache
echo "🗑️  Cleaning module cache..."
rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex 2>/dev/null || true
echo "✅ Module cache cleaned"
echo ""

echo "✨ All build artifacts cleaned!"
echo ""
echo "Next steps:"
echo "1. Open bitchat.xcodeproj in Xcode"
echo "2. In Xcode menu: Product → Clean Build Folder (⇧⌘K)"
echo "3. In Xcode menu: File → Packages → Reset Package Caches"
echo "4. In Xcode menu: File → Packages → Resolve Package Versions"
echo "5. Build the project: Product → Build (⌘B)"
echo ""
echo "If you still see errors, check XCODE_BUILD_FIX.md for specific error solutions."
