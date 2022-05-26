#!/usr/bin/env bash --login --noprofile

source "$(git rev-parse --show-toplevel)"/.buildkite/common.sh
source "$(git rev-parse --show-toplevel)"/.github/workflows/xcode_select.sh

configure_user_bazelrc

# clean
bazel clean

# builds and tests with bazel

bazel build --ios_multi_cpus=sim_arm64  --features apple.virtualize_frameworks -- //... -//tests/ios/...

# Misc issues:
# Carthage is busted for -//tests/ios/frameworks/sources-with-prebuilt-binaries/...
# Fails on a non fat framework for //tests/ios/unit-test/test-imports-app/
bazel build --ios_multi_cpus=sim_arm64 --features apple.virtualize_frameworks \
    --apple_platform_type=ios \
    --deleted_packages='' \
    -- //tests/ios/... \
    -//tests/ios/frameworks/sources-with-prebuilt-binaries/... \
    -//tests/ios/unit-test/test-imports-app/...
