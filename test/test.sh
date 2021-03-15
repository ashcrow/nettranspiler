#!/bin/bash

NEWFILES='"/etc/hostname"
"/etc/resolve.conf"
"/etc/sysconfig/network-scripts/ifcfg-fake"
"/etc/sysconfig/network-scripts/ifcfg-blah"'
KEYS='"contents"
"filesystem"
"mode"
"path"'
FAILURES=0

# Ensure we have require commands
command -v jq > /dev/null
if [ $? != 0 ]; then
    echo "jq is required for testing"
    exit 1
fi

# Ensure the new files from the fakeroot are present
test_expected_files() {
    tmpfile=$1
    testname="$2: File Check"
    result=$(jq '.storage.files[].path' ${tmpfile})
    success=1
    for fcheck in $NEWFILES; do
        if [[ $result != *"$fcheck"* ]]; then
            success=0
        fi
    done
    if [ $success == 0 ]; then
        echo "FAIL: ${testname} Files did not match"
        echo "- Expected: ${NEWFILES}"
        echo "- Got: ${result}"
        FAILURES=$(echo "$FAILURES + 1" | bc)
    else
        echo "PASS: ${testname}"
    fi
}

# Ensure that the minimum expected keys are set
test_expected_keys() {
    tmpfile=$1
    testname="$2: Key Check"
    success=1
    failures=""
    array_size=$(jq '.storage.files | length' ${tmpfile})
    array_size=$(echo ${array_size} - 1 | bc)
    for i in $(seq 0 ${array_size}); do
        result=$(jq ".storage.files[${i}]" ${tmpfile} | jq "keys[]")
        for check in $KEYS; do
            if [[ $result != *"$check"* ]]; then
                success=0
                failures="$failures $i"
            fi
        done
    done
    if [ $success == 0 ]; then
        echo "FAIL: ${testname} Keys did not match"
        for f in "$failures"; do
            echo "- Expected: ${KEYS}"
            echo "- Got: " $(jq ".storage.files[${f}]" ${tmpfile} | jq "keys[]")
        done
        FAILURES=$(echo "$FAILURES + 1" | bc)
    else
        echo "PASS: ${testname}"
    fi
}

# Ensure the content of a file is what is expected
test_expected_contents() {
    tmpfile=$1
    checkfile=$2
    content="$3"
    testname="$4: Content Check for $checkfile"
    sourcecontent=$(jq -r ".storage.files[] | select(.path==\"${checkfile}\") | .contents.source" ${tmpfile})
    if [ "$content" = "$sourcecontent" ]; then
            echo "PASS: ${testname}"
    else
        echo "FAIL: $testname Content does not match"
        echo "- Expected: ${content}"
        echo "- Got: ${sourcecontent}"
    fi
}


test_name="Ignition With No Storage"
tmpfile=$(mktemp)
./filetranspile -i test/ignition-no-storage.json -f test/fakeroot > ${tmpfile}
test_expected_files "${tmpfile}" "${test_name}"
test_expected_keys "${tmpfile}" "${test_name}"

test_name="Ignition With No Files"
tmpfile=$(mktemp)
./filetranspile -i test/ignition-no-files.json -f test/fakeroot > ${tmpfile}
test_expected_files "${tmpfile}" "${test_name}"
test_expected_keys "${tmpfile}" "${test_name}"

test_name="Ignition With Existing Files"
tmpfile=$(mktemp)
./filetranspile -i test/ignition.json -f test/fakeroot > ${tmpfile}
test_expected_files "${tmpfile}" "${test_name}"
test_expected_keys "${tmpfile}" "${test_name}"

# See https://github.com/ashcrow/filetranspiler/pull/29
test_name="Ignition Overwrite With Fakeroot File"
tmpfile=$(mktemp)
./filetranspile -i test/ignition-overwrite-with-fakeroot-file.json -f test/fakeroot > ${tmpfile}
test_expected_files "${tmpfile}" "${test_name}"
test_expected_keys "${tmpfile}" "${test_name}"
# We should still have the fakeroot one and not the one in our original ignition
test_expected_contents "${tmpfile}" "/etc/resolve.conf" "data:text/plain;charset=us-ascii;base64,c2VhcmNoIDEyNy4wLjAuMQpuYW1lc2VydmVyIDEyNy4wLjAuMQo=" "${test_name}"


if [[ $FAILURES -ge 1 ]]; then
    echo "${FAILURES} failures detected"
    exit 1
fi
