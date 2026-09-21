# shellcheck shell=bash
# dot-runtime-resolve.sh — shared Dot runtime resolution for the CI wrappers.
#
# Sourced (never executed) by stack-dot-runtime, run-ci-candidate-home, run-ci,
# and the suites that must accept both Dot layouts. Dependency-free pure shell:
# only POSIX utilities plus curl, git, and tar on the release path.
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

# Extract the release tag from a curl effective URL. /releases/latest follows
# its redirect to /releases/tag/<tag>; a repository with no releases lands on
# /releases instead, which is a distinct fail-closed error, not a tag.
_dot_release_tag_from_effective_url() {
  local url=${1:-} tag=${1##*/}
  if [[ $url == */releases && $tag == releases ]]; then
    printf 'dot-runtime-resolve: repository has no releases yet: %s\n' \
      "$url" >&2
    return 1
  fi
  _dot_release_tag_valid "$tag" || {
    printf 'dot-runtime-resolve: unexpected release redirect: %s\n' \
      "$url" >&2
    return 1
  }
  printf '%s\n' "$tag"
}

# Resolve the latest release tag for owner/repo $1 (default cgraf78/dot) via
# the anonymous web redirect. This intentionally avoids api.github.com: CI has
# no token and the matrix would exhaust the unauthenticated API quota.
_dot_release_latest_tag() {
  local repo=${1:-cgraf78/dot} effective rc=0
  case $repo in
    *[!A-Za-z0-9._/-]* | */*/* | /* | */ | *..*)
      printf 'dot-runtime-resolve: invalid release repository: %s\n' \
        "$repo" >&2
      return 1
      ;;
  esac
  effective=$(curl -fsSIL -o /dev/null -w '%{url_effective}' \
    --retry 2 --retry-delay 2 --retry-max-time 65 --retry-all-errors \
    "https://github.com/$repo/releases/latest") || rc=$?
  [[ $rc -eq 0 ]] || {
    printf 'dot-runtime-resolve: could not resolve latest release for %s (curl exit %s)\n' \
      "$repo" "$rc" >&2
    return 1
  }
  _dot_release_tag_from_effective_url "$effective"
}

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

# Download asset $2 at tag $3 for platform $4 from release base $1 into $5.
# Base is https://github.com/<repo> in production; unit tests pass a file://
# fixture tree with the same releases/download/<tag>/ layout. Verifies the
# published .sha256 sidecar before extracting, and only into an empty dir.
_dot_release_fetch() {
  local base=${1:-} asset=${2:-} tag=${3:-} platform=${4:-} dest=${5:-}
  local scratch tarball sidecar sum_bin
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
  if command -v sha256sum >/dev/null 2>&1; then
    sum_bin=sha256sum
  elif command -v shasum >/dev/null 2>&1; then
    sum_bin='shasum -a 256'
  else
    printf 'dot-runtime-resolve: sha256sum or shasum is required\n' >&2
    return 1
  fi
  tarball=$asset-$tag-$platform.tar.gz
  sidecar=$tarball.sha256
  scratch=$(mktemp -d) || return 1
  # The scratch download must never survive into the extracted runtime.
  trap 'rm -rf -- "$scratch"' RETURN
  curl --fail --silent --show-error --location \
    --connect-timeout 10 --max-time 120 \
    --retry 2 --retry-delay 2 --retry-max-time 65 --retry-all-errors \
    "$base/releases/download/$tag/$tarball" -o "$scratch/$tarball" || {
    printf 'dot-runtime-resolve: could not download %s\n' "$tarball" >&2
    return 1
  }
  curl --fail --silent --show-error --location \
    --connect-timeout 10 --max-time 60 \
    --retry 2 --retry-delay 2 --retry-max-time 65 --retry-all-errors \
    "$base/releases/download/$tag/$sidecar" -o "$scratch/$sidecar" || {
    printf 'dot-runtime-resolve: could not download %s\n' "$sidecar" >&2
    return 1
  }
  # shellcheck disable=SC2086 # The checksum command is selected above.
  (cd "$scratch" && $sum_bin -c "$sidecar") >/dev/null || {
    printf 'dot-runtime-resolve: checksum mismatch for %s\n' "$tarball" >&2
    return 1
  }
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
  trap - RETURN
  rm -rf -- "$scratch"
}

# Print the 12-hex short revision from `$1 version`, e.g.
# `dot commit 41e0dcd55ae0 (config 1; extensions 1; library 1)`.
# `unknown` builds fail closed: an unidentified binary cannot bind to a tag.
_dot_release_version_short12() {
  local bin=${1:-} output line
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
  [[ $line =~ ^dot\ commit\ ([0-9a-f]{12})\ \( ]] || {
    printf 'dot-runtime-resolve: unexpected version line: %s\n' \
      "${line:-<empty>}" >&2
    return 1
  }
  printf '%s\n' "${BASH_REMATCH[1]}"
}

# Verify release root $1 was built from tag $2 for platform $3 at commit
# $4: native binary present, its short12 bound to both the tag suffix and
# the commit prefix, and the packaged install metadata agreeing when
# present. The platform binding catches a mislabeled archive before any
# consumer tries to execute a foreign binary.
_dot_release_verify_root() {
  local root=${1:-} tag=${2:-} platform=${3:-} sha=${4:-}
  local short meta meta_sha meta_platform meta_version
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
  short=$(_dot_release_version_short12 "$root/dot") || return 1
  [[ $short == "${tag##*-}"* && $sha == "$short"* ]] || {
    printf 'dot-runtime-resolve: binary %s does not match tag %s\n' \
      "$short" "$tag" >&2
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
