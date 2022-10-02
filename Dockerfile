# bump: alpine /FROM alpine:([\d.]+)/ docker:alpine|^3
# bump: alpine link "Release notes" https://alpinelinux.org/posts/Alpine-$LATEST-released.html
FROM alpine:3.16.2 AS base

FROM base AS download
WORKDIR /tmp
RUN apk add --no-cache \
  coreutils \
  wget \
  git \
  tar

FROM base AS builder
WORKDIR /tmp
RUN apk add --no-cache \
  coreutils \
  openssl-dev openssl-libs-static \
  bash \
  build-base \
  autoconf automake \
  libtool \
  diffutils \
  cmake meson ninja \
  yasm nasm \
  texinfo \
  xxd
# -O3 makes sure we compile with optimization. setting CFLAGS/CXXFLAGS seems to override
# default automake cflags.
# -static-libgcc is needed to make gcc not include gcc_s as "as-needed" shared library which
# cmake will include as a implicit library.
# other options to get hardened build (same as ffmpeg hardened)
ARG CFLAGS="-O3 -s -static-libgcc -fno-strict-overflow -fstack-protector-all -fPIC"
ARG CXXFLAGS="-O3 -s -static-libgcc -fno-strict-overflow -fstack-protector-all -fPIC"
ARG LDFLAGS="-Wl,-z,relro,-z,now"

FROM download AS vmaf_download
# bump: vmaf /VMAF_VERSION=([\d.]+)/ https://github.com/Netflix/vmaf.git|*
# bump: vmaf after ./hashupdate Dockerfile VMAF $LATEST
# bump: vmaf link "Release" https://github.com/Netflix/vmaf/releases/tag/v$LATEST
# bump: vmaf link "Source diff $CURRENT..$LATEST" https://github.com/Netflix/vmaf/compare/v$CURRENT..v$LATEST
ARG VMAF_VERSION=2.3.1
ARG VMAF_URL="https://github.com/Netflix/vmaf/archive/refs/tags/v$VMAF_VERSION.tar.gz"
ARG VMAF_SHA256=8d60b1ddab043ada25ff11ced821da6e0c37fd7730dd81c24f1fc12be7293ef2
RUN \
  wget $WGET_OPTS -O vmaf.tar.gz "$VMAF_URL" && \
  echo "$VMAF_SHA256  vmaf.tar.gz" | sha256sum --status -c - && \
  mkdir vmaf && \
  tar xf vmaf.tar.gz -C vmaf --strip-components=1

# before aom as libvmaf uses it
FROM builder AS vmaf
COPY --link --from=vmaf_download /tmp/vmaf/ /tmp/vmaf/
RUN \
  cd vmaf/libvmaf && meson build --buildtype=release -Ddefault_library=static -Dbuilt_in_models=true -Denable_tests=false -Denable_docs=false -Denable_avx512=true -Denable_float=true && \
  ninja -j$(nproc) -vC build install
# extra libs stdc++ is for vmaf https://github.com/Netflix/vmaf/issues/788
RUN  sed -i 's/-lvmaf /-lvmaf -lstdc++ /' /usr/local/lib/pkgconfig/libvmaf.pc

FROM download AS aom_download
# bump: aom /AOM_VERSION=([\d.]+)/ git:https://aomedia.googlesource.com/aom|*
# bump: aom after ./hashupdate Dockerfile AOM $LATEST
# bump: aom after COMMIT=$(git ls-remote https://aomedia.googlesource.com/aom v$LATEST^{} | awk '{print $1}') && sed -i -E "s/^ARG AOM_COMMIT=.*/ARG AOM_COMMIT=$COMMIT/" Dockerfile
# bump: aom link "CHANGELOG" https://aomedia.googlesource.com/aom/+/refs/tags/v$LATEST/CHANGELOG
ARG AOM_VERSION=3.5.0
ARG AOM_URL="https://aomedia.googlesource.com/aom"
ARG AOM_COMMIT=bcfe6fbfed315f83ee8a95465c654ee8078dbff9
RUN \
  git clone --depth 1 --branch v$AOM_VERSION "$AOM_URL" && \
  cd aom && test $(git rev-parse HEAD) = $AOM_COMMIT

# build after libvmaf
FROM builder AS aom
COPY --link --from=aom_download /tmp/aom/ /tmp/aom/
COPY --link --from=vmaf /usr/local/lib/pkgconfig/libvmaf.pc /usr/local/lib/pkgconfig/libvmaf.pc
COPY --link --from=vmaf /usr/local/lib/libvmaf.a /usr/local/lib/libvmaf.a
COPY --link --from=vmaf /usr/local/include/libvmaf/ /usr/local/include/libvmaf/
RUN \
  cd aom && \
  mkdir build_tmp && cd build_tmp && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_EXAMPLES=NO \
    -DENABLE_DOCS=NO \
    -DENABLE_TESTS=NO \
    -DENABLE_TOOLS=NO \
    -DCONFIG_TUNE_VMAF=1 \
    -DENABLE_NASM=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    .. && \
  make -j$(nproc) install

FROM download AS libaribb24_download
# bump: libaribb24 /LIBARIBB24_VERSION=([\d.]+)/ https://github.com/nkoriyama/aribb24.git|*
# bump: libaribb24 after ./hashupdate Dockerfile LIBARIBB24 $LATEST
# bump: libaribb24 link "Release notes" https://github.com/nkoriyama/aribb24/releases/tag/$LATEST
ARG LIBARIBB24_VERSION=1.0.3
ARG LIBARIBB24_URL="https://github.com/nkoriyama/aribb24/archive/v$LIBARIBB24_VERSION.tar.gz"
ARG LIBARIBB24_SHA256=f61560738926e57f9173510389634d8c06cabedfa857db4b28fb7704707ff128
RUN \
  wget $WGET_OPTS -O libaribb24.tar.gz ${LIBARIBB24_URL} && \
  echo "$LIBARIBB24_SHA256  libaribb24.tar.gz" | sha256sum --status -c - && \
  mkdir libaribb24 && \
  tar xf libaribb24.tar.gz -C libaribb24 --strip-components=1

FROM builder AS libaribb24
COPY --link --from=libaribb24_download /tmp/libaribb24/ /tmp/libaribb24/
RUN apk add --no-cache \
  libpng-dev
RUN \
  cd libaribb24 && \
  autoreconf -fiv && \
  ./configure --enable-static --disable-shared && \
  make -j$(nproc) && make install

FROM download AS libass_download
# bump: libass /LIBASS_VERSION=([\d.]+)/ https://github.com/libass/libass.git|*
# bump: libass after ./hashupdate Dockerfile LIBASS $LATEST
# bump: libass link "Release notes" https://github.com/libass/libass/releases/tag/$LATEST
ARG LIBASS_VERSION=0.16.0
ARG LIBASS_URL="https://github.com/libass/libass/releases/download/$LIBASS_VERSION/libass-$LIBASS_VERSION.tar.gz"
ARG LIBASS_SHA256=fea8019b1887cab9ab00c1e58614b4ec2b1cee339b3f7e446f5fab01b032d430
RUN \
  wget $WGET_OPTS -O libass.tar.gz "$LIBASS_URL" && \
  echo "$LIBASS_SHA256  libass.tar.gz" | sha256sum --status -c - && \
  mkdir libass && \
  tar xf libass.tar.gz -C libass --strip-components=1

FROM builder AS libass
COPY --link --from=libass_download /tmp/libass/ /tmp/libass/
RUN apk add --no-cache \
  freetype freetype-dev freetype-static \
  fribidi-dev fribidi-static \
  harfbuzz-dev harfbuzz-static \
  fontconfig-dev fontconfig-static
RUN \
  cd libass && ./configure --disable-shared --enable-static && \
  make -j$(nproc) && make install

FROM download AS libbluray_download
# bump: libbluray /LIBBLURAY_VERSION=([\d.]+)/ https://code.videolan.org/videolan/libbluray.git|*
# bump: libbluray after ./hashupdate Dockerfile LIBBLURAY $LATEST
# bump: libbluray link "ChangeLog" https://code.videolan.org/videolan/libbluray/-/blob/master/ChangeLog
ARG LIBBLURAY_VERSION=1.3.3
ARG LIBBLURAY_URL="https://code.videolan.org/videolan/libbluray/-/archive/$LIBBLURAY_VERSION/libbluray-$LIBBLURAY_VERSION.tar.gz"
ARG LIBBLURAY_SHA256=b29ead1050c8a75729eef645d1d94c112845bbce7cf507cad7bc8edf4d04ebe7
RUN \
  wget $WGET_OPTS -O libbluray.tar.gz "$LIBBLURAY_URL" && \
  echo "$LIBBLURAY_SHA256  libbluray.tar.gz" | sha256sum --status -c - && \
  mkdir libbluray && \
  tar xf libbluray.tar.gz -C libbluray --strip-components=1 && \
  cd libbluray && \
  git clone https://code.videolan.org/videolan/libudfread.git contrib/libudfread

