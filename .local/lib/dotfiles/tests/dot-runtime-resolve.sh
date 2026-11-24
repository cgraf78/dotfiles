# shellcheck shell=bash
# dot-runtime-resolve.sh — shared Dot runtime resolution for the CI wrappers.
#
# Sourced (never executed) by stack-dot-runtime, run-ci-candidate-home, run-ci,
# and the suites that must accept both Dot layouts. jq enables authenticated
# transport for GitHub assets when the caller supplies a token.
#
# Two layouts exist after the dot Rust cutover:
#   git checkout  — $root/bin/dot plus a .git directory (explicit revisions).
#   release root  — $root/dot native binary, lib/dot/public payload, no .git
#                   (revision `latest`, consumed from a published release).
# Every predicate and resolver here fails closed with a diagnostic on stderr.

# True when $1 is a release root: native binary at the top level, the public
# API payload beside it, and no Git checkout metadata. Release archives stage
# the binary at the archive root (RELEASE_BINARY_DEST defaults to $BINARY).
_dot_runtime_is_release_root() {
  local root=${1:-}
  [[ -n $root && -x $root/dot && ! -L $root/dot && ! -e $root/.git &&
    -r $root/lib/dot/public/xdg.sh ]]
}

# Print the release asset platform label for a runner. Optional arguments
# override live uname probing so unit tests can cover every runner shape
# without forking per-platform shells.
_dot_runtime_release_platform() {
  local kernel=${1:-$(uname -s)} machine=${2:-$(uname -m)}
  local system=${3:-$(uname -o 2>/dev/null || true)} arch

  # Termux reports Android through uname -o; the PREFIX spelling is the
  # established fallback (see android-ci-smoke) for minimal uname builds.
  if [[ $system == Android || ${PREFIX:-} == *com.termux*/usr ]]; then
    case $machine in
      x86_64) arch=x86_64 ;;
      aarch64 | arm64) arch=aarch64 ;;
      *)
        printf 'dot-runtime-resolve: unsupported Android architecture: %s\n' \
          "$machine" >&2
        return 1
        ;;
    esac
    printf 'android-%s\n' "$arch"
    return 0
  fi

  case $kernel in
    Linux) ;;
    Darwin) ;;
    *)
      printf 'dot-runtime-resolve: unsupported kernel: %s\n' "$kernel" >&2
      return 1
      ;;
  esac
  case $machine in
    x86_64) arch=x86_64 ;;
    # Apple Silicon reports arm64; Linux reports aarch64 for the same ISA.
    aarch64 | arm64) arch=aarch64 ;;
    *)
      printf 'dot-runtime-resolve: unsupported %s architecture: %s\n' \
        "$kernel" "$machine" >&2
      return 1
      ;;
  esac
  case $kernel in
    Linux) printf 'linux-%s-musl\n' "$arch" ;;
    Darwin)
      case $arch in
        x86_64) printf 'macos-x86_64\n' ;;
        *) printf 'macos-aarch64\n' ;;
      esac
      ;;
  esac
}

