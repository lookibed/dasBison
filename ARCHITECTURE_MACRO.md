# dasBison architecture: the `[bison]` macro

A companion of `ARCHITECTURE.md`, under the same contract (`ARCHITECTURE_COMMON.md`): the
`[bison]` annotation over the core - its grammar, values, compile-time tables, generated driver and
errors - and the `%bison~` reader, its text front end.

## The `[bison]` macro {#macro}

`[bison(tokens = Enum, lexer = scan)]` on `def name(var p : Parser) : T` - or a parser struct of
another lexer (`#lexer-contract`) - reads the body as a
grammar when the module compiles. The body holds calls only: `rule("lhs", "rhs")`, with or without
an action block, `prec_left` / `prec_right` / `prec_nonassoc("tok", ...)`, and one `root("rule")`, its
argument a literal (the first rule's left-hand side when absent, as in yacc). A right-hand side is text: an identifier
that is some rule's left-hand side is that rule, one that is a member of `Enum` is that token with
the member's value as its kind, a quoted character (`'+'`, `'\''`) is the token whose kind is its
byte, an empty string is the epsilon production, and a trailing `%prec NAME` gives the production
the level of `NAME`. A precedence argument is a token name, a quoted character or a bare
punctuation character, which names the token a right-hand side writes quoted (`\` is `'\\'`);
a name neither a token nor a quoted character is a pseudo-terminal no kind reaches (yacc's
`%prec UMINUS`). `scan` is the function the parser pulls tokens from: one token per call,
`p.lexer.tok.kind` its kind, `false` at the end of input or on a lexer error. `Enum` is the enum the module sees by that name: its own, else the one a module it requires -
directly or through a public require - declares; two such modules are an ambiguity, and an enum
only some other loaded module declares is unknown. The enum is read from the AST at parse time, so a member's value is an integer literal of any
width or sign (a typed enum's `200u8` included), `-` before one, or the previous member's plus
one; an expression (`1 << 3`, a constant's name) is refused.

`grammar_from_text` turns the text into the core's builder; the macro adds nothing to the
construction. A terminal is keyed by its kind: two names for one kind are an error, so an enum
member cannot alias a quoted byte. The kind map the driver reads is an array indexed by kind,
which bounds kinds to `0 .. 65535`.

## The lexer contract {#lexer-contract}

The generated driver reads the lexer by field name, not by type: the macro emits the driver per
function, and inference types each read against the parser struct that function takes - `Parser`
for a dasFlex lexer, or any struct with `ParserStatus`'s fields (`failed`, `err`, `line`, `col`)
and a `lexer`, the status fields typed as `ParserStatus` types them (`failed : bool`, `err :
string`, `line`, `col : int`). `scan(var lexer) : bool` returns `true` with the token in
`lexer.tok`, or `false` at the end of input or, with `lexer.failed : bool` set, on an error the
lexer words in `lexer.err : string` at `lexer.line` / `lexer.col : int`; `lexer.file : string`
names the input, `""` none. Of a token the driver reads `kind : int`, `line` and `col : int`, and
it keeps the token whole on `array<typedecl(p.lexer.tok)>`, so a token with more fields (a
pp-token's `has_space`, `at_bol`, `sym`) or other ones (a hand-written lexer's value) reaches an
action as it was scanned, typed as the action's argument. A token is a plain value: the driver
copies every token it shifts onto that stack, so a token carrying an array would allocate per
shift. The macro reads the parser struct, its `lexer` and its token from the AST before inference
and fails the compile at the function when a field of the token does not copy or `kind` is not an
`int`, naming the field; a type declared after the function is not resolved there and goes to
inference unchecked, which reports the builtin error at the driver.
The `%bison~` reader writes `var p : Parser` (`#reader`), so another lexer drives a grammar
through `[bison]` only. The two helpers that read the
parser, `bison_lexer_failed` and `bison_syntax_error`, are generic in it. There is no interface
class: one would put a virtual call per token on the driver's path and a conversion of every token
into the interface's type. For `Parser` the driver compiles to the interpreter nodes the
`FlexLexer`-typed driver did - the same node per statement, the two error helpers called as their
generic instances, whose bodies are the old ones node for node. `parser_open` and `text(lx, t)`
are the dasFlex lexer's; another lexer opens itself and reads its own text.

## Values {#values}

Every symbol on the parse stack has a value or none. A named token's value is its token, as the lexer scanned it; a
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

The value stack is one `array<T>` per rule that yields, plus `array<typedecl(p.lexer.tok)>` for the tokens
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

`[bison(expected = N)]` is yacc's `%expect N` with bison's counts: exactly `N` shift/reduce conflicts
and no reduce/reduce one, else a compile error at the function, `conflict_mismatch`'s `expected N
shift/reduce conflicts, found M` and `expected 0 reduce/reduce conflicts, found K`, then the cells
in `format_report`'s `bison -v` words. An `expected` that is not an int of 0 or more fails the
compile; `expect` is a reserved word, and annotation argument names accept only a few keywords.
Without `expected`, a default-resolved conflict is `conflict_warning`'s compile warning, given the
way the style lint gives findings. The lint's path is its caller's: its `[lint_macro]`, run in a
module that requires `daslib/style_lint`, reports into the compile (`macro_style_warning`); a
runner's `*_collect` call gets an array; a bare call logs. No caller hands an annotation an array,
so the warning is `macro_style_warning` at the function when the module sees `style_lint`, and
`to_log(LOG_WARNING, ...)` otherwise - a lint runner's compile included, so it does not fail the file.
`style_lint_armed` is the twin of `daslib/style_lint`'s private `st048_requires_match` - the
program's modules scanned for one the compiling module sees directly - and a public daslib "module
X is visible from here" helper would fold the two.

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
reads `token kind N`. The expected set is `lr_parse`'s (`ARCHITECTURE.md#driver`): every terminal some reduce
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
