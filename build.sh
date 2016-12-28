#!/usr/bin/env bash

export ROOT=`pwd`

sudo apt-get update
sudo apt-get -y install \
	autoconf \
	automake \
	build-essential \
	cmake \
	libass-dev \
	libfdk-aac-dev \
	libfreetype6-dev \
	libmp3lame-dev \
	libopus-dev \
	libtheora-dev \
	libtool \
	libvorbis-dev \
	libx264-dev \
	mercurial \
	pkg-config \
	texinfo \
	yasm \
	zlib1g-dev

git submodule init

# libx265
cd $ROOT/x265/build/linux
PATH="$HOME/bin:$PATH" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DENABLE_SHARED:bool=off ../../source
make
make install
make distclean

# libvpx
cd $ROOT/libvpx
PATH="$HOME/bin:$PATH" ./configure --prefix="$HOME/ffmpeg_build" --disable-examples --disable-unit-tests
PATH="$HOME/bin:$PATH" make
make install
make clean

cd $ROOT/ffmpeg
PATH="$HOME/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure \
	--prefix="$HOME/ffmpeg_build" \
	--pkg-config-flags="--static" \
	--extra-cflags="-I$HOME/ffmpeg_build/include" \
	--extra-ldflags="-L$HOME/ffmpeg_build/lib" \
	--bindir="$HOME/bin" \
	--enable-gpl \
	--enable-nonfree \
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
	--enable-libxvid \
	--arch=x86_64 \
	--disable-cuda \
	--disable-cuvid \
	--disable-nvenc \
	--cpu=i686
PATH="$HOME/bin:$PATH" make
make install
make distclean
hash -r
