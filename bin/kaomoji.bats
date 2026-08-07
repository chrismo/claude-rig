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
  # Compare via files, not an interpolated shell string: `¯\_(ツ)_/¯` has
  # backslashes that a "$(cat ...)" round-trip mangles, so the old form
  # failed only on the draws that happened to pick it.
  "$KAOMOJI" --list shrug > "$BATS_TEST_TMPDIR/faces"
  grep -Fxq -f "$BATS_TEST_TMPDIR/clipboard" "$BATS_TEST_TMPDIR/faces"
}

@test "exact mood name wins over any partial interpretation" {
  run bash -c "diff <('$KAOMOJI' list cat) <('$KAOMOJI' list cat)"
  [ "$status" -eq 0 ]
  run "$KAOMOJI" cat 99
  [ "$status" -eq 0 ]
  # 'cat' is exact, so the pool is exactly the cat faces (4 of them).
  exact=$("$KAOMOJI" list cat | wc -l | tr -d ' ')
  [ "${#lines[@]}" -eq "$exact" ]
}

@test "partial matches a single mood" {
  # 'determ' hits only determined -- no synonym contains it.
  run bash -c "diff <('$KAOMOJI' determ 99 | LC_ALL=C sort -u) <('$KAOMOJI' list determined | LC_ALL=C sort -u)"
  [ "$status" -eq 0 ]
}

