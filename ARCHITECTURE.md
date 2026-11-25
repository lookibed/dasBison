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
  the token kind of every terminal), `conflict_warning`, and the lexing both text front ends share
  (`quoted_char`, `is_name_start`, `is_name_char`), so a quoted character or a name reads the same
  in a right-hand side and in `%bison~` text. Emits no code.
- `bison/bison_parser.das` - what a generated parser runs on: `Parser`, `parser_open`,
  `text(lx, token)`, and the helpers the driver calls (`bison_pop`, `bison_terminal`,
  `bison_keep_popped`, `bison_expected`, `bison_syntax_error`, `bison_lexer_failed`). Builds no
  tables.
- `bison/bison_macro.das` - the `[bison]` function annotation: reads the body's calls, builds and
  resolves the tables, and emits the globals, the action functions and the driver. Holds no
  runtime code the generated parser calls.
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

## The `[bison]` macro {#macro}

`[bison(tokens = Enum, lexer = scan)]` on `def name(var p : Parser) : T` reads the body as a
grammar when the module compiles. The body holds calls only: `rule("lhs", "rhs")`, with or without
an action block, `prec_left` / `prec_right` / `prec_nonassoc("tok", ...)`, and one `root("rule")`, its
argument a literal (the first rule's left-hand side when absent, as in yacc). A right-hand side is text: an identifier
that is some rule's left-hand side is that rule, one that is a member of `Enum` is that token with
the member's value as its kind, a quoted character (`'+'`, `'\''`) is the token whose kind is its
byte, an empty string is the epsilon production, and a trailing `%prec NAME` gives the production
the level of `NAME`. A precedence argument is a token name, a quoted character or a bare
punctuation character, which names the token a right-hand side writes quoted (`\` is `'\\'`);
a name neither a token nor a quoted character is a pseudo-terminal no kind reaches (yacc's
`%prec UMINUS`). `scan` is the `[flex]` function the parser pulls tokens
from: one token per call, `p.lexer.tok.kind` its kind, `false` at the end of input or on a lexer
error. `Enum` is the enum the module sees by that name: its own, else the one a module it requires -
directly or through a public require - declares; two such modules are an ambiguity, and an enum
only some other loaded module declares is unknown. The enum is read from the AST at parse time, so a member's value is an integer literal of any
width or sign (a typed enum's `200u8` included), `-` before one, or the previous member's plus
one; an expression (`1 << 3`, a constant's name) is refused.

`grammar_from_text` turns the text into the core's builder; the macro adds nothing to the
construction. A terminal is keyed by its kind: two names for one kind are an error, so an enum
member cannot alias a quoted byte. The kind map the driver reads is an array indexed by kind,
which bounds kinds to `0 .. 65535`.

## Values {#values}

Every symbol on the parse stack has a value or none. A named token's value is its `FlexToken`; a
quoted character has none. A rule yields a value when an action of it returns one (a declared
result type other than `void`, or a `return` with a value in the block, not counting the blocks
nested in it); its type is the result type of the first such action. Every action of a rule
yields or every action of it does not. An action takes the values of its right-hand side in
order, or no argument at all; a production without an action passes its one value on (yacc's
`$$ = $1`) and is an error when it carries none or several in a rule that yields. A rule that
yields no value runs its actions for their effect. The root yields, and its value is the parser's
result.

Each action becomes a private function `<name>`bison`act`<i>(var p : Parser; args...)`, its result
type the block's or inferred. Its arguments are `var`: the value is popped off its stack and
belongs to the action, which can grow a list it was handed and return it. The parameter and the
arguments are generated variables - the grammar fixes their number and the macro their `var` - so
the argument lints skip them, while the body is linted as the user wrote it. The block's body runs
in that function, so `p` - the parser function's parameter, under its own name - is in scope and
nothing else of the parser is.

The value stack is one `array<T>` per rule that yields, plus `array<FlexToken>` for the tokens
and `array<int>` for the states. `apply` runs before type inference, when no action's result type
is known, so the macro cannot write a `variant` of the value types; it declares each rule's stack
as `array<typedecl(<first action>(p, default<args>...)) -const>`, which inference resolves. A stack
per symbol is exact: a reduce pops from the top of the parse stack, so the topmost value of a rule
is the last element of that rule's array. The stacks are plain arrays in the interpreter and the
JIT alike, with no tag to test and no boxing. The type agreement the typed stacks cannot report
by themselves - another action of the rule, or a pass-through, against the stack's type - is a
`static_assert` the driver opens with, reported at the rule's line.

## Compile-time tables {#compile-time-tables}

The annotation's `apply` builds the tables through `build_lalr` and `resolve_precedence` and stores
the resolved copy as private globals of the user's module - `action`, `goto`, the kind map, the
terminal names, and the left-hand side and length of every production (`prod_columns`, the columns
`lr_parse` hands `lr_expected` too) - each a `to_array_move` of a fixed array literal, the pattern
dasFlex's tables use. The running program builds nothing; the macro module requires the core, the
user's module only `bison/bison_parser` through it.

A conflict precedence leaves to yacc's default is reported as a compile warning
(`to_log(LOG_WARNING, ...)`): `conflict_warning` names the counts and the cells in `format_report`'s
`bison -v` words. `[bison(expected = N)]` is yacc's `%expect N`: it silences the warning when the
grammar has exactly `N` shift/reduce conflicts and no reduce/reduce one, and a different count warns
with the expectation named. A reduce/reduce conflict always warns. An `expected` that is not an int
of 0 or more fails the compile. The argument is `expected` because `expect` is a reserved word in
daslang and annotation argument names accept only a few keywords.

## The generated driver {#macro-driver}

The function's body becomes one loop over one state stack. With no lookahead held, it calls the
lexer: a token's kind goes through the kind map to its terminal, the lexer's `false` becomes the
`<end>` terminal, or a lexer error. It then reads the resolved `action` cell: a shift pushes the
state and the token and drops the lookahead; accept pops the root's value and returns it; a
reduce dispatches on the production by a chain of `if (prod == k) { ... continue }`, one arm per
production, which pops the right-hand side's states and values (into locals, last symbol first,
so the arguments never depend on evaluation order), calls the action function, pushes its result
on the rule's stack and the goto state on the state stack. An if chain keeps every arm an
ordinary block the interpreter and LLVM both take as written; the arms are as many as the
grammar's productions. `LR_MAX_REDUCES` bounds the reduces between two shifts, as in `lr_parse`.
Every node of the driver is marked generated and the action functions are not, so the style
lints over the user's module read each action as the user's code - its complexity, its length -
and skip the skeleton.