# True when $1 is a release tag: UTC stamp plus the 8-hex commit suffix the
# shared release scheme derives from the tagged commit.
_dot_release_tag_valid() {
  [[ ${1:-} =~ ^[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$ ]]
}

# Use the lock-checked capability harness for the anonymous latest lookup.
_dot_release_latest_tag() (
  # shellcheck source=capability-harness/dot-release.sh
  . "${BASH_SOURCE[0]%/*}/capability-harness/dot-release.sh" || return
  capability_dot_release_latest_tag "${1:-cgraf78/dot}"
)

# Print the full commit SHA a release tag points at. The shared scheme tags
# the commit directly (lightweight), but an annotated tag would answer with
# the tag object first, so always prefer the peeled ^{commit} line. The tag
# suffix must equal the commit prefix: that binding is what makes a poisoned
# Git configuration useless (an attacker cannot mint a colliding prefix).
_dot_release_commit_for_tag() {
  local repo=${1:-} tag=${2:-} line sha
  [[ -n $repo ]] || {
    printf 'dot-runtime-resolve: missing repository for tag lookup\n' >&2
    return 1
  }
  _dot_release_tag_valid "$tag" || {
    printf 'dot-runtime-resolve: invalid release tag: %s\n' \
      "${tag:-<empty>}" >&2
    return 1
  }
  # ls-remote is a read-only remote operation; scrub caller Git configuration
  # the same way the wrappers do so inherited rewrites cannot redirect it.
  line=$(env -u GIT_CONFIG -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS \
    -u GIT_NAMESPACE -u GIT_PREFIX \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_NO_REPLACE_OBJECTS=1 \
    git --no-replace-objects ls-remote "$repo" \
    "refs/tags/$tag" "refs/tags/$tag^{}" 2>/dev/null) || {
    printf 'dot-runtime-resolve: could not read tag %s from %s\n' \
      "$tag" "$repo" >&2
    return 1
  }
  sha=$(printf '%s\n' "$line" |
    awk '$2 ~ /\^\{\}$/ { peeled = $1 } $2 !~ /\^/ { plain = $1 }
      END { if (peeled != "") print peeled; else if (plain != "") print plain }')
  [[ $sha =~ ^[0-9a-f]{40}$ && $sha == "${tag##*-}"* ]] || {
    printf 'dot-runtime-resolve: tag %s does not resolve to its commit\n' \
      "$tag" >&2
    return 1
  }
  printf '%s\n' "$sha"
}

# CI's GitHub downloads use the shared, lock-checked transport. Custom bases,
# including file:// fixtures, keep their exact URL and never receive a token.
_dot_release_asset() {
  local base=$1 tag=$2 filename=$3 output=$4 seconds=$5
  local -a options=(--connect-timeout 10 --max-time "$seconds"
    --retry 2 --retry-delay 2 --retry-max-time 65 --retry-all-errors)
  case $base in
    https://github.com/*) (
      # shellcheck source=capability-harness/github-release.sh
      . "${BASH_SOURCE[0]%/*}/capability-harness/github-release.sh" || return
      github_release_download "${base#https://github.com/}" "$tag" "$filename" \
        "$output" "${options[@]}"
    ) ;;
    *)
      curl -q --fail --silent --show-error --location "${options[@]}" \
        "$base/releases/download/$tag/$filename" -o "$output"
      ;;
  esac
}

# Download asset $2 at tag $3 for platform $4 from release base $1 into $5.
# Base is https://github.com/<repo> in production; unit tests pass a file://
# fixture tree with the same releases/download/<tag>/ layout. Verifies the
# published .sha256 sidecar before extracting, and only into an empty dir.
_dot_release_fetch() (
  # shellcheck source=capability-harness/dot-release.sh
  . "${BASH_SOURCE[0]%/*}/capability-harness/dot-release.sh" || return
  local base=${1:-} asset=${2:-} tag=${3:-} platform=${4:-} dest=${5:-}
  local scratch tarball sidecar
  [[ -n $base && -n $asset && -n $dest ]] || {
    printf 'dot-runtime-resolve: missing fetch arguments\n' >&2
    return 1
  }
  _dot_release_tag_valid "$tag" || {
    printf 'dot-runtime-resolve: invalid release tag: %s\n' \
      "${tag:-<empty>}" >&2
    return 1
  }
  case $asset in
    *[!A-Za-z0-9._-]*)
      printf 'dot-runtime-resolve: unsafe asset name: %s\n' "$asset" >&2
      return 1
      ;;
  esac
  case $platform in
    *[!A-Za-z0-9._-]* | "")
      printf 'dot-runtime-resolve: unsafe asset platform: %s\n' \
        "${platform:-<empty>}" >&2
      return 1
      ;;
  esac
  [[ -d $dest ]] || {
    printf 'dot-runtime-resolve: missing destination directory: %s\n' \
      "$dest" >&2
    return 1
  }
  [[ -z $(ls -A "$dest") ]] || {
    printf 'dot-runtime-resolve: refusing to extract into a nonempty directory: %s\n' \
      "$dest" >&2
    return 1
  }
  tarball=$asset-$tag-$platform.tar.gz
  sidecar=$tarball.sha256
  scratch=$(mktemp -d) || return 1
  # The scratch download must never survive either an early error or
  # successful extraction, and its cleanup belongs to this subshell.
  trap 'rm -rf -- "$scratch"' EXIT
  _dot_release_asset "$base" "$tag" "$tarball" "$scratch/$tarball" 120 || {
    printf 'dot-runtime-resolve: could not download %s\n' "$tarball" >&2
    return 1
  }
  _dot_release_asset "$base" "$tag" "$sidecar" "$scratch/$sidecar" 60 || {
    printf 'dot-runtime-resolve: could not download %s\n' "$sidecar" >&2
    return 1
  }
  capability_dot_release_verify_checksum "$scratch/$tarball" "$scratch/$sidecar" || return
  tar -xzf "$scratch/$tarball" -C "$dest" || {
    printf 'dot-runtime-resolve: could not extract %s\n' "$tarball" >&2
    return 1
  }
  # An upstream archive must never ship shdeps' own ownership marker; one
  # that does would masquerade as provider state during later cleanup.
  if [[ -e $dest/.shdeps-release-layout || -L $dest/.shdeps-release-layout ]]; then
    printf 'dot-runtime-resolve: archive ships reserved shdeps marker\n' >&2
    return 1
  fi
)

