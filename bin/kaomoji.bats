#!/usr/bin/env bats
#
# Run with a bash 4+ ahead of bats on PATH:
#   PATH="/opt/homebrew/opt/bash/bin:$PATH" bats bin/kaomoji.bats

setup() {
  KAOMOJI="${BATS_TEST_DIRNAME}/kaomoji"
  # Stub pbcopy so tests never touch the real clipboard.
  STUB_DIR="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB_DIR"
  cat > "$STUB_DIR/pbcopy" <<EOF
#!/usr/bin/env bash
cat > "$BATS_TEST_TMPDIR/clipboard"
EOF
  chmod +x "$STUB_DIR/pbcopy"
  PATH="$STUB_DIR:$PATH"
}

clipboard() { cat "$BATS_TEST_TMPDIR/clipboard"; }

@test "summons one face by default" {
  run "$KAOMOJI"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ -n "${lines[0]}" ]
}

@test "copies the printed face to the clipboard" {
  run "$KAOMOJI"
  [ "$status" -eq 0 ]
  [ "$(clipboard)" = "${lines[0]}" ]
}

@test "clipboard content has no trailing newline" {
  run "$KAOMOJI"
  [ "$status" -eq 0 ]
  # wc -l counts newlines; a trailing-newline-free single line gives 0.
  [ "$(wc -l < "$BATS_TEST_TMPDIR/clipboard" | tr -d ' ')" -eq 0 ]
}

@test "a mood argument picks from that mood" {
  run "$KAOMOJI" shrug
  [ "$status" -eq 0 ]
  run bash -c "'$KAOMOJI' --list shrug | grep -Fxq \"$(cat "$BATS_TEST_TMPDIR/clipboard")\""
  [ "$status" -eq 0 ]
}

@test "unknown mood fails with a helpful message" {
  run "$KAOMOJI" nonsense
  [ "$status" -eq 1 ]
  [[ "$output" == *"no such mood: nonsense"* ]]
  [[ "$output" == *"moods:"* ]]
}

@test "--list with no mood lists mood names" {
  run "$KAOMOJI" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"shrug"* ]]
  [[ "$output" == *"table-flip"* ]]
  [[ "$output" == *"friday"* ]]
}

@test "--list MOOD prints only that mood's faces, no blank lines" {
  run "$KAOMOJI" --list shrug
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -gt 1 ]
  for line in "${lines[@]}"; do
    [ -n "$line" ]
  done
}

@test "--list does not touch the clipboard" {
  run "$KAOMOJI" --list
  [ "$status" -eq 0 ]
  [ ! -f "$BATS_TEST_TMPDIR/clipboard" ]
}

@test "--all prints every mood with indented faces" {
  run "$KAOMOJI" --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"shrug:"* ]]
  [ ! -f "$BATS_TEST_TMPDIR/clipboard" ]
}

@test "-n prints that many candidates" {
  run "$KAOMOJI" -n 3 happy
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "-n copies only the first candidate" {
  run "$KAOMOJI" -n 3 happy
  [ "$status" -eq 0 ]
  [ "$(clipboard)" = "${lines[0]}" ]
}

@test "-n rejects non-numeric values" {
  run "$KAOMOJI" -n abc
  [ "$status" -eq 2 ]
}

@test "-n rejects zero" {
  run "$KAOMOJI" -n 0
  [ "$status" -eq 2 ]
}

@test "rejects two mood arguments" {
  run "$KAOMOJI" happy sad
  [ "$status" -eq 2 ]
  [[ "$output" == *"too many arguments"* ]]
}

@test "unknown option fails with usage" {
  run "$KAOMOJI" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "--help exits clean" {
  run "$KAOMOJI" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage:"* ]]
}

@test "re-execs successfully under macOS bash 3.2" {
  # The whole point of the re-exec guard. Without this the suite only ever
  # tests the bash-4 path, because bats already runs under bash 4.
  if [ ! -x /bin/bash ]; then skip "no /bin/bash"; fi
  case "$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}')" in
    [4-9]|[1-9][0-9]) skip "/bin/bash is already 4+" ;;
  esac
  run /bin/bash "$KAOMOJI" shrug
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "every listed mood has at least one face" {
  run "$KAOMOJI" --list
  [ "$status" -eq 0 ]
  for mood in $output; do
    run "$KAOMOJI" --list "$mood"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
  done
}

@test "every mood is summonable" {
  moods=$("$KAOMOJI" --list)
  for mood in $moods; do
    run "$KAOMOJI" "$mood"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
  done
}
