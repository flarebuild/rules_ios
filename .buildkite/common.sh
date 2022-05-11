# common shell settings, functions, environment variables
# to include:
# source "$(git rev-parse --show-toplevel)"/.buildkite/common.sh

# this is needed specifically for MacOS buildkite agents to update PATH
source ~/.bashrc

set -o errexit  # Exit immediately if a pipeline ... exits with a non-zero status
set -o pipefail # ... return value of a pipeline is the value of the last (rightmost) command to exit with a non-zero status
set -o nounset  # Treat unset variables ... as an error

# hope this works, since flare's mac worker doesn't have this dep baked in yet...
sudo gem install bundler:2.1.4

function lowercase() {
    echo "$@" | tr '[:upper:]' '[:lower:]'
}

function is_darwin() {
    if [[ $(lowercase $(uname -s)) = "darwin" ]]; then
        return 0
    else
        return 1
    fi
}

# START exit processing
declare -A __on_exit_functions

function __on_exit() {
    local rc=$?
    if [[ ${rc} -eq 0 ]]; then
        echo "--- Run exit commands (exit code ignored)"
    else
        echo "EXIT CODE: ${rc}"
        echo "^^^ +++ Run exit commands (exit code ignored)"
    fi
    for exit_f in "${!__on_exit_functions[@]}"; do
        echo "=== Exit command: ${exit_f}"
        ${exit_f} || true
    done
}

trap __on_exit EXIT SIGINT SIGTERM

# on_exit_add() adds command to run on script exit
# useful for cleanup
function on_exit_add() {
    __on_exit_functions["$@"]=""
}
# END exit processing

# make sure we run from repo root
cd "$(git rev-parse --show-toplevel)"

# fetch tags, buildkite won't do this: https://github.com/buildkite/agent/issues/338
git fetch --tags

[ "${BUILDKITE:-false}" == "true" ] || {
    echo not in Buildkite
    #exit 1
}

if [[ ${BUILDKITE_PULL_REQUEST} != "false" ]]; then
    git fetch origin ${BUILDKITE_PULL_REQUEST_BASE_BRANCH}
    if ! git merge-base --is-ancestor origin/${BUILDKITE_PULL_REQUEST_BASE_BRANCH} HEAD; then
        buildkite-agent annotate --style error "PR ${BUILDKITE_PULL_REQUEST} is out-of-date"
        exit 1
    fi
fi

# this should be done before invoking bazel
is_darwin || gcloud auth configure-docker --quiet

