#!/bin/bash

dir="testdata"
for f in "$dir"/*; do
  d=$(diff <(cat $f | zig build run) <(cat $f | jq .))
  if [ -z $d ]; then
    echo "success: ${f}"
  else
    echo "fail: ${f}. diff=${d}"
  fi
done


