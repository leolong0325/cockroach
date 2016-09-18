#!/usr/bin/env bash

set -euo pipefail

export PKG=${PKG:-./...}

TestCopyrightHeaders() {
  echo "checking for missing license headers"
  ! git grep -LE '^// (Copyright|Code generated by)' -- '*.go'
}

TestTimeutil() {
  echo "checking for time.Now and time.Since calls (use timeutil instead)"
  ! git grep -nE 'time\.(Now|Since)' -- '*.go' | grep -vE '^util/(log|timeutil)/\w+\.go\b'
}

TestEnvutil() {
  echo "checking for os.Getenv calls (use envutil.EnvOrDefault*() instead)"
  ! git grep -nF 'os.Getenv' -- '*.go' | grep -vE '^((util/(log|envutil|sdnotify))|acceptance(/.*)?)/\w+\.go\b'
}

TestGrpc() {
  echo "checking for grpc.NewServer calls (use rpc.NewServer instead)"
  ! git grep -nF 'grpc.NewServer()' -- '*.go' | grep -vE '^rpc/context(_test)?\.go\b'
}

TestProtoClone() {
  echo "checking for proto.Clone calls (use protoutil.Clone instead)"
  ! git grep -nE '\.Clone\([^)]+\)' -- '*.go' | grep -vF 'protoutil.Clone' | grep -vE '^util/protoutil/clone(_test)?\.go\b'
}

TestProtoMarshal() {
  echo "checking for proto.Marshal calls (use protoutil.Marshal instead)"
  ! git grep -nE '\.Marshal\([^)]+\)' -- '*.go' | grep -vE '(json|yaml|protoutil)\.Marshal' | grep -vE '^util/protoutil/marshal(_test)?\.go\b'
}

TestSyncMutex() {
  echo "checking for sync.{,RW}Mutex usage (use syncutil.{,RW}Mutex instead)"
  ! git grep -nE 'sync\.(RW)?Mutex' -- '*.go' | grep -vE '^util/syncutil/mutex_sync\.go\b'
}

TestMissingLeakTest() {
  echo "checking for missing defer leaktest.AfterTest"
  util/leaktest/check-leaktest.sh
}

TestMisspell() {
  # https://github.com/client9/misspell/issues/62
  # https://github.com/client9/misspell/issues/63
  ! git ls-files | xargs misspell | grep -vE 'found "(computable|duplicative)" a misspelling of'
}

TestTabsInShellScripts() {
  echo "checking for tabs in shell scripts"
  ! git grep -F "$(echo -ne '\t')" -- '*.sh'
}

TestForbiddenImports() {
  echo "checking for forbidden imports"
  local log=$(mktemp -t test-forbidden-imports.XXXXXX)
  trap "rm -f ${log}" EXIT

  go list -f '{{ $ip := .ImportPath }}{{ range .Imports}}{{ $ip }}: {{ println . }}{{end}}{{ range .TestImports}}{{ $ip }}: {{ println . }}{{end}}{{ range .XTestImports}}{{ $ip }}: {{ println . }}{{end}}' "$PKG" | \
       grep -E ' (github.com/golang/protobuf/proto|github.com/satori/go\.uuid|log|path|context)$' | \
       grep -vE 'cockroach/(base|security|util/(log|randutil|stop)): log$' | \
       grep -vE 'cockroach/(server/serverpb|ts/tspb): github.com/golang/protobuf/proto$' | \
       grep -vF 'util/uuid: github.com/satori/go.uuid' | tee ${log}; \
    if grep -E ' path$' ${log} > /dev/null; then \
       echo; echo "Please use 'path/filepath' instead of 'path'."; echo; \
    fi; \
    if grep -E ' log$' ${log} > /dev/null; then \
       echo; echo "Please use 'util/log' instead of 'log'."; echo; \
    fi; \
    if grep -E ' github.com/golang/protobuf/proto$' ${log} > /dev/null; then \
       echo; echo "Please use 'gogo/protobuf/proto' instead of 'golang/protobuf/proto'."; echo; \
    fi; \
    if grep -E ' github.com/satori/go\.uuid$' ${log} > /dev/null; then \
       echo; echo "Please use 'util/uuid' instead of 'satori/go.uuid'."; echo; \
    fi; \
    if grep -E ' context$' ${log} > /dev/null; then \
       echo; echo "Please use 'golang.org/x/net/context' instead of 'context'."; echo; \
    fi; \
    test ! -s ${log}
  ret=$?
  return $ret
}

