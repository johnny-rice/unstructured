#!/usr/bin/env bash

set -u -o pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
SKIPPED_FILES_LOG=$SCRIPT_DIR/skipped-files.txt
PYTHON=${PYTHON:-python}
# If the file already exists, reset it
if [ -f "$SKIPPED_FILES_LOG" ]; then
  rm "$SKIPPED_FILES_LOG"
fi
touch "$SKIPPED_FILES_LOG"
cd "$SCRIPT_DIR"/.. || exit 1

EVAL_OUTPUT_ROOT=${EVAL_OUTPUT_ROOT:-$SCRIPT_DIR}

# NOTE(crag): sets number of tesseract threads to 1 which may help with more reproducible outputs
export OMP_THREAD_LIMIT=1

all_tests=(
  's3-minio.sh'
  'astradb.sh'
  'azure.sh'
  # NOTE(yuming): The pdf-fast-reprocess test should be put after any tests that save downloaded files
  'pdf-fast-reprocess.sh'
  'local.sh'
  'local-single-file.sh'
  'local-single-file-basic-chunking.sh'
  'local-single-file-chunk-no-orig-elements.sh'
  'local-single-file-with-encoding.sh'
  'local-single-file-with-pdf-infer-table-structure.sh'
)

full_python_matrix_tests=(
  #  'sharepoint.sh'
  'local.sh'
  'local-single-file.sh'
  'local-single-file-with-encoding.sh'
  'local-single-file-with-pdf-infer-table-structure.sh'
  # NOTE(scanny): This test is disabled because it routinely flakes on OCR differences
  # 's3.sh'
  'azure.sh'
)

CURRENT_TEST="none"

function print_last_run() {
  if [ "$CURRENT_TEST" != "none" ]; then
    echo "Last ran script: $CURRENT_TEST"
  fi
  echo "######## SKIPPED TESTS: ########"
  cat "$SKIPPED_FILES_LOG"
}

trap print_last_run EXIT

python_version=$(${PYTHON} --version 2>&1)

tests_to_ignore=(
  'notion.sh'
  'local-embed-mixedbreadai.sh'
  'hubspot.sh'
)

for test in "${all_tests[@]}"; do
  CURRENT_TEST="$test"
  # IF: python_version is not 3.10 (wildcarded to match any subminor version) AND the current test is not in full_python_matrix_tests
  # Note: to test we expand the full_python_matrix_tests array to a string and then regex match the current test
  if [[ "$python_version" != "Python 3.10"* ]] && [[ ! "${full_python_matrix_tests[*]}" =~ $test ]]; then
    echo "--------- SKIPPING SCRIPT $test ---------"
    continue
  fi
  echo "--------- RUNNING SCRIPT $test ---------"
  echo "Running ./test_unstructured_ingest/$test"
  ./test_unstructured_ingest/src/"$test"
  rc=$?
  if [[ $rc -eq 8 ]]; then
    echo "$test (skipped due to missing env var)" | tee -a "$SKIPPED_FILES_LOG"
  else
    # Check if the test is in tests_to_ignore
    ignore_test=false
    for ignore in "${tests_to_ignore[@]}"; do
      if [[ "$ignore" == "$test" ]]; then
        ignore_test=true
        break
      fi
    done
    if $ignore_test; then
      echo "$test (skipped checking error code: $rc)" | tee -a "$SKIPPED_FILES_LOG"
      continue
    elif [[ $rc -ne 0 ]]; then
      exit $rc
    fi
  fi
  echo "--------- FINISHED SCRIPT $test ---------"
done

set +e

all_eval=(
  'text-extraction'
  'element-type'
)
for eval in "${all_eval[@]}"; do
  CURRENT_TEST="evaluation-metrics.sh $eval"
  echo "--------- RUNNING SCRIPT evaluation-metrics.sh $eval ---------"
  ./test_unstructured_ingest/evaluation-metrics.sh "$eval" "$EVAL_OUTPUT_ROOT"
  echo "--------- FINISHED SCRIPT evaluation-metrics.sh $eval ---------"
done
