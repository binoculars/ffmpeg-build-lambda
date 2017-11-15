FROM debian AS build

ARG NUM_CORES=2

ENV \
	PREFIX="/tmp/ffmpeg_build" \
	PKG_CONFIG_PATH="/tmp/ffmpeg_build/lib/pkgconfig"

# Dependencies
RUN apt-get update -qq \
	&& apt-get -y install \
		autoconf \
		automake \
		build-essential \
		cmake \
		git \
		libass-dev \
		libfreetype6-dev \
		libsdl2-dev \
		libtheora-dev \
		libtool \
		libva-dev \
		libvdpau-dev \
		libvorbis-dev \
		libxcb1-dev \
		libxcb-shm0-dev \
		libxcb-xfixes0-dev \
		mercurial \
		pkg-config \
		texinfo \
		wget \
		zlib1g-dev \
		fontconfig \
		frei0r-plugins-dev \
		libass-dev \
		libfontconfig1-dev \
		libmp3lame-dev \
		libopencore-amrnb-dev \
		libopencore-amrwb-dev \
		libopus-dev \
		libspeex-dev \
		libtheora-dev \
		libvorbis-dev \
		libvo-amrwbenc-dev \
		libwebp-dev \
		libx264-dev \
		libnuma-dev \
		libvpx-dev \
		libxvidcore-dev \
		texinfo \
		yasm \
	&& apt-get clean \
	&& apt-get autoremove -y \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# openjpeg
RUN git clone https://github.com/uclouvain/openjpeg.git --branch master --single-branch \
	&& cd openjpeg \
	&& cmake -DBUILD_THIRDPARTY:BOOL=ON -DCMAKE_INSTALL_PREFIX="${PREFIX}" . \
	&& make -j "${NUM_CORES}" \
	&& make install \
	&& make clean

# libx265
RUN git clone https://github.com/videolan/x265.git --branch master --single-branch \
	&& cd ./x265/build/linux \
	&& cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="${PREFIX}" -DENABLE_SHARED:bool=off ../../source \
	&& make -j "${NUM_CORES}" \
	&& make install \
	&& make clean

# fribidi
RUN git clone https://github.com/fribidi/fribidi.git --branch master --single-branch \
	&& cd fribidi \
	&& sed -i 's/^SUBDIRS =.*/SUBDIRS=gen.tab charset lib/' Makefile.am \
	&& ./bootstrap --no-config \
	&& ./configure -prefix="${PREFIX}" --enable-static=yes --enable-shared=no \
	&& make -j "${NUM_CORES}" \
	&& make install \
	&& make clean

# soxr
RUN git clone https://git.code.sf.net/p/soxr/code soxr --branch master --single-branch \
	&& cd soxr \
	&& mkdir build \
	&& cd build \
	&& cmake -Wno-dev -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" -DBUILD_SHARED_LIBS=OFF .. \
	&& make -j "${NUM_CORES}" \
	&& make install \
	&& make clean

# FFmpeg
RUN export \
		BIN_DIR="/opt/ffmpeg/bin" \
		PATH="${BIN_DIR}:${PATH}" \
	&& git clone https://github.com/ffmpeg/ffmpeg.git --branch master --single-branch \
	&& cd ./ffmpeg \
	&& ./configure \
		--cc=gcc-6 \
		--prefix="${PREFIX}" \
		--pkg-config-flags="--static" \
		--extra-cflags="-I${PREFIX}/include -static" \
		--extra-ldflags="-L${PREFIX}/lib -static" \
		--extra-libs="-lpthread -lm" \
		--bindir="${BIN_DIR}" \
		--cpu="sandybridge" \
		--arch="x84_64" \
		--disable-shared \
		--enable-static \
		--disable-debug \
		--disable-runtime-cpudetect \
		--disable-ffplay \
		--disable-ffserver \
		--disable-doc \
		--disable-network \
		--disable-devices \
		# Protocols
		--disable-protocols \
		--enable-protocol=file \
		--enable-protocol=pipe \
		--enable-protocol=tee \
		# Libraries
		--enable-libmp3lame \
		--enable-libvpx \
		--enable-libwebp \
		--enable-libopus \
		--enable-fontconfig \
		--enable-gray \
		--enable-libfreetype \
		--enable-libopenjpeg \
		--enable-libspeex \
		--enable-libtheora \
		--enable-libvorbis \
		--enable-libfribidi \
		# # GPL
		--enable-gpl \
		--enable-frei0r \
		--enable-libx264 \
		--enable-libx265 \
		--enable-libxvid \
		# # GPLv3
		--enable-version3 \
		--enable-libopencore-amrnb \
		--enable-libopencore-amrwb \
		--enable-libvo-amrwbenc \
	|| if [ $? -gt 0 ]; then \
		tail -n 100 ./ffbuild/config.log && \
		exit 1 \
	; fi \
	&& make -j "${NUM_CORES}" \
	&& make install \
	&& make distclean

FROM alpine as dist

COPY --from=build /opt/ /opt/
COPY --from=build /tmp/ffmpeg/COPYING.GPLv3 /opt/ffmpeg/

RUN cd /opt/ffmpeg/bin \
	&& for file in *; do \
		ln -s /opt/ffmpeg/bin/${file} /usr/local/bin/${file} \
	; done

CMD [ "ffmpeg" ]
