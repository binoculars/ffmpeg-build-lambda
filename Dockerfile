FROM ubuntu:20.04 AS build

ARG NUM_CORES=2

ENV \
	PREFIX="/tmp/ffmpeg_build" \
	DEBIAN_FRONTEND=noninteractive

# Dependencies
RUN apt-get update \
	&& apt-get -y install \
		autoconf \
		automake \
		build-essential \
		cmake \
		curl \
		fontconfig \
		frei0r-plugins-dev \
		git \
		git-core \
		libass-dev \
		libfdk-aac-dev \
		libfontconfig1-dev \
		libfreetype6-dev \
		libfribidi-dev \
		libgnutls28-dev \
		libmp3lame-dev \
		libnuma-dev \
		libopencore-amrnb-dev \
		libopencore-amrwb-dev \
		libopenjp2-7-dev \
		libopus-dev \
		libsdl2-dev \
		libspeex-dev \
		libtheora-dev \
		libtool \
		libva-dev \
		libvdpau-dev \
		libvo-amrwbenc-dev \
		libvorbis-dev \
		libvpx-dev \
		libwebp-dev \
		libx264-dev \
		libx265-dev \
		libxcb-shm0-dev \
		libxcb-xfixes0-dev \
		libxcb1-dev \
		libxvidcore-dev \
		mercurial \
		meson \
		ninja-build \
		pkg-config \
		texinfo \
		wget \
		yasm \
		zlib1g-dev \
	&& apt-get clean \
	&& apt-get autoremove -y \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# # openjpeg
# RUN git clone https://github.com/uclouvain/openjpeg.git --branch master --single-branch \
# 	&& cd openjpeg \
# 	&& cmake -DBUILD_THIRDPARTY:BOOL=ON -DCMAKE_INSTALL_PREFIX="${PREFIX}" . \
# 	&& make -j "${NUM_CORES}" \
# 	&& make install \
# 	&& make clean

## openjpeg https://github.com/uclouvain/openjpeg
RUN \
        DIR=/tmp/openjpeg && \
        mkdir -p ${DIR} && \
        cd ${DIR} && \
        curl -sL https://github.com/uclouvain/openjpeg/archive/v2.1.2.tar.gz | \
        tar -zx --strip-components=1 && \
        cmake -DBUILD_THIRDPARTY:BOOL=ON -DCMAKE_INSTALL_PREFIX="${PREFIX}" . && \
        make && \
        make install && \
        rm -rf ${DIR}


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
RUN git clone https://github.com/ffmpeg/ffmpeg.git --branch master --single-branch
RUN export \
		BIN_DIR="/opt/ffmpeg/bin" \
		PATH="${BIN_DIR}:${PATH}" \
	&& cd ./ffmpeg \
	&& ./configure \
		--cc=gcc \
		--prefix="${PREFIX}" \
		--pkg-config="pkg-config --static" \
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
