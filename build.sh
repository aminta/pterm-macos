#!/bin/bash
# Build Pterm.app (PTerm 6.0.4) for macOS 11 and later, as a universal
# binary (Apple Silicon + Intel), with wxWidgets, SDL2 and libsndfile
# linked statically.  Needs the Xcode command line tools and cmake.
#
#   ./build.sh            -> dist/Pterm-<version>-macOS-universal.zip
#
# The dependencies are downloaded and built once into build/.

set -e
TOP=$(cd "$(dirname "$0")" && pwd)
BUILD=$TOP/build
DEPS=$BUILD/deps
SRC=$BUILD/src
DIST=$TOP/dist

VERSION=6.0.4
WX=3.2.11
SDL2=2.32.10
SNDFILE=1.2.2
MINOS=11.0
ARCHS="arm64 x86_64"
JOBS=$(sysctl -n hw.ncpu)

ARCHFLAGS=""
for a in $ARCHS; do ARCHFLAGS="$ARCHFLAGS -arch $a"; done
CMAKE_ARCHS=$(echo $ARCHS | tr ' ' ';')

mkdir -p "$SRC" "$DEPS" "$DIST"

fetch () {   # url dir
    if [ ! -d "$SRC/$2" ]; then
        echo "== downloading $2"
        curl -sSL "$1" | tar -x -C "$SRC" -f -
    fi
}

cmake_dep () {   # srcdir extra-args...
    local dir=$1; shift
    cmake -S "$SRC/$dir" -B "$BUILD/$dir-build" \
        -DCMAKE_OSX_ARCHITECTURES="$CMAKE_ARCHS" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=$MINOS \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$DEPS" \
        -DCMAKE_PREFIX_PATH=/nonexistent \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 "$@" > "$BUILD/$dir.log" 2>&1
    cmake --build "$BUILD/$dir-build" -j $JOBS >> "$BUILD/$dir.log" 2>&1
    cmake --install "$BUILD/$dir-build" >> "$BUILD/$dir.log" 2>&1
}

# ---- SDL2 (audio for the GSW music device) ----
if [ ! -f "$DEPS/lib/libSDL2.a" ]; then
    fetch https://github.com/libsdl-org/SDL/releases/download/release-$SDL2/SDL2-$SDL2.tar.gz SDL2-$SDL2
    echo "== building SDL2 $SDL2"
    cmake_dep SDL2-$SDL2 -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TEST=OFF
fi

# ---- libsndfile (saving GSW audio to a file) ----
if [ ! -f "$DEPS/lib/libsndfile.a" ]; then
    fetch https://github.com/libsndfile/libsndfile/releases/download/$SNDFILE/libsndfile-$SNDFILE.tar.xz libsndfile-$SNDFILE
    echo "== building libsndfile $SNDFILE"
    cmake_dep libsndfile-$SNDFILE -DBUILD_SHARED_LIBS=OFF -DENABLE_EXTERNAL_LIBS=OFF \
        -DENABLE_MPEG=OFF -DBUILD_PROGRAMS=OFF -DBUILD_EXAMPLES=OFF \
        -DBUILD_TESTING=OFF -DENABLE_CPACK=OFF -DINSTALL_MANPAGES=OFF
fi

# ---- wxWidgets (static, only bundled third party libraries) ----
if [ ! -x "$DEPS/bin/wx-config" ]; then
    fetch https://github.com/wxWidgets/wxWidgets/releases/download/v$WX/wxWidgets-$WX.tar.bz2 wxWidgets-$WX
    echo "== building wxWidgets $WX (this takes a while)"
    mkdir -p "$BUILD/wx-build"
    (cd "$BUILD/wx-build" && env -u CPPFLAGS -u LDFLAGS "$SRC/wxWidgets-$WX/configure" \
        --prefix="$DEPS" --with-osx_cocoa --disable-shared \
        --enable-universal_binary=$(echo $ARCHS | tr ' ' ',') \
        --with-macosx-version-min=$MINOS \
        --with-libpng=builtin --with-libjpeg=builtin --with-libtiff=builtin \
        --with-zlib=builtin --with-expat=builtin --with-regex=builtin \
        --without-liblzma --disable-webview --disable-mediactrl --disable-sys-libs \
        > "$BUILD/wx-configure.log" 2>&1 &&
     make -j $JOBS > "$BUILD/wx-make.log" 2>&1 &&
     make install > "$BUILD/wx-install.log" 2>&1)
