## Regular-expression engine for C3

Efficient (non‑backtracking) Thompson NFA regular‑expression engine for **C3**,
with **submatch tracking** and **leftmost‑longest** semantics. Ported from the
classic Plan 9 implementation by Rob Pike.

---

### Features

* Linear‑time matching (no catastrophic backtracking)
* Submatches (capture groups) with indices
* Alternation `|`, concatenation, quantifiers `* + ?`, grouping `(...)`
* Character classes `[abc]`, ranges `[a-z]`, and negation `[^...]`
* Anchors `^` and `$`, dot `.`
* UTF‑8 aware: operates on Unicode code points (runes)
* Leftmost‑longest match semantics (egrep‑style)
* Small, dependency‑light C3 library (`.c3l`)

> Not in scope: backreferences, look‑around, and other Perl/PCRE extensions.

---

### Install (via c3l)

Use **[c3l](https://github.com/konimarti/c3l)** to
fetch and wire the dependency automatically.

From your project root (where `project.json` lives):

```bash
# Fetch a specific version tag (recommended)
c3l fetch https://github.com/konimarti/regexp9.c3l vX.Y.Z

# Or fetch the default branch
c3l fetch https://github.com/konimarti/regexp9.c3l
```

This updates `project.json` and stores the compressed library under your
dependency search path.

> **Tip:** To update later, run `c3l update regexp9`. To remove, `c3l remove regexp9`.

---

### Alternative: manual installation

If you prefer not to use c3l:
1. **Add the library path** to your project’s `project.json` → `dependency-search-paths`.
2. **Add the dependency name** to `dependencies`.

Example `project.json` snippet:

```json
{
  "dependency-search-paths": [
    "lib",                
    "../third_party"      
  ],
  "dependencies": [
    "regexp9"
  ]
}
```

Place the `regexp9.c3l` folder anywhere listed in `dependency-search-paths` (e.g., `third_party/regexp9.c3l`).

---

### Quick start

```c
import regexp9;

fn void main() {

    // Compiled program
    Reprog *prog = regexp9::compile("(ab|a)b+")!!;   

    // Execute with captures (up to 10 capture pairs)
    Resub[10] subs;
    if (regexp9::match(prog, "aabbb", subs[..], 10)!!) {
        // subs[0] = whole match, subs[1] = group 1, etc.
        // Each Resub can return its match with subs[i].match().
    }
}
```

String replacement (if you need it):

```c
// Given a successful regexec, produce a substituted string using \1, \2, ...
String s = regexp9::substitute(mem, "X-\\1-Y", subs[..]);
defer s.free(mem);
```

> Type/func names mirror the Plan 9 API. See `regexp9.c3` and
> `regexp9_test.c3` for the exact signatures in this port.

---

### API overview

C3 API:
* `Reprog*? compile(Allocator allocator, ZString pattern)` — Compile pattern into a program
* `Reprog*? tcompile(ZString pattern)` — Compile pattern into a program that is allocated on tmem
* `bool? match(Reprog* prog, ZString text, Resub[] subs = {})` — Run program on text; fill `subs` with capture ranges
* `String substitute(String src, Resub[] subs)` — Expand `\1`, `\2`, … with captures

Plan9 API:
* `Reprog*? regcomp(ZString s)` — Compile pattern into a program
* `int regexec(Reprog* prog, char* text, Resub* subs, int slen)` — Run program on text; fill `subs` with capture ranges
* `void regsub(char* src, char* dst, int dlen, Resub* subs, int slen)` — Expand `\1`, `\2`, … using captures

* Types:

  * `Reprog` — compiled Thompson NFA program
  * `Resub` — capture groups

---

### Supported syntax (summary)

```
Literals:         a b c …  (escape metacharacters with \)
Classes:          [abc] [a-z] [^...] (negation)
Dot:              .        (any char)
Anchors:          ^  $
Grouping:         ( ... )
Alternation:      A|B
Quantifiers:      A*  A+  A?    (greedy)
```

---

### Tests & Benchmarks

```bash
# Run the benchmarks 
c3c bench

#  Run the tests
c3c test
```

---

### Performance notes

* Thompson NFA executed in lock‑step (the “Pike VM”) → linear in input length.
* Two worklists per input character; ε‑closure is expanded eagerly.
* Submatch registers propagate per thread; no backtracking required to recover captures.

---

### Roadmap / ideas

* Pre‑filter for literal prefixes to skip obvious non‑matches
* Improve error handling
* Rewrite parts into more idiomatic C3
* Additional character‑class helpers (`\d`, `\s`, `\w`) as short‑hands

PRs are welcome.

---

### Acknowledgments

Plan 9 regexp by **Rob Pike**; background write‑ups by **Russ Cox** on Thompson
NFAs and submatch tracking.

[https://9fans.github.io/plan9port/unix/]
[https://swtch.com/~rsc/regexp/regexp1.html]


