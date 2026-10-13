#!/bin/bash

path=`dirname $0`

OUTPUT_DIR=$1
TARGET_NAME=plugin_onDemandResources
OUTPUT_SUFFIX=a
CONFIG=Release

#
# Checks exit value for error
# 
checkError() {
    if [ $? -ne 0 ]
    then
        echo "Exiting due to errors (above)"
        exit -1
    fi
}

# 
# Canonicalize relative paths to absolute paths
# 
pushd $path > /dev/null
dir=`pwd`
path=$dir
popd > /dev/null

if [ -z "$OUTPUT_DIR" ]
then
    OUTPUT_DIR=.
fi

pushd $OUTPUT_DIR > /dev/null
dir=`pwd`
OUTPUT_DIR=$dir
popd > /dev/null

echo "OUTPUT_DIR: $OUTPUT_DIR"

# Clean
xcodebuild -project "$path/Plugin.xcodeproj" -configuration $CONFIG clean
checkError

# iOS
xcodebuild -project "$path/Plugin.xcodeproj" -configuration $CONFIG -sdk iphoneos
checkError

# iOS-sim
xcodebuild -project "$path/Plugin.xcodeproj" -configuration $CONFIG -sdk iphonesimulator
checkError

# Device and simulator libraries, side by side (the plugins/<build>/iphone
# and iphone-sim layout). No merged "universal" lib: both carry an arm64
# slice now (the simulator one for Apple-silicon Macs), which lipo can't merge.
for PLATFORM in iphone iphone-sim
do
    SDK=iphoneos
    if [ "$PLATFORM" = "iphone-sim" ]; then SDK=iphonesimulator; fi
    mkdir -p "$OUTPUT_DIR/$PLATFORM"
    cp "$path"/build/$CONFIG-$SDK/lib$TARGET_NAME.$OUTPUT_SUFFIX "$OUTPUT_DIR/$PLATFORM/"
    checkError
    echo "$OUTPUT_DIR/$PLATFORM/lib$TARGET_NAME.$OUTPUT_SUFFIX: $(lipo -archs "$OUTPUT_DIR/$PLATFORM/lib$TARGET_NAME.$OUTPUT_SUFFIX")"
done