TestImportNames() {
    echo "checking for named imports"
    if git grep -h '^\(import \|[[:space:]]*\)\(\|[a-z]* \)"database/sql"$' -- '*.go' | grep -v '\<gosql "database/sql"'; then
        echo "Import 'database/sql' as 'gosql' to avoid confusion with 'cockroach/sql'."
        return 1
    fi
    return 0
}

TestIneffassign() {
  ! ineffassign . | grep -vF '.pb.go' # https://github.com/gogo/protobuf/issues/149
}

TestErrcheck() {
  errcheck -ignore 'bytes:Write.*,io:Close,net:Close,net/http:Close,net/rpc:Close,os:Close,database/sql:Close' "$PKG"
}

TestReturnCheck() {
  returncheck "$PKG"
}

TestVet() {
  local vet=$(go tool vet -all -shadow -printfuncs Info:1,Infof:1,InfofDepth:2,Warning:1,Warningf:1,WarningfDepth:2,Error:1,Errorf:1,ErrorfDepth:2,Fatal:1,Fatalf:1,FatalfDepth:2,UnimplementedWithIssueErrorf:1 . 2>&1)
  ! echo "$vet" | grep -vE 'declaration of "?(pE|e)rr"? shadows' | grep -vE '\.pb\.gw\.go:[0-9]+: declaration of "?ctx"? shadows' | grep -vE '^vet: cannot process directory \.git'
}

TestGolint() {
  ! golint "$PKG" | grep -vE '((\.pb|\.pb\.gw|embedded|_string)\.go|sql/parser/(yaccpar|sql\.y):)'
}

TestGoSimple() {
  ! gosimple "$PKG" | grep -vF 'embedded.go'
}

TestVarcheck() {
  ! varcheck -e "$PKG" | \
    grep -vE '(_string.go|sql/parser/(yacctab|sql\.y)|\.pb\.go|pgerror/codes.go)'
}

TestGofmtSimplify() {
  ! gofmt -s -d -l . 2>&1 | grep -vE '^\.git/'
}

TestGoimports() {
  ! goimports -l . | read
}

TestUnconvert() {
  ! unconvert "$PKG" | grep -vF '.pb.go:'
}

TestUnused() {
  ! unused -exported ./... | grep -vE '(\.pb\.go:|/C:|_string.go:|embedded.go:|parser/(yacc|sql.y)|util/interval/interval.go:|_cgo|Mutex|pgerror/codes.go)'
}

TestStaticcheck() {
  staticcheck ./...
}

# Run all the tests, wrapped in a similar output format to "go test"
# so we can use go2xunit to generate reports in CI.

runcheck() {
  local name="$1"
  shift
  echo "=== RUN $name"
  local start=$(date +%s)
  output=$(eval "$name")
  local status=$?
  local end=$(date +%s)
  local runtime=$((end-start))
  if [ $status -eq 0 ]; then
    echo "--- PASS: $name ($runtime.00s)"
  else
    echo "--- FAIL: $name ($runtime.00s)"
    echo "$output"
  fi
  return $status
}

exit_status=0

# "declare -F" lists all the defined functions, in the form
# declare -f runcheck
# declare -f TestUnused
tests=$(declare -F|cut -d' ' -f3|grep '^Test'|grep "${TESTS-.}")
export -f runcheck
export -f $tests
if hash parallel 2>/dev/null; then
  parallel -j4 runcheck {} ::: $tests || exit_status=$?
else
  for i in $tests; do
    check_status=0
    runcheck $i || check_status=$?
    if [ $exit_status -eq 0 ]; then
      exit_status=$check_status
    fi
  done
fi

if [ $exit_status -eq 0 ]; then
  echo "ok check-style 0.000s"
else
  echo "FAIL check-style 0.000s"
fi
exit $exit_status
