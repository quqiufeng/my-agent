#!/bin/bash
# test_staticpy.sh — StaticPy 端到端测试
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

echo "=== StaticPy End-to-End Tests ==="

fail_count=0

run_test() {
    local src="tests/$1"
    local stem="$2"
    local expected="$3"
    
    echo ""
    echo "--- Testing $src ---"
    bash static_build.sh "$src" "$stem"
    
    if [ ! -x "./$stem" ]; then
        echo "FAIL: ./$stem not found or not executable"
        fail_count=$((fail_count + 1))
        return
    fi
    
    local output
    output=$("./$stem" 2>&1 || true)
    echo "$output"
    
    if echo "$output" | grep -q "$expected"; then
        echo "PASS: $src"
    else
        echo "FAIL: expected '$expected' in output"
        fail_count=$((fail_count + 1))
    fi
}

run_test_or() {
    local src="tests/$1"
    local stem="$2"
    shift 2
    
    echo ""
    echo "--- Testing $src ---"
    bash static_build.sh "$src" "$stem"
    
    if [ ! -x "./$stem" ]; then
        echo "FAIL: ./$stem not found or not executable"
        fail_count=$((fail_count + 1))
        return
    fi
    
    local output
    output=$("./$stem" 2>&1 || true)
    echo "$output"
    
    for expected in "$@"; do
        if echo "$output" | grep -q "$expected"; then
            echo "PASS: $src"
            return
        fi
    done
    echo "FAIL: expected one of '$*' in output"
    fail_count=$((fail_count + 1))
}

run_test "test_staticpy_basic.py" "static_basic" "INT OK"
run_test "test_staticpy_np.py" "static_np" "NP MEAN OK"
run_test "test_staticpy_blas.py" "static_blas" "NP ARRAY OK"
run_test "test_staticpy_intvec.py" "static_intvec" "INT VECTOR OK"
run_test "test_staticpy_fib.py" "static_fib" "FIB OK"
run_test "test_staticpy_from_import.py" "static_from_import" "FROM IMPORT OK"
run_test "test_staticpy_ml.py" "static_ml" "ML STYLE OK"
run_test "test_staticpy_pythonic.py" "static_pythonic" "PYTHONIC OK"
run_test "test_staticpy_dataclass.py" "static_dataclass" "DATACLASS OK"
STATICPY_WARN=1 run_test "test_staticpy_superset.py" "static_superset" "SUPERSET OK"
run_test "test_staticpy_closure.py" "static_closure" "CLOSURE OK"
run_test_or "test_staticpy_torch.py" "static_torch" "TORCH MATMUL OK" "TORCH NOT AVAILABLE"

echo ""
echo "--- Testing staticc.py ---"
rm -rf /tmp/staticpy-cache/staticc_* /tmp/static-build-*
# Compile-check staticc.py with the StaticPy pipeline (binary runtime is still WIP)
STATICPY_WARN=1 bash static_build.sh staticc.py staticc
# Run the self-hosted compiler ELF
./staticc test_staticc_input.sp /tmp/test_staticc_output.scm
output=$(/opt/ChezScheme/ta6le/bin/ta6le/scheme -q static_prelude.scm /tmp/test_staticc_output.scm 2>&1 || true)
echo "$output"
if echo "$output" | grep -q "30"; then
    echo "PASS: staticc.py"
else
    echo "FAIL: expected '30' in staticc output"
    fail_count=$((fail_count + 1))
fi

echo ""
echo "--- Typecheck unit tests ---"
python3 tests/test_staticpy_typecheck.py

echo ""
echo "=== Summary ==="
if [ "$fail_count" -eq 0 ]; then
    echo "All StaticPy tests passed."
else
    echo "$fail_count test(s) failed."
    exit 1
fi
