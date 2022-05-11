#!/usr/bin/env bash --login --noprofile

source "$(git rev-parse --show-toplevel)"/.buildkite/common.sh
source "$(git rev-parse --show-toplevel)"/.github/workflows/xcode_select.sh

configure_user_bazelrc

# clean
bazel clean

# builds and tests with bazel
bazel_with_flareparse test --local_test_jobs=1 -- //... -//tests/ios/...
bazel_with_flareparse test --local_test_jobs=1 --apple_platform_type=ios --deleted_packages='' -- //tests/ios/...