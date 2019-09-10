FROM debian:stretch AS build

ARG NUM_CORES=2

ENV \
	PREFIX="/tmp/ffmpeg_build" \
	PKG_CONFIG_PATH="/tmp/ffmpeg_build/lib/pkgconfig" \
	OPENJPEG_VERSION="2.3.1" \
	VIDEOLAN_X265_VERSION="3.1.2" \
	FRIBIDI_VERSION="0.19.7" \
	FDK_AAC_VERSION="2.0.0" \
	FFMPEG_VERSION="4.2.1"

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
		libx265-dev \
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
RUN wget https://github.com/uclouvain/openjpeg/archive/v${OPENJPEG_VERSION}.tar.gz -O openjpeg.tar.gz \
	&& tar xzvf openjpeg.tar.gz \
	&& cd openjpeg-${OPENJPEG_VERSION} \
	&& cmake -DBUILD_THIRDPARTY:BOOL=ON -DCMAKE_INSTALL_PREFIX="${PREFIX}" . \
	&& make -j "${NUM_CORES}" \
	&& make install \
	&& make clean

# fribidi
RUN wget https://github.com/fribidi/fribidi/archive/${FRIBIDI_VERSION}.tar.gz -O fribidi.tar.gz \
	&& tar xzvf fribidi.tar.gz \
	&& cd fribidi-${FRIBIDI_VERSION} \
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


RUN wget https://github.com/videolan/x265/archive/${VIDEOLAN_X265_VERSION}.tar.gz -O x265.tar.gz && \
	tar xzvf x265.tar.gz && \
	cd x265-${VIDEOLAN_X265_VERSION}/build/linux && \
	cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="${PREFIX}" -DENABLE_SHARED=off ../../source && \
	make && \
	make install

RUN wget https://github.com/mstorsjo/fdk-aac/archive/v${FDK_AAC_VERSION}.tar.gz -O fdk-aac.tar.gz && \
	tar xzvf fdk-aac.tar.gz && \
	cd fdk-aac-${FDK_AAC_VERSION} && \
	autoreconf -fiv && \
	./configure --prefix="${PREFIX}" --disable-shared && \
	make && \
	make install

# FFmpeg
RUN export \
		BIN_DIR="/opt/ffmpeg/bin" \
		PATH="${BIN_DIR}:${PATH}" \
	&& wget https://github.com/FFmpeg/FFmpeg/archive/n${FFMPEG_VERSION}.tar.gz -O ffmpeg.tar.gz \
	&& tar xzvf ffmpeg.tar.gz \
	&& cd ./FFmpeg-n${FFMPEG_VERSION} \
	&& ./configure \
		--cc=gcc \
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
		--enable-libfdk-aac \
		# # GPL
		--enable-gpl \
		--enable-frei0r \
		--enable-libx264 \
		--enable-libx265 \
		--enable-libxvid \
		--enable-nonfree \
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
	&& make distclean \
	&& cp /tmp/FFmpeg-n${FFMPEG_VERSION}/COPYING.GPLv3 /opt/ffmpeg/COPYING.GPLv3

FROM alpine as dist

COPY --from=build /opt/ /opt/

RUN cd /opt/ffmpeg/bin \
	&& for file in *; do \
		ln -s /opt/ffmpeg/bin/${file} /usr/local/bin/${file} \
	; done

CMD [ "ffmpeg" ]
