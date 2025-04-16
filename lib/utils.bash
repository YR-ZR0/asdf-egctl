#!/usr/bin/env bash

set -euo pipefail

GH_REPO="https://github.com/envoyproxy/gateway"
TOOL_NAME="egctl"
TOOL_TEST="egctl -version"

fail() {
	echo -e "asdf-$TOOL_NAME: $*"
	exit 1
}

curl_opts=(-fsSL)

# NOTE: You might want to remove this if <YOUR TOOL> is not hosted on GitHub releases.
if [ -n "${GITHUB_API_TOKEN:-}" ]; then
	curl_opts=("${curl_opts[@]}" -H "Authorization: token $GITHUB_API_TOKEN")
fi

sort_versions() {
	sed 'h; s/[+-]/./g; s/.p\([[:digit:]]\)/.z\1/; s/$/.z/; G; s/\n/ /' |
		LC_ALL=C sort -t. -k 1,1 -k 2,2n -k 3,3n -k 4,4n -k 5,5n | awk '{print $2}'
}

list_github_tags() {
	git ls-remote --tags --refs "$GH_REPO" |
		grep -o 'refs/tags/.*' | cut -d/ -f3- |
		sed 's/^v//' # NOTE: You might want to adapt this sed to remove non-version strings from tags
}

list_all_versions() {
	# TODO: Adapt this. By default we simply list the tag names from GitHub releases.
	# Change this function if <YOUR TOOL> has other means of determining installable versions.
	list_github_tags
}

# Detection based on the official install script
get_platform() {
platform=''
machine=$(uname -m)
case "$(uname -s | tr '[:upper:]' '[:lower:]')" in
"linux")
	case "$machine" in
	"arm64"* | "aarch64"* ) platform='linux-arm64' ;;
	"arm"* | "aarch"*) platform='linux-arm' ;;
	*"64") platform='linux64' ;;
	*) fail "Architecture not supported: $machine" ;;
	esac
	;;
"darwin") platform='osx' ;;
*) fail "OS not supported: $(uname -s)" ;;
esac
echo $platform
}

download_release() {
    local version filename url
    version="$1"
    filename="$2"
    os=$(get_platform)
    arch="amd64"  # Default architecture

    # Map platform to the correct OS name
    case "$os" in
    "linux64")
        os="linux"
        arch="amd64"
        ;;
    "linux-arm64")
        os="linux"
        arch="arm64"
        ;;
    "osx")
        os="darwin"
        arch="amd64"
        ;;
    *)
        fail "Platform not supported: $os"
        ;;
    esac

    if [[ "$version" == "latest" ]]; then
        # For latest version, get the latest tag first
        url="$GH_REPO/releases/download/$version/${TOOL_NAME}_${version}_${os}_${arch}.tar.gz"
    else
        url="$GH_REPO/releases/download/v${version}/${TOOL_NAME}_v${version}_${os}_${arch}.tar.gz"
    fi

    echo "* Downloading $TOOL_NAME release $version..."
    echo "* URL: $url"
    curl "${curl_opts[@]}" -o "$filename" -C - "$url" || fail "Could not download $url"
}

install_version() {
	local install_type="$1"
	local version="$2"
	local install_path="${3%/bin}/bin"

	if [ "$install_type" != "version" ]; then
		fail "asdf-$TOOL_NAME supports release installs only"
	fi

	(
		mkdir -p "$install_path"
		cp -r "$ASDF_DOWNLOAD_PATH"/* "$install_path"

		local tool_cmd
		tool_cmd="$(echo "$TOOL_TEST" | cut -d' ' -f1)"
		test -x "$install_path/$tool_cmd" || fail "Expected $install_path/$tool_cmd to be executable."

		echo "$TOOL_NAME $version installation was successful!"
	) || (
		rm -rf "$install_path"
		fail "An error occurred while installing $TOOL_NAME $version."
	)
}

