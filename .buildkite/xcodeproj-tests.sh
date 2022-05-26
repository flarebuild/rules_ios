#!/usr/bin/env bash --login --noprofile

source "$(git rev-parse --show-toplevel)"/.buildkite/common.sh
source "$(git rev-parse --show-toplevel)"/.github/workflows/xcode_select.sh

configure_user_bazelrc

# clean
bazel clean

"$(git rev-parse --show-toplevel)"/tests/xcodeproj-tests.sh --clean