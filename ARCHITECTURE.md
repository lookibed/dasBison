# dasBison architecture

This document follows `ARCHITECTURE_COMMON.md` (a copy sits at this package's root). dasBison is a
pure daslang parser generator: LALR(1) tables over integer terminals, a byte-class front end on top
of them, a deterministic driver, and the `[bison]` macro, which builds the tables at compile time
and generates a typed parser over a dasFlex lexer, and the `%bison~` reader, its yacc-like text form.
The core (`lalr`, `prec`, `bytes`,
`grammar_text`) depends on `daslib/` alone; `bison_parser` and `bison_macro` also depend on
dasFlex's runtime module `flex/flex`, the only package dasBison requires.

## File charters

- `bison/lalr.das` - the core: `LalrBuilder` (`term_id`, `declare_terms`, `rule_id`,
  `add_production`, `term_sym`, `rule_sym`; `intern`, the name table under `term_id`, `rule_id`
  and the byte adapter's rules), `build_lalr` and its result `LalrTables`, the conflict report
  (`describe_conflicts`, `describe_prod`, `describe_action`), the driver (`lr_parse`, `LrParse`),
  and `lr_expected`, the expected-set walk over flat tables that `lr_parse` and a `[bison]`
  parser both call. Knows nothing of bytes or text. `LalrBuilder.prec_terms` and `prec_prods`
  hold the precedence declarations; only `bison/prec.das` writes or reads them.
- `bison/prec.das` - the precedence layer: the declarations (`prec_left`, `prec_right`,
  `prec_nonassoc`, `prec_of_production`), `resolve_precedence` and its `PrecResult` /
  `PrecReport` / `PrecCell`, and `format_report`. Reads the core's tables, never builds them.
- `bison/bytes.das` - the byte adapter: `GrammarBuilder` over byte sets (`sym_byte`, `sym_bytes`,
  `sym_rule`), the byte partition, `build_grammar` and its result `Grammar` (`byte_class`,
  `nclasses`, the core's `tables`), and `byte_terms` / `lr_parse_bytes`.
- `bison/grammar_text.das` - grammars as yacc-like text: `parse_rhs` (`TextRhs`, `TextSymbol`),
  `grammar_from_text` from `TextRule`s and `TextPrec`s into a `TextGrammar` (the core's builder,
  the token kind of every terminal), `conflict_warning` and `conflict_mismatch`, and the lexing both text front ends share
  (`quoted_char`, `is_name_start`, `is_name_char`), so a quoted character or a name reads the same
  in a right-hand side and in `%bison~` text. Emits no code.
- `bison/bison_parser.das` - what a generated parser runs on: `Parser`, `parser_open`,
  `text(lx, token)`, and the helpers the driver calls (`bison_pop`, `bison_terminal`,
  `bison_keep_popped`, `bison_expected`, `bison_syntax_error`, `bison_lexer_failed`). Builds no
  tables.
- `bison/bison_macro.das` - the `[bison]` function annotation: reads the body's calls, builds and
  resolves the tables, and emits the globals, the action functions and the driver. Holds no
  runtime code the generated parser calls. Its design, and the reader's: `ARCHITECTURE_MACRO.md`.
- `bison/bison_reader.das` - the `%bison~` reader: `bison_reader_source` (the text into the source
  of a `[bison]` function, `BisonReaderOutput`) and the `BisonReader` reader macro. Builds no
  tables and no AST; `bison_macro` requires it publicly, so `require bison/bison_macro` brings it.
- `tutorials/` - one runnable page per topic; `01_calculator.das` is the macro's walk-through,
  `02_bison_reader.das` the same calculator as `%bison~` text.
- `tests/` - the package's tests; `tests/_grammar_c11.das` is the C11 grammar fixture (the
  owner's probe grammar, its productions folded into `add_production` literals), which dastest
  skips as a test for its leading `_`, as it skips the other shared helpers (`_compile_issues`,
  `_bison_run`, `_lalr_fixtures`).

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

## Lookaheads and tables {#lookaheads}

LR(0) kernels, then LALR(1) lookaheads by spontaneous generation and propagation (the dragon
book's 4.7.5): each kernel item's closure is taken once with the marker `#`. The table step
reuses the same marker closure: a completed item whose lookahead is a terminal reduces on it, and
one whose lookahead is `#` reduces on every lookahead of its kernel item.

## Conflicts are kept {#conflicts}

A cell more than one action claims is not an error and is not resolved. Shifts are written
first, so the cell's first action - a shift when there is one - stays in `action` and every other
action goes to `alt[cell]`, without duplicates. `conflicts` counts the cells, `first_conflict`
names the first, `describe_conflicts` lists each with all its actions. Precedence and
associativity are not part of the core: the precedence layer chooses among a cell's actions
only because none was dropped (`#precedence`).

## Well-formed grammars {#well-formed}

`build_lalr` sets `err` and builds no tables when the root is not a rule, a production names an
undeclared terminal or rule, or a rule the root reaches derives no terminal string (a rule with
no production included). The last is the error dasLR1 reports, with the same text, naming the
first such rule; `err_rule` holds its name, so a front end places the error at the rule's line. A rule the root never reaches is not checked: a grammar keeps its helpers.

## The driver {#driver}

`lr_parse` runs one stack and takes the primary action of a cell (`action`, never `alt`), which is
the shift in a shift/reduce cell - the dangling `else` binds to the inner `if`. On a refusal it
reports the token position, the state and the refused terminal, and the expected terminals: every
terminal that some reduce chain ends in a shift or accept for, from the stack the refused token was
read on. An LALR state merged from several contexts reduces on a token none of them takes, so the
stack at the refusal has lost terminals that were valid when the token was read; before each reduce,
`lr_keep_popped` keeps the read-time states the reduce removes, and `lr_stack_at_read` rebuilds that
stack. A `[bison]` driver calls the same two, through `bison_keep_popped` and `bison_expected`,
since the user's module sees only `bison/bison_parser`. The list is exact and not just the nonzero
cells of a state. `LR_MAX_REDUCES` bounds the reductions between two shifts, so a cyclic grammar's
primary actions cannot loop.

## The precedence layer {#precedence}

`bison/prec.das` resolves conflicts after `build_lalr`, the way yacc does, from declarations kept
in the builder. Each `prec_left` / `prec_right` / `prec_nonassoc` call gives its terminals the next
level, so a later call binds tighter. A production takes the precedence of its last terminal, or
of the terminal `prec_of_production` names (`%prec`); a production whose last terminal has no level
has none. `resolve_precedence(t, gb)` walks the conflicting cells in index order; in each, every
reduce (by ascending production) is held against the cell's shift while a shift remains:

| shift on `a`, reduce by `p` | result |
|---|---|
| `prec(p) > prec(a)` | reduce; the shift goes |
| `prec(p) < prec(a)` | shift; the reduce goes |
| equal, `a` is `%left` | reduce |
| equal, `a` is `%right` | shift |
| equal, `a` is `%nonassoc` | error: the cell gets action 0, every action goes |
| `a` or `p` has no level | kept for the default |
| no shift (reduce/reduce) | kept for the default; precedence is never used |

A cell left with one action is resolved by precedence. A cell left with more is unresolved: yacc's
default picks the shift, or else the production that comes first in the grammar, and the cell
still counts as a conflict - its losers stay in `alt`, `conflicts` counts it, and the report lists
it in `bison -v`'s words (`State N conflicts: K shift/reduce, M reduce/reduce`, then each action,
the losers in brackets). The counts are bison's: one shift/reduce for a cell with a shift and a
reduce, one reduce/reduce for each reduce past the first. Every action that leaves a cell is in
that cell's `PrecCell.removed`.

The result is a copy: the input tables keep every action, so the same build serves another set of
declarations, `describe_conflicts` still shows what the grammar itself leaves open, and
resolution is a function of (tables, declarations) rather than a mutation whose history is lost.
The copy is an ordinary `LalrTables`: `lr_parse` reads it unchanged, and an error cell refuses its
terminal with the expected set the reduce chains compute (`#driver`).