FROM builder AS libbluray
COPY --link --from=libbluray_download /tmp/libbluray/ /tmp/libbluray/
RUN apk add --no-cache \
  libxml2-dev \
  freetype freetype-dev freetype-static \
  fontconfig-dev fontconfig-static
RUN \
  cd libbluray && \
  autoreconf -fiv && ./configure --with-pic --disable-doxygen-doc --disable-doxygen-dot --enable-static --disable-shared --disable-examples --disable-bdjava-jar && \
  make -j$(nproc) install

FROM download AS dav1d_download
# bump: dav1d /DAV1D_VERSION=([\d.]+)/ https://code.videolan.org/videolan/dav1d.git|*
# bump: dav1d after ./hashupdate Dockerfile DAV1D $LATEST
# bump: dav1d link "Release notes" https://code.videolan.org/videolan/dav1d/-/tags/$LATEST
ARG DAV1D_VERSION=1.0.0
ARG DAV1D_URL="https://code.videolan.org/videolan/dav1d/-/archive/$DAV1D_VERSION/dav1d-$DAV1D_VERSION.tar.gz"
ARG DAV1D_SHA256=047b8229511a82b5718a1d34c86c067b078efd02f602986d2ed09b23182ec136
RUN \
  wget $WGET_OPTS -O dav1d.tar.gz "$DAV1D_URL" && \
  echo "$DAV1D_SHA256  dav1d.tar.gz" | sha256sum --status -c - && \
  mkdir dav1d && \
  tar xf dav1d.tar.gz -C dav1d --strip-components=1

FROM builder AS dav1d
COPY --link --from=dav1d_download /tmp/dav1d/ /tmp/dav1d/
RUN \
  cd dav1d && meson build --buildtype release -Ddefault_library=static && \
  ninja -j$(nproc) -C build install

FROM download AS davs2_download
# bump: davs2 /DAVS2_VERSION=([\d.]+)/ https://github.com/pkuvcl/davs2.git|^1
# bump: davs2 after ./hashupdate Dockerfile DAVS2 $LATEST
# bump: davs2 link "Release" https://github.com/pkuvcl/davs2/releases/tag/$LATEST
# bump: davs2 link "Source diff $CURRENT..$LATEST" https://github.com/pkuvcl/davs2/compare/v$CURRENT..v$LATEST
ARG DAVS2_VERSION=1.7
ARG DAVS2_URL="https://github.com/pkuvcl/davs2/archive/refs/tags/$DAVS2_VERSION.tar.gz"
ARG DAVS2_SHA256=b697d0b376a1c7f7eda3a4cc6d29707c8154c4774358303653f0a9727f923cc8
RUN \
  wget $WGET_OPTS -O davs2.tar.gz "$DAVS2_URL" && \
  echo "$DAVS2_SHA256  davs2.tar.gz" | sha256sum --status -c - && \
  mkdir davs2 && \
  tar xf davs2.tar.gz -C davs2 --strip-components=1

FROM builder AS davs2
COPY --link --from=davs2_download /tmp/davs2/ /tmp/davs2/
RUN \
# TODO: seems to be issues with asm on musl
  cd davs2/build/linux && \
  ./configure --disable-asm --enable-pic --enable-strip --disable-cli && \
  make -j$(nproc) install

FROM download AS libgme_download
# bump: libgme /LIBGME_COMMIT=([[:xdigit:]]+)/ gitrefs:https://bitbucket.org/mpyne/game-music-emu.git|re:#^refs/heads/master$#|@commit
# bump: libgme after ./hashupdate Dockerfile LIBGME $LATEST
# bump: libgme link "Source diff $CURRENT..$LATEST" https://bitbucket.org/mpyne/game-music-emu/branches/compare/$CURRENT..$LATEST
ARG LIBGME_URL="https://bitbucket.org/mpyne/game-music-emu.git"
ARG LIBGME_COMMIT=6cd4bdb69be304f58c9253fb08b8362f541b3b4b
RUN \
  git clone "$LIBGME_URL" libgme && \
  cd libgme && git checkout $LIBGME_COMMIT

FROM builder AS libgme
COPY --link --from=libgme_download /tmp/libgme/ /tmp/libgme/
RUN \
  cd libgme && \
  mkdir build && cd build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_UBSAN=OFF \
    .. && \
  make -j$(nproc) install

FROM download AS libgsm_download
# bump: libgsm /LIBGSM_COMMIT=([[:xdigit:]]+)/ gitrefs:https://github.com/timothytylee/libgsm.git|re:#^refs/heads/master$#|@commit
# bump: libgsm after ./hashupdate Dockerfile LIBGSM $LATEST
# bump: libgsm link "Changelog" https://github.com/timothytylee/libgsm/blob/master/ChangeLog
ARG LIBGSM_URL="https://github.com/timothytylee/libgsm.git"
ARG LIBGSM_COMMIT=98f1708fb5e06a0dfebd58a3b40d610823db9715
RUN \
  git clone "$LIBGSM_URL" && \
  cd libgsm && git checkout $LIBGSM_COMMIT

