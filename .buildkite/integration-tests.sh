#!/usr/bin/env bash --login --noprofile

# hope this works, since flare's mac worker doesn't have this dep baked in yet...
gem install bundler:2.1.4

source "$(git rev-parse --show-toplevel)"/.buildkite/common.sh
source "$(git rev-parse --show-toplevel)"/.github/workflows/xcode_select.sh

configure_user_bazelrc

# clean
bazel clean

# builds and tests with bazel
bazel test --local_test_jobs=1 -- //... -//tests/ios/...
bazel test --local_test_jobs=1 --apple_platform_type=ios --deleted_packages='' -- //tests/ios/...