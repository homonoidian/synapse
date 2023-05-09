#!/bin/bash
shards build synapse -Dpreview_mt --release --link-flags "-L$(pwd)" --no-debug
