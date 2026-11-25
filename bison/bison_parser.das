options gen2
options indenting = 4
options strict_smart_pointers = true

module bison_parser shared public

require bison/lalr
require flex/flex public
require daslib/strings_boost

// What a `[bison]` parser runs on: the `Parser` it takes, and the helpers its generated driver
// calls - the value stack's pop, the token kind's terminal, the expected set, the error text.

//! The parser's state: the lexer it reads tokens from, and where and why it failed.
struct Parser {
    lexer : FlexLexer
    failed : bool
    err : string            //!< `file:line:col: unexpected TOKEN, expected one of: a, b`
    line : int              //!< where the refused token starts; the lexer's position at the end
    col : int
}

//! Open `src` for parsing: the lexer over it, no error.
def parser_open(var p : Parser; src : string; file : string = "") {
    flex_open(p.lexer, src, file)
    p.failed = false
    p.err = ""
    p.line = 0
    p.col = 0
}

//! The text of token `t` from the input of `lx`.
def text(lx : FlexLexer; t : FlexToken) : string {
    return t.text if (!empty(t.text))
    return slice(lx.bytes, t.start, t.start + t.len)
}

//! The top value of a value stack, moved out and popped.
def bison_pop(var stack : array<auto(TT)>) : TT -const -& {
    var top <- stack[length(stack) - 1]
    stack |> pop()
    return <- top
}

//! The terminal of token kind `kind` through the kind map, -2 for a kind the grammar does not know.
def bison_terminal(kind_terms : array<int>; kind : int) : int =>
    kind >= 0 && kind < length(kind_terms) ? kind_terms[kind] : -2

//! The expected terminals of a refused token, from the stack it was read on (`states[0 .. low)`
//! and `saved`) and the emitted tables: `action`, `goto_nt`, the left-hand side and length per
//! production, the table sizes.
[arch(at="../ARCHITECTURE.md#driver")]
def bison_expected(action, goto_nt, lhs, len : array<int>; nterms, nrules : int;
                   states : array<int>; low : int; saved : array<int>) : array<int> {
    var inscope at_read <- lr_stack_at_read(states, low, saved)
    return <- lr_expected(action, goto_nt, lhs, len, nterms, nrules, at_read)
}

//! Before a reduce cuts the state stack to `depth`: the states the token was read on that the cut
//! removes go to `saved` (`lr_keep_popped`).
def bison_keep_popped(states : array<int>; var low : int&; var saved : array<int>; depth : int) {
    lr_keep_popped(states, low, saved, depth)
}

//! The lexer refused a byte: its error is the parser's.
def bison_lexer_failed(var p : Parser) {
    p.failed = true
    p.err = p.lexer.err
    p.line = p.lexer.line
    p.col = p.lexer.col
}

//! The parser refused terminal `term` (`eof` at the end of input, -2 for a kind the grammar does
//! not know): `file:line:col: unexpected TOKEN, expected one of: a, b, c`.
def bison_syntax_error(var p : Parser; names : array<string>; term, eof : int;
                       expected : array<int>) {
    p.failed = true
    let at_end = term == eof
    p.line = at_end ? p.lexer.line : p.lexer.tok.line
    p.col = at_end ? p.lexer.col : p.lexer.tok.col
    let place = empty(p.lexer.file) ? "" : "{p.lexer.file}:"
    let what = term >= 0 ? names[term] : "token kind {p.lexer.tok.kind}"
    let want = join([for (x in expected); names[x]], ", ")
    p.err = "{place}{p.line}:{p.col}: unexpected {what}, expected one of: {want}"
}
