#!/usr/bin/env bash

set -e
ROOT=`pwd`

if [ "$TRAVIS_EVENT_TYPE" == 'cron' ]; then
	REPO=`git config remote.origin.url`
	SSH_REPO=${REPO/https:\/\/github.com\//git@github.com:}
	chmod 600 deploy_key
	eval `ssh-agent -s`
	ssh-add deploy_key

	TODAY=`date -u +%F`

	git submodule foreach 'git checkout master && git fetch origin master --tags && git pull'

	if [ -z $(git status -s) ]; then
		git commit -am "Update to latest master on all for $TODAY"
	fi

	# Tag the nightly release
	git tag -a "nightly-$TODAY" -m "Nightly build for $TODAY"

	function latest_tag() {
		git describe --tags "`git rev-list HEAD --not --tags='nightly*' --max-count=1`"
	}

	# If the FFmpeg repo has a newer tag, create a tag for this repo and push
	git fetch $SSH_REPO --tags
	MAIN_LATEST_TAG=`latest-tag`

	cd $ROOT/ffmpeg
	git FFMPEG_LATEST_TAG=`latest-tag`

	cd $ROOT

	if [ $MAIN_LATEST_TAG != $FFMPEG_LATEST_TAG ]; then
		git checkout -b release/$FFMPEG_LATEST_TAG
		git submodule foreach 'git checkout $(git describe --tags $(git rev-list --tags --max-count=1))'
		MSG="Release for FFmpeg $FFMPEG_LATEST_TAG"$'\n'`git submodule foreach --quiet 'echo "$name: $(git describe --tags)"'`
		git commit -am "${MSG[@]}"
		git tag -a $FFMPEG_LATEST_TAG -m "${MSG[@]}"
	fi

	git push $SSH_REPO master --tags

	exit 0
fi

# Don't build master, since it will only contain the latest nightly commits.
if [ "$TRAVIS_BRANCH" == "master" ]; then
	echo "Just keeping things up-to-date"
	exit 0;
fi

# libx265
echo "Building libx265"
cd $ROOT/x265/build/linux
PATH="$HOME/bin:$PATH" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DENABLE_SHARED:bool=off ../../source
make
make install

# libvpx
echo "Building libvpx"
cd $ROOT/libvpx
PATH="$HOME/bin:$PATH" ./configure --prefix="$HOME/ffmpeg_build" --disable-examples --disable-unit-tests
PATH="$HOME/bin:$PATH" make
make install
make clean

echo "Building FFmpeg"
cd $ROOT/ffmpeg
PATH="$HOME/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure \
	--prefix="$HOME/ffmpeg_build" \
	--pkg-config-flags="--static" \
	--extra-cflags="-I$HOME/ffmpeg_build/include" \
	--extra-ldflags="-L$HOME/ffmpeg_build/lib" \
	--bindir="$HOME/bin" \
	--arch="x86_64" \
	--enable-gpl \
	--disable-runtime-cpudetect \
	--disable-ffplay \
	--disable-ffserver \
	--disable-doc \
	--disable-network \
	--disable-protocols \
	--enable-protocol=file \
	--enable-protocol=pipe \
	--enable-protocol=tee \
	--enable-libfdk-aac \
	--enable-libmp3lame \
	--enable-libvpx \
	--enable-libx264 \
	--enable-libx265 \
	--enable-libxvid
PATH="$HOME/bin:$PATH" make
make install
make distclean
hash -r

# Generate README.txt
echo "Generating README"
echo "
`figlet -f slant "FFmpeg"`

Build version: $TRAVIS_TAG
Build date: `date -u`

`$HOME/bin/ffmpeg -version`

This build of FFmpeg is licensed under the GPL. See the source code for details.
" > $HOME/bin/README.txt

tar -czvf $TRAVIS_BUILD_DIR/ffmpeg-build-lambda.tar.gz $HOME/bin/*