FROM builder AS libgsm
COPY --link --from=libgsm_download /tmp/libgsm/ /tmp/libgsm/
RUN \
  cd libgsm && \
  # Makefile is garbage, hence use specific compile arguments and flags
  # no need to build toast cli tool \
  rm src/toast* && \
  SRC=$(echo src/*.c) && \
  gcc ${CFLAGS} -c -ansi -pedantic -s -DNeedFunctionPrototypes=1 -Wall -Wno-comment -DSASR -DWAV49 -DNDEBUG -I./inc ${SRC} && \
  ar cr libgsm.a *.o && ranlib libgsm.a && \
  mkdir -p /usr/local/include/gsm && \
  cp inc/*.h /usr/local/include/gsm && \
  cp libgsm.a /usr/local/lib

FROM download AS kvazaar_download
# bump: kvazaar /KVAZAAR_VERSION=([\d.]+)/ https://github.com/ultravideo/kvazaar.git|^2
# bump: kvazaar after ./hashupdate Dockerfile KVAZAAR $LATEST
# bump: kvazaar link "Release notes" https://github.com/ultravideo/kvazaar/releases/tag/v$LATEST
ARG KVAZAAR_VERSION=2.1.0
ARG KVAZAAR_URL="https://github.com/ultravideo/kvazaar/archive/v$KVAZAAR_VERSION.tar.gz"
ARG KVAZAAR_SHA256=bbdd3112182e5660a1c339e30677f871b6eac1e5b4ff1292ee1ae38ecbe11029
RUN \
  wget $WGET_OPTS -O kvazaar.tar.gz "$KVAZAAR_URL" && \
  echo "$KVAZAAR_SHA256  kvazaar.tar.gz" | sha256sum --status -c - && \
  mkdir kvazaar && \
  tar xf kvazaar.tar.gz -C kvazaar --strip-components=1

FROM builder AS kvazaar
COPY --link --from=kvazaar_download /tmp/kvazaar/ /tmp/kvazaar/
RUN \
  cd kvazaar && \
  ./autogen.sh && ./configure --disable-shared --enable-static && \
  make -j$(nproc) install

FROM download AS libmodplug_download
# bump: libmodplug /LIBMODPLUG_VERSION=([\d.]+)/ fetch:https://sourceforge.net/projects/modplug-xmms/files/|/libmodplug-([\d.]+).tar.gz/
# bump: libmodplug after ./hashupdate Dockerfile LIBMODPLUG $LATEST
# bump: libmodplug link "NEWS" https://sourceforge.net/p/modplug-xmms/git/ci/master/tree/libmodplug/NEWS
ARG LIBMODPLUG_VERSION=0.8.9.0
ARG LIBMODPLUG_URL="https://downloads.sourceforge.net/modplug-xmms/libmodplug-$LIBMODPLUG_VERSION.tar.gz"
ARG LIBMODPLUG_SHA256=457ca5a6c179656d66c01505c0d95fafaead4329b9dbaa0f997d00a3508ad9de
RUN \
  wget $WGET_OPTS -O libmodplug.tar.gz "$LIBMODPLUG_URL" && \
  echo "$LIBMODPLUG_SHA256  libmodplug.tar.gz" | sha256sum --status -c - && \
  mkdir libmodplug && \
  tar xf libmodplug.tar.gz -C libmodplug --strip-components=1

FROM builder AS libmodplug
COPY --link --from=libmodplug_download /tmp/libmodplug/ /tmp/libmodplug/
RUN \
  cd libmodplug && \
  ./configure --disable-shared --enable-static && \
  make -j$(nproc) install

FROM download AS mp3lame_download
# bump: mp3lame /MP3LAME_VERSION=([\d.]+)/ svn:http://svn.code.sf.net/p/lame/svn|/^RELEASE__(.*)$/|/_/./|*
# bump: mp3lame after ./hashupdate Dockerfile MP3LAME $LATEST
# bump: mp3lame link "ChangeLog" http://svn.code.sf.net/p/lame/svn/trunk/lame/ChangeLog
ARG MP3LAME_VERSION=3.100
ARG MP3LAME_URL="https://sourceforge.net/projects/lame/files/lame/$MP3LAME_VERSION/lame-$MP3LAME_VERSION.tar.gz/download"
ARG MP3LAME_SHA256=ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e
RUN \
  wget $WGET_OPTS -O lame.tar.gz "$MP3LAME_URL" && \
  echo "$MP3LAME_SHA256  lame.tar.gz" | sha256sum --status -c - && \
  mkdir lame && \
  tar xf lame.tar.gz -C lame --strip-components=1

FROM builder AS mp3lame
COPY --link --from=mp3lame_download /tmp/lame/ /tmp/lame/
RUN \
  cd lame && \
  ./configure --disable-shared --enable-static --enable-nasm --disable-gtktest --disable-cpml --disable-frontend && \
  make -j$(nproc) install

FROM download AS libmysofa_download
# bump: libmysofa /LIBMYSOFA_VERSION=([\d.]+)/ https://github.com/hoene/libmysofa.git|^1
# bump: libmysofa after ./hashupdate Dockerfile LIBMYSOFA $LATEST
# bump: libmysofa link "Release" https://github.com/hoene/libmysofa/releases/tag/$LATEST
# bump: libmysofa link "Source diff $CURRENT..$LATEST" https://github.com/hoene/libmysofa/compare/v$CURRENT..v$LATEST
ARG LIBMYSOFA_VERSION=1.2.1
ARG LIBMYSOFA_URL="https://github.com/hoene/libmysofa/archive/refs/tags/v$LIBMYSOFA_VERSION.tar.gz"
ARG LIBMYSOFA_SHA256=94cb02e488de4dc0860c8d23b29d93d290bb0a004d4aa17e1642985bba158ee9
RUN \
  wget $WGET_OPTS -O libmysofa.tar.gz "$LIBMYSOFA_URL" && \
  echo "$LIBMYSOFA_SHA256  libmysofa.tar.gz" | sha256sum --status -c - && \
  mkdir libmysofa && \
  tar xf libmysofa.tar.gz -C libmysofa --strip-components=1

FROM builder AS libmysofa
COPY --link --from=libmysofa_download /tmp/libmysofa/ /tmp/libmysofa/
RUN apk add --no-cache \
  zlib-dev zlib-static
RUN \
  cd libmysofa/build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTS=OFF \
    .. && \
  make -j$(nproc) install

FROM download AS opencoreamr_download
# bump: opencoreamr /OPENCOREAMR_VERSION=([\d.]+)/ fetch:https://sourceforge.net/projects/opencore-amr/files/opencore-amr/|/opencore-amr-([\d.]+).tar.gz/
# bump: opencoreamr after ./hashupdate Dockerfile OPENCOREAMR $LATEST
# bump: opencoreamr link "ChangeLog" https://sourceforge.net/p/opencore-amr/code/ci/master/tree/ChangeLog
ARG OPENCOREAMR_VERSION=0.1.6
ARG OPENCOREAMR_URL="https://sourceforge.net/projects/opencore-amr/files/opencore-amr/opencore-amr-$OPENCOREAMR_VERSION.tar.gz"
ARG OPENCOREAMR_SHA256=483eb4061088e2b34b358e47540b5d495a96cd468e361050fae615b1809dc4a1
RUN \
  wget $WGET_OPTS -O opencoreamr.tar.gz "$OPENCOREAMR_URL" && \
  echo "$OPENCOREAMR_SHA256  opencoreamr.tar.gz" | sha256sum --status -c - && \
  mkdir opencoreamr && \
  tar xf opencoreamr.tar.gz -C opencoreamr --strip-components=1

FROM builder AS opencoreamr
COPY --link --from=opencoreamr_download /tmp/opencoreamr/ /tmp/opencoreamr/
RUN \
  cd opencoreamr && \
  ./configure --enable-static --disable-shared && \
  make -j$(nproc) install

FROM download AS openjpeg_download
# bump: openjpeg /OPENJPEG_VERSION=([\d.]+)/ https://github.com/uclouvain/openjpeg.git|*
# bump: openjpeg after ./hashupdate Dockerfile OPENJPEG $LATEST
# bump: openjpeg link "CHANGELOG" https://github.com/uclouvain/openjpeg/blob/master/CHANGELOG.md
ARG OPENJPEG_VERSION=2.5.0
ARG OPENJPEG_URL="https://github.com/uclouvain/openjpeg/archive/v$OPENJPEG_VERSION.tar.gz"
ARG OPENJPEG_SHA256=0333806d6adecc6f7a91243b2b839ff4d2053823634d4f6ed7a59bc87409122a
RUN \
  wget $WGET_OPTS -O openjpeg.tar.gz "$OPENJPEG_URL" && \
  echo "$OPENJPEG_SHA256  openjpeg.tar.gz" | sha256sum --status -c - && \
  mkdir openjpeg && \
  tar xf openjpeg.tar.gz -C openjpeg --strip-components=1

FROM builder AS openjpeg
COPY --link --from=openjpeg_download /tmp/openjpeg/ /tmp/openjpeg/
RUN \
  cd openjpeg && mkdir build && cd build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_PKGCONFIG_FILES=ON \
    -DBUILD_CODEC=OFF \
    -DWITH_ASTYLE=OFF \
    -DBUILD_TESTING=OFF \
    .. && \
  make -j$(nproc) install

FROM download AS opus_download
# bump: opus /OPUS_VERSION=([\d.]+)/ https://github.com/xiph/opus.git|^1
# bump: opus after ./hashupdate Dockerfile OPUS $LATEST
# bump: opus link "Release notes" https://github.com/xiph/opus/releases/tag/v$LATEST
# bump: opus link "Source diff $CURRENT..$LATEST" https://github.com/xiph/opus/compare/v$CURRENT..v$LATEST
ARG OPUS_VERSION=1.3.1
ARG OPUS_URL="https://archive.mozilla.org/pub/opus/opus-$OPUS_VERSION.tar.gz"
ARG OPUS_SHA256=65b58e1e25b2a114157014736a3d9dfeaad8d41be1c8179866f144a2fb44ff9d
RUN \
  wget $WGET_OPTS -O opus.tar.gz "$OPUS_URL" && \
  echo "$OPUS_SHA256  opus.tar.gz" | sha256sum --status -c - && \
  mkdir opus && \
  tar xf opus.tar.gz -C opus --strip-components=1

FROM builder AS opus
COPY --link --from=opus_download /tmp/opus/ /tmp/opus/
RUN \
  cd opus && \
  ./configure --disable-shared --enable-static --disable-extra-programs --disable-doc && \
  make -j$(nproc) install

FROM download AS rav1e_download
# bump: rav1e /RAV1E_VERSION=([\d.]+)/ https://github.com/xiph/rav1e.git|/\d+\./|*
# bump: rav1e after ./hashupdate Dockerfile RAV1E $LATEST
# bump: rav1e link "Release notes" https://github.com/xiph/rav1e/releases/tag/v$LATEST
ARG RAV1E_VERSION=0.5.1
ARG RAV1E_URL="https://github.com/xiph/rav1e/archive/v$RAV1E_VERSION.tar.gz"
ARG RAV1E_SHA256=7b3060e8305e47f10b79f3a3b3b6adc3a56d7a58b2cb14e86951cc28e1b089fd
RUN \
  wget $WGET_OPTS -O rav1e.tar.gz "$RAV1E_URL" && \
  echo "$RAV1E_SHA256  rav1e.tar.gz" | sha256sum --status -c - && \
  mkdir rav1e && \
  tar xf rav1e.tar.gz -C rav1e --strip-components=1

FROM builder AS rav1e
COPY --link --from=rav1e_download /tmp/rav1e/ /tmp/rav1e/
RUN apk add --no-cache \
  rust cargo
# debug builds a bit faster and we don't care about runtime speed
RUN cargo install --debug --version 0.9.5 cargo-c
RUN \
  cd rav1e && \
  cargo cinstall --release
# cargo-c/alpine rustc results in Libs.private depend on gcc_s
# https://gitlab.alpinelinux.org/alpine/aports/-/issues/11806
RUN sed -i 's/-lgcc_s//' /usr/local/lib/pkgconfig/rav1e.pc

FROM download AS rubberband_download
# bump: rubberband /RUBBERBAND_VERSION=([\d.]+)/ https://github.com/breakfastquay/rubberband.git|^2
# bump: rubberband after ./hashupdate Dockerfile RUBBERBAND $LATEST
# bump: rubberband link "CHANGELOG" https://github.com/breakfastquay/rubberband/blob/default/CHANGELOG
# bump: rubberband link "Source diff $CURRENT..$LATEST" https://github.com/breakfastquay/rubberband/compare/$CURRENT..$LATEST
ARG RUBBERBAND_VERSION=2.0.2
ARG RUBBERBAND_URL="https://breakfastquay.com/files/releases/rubberband-$RUBBERBAND_VERSION.tar.bz2"
ARG RUBBERBAND_SHA256=b9eac027e797789ae99611c9eaeaf1c3a44cc804f9c8a0441a0d1d26f3d6bdf9
RUN \
  wget $WGET_OPTS -O rubberband.tar.bz2 "$RUBBERBAND_URL" && \
  echo "$RUBBERBAND_SHA256  rubberband.tar.bz2" | sha256sum --status -c - && \
  mkdir rubberband && \
  tar xf rubberband.tar.bz2 -C rubberband --strip-components=1

FROM builder AS rubberband
COPY --link --from=rubberband_download /tmp/rubberband/ /tmp/rubberband/
RUN apk add --no-cache \
  fftw-dev \
  libsamplerate-dev
RUN \
  cd rubberband && \
  meson -Ddefault_library=static -Dfft=fftw -Dresampler=libsamplerate build && \
  ninja -j$(nproc) -vC build install && \
  echo "Requires.private: fftw3 samplerate" >> /usr/local/lib/pkgconfig/rubberband.pc

FROM download AS libshine_download
# bump: LIBSHINE /LIBSHINE_VERSION=([\d.]+)/ https://github.com/toots/shine.git|*
# bump: LIBSHINE after ./hashupdate Dockerfile LIBSHINE $LATEST
# bump: LIBSHINE link "CHANGELOG" https://github.com/toots/shine/blob/master/ChangeLog
# bump: LIBSHINE link "Source diff $CURRENT..$LATEST" https://github.com/toots/shine/compare/$CURRENT..$LATEST
ARG LIBSHINE_VERSION=3.1.1
ARG LIBSHINE_URL="https://github.com/toots/shine/releases/download/$LIBSHINE_VERSION/shine-$LIBSHINE_VERSION.tar.gz"
ARG LIBSHINE_SHA256=58e61e70128cf73f88635db495bfc17f0dde3ce9c9ac070d505a0cd75b93d384
RUN \
  wget $WGET_OPTS -O libshine.tar.gz "$LIBSHINE_URL" && \
  echo "$LIBSHINE_SHA256  libshine.tar.gz" | sha256sum --status -c - && \
  mkdir libshine && \
  tar xf libshine.tar.gz -C libshine --strip-components=1

FROM builder AS libshine
COPY --link --from=libshine_download /tmp/libshine/ /tmp/libshine/
RUN \
  cd libshine && \
  ./configure --with-pic --enable-static --disable-shared --disable-fast-install && \
  make -j$(nproc) install

FROM download AS speex_download
# bump: speex /SPEEX_VERSION=([\d.]+)/ https://github.com/xiph/speex.git|*
# bump: speex after ./hashupdate Dockerfile SPEEX $LATEST
# bump: speex link "ChangeLog" https://github.com/xiph/speex//blob/master/ChangeLog
# bump: speex link "Source diff $CURRENT..$LATEST" https://github.com/xiph/speex/compare/$CURRENT..$LATEST
ARG SPEEX_VERSION=1.2.1
ARG SPEEX_URL="https://github.com/xiph/speex/archive/Speex-$SPEEX_VERSION.tar.gz"
ARG SPEEX_SHA256=beaf2642e81a822eaade4d9ebf92e1678f301abfc74a29159c4e721ee70fdce0
RUN \
  wget $WGET_OPTS -O speex.tar.gz "$SPEEX_URL" && \
  echo "$SPEEX_SHA256  speex.tar.gz" | sha256sum --status -c - && \
  mkdir speex && \
  tar xf speex.tar.gz -C speex --strip-components=1

FROM builder AS speex
COPY --link --from=speex_download /tmp/speex/ /tmp/speex/
RUN \
  cd speex && \
  ./autogen.sh && ./configure --disable-shared --enable-static && \
  make -j$(nproc) install

FROM download AS svtav1_download
# bump: svtav1 /SVTAV1_VERSION=([\d.]+)/ https://gitlab.com/AOMediaCodec/SVT-AV1.git|*
# bump: svtav1 after ./hashupdate Dockerfile SVTAV1 $LATEST
# bump: svtav1 link "Release notes" https://gitlab.com/AOMediaCodec/SVT-AV1/-/releases/v$LATEST
ARG SVTAV1_VERSION=1.2.1
ARG SVTAV1_URL="https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v$SVTAV1_VERSION/SVT-AV1-v$SVTAV1_VERSION.tar.bz2"
ARG SVTAV1_SHA256=805827daa8aedec4f1362b959f377075e2a811680bfc76b6f4fbf2ef4e7101d4
RUN \
  wget $WGET_OPTS -O svtav1.tar.bz2 "$SVTAV1_URL" && \
  echo "$SVTAV1_SHA256  svtav1.tar.bz2" | sha256sum --status -c - && \
  mkdir svtav1 && \
  tar xf svtav1.tar.bz2 -C svtav1 --strip-components=1

FROM builder AS svtav1
COPY --link --from=svtav1_download /tmp/svtav1/ /tmp/svtav1/
RUN \
  cd svtav1/Build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    .. && \
  make -j$(nproc) install

FROM download AS ogg_download
# bump: ogg /OGG_VERSION=([\d.]+)/ https://github.com/xiph/ogg.git|*
# bump: ogg after ./hashupdate Dockerfile OGG $LATEST
# bump: ogg link "CHANGES" https://github.com/xiph/ogg/blob/master/CHANGES
# bump: ogg link "Source diff $CURRENT..$LATEST" https://github.com/xiph/ogg/compare/v$CURRENT..v$LATEST
ARG OGG_VERSION=1.3.5
ARG OGG_URL="https://downloads.xiph.org/releases/ogg/libogg-$OGG_VERSION.tar.gz"
ARG OGG_SHA256=0eb4b4b9420a0f51db142ba3f9c64b333f826532dc0f48c6410ae51f4799b664
RUN \
  wget $WGET_OPTS -O libogg.tar.gz "$OGG_URL" && \
  echo "$OGG_SHA256  libogg.tar.gz" | sha256sum --status -c - && \
  mkdir ogg && \
  tar xf libogg.tar.gz -C ogg --strip-components=1

# has to be before theora
FROM builder AS ogg
COPY --link --from=ogg_download /tmp/ogg/ /tmp/ogg/
RUN \
  cd ogg && \
  ./configure --disable-shared --enable-static && \
  make -j$(nproc) install

FROM download AS theora_download
# bump: theora /THEORA_VERSION=([\d.]+)/ https://github.com/xiph/theora.git|*
# bump: theora after ./hashupdate Dockerfile THEORA $LATEST
# bump: theora link "Release notes" https://github.com/xiph/theora/releases/tag/v$LATEST
# bump: theora link "Source diff $CURRENT..$LATEST" https://github.com/xiph/theora/compare/v$CURRENT..v$LATEST
ARG THEORA_VERSION=1.1.1
ARG THEORA_URL="https://downloads.xiph.org/releases/theora/libtheora-$THEORA_VERSION.tar.bz2"
ARG THEORA_SHA256=b6ae1ee2fa3d42ac489287d3ec34c5885730b1296f0801ae577a35193d3affbc
RUN \
  wget $WGET_OPTS -O libtheora.tar.bz2 "$THEORA_URL" && \
  echo "$THEORA_SHA256  libtheora.tar.bz2" | sha256sum --status -c - && \
  mkdir theora && \
  tar xf libtheora.tar.bz2 -C theora --strip-components=1

FROM builder AS theora
COPY --link --from=theora_download /tmp/theora/ /tmp/theora/
COPY --link --from=ogg /usr/local/lib/pkgconfig/ogg.pc /usr/local/lib/pkgconfig/ogg.pc
COPY --link --from=ogg /usr/local/lib/libogg.a /usr/local/lib/libogg.a
COPY --link --from=ogg /usr/local/include/ogg/ /usr/local/include/ogg/
RUN \
  # --build=$(arch)-unknown-linux-gnu helps with guessing the correct build. For some reason,
  # build script can't guess the build type in arm64 (hardware and emulated) environment.
  cd theora && \
  ./configure --build=$(arch)-unknown-linux-gnu --disable-examples --disable-oggtest --disable-shared --enable-static && \
  make -j$(nproc) install

FROM download AS twolame_download
# bump: twolame /TWOLAME_VERSION=([\d.]+)/ https://github.com/njh/twolame.git|*
# bump: twolame after ./hashupdate Dockerfile TWOLAME $LATEST
# bump: twolame link "Source diff $CURRENT..$LATEST" https://github.com/njh/twolame/compare/v$CURRENT..v$LATEST
ARG TWOLAME_VERSION=0.4.0
ARG TWOLAME_URL="https://github.com/njh/twolame/releases/download/$TWOLAME_VERSION/twolame-$TWOLAME_VERSION.tar.gz"
ARG TWOLAME_SHA256=cc35424f6019a88c6f52570b63e1baf50f62963a3eac52a03a800bb070d7c87d
RUN \
  wget $WGET_OPTS -O twolame.tar.gz "$TWOLAME_URL" && \
  echo "$TWOLAME_SHA256  twolame.tar.gz" | sha256sum --status -c - && \
  mkdir twolame && \
  tar xf twolame.tar.gz -C twolame --strip-components=1

FROM builder AS twolame
COPY --link --from=twolame_download /tmp/twolame/ /tmp/twolame/
RUN \
  cd twolame && \
  ./configure --disable-shared --enable-static --disable-sndfile --with-pic && \
  make -j$(nproc) install

FROM download AS uavs3d_download
# bump: uavs3d /UAVS3D_COMMIT=([[:xdigit:]]+)/ gitrefs:https://github.com/uavs3/uavs3d.git|re:#^refs/heads/master$#|@commit
# bump: uavs3d after ./hashupdate Dockerfile UAVS3D $LATEST
# bump: uavs3d link "Source diff $CURRENT..$LATEST" https://github.com/uavs3/uavs3d/compare/$CURRENT..$LATEST
ARG UAVS3D_URL="https://github.com/uavs3/uavs3d.git"
ARG UAVS3D_COMMIT=0133ee4b4bbbef7b88802e7ad019b14b9b852c2b
RUN \
  git clone "$UAVS3D_URL" && \
  cd uavs3d && git checkout $UAVS3D_COMMIT

FROM builder AS uavs3d
COPY --link --from=uavs3d_download /tmp/uavs3d/ /tmp/uavs3d/
RUN \
  cd uavs3d && \
# Removes BIT_DEPTH 10 to be able to build on other platforms. 10 was overkill anyways.
#  sed -i 's/define BIT_DEPTH 8/define BIT_DEPTH 10/' source/decore/com_def.h && \
  mkdir build/linux && cd build/linux && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    ../.. && \
  make -j$(nproc) install

FROM download AS vidstab_download
# bump: vid.stab /VIDSTAB_VERSION=([\d.]+)/ https://github.com/georgmartius/vid.stab.git|*
# bump: vid.stab after ./hashupdate Dockerfile VIDSTAB $LATEST
# bump: vid.stab link "Changelog" https://github.com/georgmartius/vid.stab/blob/master/Changelog
ARG VIDSTAB_VERSION=1.1.0
ARG VIDSTAB_URL="https://github.com/georgmartius/vid.stab/archive/v$VIDSTAB_VERSION.tar.gz"
ARG VIDSTAB_SHA256=14d2a053e56edad4f397be0cb3ef8eb1ec3150404ce99a426c4eb641861dc0bb
RUN \
  wget $WGET_OPTS -O vid.stab.tar.gz "$VIDSTAB_URL" && \
  echo "$VIDSTAB_SHA256  vid.stab.tar.gz" | sha256sum --status -c - && \
  mkdir vidstab && \
  tar xf vid.stab.tar.gz -C vidstab --strip-components=1

FROM builder AS vidstab
COPY --link --from=vidstab_download /tmp/vidstab/ /tmp/vidstab/
RUN \
  cd vidstab && mkdir build && cd build && \
  # This line workarounds the issue that happens when the image builds in emulated (buildx) arm64 environment.
  # Since in emulated container the /proc is mounted from the host, the cmake not able to detect CPU features correctly.
  sed -i 's/include (FindSSE)/if(CMAKE_SYSTEM_ARCH MATCHES "amd64")\ninclude (FindSSE)\nendif()/' ../CMakeLists.txt && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_SYSTEM_ARCH=$(arch) \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DUSE_OMP=ON \
    .. && \
  make -j$(nproc) install
RUN echo "Libs.private: -ldl" >> /usr/local/lib/pkgconfig/vidstab.pc

FROM download AS vorbis_download
# bump: vorbis /VORBIS_VERSION=([\d.]+)/ https://github.com/xiph/vorbis.git|*
# bump: vorbis after ./hashupdate Dockerfile VORBIS $LATEST
# bump: vorbis link "CHANGES" https://github.com/xiph/vorbis/blob/master/CHANGES
# bump: vorbis link "Source diff $CURRENT..$LATEST" https://github.com/xiph/vorbis/compare/v$CURRENT..v$LATEST
ARG VORBIS_VERSION=1.3.7
ARG VORBIS_URL="https://downloads.xiph.org/releases/vorbis/libvorbis-$VORBIS_VERSION.tar.gz"
ARG VORBIS_SHA256=0e982409a9c3fc82ee06e08205b1355e5c6aa4c36bca58146ef399621b0ce5ab
RUN \
  wget $WGET_OPTS -O libvorbis.tar.gz "$VORBIS_URL" && \
  echo "$VORBIS_SHA256  libvorbis.tar.gz" | sha256sum --status -c - && \
  mkdir vorbis && \
  tar xf libvorbis.tar.gz -C vorbis --strip-components=1

FROM builder AS vorbis
COPY --link --from=vorbis_download /tmp/vorbis/ /tmp/vorbis/
COPY --link --from=ogg /usr/local/lib/pkgconfig/ogg.pc /usr/local/lib/pkgconfig/ogg.pc
COPY --link --from=ogg /usr/local/lib/libogg.a /usr/local/lib/libogg.a
COPY --link --from=ogg /usr/local/include/ogg/ /usr/local/include/ogg/
RUN \
  cd vorbis && \
  ./configure --disable-shared --enable-static --disable-oggtest && \
  make -j$(nproc) install

FROM download AS libvpx_download
# bump: libvpx /VPX_VERSION=([\d.]+)/ https://github.com/webmproject/libvpx.git|*
# bump: libvpx after ./hashupdate Dockerfile VPX $LATEST
# bump: libvpx link "CHANGELOG" https://github.com/webmproject/libvpx/blob/master/CHANGELOG
# bump: libvpx link "Source diff $CURRENT..$LATEST" https://github.com/webmproject/libvpx/compare/v$CURRENT..v$LATEST
ARG VPX_VERSION=1.12.0
ARG VPX_URL="https://github.com/webmproject/libvpx/archive/v$VPX_VERSION.tar.gz"
ARG VPX_SHA256=f1acc15d0fd0cb431f4bf6eac32d5e932e40ea1186fe78e074254d6d003957bb
RUN \
  wget $WGET_OPTS -O libvpx.tar.gz "$VPX_URL" && \
  echo "$VPX_SHA256  libvpx.tar.gz" | sha256sum --status -c - && \
  mkdir libvpx && \
  tar xf libvpx.tar.gz -C libvpx --strip-components=1

FROM builder AS libvpx
COPY --link --from=libvpx_download /tmp/libvpx/ /tmp/libvpx/
RUN \
  cd libvpx && \
  ./configure --enable-static --enable-vp9-highbitdepth --disable-shared --disable-unit-tests --disable-examples && \
  make -j$(nproc) install

FROM download AS libwebp_download
# bump: libwebp /LIBWEBP_VERSION=([\d.]+)/ https://github.com/webmproject/libwebp.git|*
# bump: libwebp after ./hashupdate Dockerfile LIBWEBP $LATEST
# bump: libwebp link "Release notes" https://github.com/webmproject/libwebp/releases/tag/v$LATEST
# bump: libwebp link "Source diff $CURRENT..$LATEST" https://github.com/webmproject/libwebp/compare/v$CURRENT..v$LATEST
ARG LIBWEBP_VERSION=1.2.4
ARG LIBWEBP_URL="https://github.com/webmproject/libwebp/archive/v$LIBWEBP_VERSION.tar.gz"
ARG LIBWEBP_SHA256=dfe7bff3390cd4958da11e760b65318f0a48c32913e4d5bc5e8d55abaaa2d32e
RUN \
  wget $WGET_OPTS -O libwebp.tar.gz "$LIBWEBP_URL" && \
  echo "$LIBWEBP_SHA256  libwebp.tar.gz" | sha256sum --status -c - && \
  mkdir libwebp && \
  tar xf libwebp.tar.gz -C libwebp --strip-components=1

FROM builder AS libwebp
COPY --link --from=libwebp_download /tmp/libwebp/ /tmp/libwebp/
RUN \
  cd libwebp && \
  ./autogen.sh && ./configure --disable-shared --enable-static --with-pic --enable-libwebpmux --disable-libwebpextras --disable-libwebpdemux --disable-sdl --disable-gl --disable-png --disable-jpeg --disable-tiff --disable-gif && \
  make -j$(nproc) install

FROM download AS x264_download
# x264 only have a stable branch no tags and we checkout commit so no hash is needed
# bump: x264 /X264_VERSION=([[:xdigit:]]+)/ gitrefs:https://code.videolan.org/videolan/x264.git|re:#^refs/heads/stable$#|@commit
# bump: x264 after ./hashupdate Dockerfile X264 $LATEST
# bump: x264 link "Source diff $CURRENT..$LATEST" https://code.videolan.org/videolan/x264/-/compare/$CURRENT...$LATEST
ARG X264_URL="https://code.videolan.org/videolan/x264.git"
ARG X264_VERSION=baee400fa9ced6f5481a728138fed6e867b0ff7f
RUN \
  git clone "$X264_URL" && \
  cd x264 && \
  git checkout $X264_VERSION

FROM builder AS x264
COPY --link --from=x264_download /tmp/x264/ /tmp/x264/
RUN \
  cd x264 && \
  ./configure --enable-pic --enable-static --disable-cli --disable-lavf --disable-swscale && \
  make -j$(nproc) install

FROM download AS x265_download
# x265 release is over 1 years old and master branch has a lot of fixes and improvements, so we checkout commit so no hash is needed
# bump: x265 /X265_VERSION=([[:xdigit:]]+)/ gitrefs:https://bitbucket.org/multicoreware/x265_git.git|re:#^refs/heads/master$#|@commit
# bump: x265 after ./hashupdate Dockerfile X265 $LATEST
# bump: x265 link "Source diff $CURRENT..$LATEST" https://bitbucket.org/multicoreware/x265_git/branches/compare/$LATEST..$CURRENT#diff
ARG X265_VERSION=931178347b3f73e40798fd5180209654536bbaa5
ARG X265_SHA256=eb07c919a62d4a6724b44427844c214ab7ddf57c85b3ccf3f2b8111763ac2966
ARG X265_URL="https://bitbucket.org/multicoreware/x265_git/get/$X265_VERSION.tar.bz2"
RUN \
  wget $WGET_OPTS -O x265_git.tar.bz2 "$X265_URL" && \
  echo "$X265_SHA256  x265_git.tar.bz2" | sha256sum --status -c - && \
  mkdir x265 && \
  tar xf x265_git.tar.bz2 -C x265 --strip-components=1

FROM builder AS x265
COPY --link --from=x265_download /tmp/x265/ /tmp/x265/
# -w-macro-params-legacy to not log lots of asm warnings
# https://bitbucket.org/multicoreware/x265_git/issues/559/warnings-when-assembling-with-nasm-215
# TODO: remove 'sed' hack when upstream (x265) fixes the issue and adds '-DPIC' to ARM_ARGS
# https://bitbucket.org/multicoreware/x265_git/issues/619/missing-dpic-for-arm-causes-link-error-on
# CMAKEFLAGS issue
# https://bitbucket.org/multicoreware/x265_git/issues/620/support-passing-cmake-flags-to-multilibsh
RUN apk add --no-cache \
  git \
  numactl-dev
RUN \
  cd x265/build/linux && \
  sed -i '/^cmake / s/$/ -G "Unix Makefiles" ${CMAKEFLAGS}/' ./multilib.sh && \
  sed -i 's/ -DENABLE_SHARED=OFF//g' ./multilib.sh && \
  sed -i 's/set(ARM_ARGS -fPIC -flax-vector-conversions)/set(ARM_ARGS -DPIC -fPIC -flax-vector-conversions)/' ../../source/CMakeLists.txt && \
  MAKEFLAGS="-j$(nproc)" \
  CMAKEFLAGS="-DENABLE_SHARED=OFF -DCMAKE_VERBOSE_MAKEFILE=ON -DENABLE_AGGRESSIVE_CHECKS=ON -DCMAKE_ASM_NASM_FLAGS=-w-macro-params-legacy -DENABLE_NASM=ON -DCMAKE_BUILD_TYPE=Release" \
  ./multilib.sh && \
  make -C 8bit -j$(nproc) install

FROM download AS xavs2_download
# bump: xavs2 /XAVS2_VERSION=([\d.]+)/ https://github.com/pkuvcl/xavs2.git|^1
# bump: xavs2 after ./hashupdate Dockerfile XAVS2 $LATEST
# bump: xavs2 link "Release" https://github.com/pkuvcl/xavs2/releases/tag/$LATEST
# bump: xavs2 link "Source diff $CURRENT..$LATEST" https://github.com/pkuvcl/xavs2/compare/v$CURRENT..v$LATEST
ARG XAVS2_VERSION=1.4
ARG XAVS2_URL="https://github.com/pkuvcl/xavs2/archive/refs/tags/$XAVS2_VERSION.tar.gz"
ARG XAVS2_SHA256=1e6d731cd64cb2a8940a0a3fd24f9c2ac3bb39357d802432a47bc20bad52c6ce
RUN \
  wget $WGET_OPTS -O xavs2.tar.gz "$XAVS2_URL" && \
  echo "$XAVS2_SHA256  xavs2.tar.gz" | sha256sum --status -c - && \
  mkdir xavs2 && \
  tar xf xavs2.tar.gz -C xavs2 --strip-components=1

FROM builder AS xavs2
COPY --link --from=xavs2_download /tmp/xavs2/ /tmp/xavs2/
RUN \
  # TODO: seems to be issues with asm on musl
  cd xavs2/build/linux && \
  ./configure --disable-asm --enable-pic --disable-cli && \
  make -j$(nproc) install

FROM download AS xvid_download
# http://websvn.xvid.org/cvs/viewvc.cgi/trunk/xvidcore/build/generic/configure.in?revision=2146&view=markup
# bump: xvid /XVID_VERSION=([\d.]+)/ svn:http://anonymous:@svn.xvid.org|/^release-(.*)$/|/_/./|^1
# bump: xvid after ./hashupdate Dockerfile XVID $LATEST
# add extra CFLAGS that are not enabled by -O3
ARG XVID_VERSION=1.3.7
ARG XVID_URL="https://downloads.xvid.com/downloads/xvidcore-$XVID_VERSION.tar.gz"
ARG XVID_SHA256=abbdcbd39555691dd1c9b4d08f0a031376a3b211652c0d8b3b8aa9be1303ce2d
RUN \
  wget $WGET_OPTS -O libxvid.tar.gz "$XVID_URL" && \
  echo "$XVID_SHA256  libxvid.tar.gz" | sha256sum --status -c - && \
  mkdir xvid && \
  tar xf libxvid.tar.gz -C xvid --strip-components=1

FROM builder AS xvid
COPY --link --from=xvid_download /tmp/xvid/ /tmp/xvid/
RUN \
  cd xvid/build/generic && \
  CFLAGS="$CFLAGS -fstrength-reduce -ffast-math" ./configure && \
  make -j$(nproc) && make install

FROM download AS zimg_download
# bump: zimg /ZIMG_VERSION=([\d.]+)/ https://github.com/sekrit-twc/zimg.git|*
# bump: zimg after ./hashupdate Dockerfile ZIMG $LATEST
# bump: zimg link "ChangeLog" https://github.com/sekrit-twc/zimg/blob/master/ChangeLog
ARG ZIMG_VERSION=3.0.4
ARG ZIMG_URL="https://github.com/sekrit-twc/zimg/archive/release-$ZIMG_VERSION.tar.gz"
ARG ZIMG_SHA256=219d1bc6b7fde1355d72c9b406ebd730a4aed9c21da779660f0a4c851243e32f
RUN \
  wget $WGET_OPTS -O zimg.tar.gz "$ZIMG_URL" && \
  echo "$ZIMG_SHA256  zimg.tar.gz" | sha256sum --status -c - && \
  mkdir zimg && \
  tar xf zimg.tar.gz -C zimg --strip-components=1

FROM builder AS zimg
COPY --link --from=zimg_download /tmp/zimg/ /tmp/zimg/
RUN \
  cd zimg && \
  ./autogen.sh && ./configure --disable-shared --enable-static && \
  make -j$(nproc) install

FROM download AS ffmpeg_download
# bump: ffmpeg /FFMPEG_VERSION=([\d.]+)/ https://github.com/FFmpeg/FFmpeg.git|^5
# bump: ffmpeg after ./hashupdate Dockerfile FFMPEG $LATEST
# bump: ffmpeg link "Changelog" https://github.com/FFmpeg/FFmpeg/blob/n$LATEST/Changelog
# bump: ffmpeg link "Source diff $CURRENT..$LATEST" https://github.com/FFmpeg/FFmpeg/compare/n$CURRENT..n$LATEST
ARG FFMPEG_VERSION=5.1.2
ARG FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.bz2"
ARG FFMPEG_SHA256=39a0bcc8d98549f16c570624678246a6ac736c066cebdb409f9502e915b22f2b
RUN \
  wget $WGET_OPTS -O ffmpeg.tar.bz2 "$FFMPEG_URL" && \
  echo "$FFMPEG_SHA256  ffmpeg.tar.bz2" | sha256sum --status -c - && \
  mkdir ffmpeg && \
  tar xf ffmpeg.tar.bz2 -C ffmpeg --strip-components=1

FROM builder AS ffmpeg
RUN apk add --no-cache \
  zlib-dev zlib-static \
  bzip2-dev bzip2-static \
  libxml2-dev \
  expat-dev expat-static \
  graphite2-static \
  glib-static \
  tiff tiff-dev \
  libjpeg-turbo libjpeg-turbo-dev \
  libpng-dev libpng-static \
  giflib giflib-dev \
  brotli-dev brotli-static \
  soxr-dev soxr-static \
  tcl \
  numactl-dev \
  cunit cunit-dev \
  fftw-dev \
  libsamplerate-dev \
  freetype-dev freetype-static \
  fribidi-dev fribidi-static \
  harfbuzz-dev harfbuzz-static \
  fontconfig-dev fontconfig-static
COPY --link --from=vmaf /usr/local/lib/pkgconfig/libvmaf.pc /usr/local/lib/pkgconfig/libvmaf.pc
COPY --link --from=vmaf /usr/local/lib/libvmaf.a /usr/local/lib/libvmaf.a
COPY --link --from=vmaf /usr/local/include/libvmaf/ /usr/local/include/libvmaf/
COPY --link --from=aom /usr/local/lib/pkgconfig/aom.pc /usr/local/lib/pkgconfig/aom.pc
COPY --link --from=aom /usr/local/lib/libaom.a /usr/local/lib/libaom.a
COPY --link --from=aom /usr/local/include/aom/ /usr/local/include/aom/
COPY --link --from=libaribb24 /usr/local/lib/pkgconfig/aribb24.pc /usr/local/lib/pkgconfig/aribb24.pc
COPY --link --from=libaribb24 /usr/local/lib/libaribb24.a /usr/local/lib/libaribb24.a
COPY --link --from=libaribb24 /usr/local/include/aribb24/ /usr/local/include/aribb24/
COPY --link --from=libass /usr/local/lib/pkgconfig/libass.pc /usr/local/lib/pkgconfig/libass.pc
COPY --link --from=libass /usr/local/lib/libass.a /usr/local/lib/libass.a
COPY --link --from=libass /usr/local/include/ass/ /usr/local/include/ass/
COPY --link --from=libbluray /usr/local/lib/pkgconfig/libbluray.pc /usr/local/lib/pkgconfig/libbluray.pc
COPY --link --from=libbluray /usr/local/lib/libbluray.a /usr/local/lib/libbluray.a
COPY --link --from=libbluray /usr/local/include/libbluray/ /usr/local/include/libbluray/
COPY --link --from=dav1d /usr/local/lib/pkgconfig/dav1d.pc /usr/local/lib/pkgconfig/dav1d.pc
COPY --link --from=dav1d /usr/local/lib/libdav1d.a /usr/local/lib/libdav1d.a
COPY --link --from=dav1d /usr/local/include/dav1d/ /usr/local/include/dav1d/
COPY --link --from=davs2 /usr/local/lib/pkgconfig/davs2.pc /usr/local/lib/pkgconfig/davs2.pc
COPY --link --from=davs2 /usr/local/lib/libdavs2.a /usr/local/lib/libdavs2.a
COPY --link --from=davs2 /usr/local/include/davs2* /usr/local/include/
COPY --link --from=libgme /usr/local/lib/pkgconfig/libgme.pc /usr/local/lib/pkgconfig/libgme.pc
COPY --link --from=libgme /usr/local/lib/libgme.a /usr/local/lib/libgme.a
COPY --link --from=libgme /usr/local/include/gme/ /usr/local/include/gme/
COPY --link --from=libgsm /usr/local/lib/libgsm.a /usr/local/lib/libgsm.a
COPY --link --from=libgsm /usr/local/include/gsm/ /usr/local/include/gsm/
COPY --link --from=kvazaar /usr/local/lib/pkgconfig/kvazaar.pc /usr/local/lib/pkgconfig/kvazaar.pc
COPY --link --from=kvazaar /usr/local/lib/libkvazaar.a /usr/local/lib/libkvazaar.a
COPY --link --from=kvazaar /usr/local/include/kvazaar.h /usr/local/include/kvazaar.h
COPY --link --from=libmodplug /usr/local/lib/pkgconfig/libmodplug.pc /usr/local/lib/pkgconfig/libmodplug.pc
COPY --link --from=libmodplug /usr/local/lib/libmodplug.a /usr/local/lib/libmodplug.a
COPY --link --from=libmodplug /usr/local/include/libmodplug/ /usr/local/include/libmodplug/
COPY --link --from=mp3lame /usr/local/lib/libmp3lame.a /usr/local/lib/libmp3lame.a
COPY --link --from=mp3lame /usr/local/include/lame/ /usr/local/include/lame/
COPY --link --from=libmysofa /usr/local/lib/pkgconfig/libmysofa.pc /usr/local/lib/pkgconfig/libmysofa.pc
COPY --link --from=libmysofa /usr/local/lib/libmysofa.a /usr/local/lib/libmysofa.a
COPY --link --from=libmysofa /usr/local/include/mysofa.h /usr/local/include/mysofa.h
COPY --link --from=opencoreamr /usr/local/lib/libopencore-amr* /usr/local/lib/
COPY --link --from=opencoreamr /usr/local/lib/pkgconfig/opencore-amr* /usr/local/lib/pkgconfig/
COPY --link --from=opencoreamr /usr/local/include/opencore-amrnb/ /usr/local/include/opencore-amrnb/
COPY --link --from=opencoreamr /usr/local/include/opencore-amrwb/ /usr/local/include/opencore-amrwb/
COPY --link --from=openjpeg /usr/local/lib/pkgconfig/libopenjp2.pc /usr/local/lib/pkgconfig/libopenjp2.pc
COPY --link --from=openjpeg /usr/local/lib/libopenjp2.a /usr/local/lib/libopenjp2.a
COPY --link --from=openjpeg /usr/local/include/openjpeg-2.5/ /usr/local/include/openjpeg-2.5/
COPY --link --from=opus /usr/local/lib/pkgconfig/opus.pc /usr/local/lib/pkgconfig/opus.pc
COPY --link --from=opus /usr/local/lib/libopus.a /usr/local/lib/libopus.a
COPY --link --from=opus /usr/local/include/opus/ /usr/local/include/opus/
COPY --link --from=rav1e /usr/local/lib/pkgconfig/rav1e.pc /usr/local/lib/pkgconfig/rav1e.pc
COPY --link --from=rav1e /usr/local/lib/librav1e.a /usr/local/lib/librav1e.a
COPY --link --from=rav1e /usr/local/include/rav1e/ /usr/local/include/rav1e/
COPY --link --from=rubberband /usr/local/lib/pkgconfig/rubberband.pc /usr/local/lib/pkgconfig/rubberband.pc
COPY --link --from=rubberband /usr/local/lib/librubberband.a /usr/local/lib/librubberband.a
COPY --link --from=rubberband /usr/local/include/rubberband/ /usr/local/include/rubberband/
COPY --link --from=libshine /usr/local/lib/pkgconfig/shine.pc /usr/local/lib/pkgconfig/shine.pc
COPY --link --from=libshine /usr/local/lib/libshine.a /usr/local/lib/libshine.a
COPY --link --from=libshine /usr/local/include/shine/ /usr/local/include/shine/
COPY --link --from=speex /usr/local/lib/pkgconfig/speex.pc /usr/local/lib/pkgconfig/speex.pc
COPY --link --from=speex /usr/local/lib/libspeex.a /usr/local/lib/libspeex.a
COPY --link --from=speex /usr/local/include/speex/ /usr/local/include/speex/
COPY --link --from=svtav1 /usr/local/lib/pkgconfig/SvtAv1*.pc /usr/local/lib/pkgconfig/
COPY --link --from=svtav1 /usr/local/lib/libSvtAv1*.a /usr/local/lib/
COPY --link --from=svtav1 /usr/local/include/svt-av1/ /usr/local/include/svt-av1/
COPY --link --from=ogg /usr/local/lib/pkgconfig/ogg.pc /usr/local/lib/pkgconfig/ogg.pc
COPY --link --from=ogg /usr/local/lib/libogg.a /usr/local/lib/libogg.a
COPY --link --from=ogg /usr/local/include/ogg/ /usr/local/include/ogg/
COPY --link --from=theora /usr/local/lib/pkgconfig/theora*.pc /usr/local/lib/pkgconfig/
COPY --link --from=theora /usr/local/lib/libtheora*.a /usr/local/lib/
COPY --link --from=theora /usr/local/include/theora/ /usr/local/include/theora/
COPY --link --from=twolame /usr/local/lib/pkgconfig/twolame.pc /usr/local/lib/pkgconfig/twolame.pc
COPY --link --from=twolame /usr/local/lib/libtwolame.a /usr/local/lib/libtwolame.a
COPY --link --from=twolame /usr/local/include/twolame.h /usr/local/include/twolame.h
COPY --link --from=uavs3d /usr/local/lib/pkgconfig/uavs3d.pc /usr/local/lib/pkgconfig/uavs3d.pc
COPY --link --from=uavs3d /usr/local/lib/libuavs3d.a /usr/local/lib/libuavs3d.a
COPY --link --from=uavs3d /usr/local/include/uavs3d.h /usr/local/include/uavs3d.h
COPY --link --from=vidstab /usr/local/lib/pkgconfig/vidstab.pc /usr/local/lib/pkgconfig/vidstab.pc
COPY --link --from=vidstab /usr/local/lib/libvidstab.a /usr/local/lib/libvidstab.a
COPY --link --from=vidstab /usr/local/include/vid.stab/ /usr/local/include/vid.stab/
COPY --link --from=vorbis /usr/local/lib/pkgconfig/vorbis*.pc /usr/local/lib/pkgconfig/
COPY --link --from=vorbis /usr/local/lib/libvorbis*.a /usr/local/lib/
COPY --link --from=vorbis /usr/local/include/vorbis/ /usr/local/include/vorbis/
COPY --link --from=libvpx /usr/local/lib/pkgconfig/vpx.pc /usr/local/lib/pkgconfig/vpx.pc
COPY --link --from=libvpx /usr/local/lib/libvpx.a /usr/local/lib/libvpx.a
COPY --link --from=libvpx /usr/local/include/vpx/ /usr/local/include/vpx/
COPY --link --from=libwebp /usr/local/lib/pkgconfig/libwebp*.pc /usr/local/lib/pkgconfig/
COPY --link --from=libwebp /usr/local/lib/libwebp*.a /usr/local/lib/
COPY --link --from=libwebp /usr/local/include/webp/ /usr/local/include/webp/
COPY --link --from=x264 /usr/local/lib/pkgconfig/x264.pc /usr/local/lib/pkgconfig/x264.pc
COPY --link --from=x264 /usr/local/lib/libx264.a /usr/local/lib/libx264.a
COPY --link --from=x264 /usr/local/include/x264*.h /usr/local/include/
COPY --link --from=x265 /usr/local/lib/pkgconfig/x265.pc /usr/local/lib/pkgconfig/x265.pc
COPY --link --from=x265 /usr/local/lib/libx265.a /usr/local/lib/libx265.a
COPY --link --from=x265 /usr/local/include/x265*.h /usr/local/include/
COPY --link --from=xavs2 /usr/local/lib/pkgconfig/xavs2.pc /usr/local/lib/pkgconfig/xavs2.pc
COPY --link --from=xavs2 /usr/local/lib/libxavs2.a /usr/local/lib/libxavs2.a
COPY --link --from=xavs2 /usr/local/include/xavs2*.h /usr/local/include/
COPY --link --from=xvid /usr/local/lib/libxvidcore.* /usr/local/lib/
COPY --link --from=xvid /usr/local/include/xvid.h /usr/local/include/xvid.h
COPY --link --from=zimg /usr/local/lib/pkgconfig/zimg.pc /usr/local/lib/pkgconfig/zimg.pc
COPY --link --from=zimg /usr/local/lib/libzimg.a /usr/local/lib/libzimg.a
COPY --link --from=zimg /usr/local/include/zimg* /usr/local/include/
COPY --link --from=ffmpeg_download /tmp/ffmpeg/ /tmp/ffmpeg/
RUN \
  cd ffmpeg && \
# sed changes --toolchain=hardened -pie to -static-pie
# extra ldflags stack-size=2097152 is to increase default stack size from 128KB (musl default) to something
# more similar to glibc (2MB). This fixing segfault with libaom-av1 and libsvtav1 as they seems to pass
# large things on the stack.
  sed -i 's/add_ldexeflags -fPIE -pie/add_ldexeflags -fPIE -static-pie/' configure && \
  ./configure \
  --pkg-config-flags="--static" \
  --extra-cflags="-fopenmp" \
  --extra-ldflags="-fopenmp -Wl,-z,stack-size=2097152" \
  --toolchain=hardened \
  --disable-debug \
  --disable-doc \
  --disable-shared \
  --disable-ffplay \
  --enable-static \
  --enable-small \
  --cpu="sandybridge" \
  --disable-runtime-cpudetect \
  --enable-gpl \
  --enable-version3 \
  --enable-fontconfig \
  --enable-gray \
  --enable-iconv \
  --enable-libaom \
  --enable-libaribb24 \
  --enable-libass \
  --enable-libbluray \
  --enable-libdav1d \
  --enable-libdavs2 \
  --enable-libfreetype \
  --enable-libfribidi \
  --enable-libgme \
  --enable-libgsm \
  --enable-libkvazaar \
  --enable-libmodplug \
  --enable-libmp3lame \
  --enable-libmysofa \
  --enable-libopencore-amrnb \
  --enable-libopencore-amrwb \
  --enable-libopenjpeg \
  --enable-libopus \
  --enable-librav1e \
  --enable-librubberband \
  --enable-libshine \
  --enable-libsoxr \
  --enable-libspeex \
  --enable-libsvtav1 \
  --enable-libtheora \
  --enable-libtwolame \
  --enable-libuavs3d \
  --enable-libvidstab \
  --enable-libvmaf \
  --enable-libvorbis \
  --enable-libvpx \
  --enable-libwebp \
  --enable-libx264 \
  --enable-libx265 \
  --enable-libxavs2 \
  --enable-libxml2 \
  --enable-libxvid \
  --enable-libzimg \
  || (cat ffbuild/config.log ; false) \
  && make -j$(nproc) install

FROM scratch AS final
COPY --from=ffmpeg /usr/local/bin/ffmpeg /usr/local/bin/ffprobe /
# sanity tests
RUN ["/ffmpeg", "-version"]
RUN ["/ffprobe", "-version"]
RUN ["/ffmpeg", "-hide_banner", "-buildconf"]
# stack size
RUN ["/ffmpeg", "-f", "lavfi", "-i", "testsrc", "-c:v", "libsvtav1", "-t", "100ms", "-f", "null", "-"]

FROM final
ENTRYPOINT ["/ffmpeg"]
