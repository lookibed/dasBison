# dasBison architecture

This document follows `ARCHITECTURE_COMMON.md` (a copy sits at this package's root). dasBison is a
pure daslang parser generator: LALR(1) tables built at run time over integer terminals, a byte-class
front end on top of them, and a deterministic driver. It depends on `daslib/` and on nothing under
`modules/`.

## File charters

- `bison/lalr.das` - the core: `LalrBuilder` (`term_id`, `declare_terms`, `rule_id`,
  `add_production`, `term_sym`, `rule_sym`), `build_lalr` and its result `LalrTables`, the
  conflict report (`describe_conflicts`, `describe_prod`, `describe_action`), and the driver
  (`lr_parse`, `LrParse`). Knows nothing of bytes or text.
- `bison/bytes.das` - the byte adapter: `GrammarBuilder` over byte sets (`sym_byte`, `sym_bytes`,
  `sym_rule`), the byte partition, `build_grammar` and its result `Grammar` (`byte_class`,
  `nclasses`, the core's `tables`), and `byte_terms` / `lr_parse_bytes`.
- `tests/` - the package's tests; `tests/_grammar_c11.das` is the C11 grammar fixture (the
  owner's probe grammar, its productions folded into `add_production` literals), which dastest
  skips as a test because of its leading `_`.

## Integer terminals {#int-terminals}

A terminal is an integer id `0 .. n-1`, declared by name (`term_id`) or by count
(`declare_terms`). `build_lalr` appends one more terminal, `<end>`, so the end of input is the last
id (`LalrTables.eof = nterms - 1`) and gets an ordinary column: `action[state * nterms + term]`.
A right-hand-side symbol is an `int`: a terminal id as itself, a rule `r` as `-(1 + r)`. The
augmented start `<start> ::= root` is production 0 and the last rule id. A token stream from any
lexer - a `dasFlex` scanner, a hand-written one - is an array of these ids, so the core never
sees the shape of the input.

## The byte layer is an adapter {#byte-adapter}

A byte grammar's terminals are byte sets. `build_grammar` partitions the 256 byte values into
the finest classes every set of the grammar is a union of (the same refinement dasLR1 runs,
numbered in byte order), declares class `c` as core terminal `c`, and declares every rule of the
byte grammar under the same id. A set that is one class is that terminal in place; a set that
spans several becomes a fresh rule `<setN>` with one production per class, shared by every use
of the same class set and added just before the first production that uses it. Everything then
goes through the core's public builder, and the tables the adapter returns are the core's own.
The adapter is a front end, not a second builder: one LALR implementation serves token grammars
and byte grammars, and a fix to the construction reaches both. The C11 gate shows the two paths
agree: the probe grammar builds to 479 states and 2 conflicts both through 98 byte classes and
with one integer terminal per token.

## Item keys {#item-key}

An LR(0) item (production, dot) gets a dense id: `item_base[p] + dot`, where `item_base` sums
`length(rhs) + 1` over the productions before `p`. An LR(1) key is
`int64(item) * (nterms + 1) + lookahead`, with lookaheads `0 .. nterms` (`nterms` itself is the
propagation marker `#`). The multiplier is the real alphabet width, so no field has a fixed
width: with any item count that fits in `int` and any terminal count, the key stays below 2^62.
A packing like dasLR1's (`(prod * 4096 + dot) * 1024 + la`) collides once a production passes
4096 symbols or a grammar passes 1023 terminals, which integer terminals reach easily. State
identity is the sorted list of kernel item ids.

## Lookaheads and tables

LR(0) kernels, then LALR(1) lookaheads by spontaneous generation and propagation (the dragon
book's 4.7.5): each kernel item's closure is taken once with the marker `#`. The table step
reuses the same marker closure: a completed item whose lookahead is a terminal reduces on it, and
one whose lookahead is `#` reduces on every lookahead of its kernel item.

## Conflicts are kept {#conflicts}

A cell more than one action claims is not an error and is not resolved. Shifts are written
first, so the cell's first action - a shift when there is one - stays in `action` and every other
action goes to `alt[cell]`, without duplicates. `conflicts` counts the cells, `first_conflict`
names the first, `describe_conflicts` lists each with all its actions. Precedence and
associativity are not part of the core: a later resolution layer can choose among a cell's
actions only because none was dropped.

## Well-formed grammars {#well-formed}

`build_lalr` sets `err` and builds no tables when the root is not a rule, a production names an
undeclared terminal or rule, or a rule the root reaches derives no terminal string (a rule with
no production included). The last is the error dasLR1 reports, with the same text, naming the
first such rule by id. A rule the root never reaches is not checked: a grammar keeps its helpers.

## The driver {#driver}

`lr_parse` runs one stack and takes the primary action of a cell (`action`, never `alt`), which
is the shift in a shift/reduce cell - the dangling `else` binds to the inner `if`. On a refusal
it reports the token position, the state and the refused terminal, and the expected terminals:
every terminal that some reduce chain from the current stack ends in a shift or accept for, so
the list is exact and not just the nonzero cells of the top state. `LR_MAX_REDUCES` bounds the
reductions between two shifts, so a cyclic grammar's primary actions cannot loop.
