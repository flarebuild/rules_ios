#!/usr/bin/env bash --login --noprofile

source "$(git rev-parse --show-toplevel)"/.buildkite/common.sh
source "$(git rev-parse --show-toplevel)"/.github/workflows/xcode_select.sh

configure_user_bazelrc

# clean
bazel clean

export BAZEL_BIN_SUBDIR=/tests/ios/lldb/app
bazel test tests/ios/lldb/app:objc_app_po_test  tests/ios/lldb/app:objc_app_variable_test --config lldb_ios_test