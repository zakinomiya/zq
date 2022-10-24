#!/bin/bash

dir="testdata"

function run_zq () {
for f in "$dir"/*; do
  cat $f | zig-out/bin/zq > /dev/null
done
}

function run_jq () {
for f in "$dir"/*; do
  cat $f | jq > /dev/null
done
}

echo "zq result"
time run_zq 
echo "=========="

echo "jq result"
time run_jq