@test "a partial matching both a mood and a synonym pools both" {
  # 'rag' hits mood 'rage' AND synonym 'ragequit' -> table-flip.
  expected=$( { "$KAOMOJI" list rage; "$KAOMOJI" list table-flip; } | LC_ALL=C sort -u )
  run bash -c "'$KAOMOJI' rag 99 | LC_ALL=C sort -u"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "substring anywhere, not just prefix" {
  # 'lebra' is inside 'celebrate'.
  run bash -c "diff <('$KAOMOJI' lebra 99 | LC_ALL=C sort -u) <('$KAOMOJI' list celebrate | LC_ALL=C sort -u)"
  [ "$status" -eq 0 ]
}

@test "ambiguous partial pools all matching moods" {
  # 'table' hits table-flip and table-unflip; the pool is both.
  expected=$( { "$KAOMOJI" list table-flip; "$KAOMOJI" list table-unflip; } | LC_ALL=C sort -u )
  run bash -c "'$KAOMOJI' table 99 | LC_ALL=C sort -u"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "ambiguous partial does not error" {
  run "$KAOMOJI" table
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "synonym resolves to its mood" {
  run bash -c "diff <('$KAOMOJI' mad 99 | LC_ALL=C sort -u) <('$KAOMOJI' list rage | LC_ALL=C sort -u)"
  [ "$status" -eq 0 ]
}

@test "synonyms are single words with no hyphens" {
  run "$KAOMOJI" --synonyms
  [ "$status" -eq 0 ]
  while read -r alias target; do
    [ -n "$alias" ] || continue
    [[ ! "$alias" =~ [[:space:]] ]]
    [[ ! "$alias" =~ - ]]
  done <<< "$output"
}

@test "no synonym collides with a real mood name" {
  moods=$("$KAOMOJI" --moods)
  "$KAOMOJI" --synonyms | while read -r alias target; do
    [ -n "$alias" ] || continue
    if grep -qxF "$alias" <<< "$moods"; then
      echo "synonym '$alias' shadows real mood '$alias'" >&2
      exit 1
    fi
  done
}

@test "every synonym points at a real mood" {
  moods=$("$KAOMOJI" --moods)
  "$KAOMOJI" --synonyms | while read -r alias target; do
    [ -n "$target" ] || continue
    if ! grep -qxF "$target" <<< "$moods"; then
      echo "synonym '$alias' -> unknown mood '$target'" >&2
      exit 1
    fi
  done
}

@test "every synonym is summonable" {
  "$KAOMOJI" --synonyms | while read -r alias target; do
    [ -n "$alias" ] || continue
    "$KAOMOJI" "$alias" >/dev/null || { echo "'$alias' failed" >&2; exit 1; }
  done
}

@test "genuinely unknown mood still fails" {
  run "$KAOMOJI" zzzznope
  [ "$status" -eq 1 ]
  [[ "$output" == *"no such mood"* ]]
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

@test "list shows synonyms in parens after the mood" {
  run "$KAOMOJI" list
  [ "$status" -eq 0 ]
  # Aliases are sorted, so rage's line reads "(angry furious mad pissed)".
  [[ "$output" == *"rage"*"(angry"*"mad"*")"* ]]
}

@test "every mood with synonyms shows them all in its list line" {
  run "$KAOMOJI" list
  [ "$status" -eq 0 ]
  while read -r alias target; do
    [ -n "$alias" ] || continue
    line=$(grep -E "^${target}( |\$)" <<< "$output")
    [[ "$line" == *"$alias"* ]] || {
      echo "list line for '$target' is missing synonym '$alias': $line" >&2
      return 1
    }
  done < <("$KAOMOJI" --synonyms)
}

@test "a mood with no synonyms has no empty parens" {
  run "$KAOMOJI" list
  [ "$status" -eq 0 ]
  [[ "$output" != *"()"* ]]
}

@test "list still names every mood at line start" {
  run "$KAOMOJI" list
  [ "$status" -eq 0 ]
  while read -r mood; do
    grep -qE "^${mood}( |\$)" <<< "$output" || {
      echo "mood '$mood' not at start of any list line" >&2
      return 1
    }
  done < <("$KAOMOJI" --moods)
}

@test "--moods prints bare names for scripting" {
  run "$KAOMOJI" --moods
  [ "$status" -eq 0 ]
  # No parens, no synonyms -- just names, one per line.
  [[ "$output" != *"("* ]]
  [[ "$output" == *"rage"* ]]
}

@test "list MOOD still prints faces, not synonyms" {
  run bash -c "diff <('$KAOMOJI' list shrug) <('$KAOMOJI' --list shrug)"
  [ "$status" -eq 0 ]
  run "$KAOMOJI" list shrug
  [[ "$output" != *"meh"* ]]
}

@test "bare 'list' subcommand lists mood names" {
  run "$KAOMOJI" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"shrug"* ]]
  [[ "$output" == *"friday"* ]]
}

@test "'list MOOD' prints that mood's faces" {
  run "$KAOMOJI" list shrug
  [ "$status" -eq 0 ]
  run bash -c "diff <('$KAOMOJI' list shrug) <('$KAOMOJI' --list shrug)"
  [ "$status" -eq 0 ]
}

@test "'MOOD list' also works" {
  run bash -c "diff <('$KAOMOJI' shrug list) <('$KAOMOJI' --list shrug)"
  [ "$status" -eq 0 ]
}

@test "-l lists mood names" {
  run bash -c "diff <('$KAOMOJI' -l) <('$KAOMOJI' --list)"
  [ "$status" -eq 0 ]
}

@test "-l MOOD prints that mood's faces" {
  run bash -c "diff <('$KAOMOJI' -l shrug) <('$KAOMOJI' --list shrug)"
  [ "$status" -eq 0 ]
}

@test "'list' does not touch the clipboard" {
  run "$KAOMOJI" list
  [ "$status" -eq 0 ]
  [ ! -f "$BATS_TEST_TMPDIR/clipboard" ]
}

@test "-l does not touch the clipboard" {
  run "$KAOMOJI" -l shrug
  [ "$status" -eq 0 ]
  [ ! -f "$BATS_TEST_TMPDIR/clipboard" ]
}

@test "bare 'all' subcommand matches --all" {
  run bash -c "diff <('$KAOMOJI' all) <('$KAOMOJI' --all)"
  [ "$status" -eq 0 ]
}

@test "no mood is named 'all'" {
  run "$KAOMOJI" --list
  [ "$status" -eq 0 ]
  for mood in $output; do
    [ "$mood" != "all" ]
  done
}

@test "no mood is named 'list'" {
  # Otherwise the subcommand would shadow a real mood.
  run "$KAOMOJI" --list
  [ "$status" -eq 0 ]
  for mood in $output; do
    [ "$mood" != "list" ]
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

@test "-n copies all candidates space-delimited" {
  run "$KAOMOJI" -n 3 happy
  [ "$status" -eq 0 ]
  [ "$(clipboard)" = "${lines[0]} ${lines[1]} ${lines[2]}" ]
}

@test "omitting the count defaults to one" {
  run "$KAOMOJI" happy
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "count as a positional second argument" {
  run "$KAOMOJI" happy 5
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 5 ]
}

@test "positional count copies all candidates space-delimited" {
  run "$KAOMOJI" happy 3
  [ "$status" -eq 0 ]
  [ "$(clipboard)" = "${lines[0]} ${lines[1]} ${lines[2]}" ]
}

@test "count of 1 copies a bare face with no padding" {
  run "$KAOMOJI" happy 1
  [ "$status" -eq 0 ]
  [ "$(clipboard)" = "${lines[0]}" ]
}

@test "multi-copy still has no trailing newline" {
  run "$KAOMOJI" happy 3
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/clipboard" | tr -d ' ')" -eq 0 ]
}

@test "multi-copy joins with exactly one space" {
  run "$KAOMOJI" happy 4
  [ "$status" -eq 0 ]
  # No double spaces, no leading/trailing space.
  [[ "$(clipboard)" != *"  "* ]]
  [[ "$(clipboard)" != " "* ]]
  [[ "$(clipboard)" != *" " ]]
}

@test "clipboard still shows exactly what was printed" {
  run "$KAOMOJI" shrug 3
  [ "$status" -eq 0 ]
  printed=$(printf '%s\n' "${lines[@]}" | tr '\n' ' ')
  printed="${printed% }"
  [ "$(clipboard)" = "$printed" ]
}

@test "positional count works without a mood" {
  run "$KAOMOJI" 4
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
}

@test "count may precede the mood" {
  run "$KAOMOJI" 3 shrug
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "positional count rejects zero" {
  run "$KAOMOJI" happy 0
  [ "$status" -eq 2 ]
}

@test "two positional counts is an error" {
  run "$KAOMOJI" 2 3
  [ "$status" -eq 2 ]
  [[ "$output" == *"too many"* ]]
}

@test "a bare number is a count, never a mood" {
  # Guards against a future mood named e.g. "7" silently shadowing the count.
  run "$KAOMOJI" --list
  [ "$status" -eq 0 ]
  for mood in $output; do
    [[ ! "$mood" =~ ^[0-9]+$ ]]
  done
}

@test "-n still works alongside positional form" {
  run "$KAOMOJI" -n 2 happy
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "--list MOOD ignores a positional count" {
  run "$KAOMOJI" --list shrug 3
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -gt 3 ]
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

@test "SKILL.md catalog lists every face the script has" {
  # The skill inlines the catalog so the model can pick in ONE round-trip
  # instead of shelling out to --list first. That duplication has to be kept
  # honest, or /kaomoji starts copying faces the script doesn't know about.
  skill="${BATS_TEST_DIRNAME}/../skills/kaomoji/SKILL.md"
  [ -f "$skill" ] || skip "SKILL.md not found"

  missing=""
  while IFS= read -r face; do
    [ -n "$face" ] || continue
    grep -qF -- "$face" "$skill" || missing+="$face"$'\n'
  done < <("$KAOMOJI" --moods | while read -r m; do "$KAOMOJI" --list "$m"; done)

  if [ -n "$missing" ]; then
    echo "faces in bin/kaomoji but missing from SKILL.md catalog:" >&2
    echo "$missing" >&2
    return 1
  fi
}

@test "SKILL.md catalog names every mood the script has" {
  skill="${BATS_TEST_DIRNAME}/../skills/kaomoji/SKILL.md"
  [ -f "$skill" ] || skip "SKILL.md not found"

  while IFS= read -r mood; do
    grep -qF -- "$mood" "$skill" || {
      echo "mood '$mood' missing from SKILL.md catalog" >&2
      return 1
    }
  done < <("$KAOMOJI" --moods)
}

@test "every listed mood has at least one face" {
  run "$KAOMOJI" --moods
  [ "$status" -eq 0 ]
  for mood in $output; do
    run "$KAOMOJI" --list "$mood"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
  done
}

@test "every mood is summonable" {
  moods=$("$KAOMOJI" --moods)
  for mood in $moods; do
    run "$KAOMOJI" "$mood"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
  done
}
