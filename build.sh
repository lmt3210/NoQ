#!/bin/bash

VERSION=$(cat NoQ.xcodeproj/project.pbxproj | \
          grep -m1 'MARKETING_VERSION' | cut -d'=' -f2 | \
          tr -d ';' | tr -d ' ')
ARCHIVE_DIR=/Users/Larry/Library/Developer/Xcode/Archives/CommandLine

rm -f make.log
touch make.log
rm -rf build

echo "Building NoQ" 2>&1 | tee -a make.log

xcodebuild -project NoQ.xcodeproj clean 2>&1 | tee -a make.log
xcodebuild -project NoQ.xcodeproj \
    -scheme "NoQ-Release" -archivePath NoQ.xcarchive \
    archive 2>&1 | tee -a make.log

rm -rf ${ARCHIVE_DIR}/NoQ-v${VERSION}.xcarchive
cp -rf NoQ.xcarchive \
    ${ARCHIVE_DIR}/NoQ-v${VERSION}.xcarchive

