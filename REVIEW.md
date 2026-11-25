# dasBison Code Review Checklist

**Read `REVIEW_COMMON.md` (package root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`.

**A diff under `bison/` that adds a `require` of a module other than one under `bison/`, one under
`daslib/`, or a builtin module the daslang executable registers itself (such as `strings` or
`math`) is a defect** - the package is installed by `daspkg` into projects that load nothing else
under `modules/`.

**A diff that resolves a table cell more than one action claims by keeping one action and dropping
the others is a defect** - the cell keeps its first action in `action` and every other in `alt`,
keyed by the cell index (`ARCHITECTURE.md#conflicts`).

**A diff that makes `bison/bytes.das` read or write anything of the core but its public builder
(`LalrBuilder`, `term_id`, `rule_id`, `add_production`, `term_sym`, `rule_sym`), `build_lalr`,
`lr_parse` and the fields of `LalrTables`, or that adds a byte, a byte class or a byte set to
`bison/lalr.das`, is a defect** - the byte layer is a front end over the integer core
(`ARCHITECTURE.md#byte-adapter`).

**A diff that keys items or (item, lookahead) pairs by a packing with a fixed field width for the
production, the dot or the lookahead is a defect** - integer terminals and long productions
overflow such a field silently (`ARCHITECTURE.md#item-key`).

**A diff that lets `build_lalr` return an empty `err` for a grammar in which a rule the root reaches
derives no terminal string, or a production names an undeclared symbol, is a defect**
(`ARCHITECTURE.md#well-formed`).

**A diff that makes the end of input anything but the last terminal id of `LalrTables` is a
defect** - every column layout, the byte adapter's included, assumes it
(`ARCHITECTURE.md#int-terminals`).

**A diff that makes `lr_parse` take an action from `alt`, or report `expected` other than through
the reduce chains from the stack, is a defect** (`ARCHITECTURE.md#driver`).

**A diff that makes `build_lalr` or anything it calls choose between the actions of a cell by
precedence, associativity or a default is a defect** - resolution is the precedence layer's, over
a copy of the tables (`ARCHITECTURE.md#precedence`).

**A diff that lets `resolve_precedence` take an action out of a cell without recording it in that
cell's `PrecCell` (`removed`, or `kept` for a default's loser), or resolve a cell by default
without counting it in `PrecReport.by_default`, is a defect** - the report is the only record
of what precedence and the default decided (`ARCHITECTURE.md#precedence`).

**A diff that changes the expected counts of `tests/c11_tests.das` (479 states, 98 classes, 2
conflicts on both paths) names the reason in its description** - they are dasLR1's own counts for
the same grammar.
