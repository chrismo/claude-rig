#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Frontmatter lint for the skills in this repo.
#
# Claude Code parses SKILL.md frontmatter leniently. pi does not — it uses the
# `yaml` npm package, which is spec-correct, and a skill it cannot parse is
# reported at startup as a skill conflict and dropped. Since install.sh now
# serves skills to both harnesses, the stricter parser sets the bar for all of
# them, not just the four on the pi allowlist: a skill can join that list later,
# and there is no reason to keep a latent YAML bug in the others.
#
# The bug this suite was written for: a plain (unquoted) scalar cannot contain
# ": " — YAML reads it as a nested mapping. dialogue's when_to_use ran
# "...halts work: never enter it..." and pi rejected the whole file.
#
# Parser preference: pi's own `yaml`, so the check is exactly what pi will do.
# Ruby's Psych is the fallback — spec-compliant, and it rejects the same shape.
# With neither, the suite skips rather than passing on no evidence.

REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

# Resolve pi's bundled yaml from wherever pi is installed: the `pi` on PATH is a
# symlink into <package>/dist/bundle/cli.js.
pi_yaml_dir() {
  local pi_bin pkg_root
  pi_bin="$(command -v pi 2>/dev/null)" || return 1
  pi_bin="$(readlink -f "$pi_bin" 2>/dev/null)" || return 1
  pkg_root="$(cd "$(dirname "$pi_bin")/../.." && pwd)" || return 1
  [[ -d "$pkg_root/node_modules/yaml" ]] || return 1
  echo "$pkg_root/node_modules/yaml"
}

# Print "FAIL <file> :: <message>" for each unparseable frontmatter block.
check_frontmatter() {
  local yaml_dir
  if yaml_dir="$(pi_yaml_dir)" && command -v node &>/dev/null; then
    node -e '
      const fs = require("fs");
      const YAML = require(process.argv[1]);
      for (const f of process.argv.slice(2)) {
        const m = fs.readFileSync(f, "utf8").match(/^---\n([\s\S]*?)\n---/);
        if (!m) { console.log("FAIL", f, ":: no frontmatter block"); continue; }
        try { YAML.parse(m[1]); }
        catch (e) { console.log("FAIL", f, "::", e.message.split("\n")[0]); }
      }
    ' "$yaml_dir" "$@"
  elif command -v ruby &>/dev/null; then
    ruby -ryaml -e '
      ARGV.each do |f|
        m = File.read(f)[/\A---\n(.*?)\n---/m, 1]
        (puts "FAIL #{f} :: no frontmatter block"; next) unless m
        begin; YAML.safe_load(m); rescue => e; puts "FAIL #{f} :: #{e.message.lines.first.strip}"; end
      end
    ' "$@"
  else
    return 2
  fi
}

@test "every SKILL.md has frontmatter a strict YAML parser accepts" {
  run check_frontmatter "$REPO"/skills/*/SKILL.md
  [ "$status" -ne 2 ] || skip "no strict YAML parser available (pi or ruby)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
