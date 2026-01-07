#!/bin/bash
#
# test.sh
# Test script for Soju
#

set -e

echo "Running SojuKit tests..."
cd SojuKit
swift test

echo ""
echo "All tests passed!"