fi

# ---- PTerm ----
echo "== building Pterm $VERSION"
PT=$BUILD/pterm
rm -rf "$PT" && mkdir -p "$PT/obj"
cp -R "$TOP/pterm-$VERSION/." "$PT/"
WXVER=$("$DEPS/bin/wx-config" --version)
cat > "$PT/wxversion.h" <<EOF
#define WXVERSION "$WXVER"
#define PTERMBUILDDATE "$(date '+%-d %B %Y') (macOS universal)"
#define PTERMSVNREV "macOS"
EOF

CFLAGS="$ARCHFLAGS -mmacosx-version-min=$MINOS -O2 -I$DEPS/include -I$DEPS/include/SDL2"
CXXFLAGS="$CFLAGS -std=gnu++11 $("$DEPS/bin/wx-config" --cxxflags)"
cd "$PT"
for f in FrameCanvas MTFile PtermApp PtermConnDialog PtermConnFailDialog \
         PtermConnection PtermPrefDialog PtermPrintout PtermProfile PtermTrace Z80; do
    c++ $CXXFLAGS -w -c $f.cpp -o obj/$f.o
done
cc $CFLAGS -w -c dtnetsubs.c -o obj/dtnetsubs.o
cc $CFLAGS -w -c pterm_sdl.c -o obj/pterm_sdl.o
c++ $CXXFLAGS -c "$TOP/mac/fixmenu.cpp" -o obj/fixmenu.o
c++ $ARCHFLAGS -mmacosx-version-min=$MINOS -o Pterm obj/*.o \
    $("$DEPS/bin/wx-config" --libs) \
    "$DEPS/lib/libSDL2.a" "$DEPS/lib/libsndfile.a" \
    -liconv -lm \
    -framework CoreAudio -framework AudioToolbox -framework CoreFoundation \
    -framework CoreServices -framework Cocoa -framework IOKit \
    -framework ForceFeedback -framework Carbon -framework CoreVideo \
    -framework Metal -framework GameController -framework CoreHaptics \
    -framework QuartzCore -framework UniformTypeIdentifiers \
    -weak_framework AVFoundation -Wl,-dead_strip

# ---- App bundle ----
APP=$BUILD/Pterm.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/licenses"
cp "$PT/Pterm" "$APP/Contents/MacOS/Pterm"
sed -e "s/@VERSION@/$VERSION/" -e "s/@MINOS@/$MINOS/" "$TOP/mac/Info.plist.in" > "$APP/Contents/Info.plist"
cp "$TOP/mac/Pterm.icns" "$APP/Contents/Resources/"
cp "$TOP/pterm-$VERSION/pterm-license.txt" "$APP/Contents/Resources/licenses/PTerm.txt"
cp "$SRC/wxWidgets-$WX/docs/licence.txt" "$APP/Contents/Resources/licenses/wxWidgets.txt"
cp "$SRC/SDL2-$SDL2/LICENSE.txt" "$APP/Contents/Resources/licenses/SDL2.txt"
cp "$SRC/libsndfile-$SNDFILE/COPYING" "$APP/Contents/Resources/licenses/libsndfile-LGPL-2.1.txt"
codesign --force --sign - --timestamp=none "$APP"

ZIP=$DIST/Pterm-$VERSION-macOS-universal.zip
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "== done: $ZIP"
lipo -info "$APP/Contents/MacOS/Pterm"
