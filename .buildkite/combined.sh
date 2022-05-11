#!/usr/bin/env bash --login --noprofile

source "$(git rev-parse --show-toplevel)"/.buildkite/common.sh
source "$(git rev-parse --show-toplevel)"/.github/workflows/xcode_select.sh

configure_user_bazelrc

# clean
bazel clean

# all build steps from github combined:

cd $(git rev-parse --show-toplevel)

# from arm64
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
# from multi-arch
bazel build -s tests/ios/app/App --apple_platform_type=ios --ios_minimum_os=10.2  --ios_multi_cpus=i386,x86_64
# from virtual frameworks
bazel build --features apple.virtualize_frameworks --local_test_jobs=1 -- //... -//tests/ios/...
# `deleted_packages` is needed below in order to override the value of the .bazelrc file
bazel build --features apple.virtualize_frameworks \
    --local_test_jobs=1 \
    --apple_platform_type=ios \
    --deleted_packages='' \
    -- //tests/ios/... \
    -//tests/ios/frameworks/sources-with-prebuilt-binaries/... # Needs more work for pre-built binaries

# from integration tests
bazel test --local_test_jobs=1 --apple_platform_type=ios --deleted_packages='' -- //tests/ios/...
bazel test --local_test_jobs=1 -- //... -//tests/ios/...
# from xcodeproj tests
./tests/xcodeproj-tests.sh --clean
# from lldb tests
export BAZEL_BIN_SUBDIR=/tests/ios/lldb/app
bazel test tests/ios/lldb/app:objc_app_po_test  tests/ios/lldb/app:objc_app_variable_test --config lldb_ios_test
