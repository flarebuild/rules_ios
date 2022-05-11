#!/usr/bin/env bash --login --noprofile

source "$(git rev-parse --show-toplevel)"/.buildkite/common.sh
source "$(git rev-parse --show-toplevel)"/.github/workflows/xcode_select.sh

configure_user_bazelrc

# clean
bazel clean

bazel build -s tests/ios/app/App --apple_platform_type=ios --ios_minimum_os=10.2  --ios_multi_cpus=i386,x86_64
