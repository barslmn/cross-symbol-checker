#!/bin/sh
test_nonexistent_target_file() {
    nonexisting_file=$(mktemp)
    rm non_existing_file
    ./check_geneset SHFM -t "$nonexistent_target_file"
}
# TODO: write more tests
