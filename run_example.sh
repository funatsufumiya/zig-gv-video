#!/bin/bash

cd examples
zig build && (cd ..; ./examples/zig-out/bin/gvvideo-example)