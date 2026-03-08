#!/bin/bash
set -e
for f in test/test_phase0.sh test/test_step2.sh test/test_step3.sh test/test_step4.sh test/test_step5.sh test/test_step6.sh test/test_step7.sh test/test_step8.sh; do
  bash "$f"
done
echo "=== All tests passed ==="