# Print the release version tag from `$1 version`, e.g.
# `dot 20260914-103531-41e0dcd5 (config 1; extensions 1; library 1)`.
# The binary reports the same public version string release tags, archive
# names, and installer metadata use (dot #190). `unknown` and garbage lines
# fail closed: an unidentified binary cannot bind to a tag.
_dot_release_version_tag() {
  local bin=${1:-} output line version
  [[ -x $bin && ! -L $bin && ! -d $bin ]] || {
    printf 'dot-runtime-resolve: not an executable binary: %s\n' \
      "${bin:-<empty>}" >&2
    return 1
  }
  output=$("$bin" version 2>/dev/null) || {
    printf 'dot-runtime-resolve: %s version failed\n' "$bin" >&2
    return 1
  }
  line=${output%%$'\n'*}
  [[ $line =~ ^dot\ ([0-9]{8}-[0-9]{6}-[0-9a-f]{8})\ \( ]] || {
    printf 'dot-runtime-resolve: unexpected version line: %s\n' \
      "${line:-<empty>}" >&2
    return 1
  }
  version=${BASH_REMATCH[1]}
  _dot_release_tag_valid "$version" || {
    printf 'dot-runtime-resolve: unexpected version line: %s\n' \
      "${line:-<empty>}" >&2
    return 1
  }
  printf '%s\n' "$version"
}

# Verify release root $1 was built from tag $2 for platform $3 at commit
# $4: native binary present, its version tag equal to the requested tag with
# its suffix bound to the commit prefix, and the packaged install metadata
# agreeing when present. The platform binding catches a mislabeled archive
# before any consumer tries to execute a foreign binary.
_dot_release_verify_root() {
  local root=${1:-} tag=${2:-} platform=${3:-} sha=${4:-}
  local version meta meta_sha meta_platform meta_version
  _dot_runtime_is_release_root "$root" || {
    printf 'dot-runtime-resolve: not a release root: %s\n' \
      "${root:-<empty>}" >&2
    return 1
  }
  _dot_release_tag_valid "$tag" || {
    printf 'dot-runtime-resolve: invalid release tag: %s\n' \
      "${tag:-<empty>}" >&2
    return 1
  }
  [[ $sha =~ ^[0-9a-f]{40}$ ]] || {
    printf 'dot-runtime-resolve: invalid release commit: %s\n' \
      "${sha:-<empty>}" >&2
    return 1
  }
  version=$(_dot_release_version_tag "$root/dot") || return 1
  [[ $version == "$tag" && $sha == "${version##*-}"* ]] || {
    printf 'dot-runtime-resolve: binary %s does not match tag %s\n' \
      "$version" "$tag" >&2
    return 1
  }
  # The packager records the built commit, tag, and platform in
  # .dot-install.json. A present but disagreeing record means a mixed or
  # tampered payload; an absent record leaves the version binding above as
  # the authority.
  meta=$root/.dot-install.json
  if [[ -f $meta && ! -L $meta ]]; then
    # A missing key must fall through to the comparisons below (which report
    # it) instead of tripping the caller's `set -e`.
    meta_sha=$(grep -o '"commit"[[:space:]]*:[[:space:]]*"[0-9a-f]*"' \
      "$meta" | head -n 1 | grep -o '[0-9a-f]*"$' | tr -d '"' || true)
    [[ $meta_sha == "$sha" ]] || {
      printf 'dot-runtime-resolve: install metadata disagrees with %s\n' \
        "$sha" >&2
      return 1
    }
    meta_version=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' \
      "$meta" | head -n 1 | sed 's/^[^"]*"[^"]*"[^"]*"//; s/"$//' || true)
    [[ $meta_version == "$tag" ]] || {
      printf 'dot-runtime-resolve: install metadata version %s disagrees with %s\n' \
        "${meta_version:-<empty>}" "$tag" >&2
      return 1
    }
    meta_platform=$(grep -o '"artifact_platform"[[:space:]]*:[[:space:]]*"[^"]*"' \
      "$meta" | head -n 1 | sed 's/^[^"]*"[^"]*"[^"]*"//; s/"$//' || true)
    [[ $meta_platform == "$platform" ]] || {
      printf 'dot-runtime-resolve: install metadata platform %s disagrees with %s\n' \
        "${meta_platform:-<empty>}" "$platform" >&2
      return 1
    }
  fi
}

# Populate release install $2 from release root $1. Plain copy (no Git): the
# stack already verified the source, and the caller re-verifies the binary.
_dot_runtime_install_copy() {
  local source=${1:-} install=${2:-}
  _dot_runtime_is_release_root "$source" || {
    printf 'dot-runtime-resolve: not a release root: %s\n' \
      "${source:-<empty>}" >&2
    return 1
  }
  [[ -n $install ]] || {
    printf 'dot-runtime-resolve: missing install destination\n' >&2
    return 1
  }
  mkdir -p "$install" || return 1
  [[ -z $(ls -A "$install") ]] || {
    printf 'dot-runtime-resolve: refusing to install into a nonempty directory: %s\n' \
      "$install" >&2
    return 1
  }
  cp -R "$source/." "$install"/ || return 1
  # The tarball ships the binary 0755; restore that mode explicitly so the
  # copy matches a Git checkout even under a restrictive caller umask.
  chmod 0755 "$install/dot" || return 1
  # A shdeps archive install writes its layout marker at switch time; the
  # fixture copy does the same so later provider runs classify this root
  # exactly like a fleet install.
  printf 'v1 archive\n' >"$install/.shdeps-release-layout" || return 1
  _dot_runtime_is_release_root "$install" || {
    printf 'dot-runtime-resolve: invalid installed release root: %s\n' \
      "$install" >&2
    return 1
  }
}

# Print the caller token value an isolated cross-check install may use for
# $1 (GH_TOKEN or GITHUB_TOKEN). The caller forwards its own token only by
# opting in with SHDEPS_ALLOW_GH_AUTH_TOKEN=1: shared CI egress would
# otherwise exhaust the unauthenticated api.github.com quota and the
# install degrades to cached data. Without the opt-in print nothing, so a
# blanked assignment keeps the install proving it needs no credentials.
_dot_cross_check_token() {
  local name=${1:-}
  [[ "${SHDEPS_ALLOW_GH_AUTH_TOKEN:-}" == "1" ]] || return 0
  case $name in
    GH_TOKEN) printf '%s' "${GH_TOKEN:-}" ;;
    GITHUB_TOKEN) printf '%s' "${GITHUB_TOKEN:-}" ;;
  esac
}
