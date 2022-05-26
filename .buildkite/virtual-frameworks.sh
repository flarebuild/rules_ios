#!/usr/bin/env bash --login --noprofile

source "$(git rev-parse --show-toplevel)"/.buildkite/common.sh
source "$(git rev-parse --show-toplevel)"/.github/workflows/xcode_select.sh

configure_user_bazelrc

# clean
bazel clean

# builds and tests with bazel

# Host config
bazel build --features apple.virtualize_frameworks --local_test_jobs=1 -- //... -//tests/ios/...

# `deleted_packages` is needed below in order to override the value of the .bazelrc file
bazel build --features apple.virtualize_frameworks \
    --local_test_jobs=1 \
    --apple_platform_type=ios \
    --deleted_packages='' \
    -- //tests/ios/... \
    -//tests/ios/frameworks/sources-with-prebuilt-binaries/... # Needs more work for pre-built binaries