function configure_user_bazelrc() {

    if [[ -n ${FLARE_API_KEY:-} ]]; then
        if [[ ${BAZEL_BES_BACKEND} == grpcs://* ]]; then
            export BAZEL_BES_BACKEND=grpcs://${FLARE_API_KEY}@${BAZEL_BES_BACKEND##grpcs://}
        elif [[ ${BAZEL_BES_BACKEND} == grpc://* ]]; then
            export BAZEL_BES_BACKEND=grpc://${FLARE_API_KEY}@${BAZEL_BES_BACKEND##grpc://}
        else
            export BAZEL_BES_BACKEND=${FLARE_API_KEY}@${BAZEL_BES_BACKEND}
        fi
    fi

    {
        echo startup --output_base=$HOME/bazel_output_base # should we move the whole output_base to tmpfs?

        echo build --config=buildkite

        # local caching, + clean inherited settings
        sed -i -e '/disk_cache/d' -e '/repository_cache/d' .bazelrc            # remove previous settings cause it takes precedence sometimes
        echo build:buildkite --disk_cache= #--disk_cache=$HOME/bazel_disk_cache # https://github.com/bazelbuild/bazel/pull/7512
        echo build:buildkite --repository_cache= --repository_cache=$HOME/bazel_repo_cache

        mkdir -p /ramfs/bazel_sandbox >/dev/null && echo build:buildkite --sandbox_base=/ramfs/bazel_sandbox

        #echo build:buildkite --noshow_progress
        #echo build:buildkite --ui_event_filters=error
        echo build:buildkite --stamp
        echo build:buildkite --noshow_timestamps
        echo build:buildkite --color=yes
        echo build:buildkite --verbose_failures
        echo build:buildkite --isatty=false #actually i think BK's terminal emulator supports this, look into

        if [[ -n ${BAZEL_REMOTE_EXECUTOR_URL:-} ]]; then
            echo build:buildkite --remote_executor=${BAZEL_REMOTE_EXECUTOR_URL}
            echo build:buildkite --define=EXECUTOR=remote
            echo build:buildkite --jobs=100
            echo build:buildkite --remote_default_exec_properties=OSFamily=MacOS
        fi

        echo build:buildkite --remote_cache=${BAZEL_REMOTE_CACHE_URL}
        echo build:buildkite --remote_upload_local_results=true
        echo build:buildkite --bes_backend=${BAZEL_BES_BACKEND}
        echo build:buildkite --bes_results_url="'${BAZEL_BES_RESULTS_URL}'"
        echo build:buildkite --remote_header=x-flare-builduser=buildkite
        echo build:buildkite --remote_header=x-flare-ac-validation-mode=safe # this leaves speed on the table but should prevent build failures
        echo build:buildkite --build_metadata=CI=true
        if [[ -n ${FLARE_API_KEY:-} ]]; then
            echo build:buildkite --remote_header=x-api-key=${FLARE_API_KEY}
            echo build:buildkite --nogoogle_default_credentials
        else
            echo build:buildkite --google_default_credentials
        fi
        #echo build:buildkite --remote_download_toplevel
        echo build:buildkite --remote_max_connections=1000 # speed up reads, maybe
        echo "\n"
    } >"$(git rev-parse --show-toplevel)"/user.bazelrc
}

function bazel_with_flareparse() {
    on_exit_add upload_bazel_logs
    # dont build flareparse in buildkite, it's supposed to be in prepared bk-agent image
    [ "${BUILDKITE:-false}" == "true" ] \
    || bazel build //src/go/cmd/flareparse/parser:flareparse

    local iid=$(uuidgen)

    bazel "$@" --invocation_id=${iid} --flare_annotate --flare_bes_results_url=${BAZEL_BES_RESULTS_URL}
    local bazel_exit_code=$?

    # add annotation to PR on GitHub
    if [[ -n ${GITHUB_BOT_KEY:-} && -n ${FLARE_INSIGHTS_API_URL:-} && -n ${BUILDKITE_PULL_REQUEST:-} ]]; then
        echo "Annotate in PR on GitHub for invocation ${iid} on branch ${BUILDKITE_BRANCH}"
        curl --silent --request POST --header "api-key:${GITHUB_BOT_KEY}" \
        "${FLARE_INSIGHTS_API_URL}/bot/add_annotation?invocationID=${iid}&branch=${BUILDKITE_BRANCH}" \
        || echo "POST failed to: ${FLARE_INSIGHTS_API_URL}/bot/add_annotation?invocationID=${iid}&branch=${BUILDKITE_BRANCH}"
    fi

    return ${bazel_exit_code}
}

# this is needed to change storage.googleapis.com in GCS links
# which is hardcoded here: https://github.com/buildkite/agent/blob/8c761767663fb2eb95907d15f17f0484c1f83848/agent/gs_uploader.go#L98
export BUILDKITE_GCS_ACCESS_HOST=storage.cloud.google.com

# artifact_upload pattern [destination]
# uploads artifacts by pattern, as `buildkite-agent artifact upload` does, but removes directory path
# by default, artifacts are uploaded to ${ARTIFACT_UPLOAD_GCS_BUCKET}/${BUILDKITE_JOB_ID}
# but you can specify custom destination
function artifact_upload() {
    local artifact=$(basename "$1")
    local artifact_dir=$(dirname "$1")
    local destination=${2:-${ARTIFACT_UPLOAD_GCS_BUCKET}/${BUILDKITE_JOB_ID}}
    pushd "${artifact_dir}"
    buildkite-agent artifact upload "${artifact}" "${destination}"
    popd
}

# artifact_upload_gz file [destination]
# uploads single artifact in gz archive, removes directory path
# by default, artifacts are uploaded to ${ARTIFACT_UPLOAD_GCS_BUCKET}/${BUILDKITE_JOB_ID}
# but you can specify custom destination
function artifact_upload_gz() {
    local artifact="$1"; shift
    gzip "${artifact}"
    artifact_upload "${artifact}.gz" "$@"
}

function upload_bazel_logs() {
    [ -d "$HOME/bazel_output_base" ] || return
    {
        set -x
        df
        df -i
        du -sxh $(pwd)/* $HOME/bazel_output_base/*
        ls -latR $HOME/bazel_output_base/
        set +x
    } 2>&1 | gzip >/tmp/output_base.listing.gz
    artifact_upload '/tmp/output_base.listing.gz'
    artifact_upload "$HOME/bazel_output_base/java.log"
    artifact_upload "$HOME/bazel_output_base/command.log"
    artifact_upload "$HOME/bazel_output_base/command.profile.gz"
}

# yarn_install() should be called from inside nodejs project dir somewhere below $HOME
function yarn_install() {
    if [ ! -f package.json ]; then
        echo NOT IN NODEJS PROJECT dir
        return 1
    fi
    local node_modules=${HOME}/node_modules
    export PATH=${PATH}:${node_modules}/.bin
    ln -s ${node_modules} node_modules
    yarn install --modules-folder ${node_modules} --frozen-lockfile
}

function bazel_build_and_test_affected() {
    COMMIT_RANGE=${COMMIT_RANGE:-$(git merge-base origin/master HEAD)".."}
    # Get a list of the current files in package form by querying Bazel.
    files=()
    for file in $(git diff --name-only ${COMMIT_RANGE}); do
        files+=($(bazel query $file))
        echo $(bazel query $file)
    done

    # Query for the associated buildables
    buildables=$(bazel query \
        --keep_going \
        --noshow_progress \
        "kind(.*_binary, rdeps(//..., set(${files[*]})))")
    # Run the tests if there were results
    if [[ ! -z $buildables ]]; then
        echo "Building binaries"
        bazel_with_flareparse build $buildables
    fi

    tests=$(bazel query \
        --keep_going \
        --noshow_progress \
        "kind(test, rdeps(//..., set(${files[*]}))) except attr('tags', 'manual', //...)")
    # Run the tests if there were results
    if [[ ! -z $tests ]]; then
        echo "Running tests"
        bazel_with_flareparse test $tests --test_output=errors --test_tag_filters=-integration
    fi
}

function prepare_kubeconfig() {
    local namespace=commit-${BUILDKITE_COMMIT:0:8}

    on_exit_add kubectl delete ns --wait=false --now=true ${namespace}

    rm -f ~/.kube/config

    kubectl create ns ${namespace}
    kubectl config set-context ${namespace}
    kubectl config use-context ${namespace}
    # cluster name set to docker-desktop to trick tilt that this is a dev cluster
    # see
    # https://github.com/tilt-dev/tilt/blob/77ae37f8f66c4b2d6df5eb526bd71954be73ecf2/internal/tiltfile/k8scontext/k8scontext.go#L90
    # https://github.com/tilt-dev/tilt/blob/bc91f220fe235c9e421577b714e6fd76c7cbf780/internal/k8s/env.go#L99
    kubectl config set-cluster 'docker-desktop' \
      --server=https://kubernetes.default.svc \
      --embed-certs --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    kubectl config set-credentials ${namespace} --token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    kubectl config set-context --current --namespace=${namespace} --user=${namespace} --cluster=docker-desktop
}