## Parse errors {#macro-errors}

A refused token - a zero cell, a kind the grammar does not know, the reduce bound - stops the
parse: `p.failed` is set, `p.line` / `p.col` are the token's position (the lexer's at the end of
input), the function returns a default-initialized value of its result type, and `p.err` is

    file:line:col: unexpected TOKEN, expected one of: a, b, c

with `file:` left out when the lexer has no file name. `TOKEN` and the expected names are the
grammar's: an enum member's name, a quoted character as written, `end of input`; an unknown kind
reads `token kind N`. The expected set is `lr_parse`'s (`#driver`): every terminal some reduce
chain from the state stack the refused token was read on ends in a shift or accept for - the
driver keeps the read-time states its reduces remove - computed by `bison_expected` from the
emitted tables, so it is exact and in terminal order. A lexer error is the parser's
error as the lexer worded it. A grammar error - an unknown name, a bad right-hand side, an action
whose arguments do not match its values - fails the compile at the rule's line; a grammar that
names no token fails it at its first rule, since the kind map would have no entry.

## Two front ends, one back end {#reader}

`[bison]` reads a grammar from `rule`, `prec_*` and `root` calls; `%bison~ name : Type, tokens = Enum,
lexer = scan ... %%` reads it from yacc-like text. The reader builds neither tables nor AST: its
`suffix` returns daslang source the parser reads in place of the text - `[bison(tokens = Enum,
lexer = scan, expected = N)] def name(var p : Parser) : Type` whose body holds a `prec_left` /
`prec_right` / `prec_nonassoc` call per precedence line, `root` for `%start`, and a
`rule("lhs", "rhs")` per alternative with its action as the block. The grammar therefore goes
through the one back end - `grammar_from_text`, `build_lalr`, `resolve_precedence`, the emitted
driver - and both forms of a grammar give the same tables, values and errors.

The declarations are `%left` / `%right` / `%nonassoc` (names as written, quoted characters
included), `%expect N` (the annotation's `expected`), `%start NAME` (the root; without it the first
rule, as in yacc) and `%type <Type> names`; `//` and `/* */` on a declaration line comment it.
Each declaration's call - a precedence call, `root` - goes on the declaration's own line. The line
`%rules` separates them from the rules rather than yacc's inner `%%`: the text ends at the first `%%`, as every reader's does, so the formatter
and the other tools that skip reader text skip all of it. A rule is `name : alternative | ... ;`;
an alternative is names, quoted characters, an optional `%prec NAME` and an optional action in
braces, last; `%empty` or nothing is the epsilon alternative; `//` and `/* */` comment the rules.

An action is daslang code with `$$` and `$n` rewritten; its strings, characters and comments -
`/* */` nested, as daslang reads them - are copied as written, so a brace or a `$` in them is not
read. `$n` is the n-th symbol of the
alternative's right-hand side, valueless terminals counted. An action that reads no `$n` takes no
argument; one that reads any takes every value of the right-hand side, as `[bison]` requires, as
`_n : T` for each symbol `n` that carries a value - a named token as its `FlexToken`, a rule that
yields as its type - and `$n` becomes `_n`. A rule yields when the text types it or one of its
actions writes `$$` or returns a value - a `return` whose next token on its line, past blanks and
block comments, is not `;`, `}` or `)`; an opening parenthesis is a value, even when its line ends
there. The types come from the text: the root's is the header's,
another rule's its `%type`; an action of a typed rule declares that result type, and an untyped
rule's type is inferred by `[bison]` from its first action (`#values`). `$$ = value` becomes
`return value`, so it ends the action; a value that has to move is returned with `return <- $n`.
`$n` on a quoted character or a rule that yields nothing, past the right-hand side, or on a rule
whose type the text does not declare is the reader's error.

The source keeps one output line per input line. An alternative's call goes on the line its action
starts on (its last symbol's when it has none), a multi-line action keeps its lines, calls that
share a line are separated by `;`, and the closing `}` takes the `%%` line. The parser is told the
source starts at the reader's line in the user's file, so `[bison]`'s errors at a rule, daslang's
errors inside an action and the reader's own errors - placed at the reader's line plus the line in
the text - all land on the line the user wrote.
