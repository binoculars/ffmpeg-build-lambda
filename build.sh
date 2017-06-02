#!/usr/bin/env bash

set -ev
ROOT=`pwd`
NUM_CORES=2

if [[ "$TRAVIS_EVENT_TYPE" == 'cron' ]] || [[ `git --no-pager log -1 --oneline` == *'[cron debug]'* ]]; then
	REPO=`git config remote.origin.url`
	SSH_REPO=${REPO/https:\/\/github.com\//git@github.com:}

	chmod 600 deploy_key
	eval `ssh-agent -s`
	ssh-add deploy_key

	TODAY=`date -u +%F`

	git fetch --tags
	git submodule foreach 'git checkout master && git fetch origin master --tags && git pull'

	if [[ -n `git status -s` ]]; then
		git commit -am "Update to latest master on all for $TODAY"
	fi

	# Gather tags latest non-nightly tags for the main repo and FFmpeg submodule
	MAIN_LATEST_TAG=`git tag | xargs -I@ git log --format=format:"%ai @%n" -1 @ | sort -r | awk '{print $4}' | grep -v "nightly*" | head -1`
	cd ffmpeg
	FFMPEG_LATEST_TAG=`git tag | xargs -I@ git log --format=format:"%ai @%n" -1 @ | sort -r | awk '{print $4}' | head -1`
	cd ..

	# Tag the nightly release
	TAG_NAME_TODAY="nightly-$TODAY"
	if ! git rev-parse -q --verify "refs/tags/$TAG_NAME_TODAY" >/dev/null; then
		git tag -a "$TAG_NAME_TODAY" -m "Nightly build for $TODAY"
	fi

	# If the FFmpeg repo has a newer tag, create a tag for this repo
	if [ "$MAIN_LATEST_TAG" != "$FFMPEG_LATEST_TAG" ] && ! git rev-parse -q --verify "refs/tags/$MAIN_LATEST_TAG" >/dev/null; then
		git checkout -b "release/$FFMPEG_LATEST_TAG"
		git submodule foreach $'git checkout $(git tag | xargs -I@ git log --format=format:"%ai @%n" -1 @ | sort -r | awk \'{print $4}\' | head -1)'
		MSG="Release for FFmpeg $FFMPEG_LATEST_TAG"$'\n'`git submodule foreach --quiet 'echo "$name: $(git describe --tags --abbrev=0)"'`
		git commit -am "${MSG[@]}"
		git tag -a "$FFMPEG_LATEST_TAG" -m "${MSG[@]}"
	fi

	# Push updated repo and tags
	git push "$SSH_REPO" master --tags

	exit 0;
fi

# libx265
cd "$ROOT/x265/build/linux"
PATH="$HOME/bin:$PATH" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DENABLE_SHARED:bool=off ../../source
make -j "$NUM_CORES"
make install

# libvpx
cd "$ROOT/libvpx"
PATH="$HOME/bin:$PATH" ./configure --prefix="$HOME/ffmpeg_build" --disable-examples --disable-unit-tests
PATH="$HOME/bin:$PATH" make -j "$NUM_CORES"
make install
make clean

args=(
	--disable-shared
	--enable-static
	--disable-debug
	--disable-runtime-cpudetect
	--disable-ffplay
	--disable-ffserver
	--disable-doc
	--disable-network
	--disable-devices

	# Protocols
	--disable-protocols
	--enable-protocol=file
	--enable-protocol=pipe
	--enable-protocol=tee
	--enable-protocol=http

	# Libraries
	--enable-libmp3lame
	--enable-libvpx
	--enable-libwebp
	--enable-libopus
	--enable-fontconfig
	--enable-gray
	--enable-libfreetype
	--enable-libmp3lame
	--enable-libopenjpeg
	--enable-libspeex
	--enable-libtheora
	--enable-libvorbis
	#--enable-libsoxr
	#--enable-libfribidi

	# GPL
	--enable-gpl
	--enable-frei0r
	--enable-libx264
	--enable-libx265
	--enable-libxvid

	# GPLv3
	--enable-version3
	--enable-libopencore-amrnb
	--enable-libopencore-amrwb
	--enable-libvo-amrwbenc
)

cd "$ROOT/ffmpeg"
PATH="$HOME/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure \
	--prefix="$HOME/ffmpeg_build" \
	--pkg-config-flags="--static" \
	--extra-cflags="-I$HOME/ffmpeg_build/include -static" \
	--extra-ldflags="-L$HOME/ffmpeg_build/lib -static" \
	--bindir="$HOME/bin" \
	--cc="$CC -m64" \
	--cpu="sandybridge" \
	--arch="x84_64" \
	${args[@]}
PATH="$HOME/bin:$PATH" make -j "$NUM_CORES"
make install
make distclean
hash -r

# Generate README.txt
echo "
`figlet -f slant "FFmpeg"`

Build version: $TRAVIS_TAG
Build date: `date -u`

`$HOME/bin/ffmpeg -version`

This build of FFmpeg is licensed under the GPLv3. See the source code for details.

The source code can be downloaded from https://github.com/$TRAVIS_REPO_SLUG/releases/tag/$TRAVIS_TAG
" > "$HOME/bin/README.txt"

cp COPYING.GPLv3 $HOME/bin

tar -czvf "$TRAVIS_BUILD_DIR/ffmpeg-build-lambda.tar.gz" -C $HOME/bin/ .
