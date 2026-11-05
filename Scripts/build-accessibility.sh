#!/bin/sh
# Builds Perry's Accessibility on a Mac with Xcode: Darwin/Accessibility,
# the Swift part of Apple's Accessibility.framework that attributed text
# needs (its attribute scope, which SwiftUI's holds), as
# Accessibility.framework/Accessibility in the directory given (see
# build-framework.sh).
#
# Usage: Scripts/build-accessibility.sh [output directory]
#   default output: .build/perry-swift-runtime
TARGET=${TARGET:-arm64-apple-ios15.0} exec "$(dirname "$0")/build-framework.sh" Accessibility "$@"
