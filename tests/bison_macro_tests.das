options gen2
options indenting = 4

require dastest/testing_boost public
require bison/bison_macro
require bison/grammar_text
require bison/lalr
require bison/prec
require flex/flex_macro
require daslib/debugger
require daslib/strings_boost
require math
require _compile_issues
require _bison_run

enum CTok {
    NUM = 256
}

[flex]
def calc_lex(var lx : FlexLexer) : bool {
    rule("[0-9]+(\\.[0-9]+)?") {
        lx |> emit(CTok.NUM)
    }
    rule("[\\-+*/()^<]") {
        lx |> emit(first_character(text(lx)))
    }
    rule("@") {
        lx |> emit(70000)
    }
    rule("#") {
        lx |> emit(-5)
    }
    rule("[ \\t\\r\\n]+") {
    }
}

[bison(tokens = CTok, lexer = calc_lex)]
def calc(var p : Parser) : float {
    prec_left("+", "-")
    prec_left("*", "/")
    rule("expr", "expr '+' expr") <| $(a : float; b : float) : float {
        return a + b
    }
    rule("expr", "expr '-' expr") <| $(a, b : float) => a - b
    rule("expr", "expr '*' expr") <| $(a, b : float) => a * b
    rule("expr", "expr '/' expr") <| $(a, b : float) => a / b
    rule("expr", "'(' expr ')'") <| $(e : float) => e
    rule("expr", "NUM") <| $(t : FlexToken) => to_float(text(p.lexer, t))
    root("expr")
}

[test(description = "the [bison] calculator evaluates by its %left lines: * binds tighter than +, - associates left, parentheses group")]
def test_calc(t : T?) {
    t |> equal(run_parser(@@calc, "1+2*3"), "7")
    t |> equal(run_parser(@@calc, "(1+2)*3"), "9")
    t |> equal(run_parser(@@calc, "2-3-4"), "-5")
    t |> equal(run_parser(@@calc, "8/2/2"), "2")
    t |> equal(run_parser(@@calc, " 1.5 * (2 + 2) "), "6")
}

[test(description = "a refused token gives file:line:col, its name and the exact expected set; the end of input and a lexer error report the same way, with the default value")]
def test_calc_errors(t : T?) {
    t |> equal(run_parser(@@calc, "1+"),
               "0 calc.txt:1:3: unexpected end of input, expected one of: '(', NUM")
    t |> equal(run_parser(@@calc, "1 2"),
               "0 calc.txt:1:3: unexpected NUM, expected one of: '+', '-', '*', '/', end of input")
    t |> equal(run_parser(@@calc, "2*(3\n+)"),
               "0 calc.txt:2:2: unexpected ')', expected one of: '(', NUM")
    t |> equal(run_parser(@@calc, "1 + x"), "0 calc.txt:1:5: unexpected 'x'")
    var p : Parser
    parser_open(p, "(1", "")
    calc(p)
    t |> success(p.failed)
    t |> equal(p.err, "1:3: unexpected end of input, expected one of: '+', '-', '*', '/', ')'")
    t |> equal(p.line, 1)
    t |> equal(p.col, 3)
}

[test(description = "a token kind the grammar does not know - inside the kind map, past it, negative - is refused as token kind N; the end of input on a later line reports that line; a Parser opened again after a failure parses clean")]
def test_runtime_edges(t : T?) {
    let after_one = "expected one of: '+', '-', '*', '/', end of input"
    t |> equal(run_parser(@@calc, "1^2"), "0 calc.txt:1:2: unexpected token kind 94, {after_one}")
    t |> equal(run_parser(@@calc, "1@"), "0 calc.txt:1:2: unexpected token kind 70000, {after_one}")
    t |> equal(run_parser(@@calc, "1#"), "0 calc.txt:1:2: unexpected token kind -5, {after_one}")
    t |> equal(run_parser(@@calc, "1+\n\n  "),
               "0 calc.txt:3:3: unexpected end of input, expected one of: '(', NUM")
    var p : Parser
    parser_open(p, "1+", "")
    calc(p)
    t |> success(p.failed)
    parser_open(p, "2*3", "")
    t |> equal(calc(p), 6.0)
    t |> success(!p.failed)
    t |> equal(p.err, "")
}

enum LoopTok {
    X = 1
}

[flex]
def loop_lex(var lx : FlexLexer) : bool {
    rule("x") {
        lx |> emit(LoopTok.X)
    }
}

// A ::= B ::= A is a cycle: on the end of input the primary reduce runs A ::= B, then B ::= A,
// forever, until the cap
[bison(tokens = LoopTok, lexer = loop_lex)]
def reduce_loop(var p : Parser) : int {
    rule("A", "B") <| $(b : int) => b
    rule("S", "B") <| $(b : int) => b
    rule("B", "A")
    rule("B", "X") <| $(x : FlexToken) => 1
    root("S")
}

[test(description = "a grammar whose primary actions reduce in a cycle stops at the reduce cap and fails as a syntax error, the default value returned")]
def test_reduce_loop(t : T?) {
    var p : Parser
    parser_open(p, "x")
    t |> equal(reduce_loop(p), 0)
    t |> success(p.failed)
    t |> equal(p.err, "1:2: unexpected end of input, expected one of: ")
}

// `<` is non-associative below `+`, `^` right-associative above it
[bison(tokens = CTok, lexer = calc_lex)]
def assoc(var p : Parser) : float {
    prec_nonassoc("<")
    prec_left("+")
    prec_right("^")
    rule("expr", "expr '<' expr") <| $(a, b : float) => a < b ? 1.0 : 0.0
    rule("expr", "expr '+' expr") <| $(a, b : float) => a + b
    rule("expr", "expr '^' expr") <| $(a, b : float) => pow(a, b)
    rule("expr", "NUM") <| $(t : FlexToken) => to_float(text(p.lexer, t))
}

[test(description = "prec_right and prec_nonassoc reach the tables through [bison]: 2^3^2 groups to the right, a < b < c is refused at the second <")]
def test_assoc(t : T?) {
    t |> equal(run_parser(@@assoc, "2^3^2"), "512")
    t |> equal(run_parser(@@assoc, "1+2^2+1"), "6")
    t |> equal(run_parser(@@assoc, "1<2"), "1")
    t |> equal(run_parser(@@assoc, "1+1<2^2"), "1")
    t |> equal(run_parser(@@assoc, "1<2<3"),
               "0 calc.txt:1:4: unexpected '<', expected one of: '+', '^', end of input")
}

enum ITok {
    IF = 1
    ELSE
    X
}

[flex]
def if_lex(var lx : FlexLexer) : bool {
    rule("if") {
        lx |> emit(ITok.IF)
    }
    rule("else") {
        lx |> emit(ITok.ELSE)
    }
    rule("x") {
        lx |> emit(ITok.X)
    }
    rule(" +") {
    }
}

// the dangling else: one shift/reduce conflict, declared with `expected = 1` and resolved by
// yacc's default shift, so the else binds to the inner if
[bison(tokens = ITok, lexer = if_lex, expected = 1)]
def ifs(var p : Parser) : string {
    rule("stmt", "IF stmt") <| $(i : FlexToken; s : string) => "if({s})"
    rule("stmt", "IF stmt ELSE stmt") <| $(i : FlexToken; a : string; e : FlexToken;
                                           b : string) => "if({a}, {b})"
    rule("stmt", "X") <| $() => "x"
}

//! a hand-written lexer's token: the fields the generated driver reads, `kind`, `line`, `col`, and a
//! value of its own
struct HandToken {
    kind : int
    line : int
    col : int
    value : int
}

//! a hand-written lexer, no dasFlex in it: the fields the generated driver reads, by name
struct HandLexer {
    src : array<int>                //!< the input's characters
    pos : int
    line : int
    col : int
    tok : HandToken
    failed : bool
    err : string
    file : string
}

struct HandParser : ParserStatus {
    lexer : HandLexer
}

enum HTok {
    NUM = 256
}

//! one token per call: a number with its value, or one of `+ * ( )`; `false` at the end, and on
//! any other byte with `failed` set
def hand_scan(var lx : HandLexer) : bool {
    while (lx.pos < length(lx.src) && lx.src[lx.pos] == ' ') {
        lx.pos++
        lx.col++
    }
    return false if (lx.pos >= length(lx.src))
    let c = lx.src[lx.pos]
    lx.tok = HandToken(kind = c, line = lx.line, col = lx.col)
    if (is_number(c)) {
        lx.tok.kind = int(HTok.NUM)
        while (lx.pos < length(lx.src) && is_number(lx.src[lx.pos])) {
            lx.tok.value = lx.tok.value * 10 + lx.src[lx.pos] - '0'
            lx.pos++
            lx.col++
        }
        return true
    }
    if (c != '+' && c != '*' && c != '(' && c != ')') {
        lx.failed = true
        lx.err = "{lx.line}:{lx.col}: no token starts with '{to_char(c)}'"
        return false
    }
    lx.pos++
    lx.col++
    return true
}

def hand_open(var p : HandParser; src : string) {
    p.lexer <- HandLexer(src <- [for (c in src); c], line = 1, col = 1, file = "hand.txt")
    p.failed = false
}

[bison(tokens = HTok, lexer = hand_scan)]
def hand_calc(var p : HandParser) : int {
    prec_left("+")
    prec_left("*")
    rule("e", "e '+' e") <| $(a, b : int) => a + b
    rule("e", "e '*' e") <| $(a, b : int) => a * b
    rule("e", "'(' e ')'")
    rule("e", "NUM") <| $(t : HandToken) => t.value
}

[test(description = "a hand-written lexer struct whose token has the driver's field names drives a [bison] grammar: its token type is the action's argument, and a refused token and the lexer's own error report as with dasFlex")]
def test_hand_lexer(t : T?) {
    var p : HandParser
    hand_open(p, "2 + 3 * (4 + 10)")
    t |> equal(hand_calc(p), 44)
    t |> success(!p.failed, p.err)
    hand_open(p, "2 +")
    t |> equal(hand_calc(p), 0)
    t |> equal(p.err, "hand.txt:1:4: unexpected end of input, expected one of: '(', NUM")
    hand_open(p, "2 3")
    hand_calc(p)
    t |> equal(p.err, "hand.txt:1:3: unexpected NUM, expected one of: '+', '*', end of input")
    hand_open(p, "2 + x")
    hand_calc(p)
    t |> equal(p.err, "1:5: no token starts with 'x'")
    t |> equal(p.line, 1)
    t |> equal(p.col, 5)
}

//! a module whose `[bison]` parser reads a hand-written lexer, its token `Token` holding `fields`
//! besides `line` and `col`
def private hand_module(fields : string) : string {
    return ("options gen2\nrequire bison/bison_macro\nenum Tok \{\n    NUM = 256\n\}\n"
        + "struct Token \{\n{fields}    line : int\n    col : int\n\}\n"
        + "struct Lexer \{\n    tok : Token\n    failed : bool\n    err : string\n    line : int\n"
        + "    col : int\n    file : string\n\}\n"
        + "struct HandParser : ParserStatus \{\n    lexer : Lexer\n\}\n"
        + "def scan(var lx : Lexer) : bool \{\n    return false\n\}\n"
        + "[bison(tokens = Tok, lexer = scan)]\ndef calc(var p : HandParser) : int \{\n"
        + "    rule(\"e\", \"NUM\") <| $(n : Token) => 1\n\}\n")
}

[test(description = "the lexer's token is a plain value: a token with an array field, or with a kind that is not an int, fails the compile at the [bison] function with the field named; a string field copies")]
def test_token_contract(t : T?) {
    let array_field = hand_module("    kind : int\n    payload : array<int>\n")
    let payload = compile_issues("tok_array.das", array_field)
    t |> has_issue(payload, "[bison] calc: the lexer's token type Token is not copyable (field payload); a token must be a plain value - keep arrays out of it")
    t |> has_issue(payload, "tok_array.das:")
    t |> success(find(payload, "can't push value") < 0, payload)
    let enum_kind = compile_issues("tok_enum.das", hand_module("    kind : Tok\n"))
    t |> has_issue(enum_kind, "[bison] calc: the lexer's token type Token has kind : Tok; the driver reads tok.kind as an int")
    t |> success(find(enum_kind, "30341") < 0, enum_kind)
    let string_field = hand_module("    kind : int\n    text : string\n")
    t |> equal(compile_issues("tok_string.das", string_field), "")
}

enum LateTok {
    NUM = 256
}

//! the parser, its lexer and its token are declared after this function: the macro sees them
//! unresolved, so the token contract goes unchecked and the driver compiles in inference
[bison(tokens = LateTok, lexer = late_scan)]
def late_sum(var p : LateParser) : int {
    rule("s", "NUM") <| $(t : LateToken) => t.value
    rule("s", "s NUM") <| $(a : int; t : LateToken) => a + t.value
}

struct LateToken {
    kind : int
    line : int
    col : int
    value : int
}

struct LateLexer {
    src : array<int>
    pos : int
    line : int
    col : int
    tok : LateToken
    failed : bool
    err : string
    file : string
}

struct LateParser : ParserStatus {
    lexer : LateLexer
}

//! one number per call, spaces between; `false` at the end
def late_scan(var lx : LateLexer) : bool {
    while (lx.pos < length(lx.src) && lx.src[lx.pos] == ' ') {
        lx.pos++
        lx.col++
    }
    return false if (lx.pos >= length(lx.src))
    lx.tok = LateToken(kind = int(LateTok.NUM), line = lx.line, col = lx.col)
    while (lx.pos < length(lx.src) && is_number(lx.src[lx.pos])) {
        lx.tok.value = lx.tok.value * 10 + lx.src[lx.pos] - '0'
        lx.pos++
        lx.col++
    }
    return true
}

[test(description = "a parser, lexer and token declared after the [bison] function compile and parse, the token contract left unchecked; the array-token variant declared after fails in inference with the builtin copy error")]
def test_declared_after(t : T?) {
    var p : LateParser
    p.lexer <- LateLexer(src <- [for (c in "1 20 300"); c], line = 1, col = 1)
    t |> equal(late_sum(p), 321)
    t |> success(!p.failed, p.err)
    let late = ("options gen2\nrequire bison/bison_macro\nenum Tok \{\n    NUM = 256\n\}\n"
        + "[bison(tokens = Tok, lexer = scan)]\ndef calc(var p : HandParser) : int \{\n"
        + "    rule(\"e\", \"NUM\") <| $(n : Token) => 1\n\}\n"
        + "struct Token \{\n    kind : int\n    payload : array<int>\n    line : int\n    col : int\n\}\n"
        + "struct Lexer \{\n    tok : Token\n    failed : bool\n    err : string\n    line : int\n"
        + "    col : int\n    file : string\n\}\n"
        + "struct HandParser : ParserStatus \{\n    lexer : Lexer\n\}\n"
        + "def scan(var lx : Lexer) : bool \{\n    return false\n\}\n")
    let issues = compile_issues("tok_late.das", late)
    t |> has_issue(issues, "error[31400]: can't push value, which can't be copied")
    t |> success(find(issues, "is not copyable") < 0, issues)
}

enum MTok {
    A = 1
    B
    C
    X
    Y
    Z
}

[flex]
def merged_lex(var lx : FlexLexer) : bool {
    rule("a") {
        lx |> emit(MTok.A)
    }
    rule("b") {
        lx |> emit(MTok.B)
    }
    rule("c") {
        lx |> emit(MTok.C)
    }
    rule("x") {
        lx |> emit(MTok.X)
    }
    rule("y") {
        lx |> emit(MTok.Y)
    }
    rule("z") {
        lx |> emit(MTok.Z)
    }
    rule(" +") {
    }
}

// LALR merges the states after `a c` and `b c`, so `E ::= C` reduces on both X and Y there
[bison(tokens = MTok, lexer = merged_lex)]
def merged(var p : Parser) : int {
    rule("S", "A E X") <| $() => 1
    rule("S", "B E Y") <| $() => 2
    rule("E", "C")
    rule("E", "C Z")
}

[test(description = "the [bison] expected set is the one of the stack the refused token was read on: the reduce a merged state runs on the doomed token does not drop a terminal valid when it was read")]
def test_expected_before_reduce(t : T?) {
    var p : Parser
    parser_open(p, "a c z x")
    t |> equal(merged(p), 1)
    parser_open(p, "a c y")
    merged(p)
    t |> equal(p.err, "1:5: unexpected Y, expected one of: X, Z")
}

enum STok : uint8 {
    NUM = 200u8
    NEG = 10u8
    END
}

[flex]
def small_lex(var lx : FlexLexer) : bool {
    rule("[0-9]+") {
        lx |> emit(STok.NUM)
    }
    rule("-") {
        lx |> emit(STok.NEG)
    }
    rule(";") {
        lx |> emit(STok.END)
    }
    rule(" +") {
    }
}

// a typed enum: its members' values are uint8 literals, END the one after NEG
[bison(tokens = STok, lexer = small_lex)]
def small(var p : Parser) : int {
    rule("s", "n END") <| $(v : int; e : FlexToken) => v
    rule("n", "NUM") <| $(t : FlexToken) => to_int(text(p.lexer, t))
    rule("n", "NEG n") <| $(m : FlexToken; v : int) => -v
}

[test(description = "a typed enum gives the token kinds: uint8 literals and the member after one are read as kinds")]
def test_typed_enum(t : T?) {
    var p : Parser
    parser_open(p, "- - 42 ;")
    t |> equal(small(p), 42)
    parser_open(p, "- 7")
    small(p)
    t |> equal(p.err, "1:4: unexpected end of input, expected one of: END")
}

def private dangling_else() : TextGrammar {
    let rules <- [TextRule(lhs = "stmt", rhs = "IF stmt"),
                  TextRule(lhs = "stmt", rhs = "IF stmt ELSE stmt"),
                  TextRule(lhs = "stmt", rhs = "X")]
    let precs : array<TextPrec>
    let tokens <- { "IF" => 1, "ELSE" => 2, "X" => 3 }
    return <- grammar_from_text(rules, precs, "", tokens)
}

[test(description = "the dangling else through [bison] shifts by default, binding else to the inner if; conflict_warning, on the report of the grammar ifs declares, names the conflict as bison -v does, and expected = 1 silences exactly it")]
def test_dangling_else(t : T?) {
    var p : Parser
    parser_open(p, "if if x else x")
    t |> equal(ifs(p), "if(if(x, x))")
    parser_open(p, "if x else if x else x")
    t |> equal(ifs(p), "if(x, if(x, x))")
    let g <- dangling_else()
    t |> equal(g.err, "")
    let res <- resolve_precedence(build_lalr(g.builder, g.root), g.builder)
    t |> equal(res.report.shift_reduce, 1)
    let cells = "State 4 conflicts: 1 shift/reduce\n    ELSE  shift, and go to state 5\n    ELSE  [reduce using rule 1 (stmt ::= IF stmt)]\n"
    t |> equal(conflict_warning("ifs", res.report),
               "[bison] ifs: 1 shift/reduce, 0 reduce/reduce conflicts, resolved by default:\n{cells}")
    t |> equal(conflict_mismatch("ifs", res.report, 1), "")
    t |> equal(conflict_mismatch("ifs", res.report, 0),
               "[bison] ifs: expected 0 shift/reduce conflicts, found 1:\n{cells}")
}

[test(description = "conflict_mismatch counts reduce/reduce conflicts apart, as bison does: expected matching the shift/reduce count still fails on a reduce/reduce one, and a missed count names both; conflict_warning names both counts")]
def test_warning_reduce_reduce(t : T?) {
    let rules <- [TextRule(lhs = "s", rhs = "a Y"), TextRule(lhs = "s", rhs = "b Y"),
                  TextRule(lhs = "s", rhs = "X Y"), TextRule(lhs = "a", rhs = "X"),
                  TextRule(lhs = "b", rhs = "X")]
    let precs : array<TextPrec>
    let g <- grammar_from_text(rules, precs, "", { "X" => 1, "Y" => 2 })
    t |> equal(g.err, "")
    let res <- resolve_precedence(build_lalr(g.builder, g.root), g.builder)
    t |> equal(res.report.shift_reduce, 1)
    t |> equal(res.report.reduce_reduce, 1)
    let rr = "expected 0 reduce/reduce conflicts, found 1"
    t |> success(starts_with(conflict_mismatch("mixed", res.report, 1),
                             "[bison] mixed: {rr}:\nState "))
    t |> success(starts_with(conflict_mismatch("mixed", res.report, 2),
                             "[bison] mixed: expected 2 shift/reduce conflicts, found 1; {rr}:\nState "))
    t |> success(starts_with(conflict_warning("mixed", res.report),
                             "[bison] mixed: 1 shift/reduce, 1 reduce/reduce conflicts, resolved by default:\nState "))
}

[test(description = "a right-hand side reads names, quoted characters with escapes and a trailing %prec, and names what is wrong with a bad one")]
def test_rhs_text(t : T?) {
    let r <- parse_rhs("expr '+' expr %prec UMINUS")
    t |> equal(length(r.syms), 3)
    t |> equal(r.syms[1].name, "'+'")
    t |> equal(r.syms[1].ch, '+')
    t |> equal(r.syms[0].ch, -1)
    t |> equal(r.prec, "UMINUS")
    t |> equal(parse_rhs("'\\'' '\\\\'").syms[0].ch, '\'')
    t |> equal(parse_rhs("'\\'' '\\\\'").syms[1].ch, '\\')
    let escapes <- parse_rhs("'\\n' '\\t' '\\r' '\\q'")
    t |> equal([for (x in escapes.syms); x.ch], ['\n', '\t', '\r', 'q'])
    t |> equal(parse_rhs("'-' e %prec '*'").prec, "'*'")
    t |> equal(parse_rhs("e %precedence").err,
               "unexpected '%' at offset 2: a symbol is a name or a quoted character")
    t |> equal(length(parse_rhs("").syms), 0)
    t |> equal(parse_rhs("a 'bc'").err,
               "a quoted character is one character between single quotes, at offset 2")
    for (bad in ["'''", "'\n'"]) {
        t |> equal(parse_rhs("a {bad}").err,
                   "a quoted character is one character between single quotes, at offset 2", bad)
    }
    t |> equal(parse_rhs("a %prec").err, "%prec needs a token name")
    t |> equal(parse_rhs("a %prec X b").err, "'b' after %prec X: %prec ends the right-hand side")
    t |> equal(parse_rhs("a + b").err,
               "unexpected '+' at offset 2: a symbol is a name or a quoted character")
}

[test(description = "a text grammar resolves names to rules, tokens and quoted bytes, keys terminals by kind, and refuses an unknown name, a kind two names share, and a root that is no rule")]
def test_text_grammar(t : T?) {
    let tokens <- { "NUM" => 256, "PLUS" => '+' }
    let precs : array<TextPrec>
    let ok <- grammar_from_text(
                                [TextRule(lhs = "e", rhs = "e '-' NUM"),
                                 TextRule(lhs = "e", rhs = "NUM")], precs, "", tokens)
    t |> equal(ok.err, "")
    t |> equal(ok.term_kinds, ['-', 256])
    t |> equal(ok.root, 0)
    let unknown <- grammar_from_text([TextRule(lhs = "e", rhs = "e NAME")], precs, "", tokens)
    t |> equal(unknown.err, "'NAME' is neither a rule nor a token")
    t |> equal(unknown.err_rule, 0)
    let same_kind <- grammar_from_text(
                                       [TextRule(lhs = "e", rhs = "NUM"),
                                        TextRule(lhs = "e", rhs = "e PLUS '+'")], precs, "", tokens)
    t |> equal(same_kind.err, "'+' and PLUS are the same token kind 43")
    t |> equal(same_kind.err_rule, 1)
    let prec_kind <- grammar_from_text([TextRule(lhs = "e", rhs = "NUM")],
                                       [
                                        TextPrec(assoc = PrecAssoc.left,
                                                 names <- ["NUM", "PLUS", "+"])], "", tokens)
    t |> equal(prec_kind.err, "'+' and PLUS are the same token kind 43")
    t |> equal(prec_kind.err_prec, 0)
    t |> equal(prec_kind.err_rule, -1)
    let no_root <- grammar_from_text([TextRule(lhs = "e", rhs = "NUM")], precs, "f", tokens)
    t |> equal(no_root.err, "root 'f' is not a rule")
    let uminus <- grammar_from_text(
                                    [TextRule(lhs = "e", rhs = "'-' e %prec UMINUS"),
                                     TextRule(lhs = "e", rhs = "NUM")],
                                    [TextPrec(assoc = PrecAssoc.left, names <- ["-"]),
                                     TextPrec(assoc = PrecAssoc.right, names <- ["UMINUS"])],
                                    "", tokens)
    t |> equal(uminus.err, "")
    t |> equal(uminus.builder.prec_prods[0], uminus.builder.term_index?["UMINUS"] ?? -2)
    t |> equal(uminus.term_kinds[uminus.builder.term_index?["UMINUS"] ?? 0], -1)
}

[test(description = "a bare backslash or quote as a precedence argument is the token a right-hand side writes quoted and escaped, not a second name for its kind")]
def test_prec_escapes(t : T?) {
    let tokens <- { "NUM" => 256 }
    let rules <- [TextRule(lhs = "e", rhs = "e '\\\\' e"), TextRule(lhs = "e", rhs = "e '\\'' e"),
                  TextRule(lhs = "e", rhs = "NUM")]
    let g <- grammar_from_text(rules, [TextPrec(assoc = PrecAssoc.left, names <- ["\\", "'"])], "",
                               tokens)
    t |> equal(g.err, "")
    t |> equal(g.term_kinds, ['\\', '\'', 256])
    t |> equal(g.builder.prec_terms[0].x, 1)
    t |> equal(g.builder.prec_terms[1].x, 1)
}

var private g_seen : array<string>

enum LTok {
    WORD = 1
}

[flex]
def list_lex(var lx : FlexLexer) : bool {
    rule("[a-z]+") {
        lx |> emit(LTok.WORD)
    }
    rule("[;]") {
        lx |> emit(';')
    }
    rule(" +") {
    }
}

// `items` yields no value: its actions return nothing and run for their effect, and the root's
// action takes no value from it
[bison(tokens = LTok, lexer = list_lex)]
def words(var p : Parser) : int {
    rule("doc", "items ';'") <| $() => length(g_seen)
    rule("items", "items WORD") <| $(w : FlexToken) {
        g_seen |> push(text(p.lexer, w))
    }
    rule("items", "")
}

[test(description = "a rule whose actions return nothing yields no value: it carries nothing on the stack, its actions run in reduce order, and an epsilon production needs no action")]
def test_void_rule(t : T?) {
    g_seen |> clear()
    var p : Parser
    parser_open(p, "a bc d ;")
    t |> equal(words(p), 3)
    t |> equal(g_seen, ["a", "bc", "d"])
}

enum JTok {
    STRING = 256
    NUMBER = 257
    TRUE = 258
    FALSE = 259
    NULL = 260
}

[flex]
def json_lex(var lx : FlexLexer) : bool {
    rule("[ \\t\\r\\n]+") {
    }
    rule("[\\\{\\\}\\[\\]:,]") {
        lx |> emit(first_character(text(lx)))
    }
    rule("true") {
        lx |> emit(JTok.TRUE)
    }
    rule("false") {
        lx |> emit(JTok.FALSE)
    }
    rule("null") {
        lx |> emit(JTok.NULL)
    }
    rule("-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?") {
        lx |> emit(JTok.NUMBER)
    }
    rule("\"([^\"\\\\]|\\\\.)*\"") {
        lx |> emit(JTok.STRING)
    }
}

enum JKind {
    null_value
    boolean
    number
    str
    arr
    obj
}

//! a JSON value: `items` holds an array's elements or an object's values, `keys` the object's keys
struct JNode {
    kind : JKind
    flag : bool
    num : double
    str : string
    keys : array<string>
    items : array<JNode?>
}

def private unquote(s : string) : string => slice(s, 1, length(s) - 1)

[bison(tokens = JTok, lexer = json_lex)]
def json(var p : Parser) : JNode? {
    rule("value", "object")
    rule("value", "array")
    rule("value", "STRING") <| $(t : FlexToken) => new JNode(kind = JKind.str,
                                                             str = unquote(text(p.lexer, t)))
    rule("value", "NUMBER") <| $(t : FlexToken) => new JNode(kind = JKind.number,
                                                             num = to_double(text(p.lexer, t)))
    rule("value", "TRUE") <| $() => new JNode(kind = JKind.boolean, flag = true)
    rule("value", "FALSE") <| $() => new JNode(kind = JKind.boolean)
    rule("value", "NULL") <| $() => new JNode(kind = JKind.null_value)
    rule("object", "'\{' '\}'") <| $() => new JNode(kind = JKind.obj)
    rule("object", "'\{' members '\}'") <| $(m : JNode?) => m
    rule("members", "STRING ':' value") <| $(k : FlexToken; v : JNode?) {
        var o = new JNode(kind = JKind.obj)
        o.keys |> push(unquote(text(p.lexer, k)))
        o.items |> push(v)
        return o
    }
    rule("members", "members ',' STRING ':' value") <| $(o : JNode?; k : FlexToken; v : JNode?) {
        o.keys |> push(unquote(text(p.lexer, k)))
        o.items |> push(v)
        return o
    }
    rule("array", "'[' ']'") <| $() => new JNode(kind = JKind.arr)
    rule("array", "'[' elements ']'") <| $(a : JNode?) => a
    rule("elements", "value") <| $(v : JNode?) {
        var a = new JNode(kind = JKind.arr)
        a.items |> push(v)
        return a
    }
    rule("elements", "elements ',' value") <| $(a : JNode?; v : JNode?) {
        a.items |> push(v)
        return a
    }
}

// a node back as compact JSON-like text, numbers as daslang prints a double
def private show(n : JNode?) : string {
    if (n.kind == JKind.obj) {
        let pairs <- [for (k, v in n.keys, n.items); k + ":" + show(v)]
        return "\{" + join(pairs, ",") + "\}"
    } elif (n.kind == JKind.arr) {
        let elems <- [for (v in n.items); show(v)]
        return "[" + join(elems, ",") + "]"
    } elif (n.kind == JKind.str) {
        return "\"{n.str}\""
    } elif (n.kind == JKind.number) {
        return "{n.num}"
    } elif (n.kind == JKind.boolean) {
        return n.flag ? "true" : "false"
    }
    return "null"
}

let private JSON_DOC = "\{
    \"name\": \"dasBison\",
    \"version\": 3,
    \"big\": 1.5e3,
    \"stable\": false,
    \"license\": null,
    \"tags\": [\"parser\", \"lalr\", \"daslang\"],
    \"empty_list\": [],
    \"empty_map\": \{\},
    \"author\": \{
        \"name\": \"lookibed\",
        \"active\": true
    \},
    \"matrix\": [
        [1, 2],
        [3, 4]
    ],
    \"nested\": [\{\"a\": [\{\}]\}],
    \"last\": \"end\"
\}"

[test(description = "a JSON grammar through [bison] builds a tree of a type the test defines from a 20-line document: pass-through rules, list rules that grow a node, empty containers")]
def test_json(t : T?) {
    t |> equal(length(split(JSON_DOC, "\n")), 20)
    var p : Parser
    parser_open(p, JSON_DOC, "doc.json")
    let root = json(p)
    t |> equal(p.err, "")
    t |> success(!p.failed)
    t |> equal(show(root), "\{name:\"dasBison\",version:3,big:1500,stable:false,license:null,tags:[\"parser\",\"lalr\",\"daslang\"],empty_list:[],empty_map:\{\},author:\{name:\"lookibed\",active:true\},matrix:[[1,2],[3,4]],nested:[\{a:[\{\}]\}],last:\"end\"\}")
    parser_open(p, "[1, -0.25, \"two\", [true, null]]")
    t |> equal(show(json(p)), "[1,-0.25,\"two\",[true,null]]")
}

[test(description = "a malformed JSON document fails at the refused token's line and column with the expected set, and the parser returns the default value")]
def test_json_errors(t : T?) {
    var p : Parser
    let missing_comma = replace(JSON_DOC, "\"active\": true", "\"active\": true \"extra\": 1")
    parser_open(p, missing_comma, "doc.json")
    t |> success(json(p) == null)
    t |> equal(p.err, "doc.json:12:24: unexpected STRING, expected one of: '\}', ','")
    parser_open(p, "\{\"a\": [1, 2,]\}", "short.json")
    t |> success(json(p) == null)
    t |> equal(p.err, "short.json:1:13: unexpected ']', expected one of: STRING, NUMBER, TRUE, FALSE, NULL, '\{', '['")
    parser_open(p, "[1, 2", "cut.json")
    json(p)
    t |> equal(p.err, "cut.json:1:6: unexpected end of input, expected one of: ',', ']'")
    parser_open(p, "\{\"k\" 1\}", "")
    json(p)
    t |> equal(p.err, "1:6: unexpected NUMBER, expected one of: ':'")
}

//! a module under the style lint, complexity limit 5, with a `[bison]` grammar of `rules`
def private linted_module(rules : string) : string {
    return ("options gen2\noptions _cyclomatic_complexity = 5\nrequire daslib/style_lint\n"
        + "require flex/flex_macro\nrequire bison/bison_macro\n"
        + "enum E \{\n    NUM = 256\n\}\n[flex]\ndef lx(var lx : FlexLexer) : bool \{\n"
        + "    rule(\"[0-9]+\") \{\n        lx |> emit(E.NUM)\n    \}\n\}\n"
        + "[bison(tokens = E, lexer = lx)]\ndef calc(var p : Parser) : int \{\n{rules}\}\n")
}

[test(description = "the style lint reads an action as the user's code: an action past the complexity limit is reported at its rule, the driver around it is not")]
def test_action_is_linted(t : T?) {
    let branchy = ("    rule(\"e\", \"NUM\") <| $(n : FlexToken) \{\n        let v = length(text(p.lexer, n))\n"
        + "        if (v == 1) return 1\n        if (v == 2) return 2\n        if (v == 3) return 3\n"
        + "        if (v == 4) return 4\n        if (v == 5) return 5\n        return v\n    \}\n")
    let issues = compile_issues("lint1.das", linted_module(branchy))
    t |> has_issue(issues, "STYLE037: function 'calc`bison`act`0' has cyclomatic complexity 6")
    t |> has_issue(issues, "lint1.das:17:")
    t |> equal(count(issues, "STYLE037"), 1)
    let plain = "    rule(\"e\", \"NUM\") <| $(n : FlexToken) => length(text(p.lexer, n))\n"
    t |> equal(compile_issues("lint2.das", linted_module(plain)), "")
}

[test(description = "a grammar that names no token fails the compile at its first rule, not at the empty kind map")]
def test_no_token(t : T?) {
    let issues = compile_issues("notok.das", linted_module("    rule(\"e\", \"\") <| $() => 1\n"))
    t |> has_issue(issues, "the grammar names no token")
    t |> has_issue(issues, "notok.das:17:")
    t |> success(find(issues, "dimension") < 0, issues)
}

//! a module with a NUM lexer and a `[bison(tokens = Tok)]` grammar over `NUM`, after `head`
def private tok_module(head : string) : string {
    return ("options gen2\nrequire flex/flex_macro\nrequire bison/bison_macro\n{head}"
        + "[flex]\ndef lx(var lx : FlexLexer) : bool \{\n    rule(\"[0-9]+\") \{\n        lx |> emit(256)\n    \}\n\}\n"
        + "[bison(tokens = Tok, lexer = lx)]\ndef calc(var p : Parser) : int \{\n"
        + "    rule(\"e\", \"NUM\") <| $(n : FlexToken) => 1\n\}\n")
}

[test(description = "the token enum is the one the module sees: a loaded enum no require reaches is unknown, two required modules that both declare it are ambiguous, the module's own wins")]
def test_token_enum_visibility(t : T?) {
    let tok1 = (name = "tok1.das",
                text = "options gen2\nmodule tok1 public\nenum Tok \{\n    NUM = 256\n\}\n")
    let tok2 = (name = "tok2.das",
                text = "options gen2\nmodule tok2 public\nenum Tok \{\n    NUM = 256\n\}\n")
    let unseen = replace(tok_module(""), "tokens = Tok", "tokens = PrecAssoc")
    t |> has_issue(compile_issues("vis1.das", unseen),
                   "tokens = PrecAssoc: no such enum the module sees")
    t |> equal(compile_issues("vis2.das", tok_module("require tok1\n"), [tok1, tok2]), "")
    let both = compile_issues("vis3.das", tok_module("require tok1\nrequire tok2\n"), [tok1, tok2])
    t |> has_issue(both, "tokens = Tok: ambiguous, an enum of tok")
    let own = "require tok1\nrequire tok2\nenum Tok \{\n    NUM = 256\n\}\n"
    t |> equal(compile_issues("vis4.das", tok_module(own), [tok1, tok2]), "")
}

[test(description = "root takes one rule name literal, once; a rule that derives no terminal string fails at its line")]
def test_root_and_structure(t : T?) {
    let tok = "enum Tok \{\n    NUM = 256\n\}\n"
    let variable = replace(tok_module(tok), "    rule(\"e\"",
                           "    root(\"e\" + \"\")\n    rule(\"e\"")
    let named = compile_issues("root1.das", variable)
    t |> has_issue(named, "root takes a rule name literal: root(\"rule\")")
    t |> has_issue(named, "root1.das:15:")
    let twice = replace(tok_module(tok), "    rule(\"e\"",
                        "    root(\"e\")\n    root(\"e\")\n    rule(\"e\"")
    let again = compile_issues("root2.das", twice)
    t |> has_issue(again, "root is named once; root(\"e\") came first")
    t |> has_issue(again, "root2.das:16:")
    let loop = replace(tok_module(tok), "<| $(n : FlexToken) => 1", "<| $(n : FlexToken) => 1\n    rule(\"e\", \"e x\")\n    rule(\"x\", \"x NUM\")")
    let dead = compile_issues("dead.das", loop)
    t |> has_issue(dead, "rule 'x' derives no terminal string")
    t |> has_issue(dead, "dead.das:17:")
}

[test(description = "expected = N takes an int of 0 or more: a string or a negative count fails the compile")]
def test_expected_arg(t : T?) {
    let tok = "enum Tok \{\n    NUM = 256\n\}\n"
    let why = "[bison] expected = N takes the number of shift/reduce conflicts, an int of 0 or more"
    for (arg in ["\"1\"", "-1"]) {
        let src = replace(tok_module(tok), "lexer = lx)", "lexer = lx, expected = {arg})")
        t |> has_issue(compile_issues("expected.das", src), why)
    }
    let zero = replace(tok_module(tok), "lexer = lx)", "lexer = lx, expected = 0)")
    t |> equal(compile_issues("expected0.das", zero), "")
}

//! a module with the dangling else, `[bison(tokens = Tok, lexer = lx{args})]` on line 19 and its
//! function on line 20, after `line4` on line 4
def private dangling_module(line4, args : string) : string {
    return ("options gen2\nrequire flex/flex_macro\nrequire bison/bison_macro\n{line4}\n"
        + "enum Tok \{\n    IF = 1\n    ELSE\n    X\n\}\n"
        + "[flex]\ndef lx(var lx : FlexLexer) : bool \{\n    rule(\"if\") \{\n        lx |> emit(Tok.IF)\n    \}\n"
        + "    rule(\"x\") \{\n        lx |> emit(Tok.X)\n    \}\n\}\n"
        + "[bison(tokens = Tok, lexer = lx{args})]\ndef ifs(var p : Parser) : int \{\n"
        + "    rule(\"s\", \"IF s\") <| $(i : FlexToken; s : int) => s\n"
        + "    rule(\"s\", \"IF s ELSE s\") <| $(i : FlexToken; a : int; e : FlexToken; b : int) => a + b\n"
        + "    rule(\"s\", \"X\") <| $(x : FlexToken) => 1\n\}\n")
}

[test(description = "expected = N that misses the grammar's conflicts fails the compile at the [bison] function with bison's counts, the reduce/reduce one apart, and the cells; expected = N that names them compiles clean")]
def test_expected_mismatch(t : T?) {
    t |> equal(compile_issues("expect1.das", dangling_module("", ", expected = 1")), "")
    let cells = "State 4 conflicts: 1 shift/reduce\n    ELSE  shift, and go to state 5\n    ELSE  [reduce using rule 1 (s ::= IF s)]"
    let zero = compile_issues("expect0.das", dangling_module("", ", expected = 0"))
    t |> has_issue(zero, "[bison] ifs: expected 0 shift/reduce conflicts, found 1:\n{cells}")
    t |> has_issue(zero, "expect0.das:20:")
    let two = compile_issues("expect2.das", dangling_module("", ", expected = 2"))
    t |> has_issue(two, "[bison] ifs: expected 2 shift/reduce conflicts, found 1:\n")
    let tok = "enum Tok \{\n    NUM = 256\n\}\n"
    let none = replace(tok_module(tok), "lexer = lx)", "lexer = lx, expected = 1)")
    let clean = compile_issues("expect_none.das", none)
    t |> has_issue(clean, "[bison] calc: expected 1 shift/reduce conflicts, found 0")
    t |> success(find(clean, "found 0:") < 0, clean)
    let rr = ("    rule(\"s\", \"a NUM\") <| $(a : int; n : FlexToken) => a\n"
        + "    rule(\"s\", \"b NUM\") <| $(b : int; n : FlexToken) => b\n"
        + "    rule(\"a\", \"NUM\") <| $(n : FlexToken) => 1\n"
        + "    rule(\"b\", \"NUM\") <| $(n : FlexToken) => 2\n")
    let rr_src = replace(bison_module(tok, rr), "lexer = lx)", "lexer = lx, expected = 0)")
    t |> has_issue(compile_issues("expect_rr.das", rr_src),
                   "[bison] calc: expected 0 reduce/reduce conflicts, found 1:\nState ")
}

//! the debug agent category `LogCapture` is installed under
let private LOG_CAPTURE = "bison_macro_tests_log"

//! the `[bison]` lines `to_log` wrote while the agent was installed, kept in the agent's context
var private captured : array<string>

//! keeps every `[bison]` log line, from any context, and holds it back from the output
class private LogCapture : DapiDebugAgent {
    def override onLog(context : Context?; at : LineInfo const?; level : int; text : string#) : bool {
        return false if (find(text, "[bison]") < 0)
        captured |> push(clone_string(text))
        return true
    }
}

//! the agent context's setup: `fork_debug_agent_context` runs it there
def setup_log_capture(_ctx : Context) {
    install_new_debug_agent(new LogCapture(), LOG_CAPTURE)
}

//! run in the agent's context: how many captured lines hold `needle`
[export, pinvoke]
def captured_hits(needle : string; var hits : int?) {
    *hits = 0
    for (line in captured) {
        *hits += find(line, needle) >= 0 ? 1 : 0
    }
}

//! how many `[bison]` log lines `blk`'s compiles wrote that hold `needle`
def private logged_hits(needle : string; blk : block) : int {
    fork_debug_agent_context(@@setup_log_capture)
    invoke(blk)
    var hits = 0
    unsafe {
        invoke_in_context(get_debug_agent_context(LOG_CAPTURE), "captured_hits", needle, addr(hits))
    }
    delete_debug_agent_context(LOG_CAPTURE)
    return hits
}

//! `unroll` over a run-time range: only a lint runner's compile takes it, so a module that ends
//! with it compiles clean only the way the runner compiles
let private LINT_ONLY = "def spin(n : int) \{\n    unroll() $ \{\n        for (i in range(n)) \{\n            pass\n        \}\n    \}\n\}\n"

[test(description = "a conflict left without expected is a warning the style lint's way: a module that requires daslib/style_lint gets it as a style warning at the [bison] function; a plain compile, a lint runner's compile and a module whose helper alone requires style_lint stay clean and log it")]
def test_conflict_warning_paths(t : T?) {
    let warning = "[bison] ifs: 1 shift/reduce, 0 reduce/reduce conflicts, resolved by default:\nState 4 conflicts: 1 shift/reduce\n"
    let linted = compile_issues("warn_lint.das", dangling_module("require daslib/style_lint", ""))
    t |> has_issue(linted, warning)
    t |> has_issue(linted, "warn_lint.das:20:")
    t |> has_issue(linted, "31209")
    let none : array<VirtualFile>
    let helper = [(name = "warn_helper.das",
                   text = "options gen2\nmodule warn_helper public\nrequire daslib/style_lint\ndef helper_one() : int => 1\n")]
    for (f in ["warn_plain.das", "warn_runner.das", "warn_private.das"]) {
        var issues = ""
        let hits = logged_hits("{f}:20: {warning}") $ {
            if (f == "warn_plain.das") {
                issues = compile_issues(f, dangling_module("", ""))
            } elif (f == "warn_runner.das") {
                issues = compile_issues(f, dangling_module("require daslib/unroll", "") + LINT_ONLY, none, true)
            } else {
                issues = compile_issues(f, dangling_module("require warn_helper", ""), helper)
            }
        }
        t |> equal(issues, "")
        t |> equal(hits, 1)
    }
}

[test(description = "a grammar with no shift/reduce conflict and one reduce/reduce conflict, left without expected, still warns: the log line names both counts")]
def test_conflict_warning_reduce_reduce_only(t : T?) {
    let body = ("    rule(\"A\", \"B\") <| $(b : int) => b\n"
        + "    rule(\"S\", \"B\") <| $(b : int) => b\n"
        + "    rule(\"B\", \"A\")\n"
        + "    rule(\"B\", \"NUM\") <| $(n : FlexToken) => 1\n"
        + "    root(\"S\")\n")
    var issues = ""
    let hits = logged_hits("warn_rr.das:14: [bison] calc: 0 shift/reduce, 1 reduce/reduce conflicts, resolved by default:\nState ") $ {
        issues = compile_issues("warn_rr.das", grammar_module(body))
    }
    t |> equal(issues, "")
    t |> equal(hits, 1)
}

//! the enum `tok_module`'s grammar reads `NUM` from
let private TOK_ENUM = "enum Tok \{\n    NUM = 256\n\}\n"

//! a module whose `[bison]` body is `body` after the three lines of `head`, which declare `Tok`;
//! the annotation is line 13, the body's first line line 15
def private bison_module(head, body : string) : string =>
    replace(tok_module(head), "    rule(\"e\", \"NUM\") <| $(n : FlexToken) => 1\n", body)

//! a module whose `[bison]` body is `body`, over `Tok.NUM`; the body's first line is line 15
def private grammar_module(body : string) : string => bison_module(TOK_ENUM, body)

[test(description = "two actions of one rule returning different types, or a pass-through of a value of another type, fail the compile at the rule's line")]
def test_type_agreement(t : T?) {
    let two_types = ("    rule(\"e\", \"NUM\") <| $(n : FlexToken) => 1\n"
        + "    rule(\"e\", \"e NUM\") <| $(a : int; n : FlexToken) => \"two\"\n")
    let issues = compile_issues("types1.das", grammar_module(two_types))
    t |> has_issue(issues, "rule(\"e\", \"e NUM\"): the action returns another type than the one of rule(\"e\", \"NUM\")")
    t |> has_issue(issues, "types1.das:16:")
    let passed = ("    rule(\"e\", \"NUM\") <| $(n : FlexToken) => 1\n    rule(\"e\", \"s\")\n"
        + "    rule(\"s\", \"NUM\") <| $(n : FlexToken) => \"s\"\n")
    let pass_issues = compile_issues("types2.das", grammar_module(passed))
    t |> has_issue(pass_issues, "rule(\"e\", \"s\"): the value passed on is not of the type of rule(\"e\", \"NUM\")")
    t |> has_issue(pass_issues, "types2.das:16:")
}

//! one compile-error case: the enum and the `[bison]` body, the message, and the line it is at
struct private MacroError {
    head : string
    body : string
    message : string
    line : int
}

//! a typed action of `NUM`, the rule every case that is not about the grammar's shape uses
let private NUM_RULE = "    rule(\"e\", \"NUM\") <| $(n : FlexToken) => 1\n"

[test(description = "every [bison] error has its message and its line: call shapes in the body, the four action checks, a root that yields nothing, the token enum's values, a kind past the map, an error of a precedence line, a bad right-hand side, an empty grammar, the annotation's own arguments")]
def test_macro_errors(t : T?) {
    let shape = "rule(\"lhs\", \"rhs\") or rule(\"lhs\", \"rhs\") <| $(values) \{ action \} expected"
    let body_only = "only rule, prec_left, prec_right, prec_nonassoc and root calls belong in a [bison] body"
    let cases <- [
        MacroError(head = TOK_ENUM, body = "    rule(\"e\")\n", message = shape, line = 15),
        MacroError(head = TOK_ENUM, body = "    rule(\"e\", \"NUM\", 1)\n", message = shape,
                   line = 15),
        MacroError(head = TOK_ENUM, body = "    let r = \"e\"\n    rule(r, \"NUM\")\n",
                   message = body_only, line = 15),
        MacroError(head = TOK_ENUM, body = "{NUM_RULE}    rule(\"e\" + \"\", \"NUM\")\n",
                   message = shape, line = 16),
        MacroError(head = TOK_ENUM, body = "    prec_left(1)\n{NUM_RULE}",
                   message = "prec_left takes token names as strings", line = 15),
        MacroError(head = TOK_ENUM, body = "{NUM_RULE}    print(\"e\")\n",
                   message = "{body_only}, not print", line = 16),
        MacroError(head = TOK_ENUM, body = "{NUM_RULE}    rule(\"e\", \"NUM NUM\")\n",
                   message = "rule(\"e\", \"NUM NUM\") needs an action: 'e' yields a value and the right-hand side carries 2 values to pass on, not one", line = 16),
        MacroError(head = TOK_ENUM, body = "{NUM_RULE}    rule(\"e\", \"e NUM\") <| $(a : int; n : FlexToken) \{\n    \}\n",
                   message = "rule(\"e\", \"e NUM\"): the action returns no value, the one of rule(\"e\", \"NUM\") does", line = 16),
        MacroError(head = TOK_ENUM,
                   body = "{NUM_RULE}    rule(\"e\", \"e NUM\") <| $(a : int) => a\n",
                   message = "rule(\"e\", \"e NUM\"): the action takes 1 arguments, the right-hand side carries 2 values", line = 16),
        MacroError(head = TOK_ENUM, body = "    rule(\"e\", \"NUM\") <| $(n) => 1\n",
                   message = "rule(\"e\", \"NUM\"): argument 'n' needs a type", line = 15),
        MacroError(head = TOK_ENUM,
                   body = "    rule(\"e\", \"NUM\") <| $(n : FlexToken) \{\n    \}\n",
                   message = "[bison] the root rule 'e' yields no value", line = 13),
        MacroError(head = "enum Tok \{\n    NUM = 1 << 8\n\}\n", body = NUM_RULE,
                   message = "[bison] tokens = Tok: the value of NUM is not an integer literal",
                   line = 13),
        MacroError(head = "enum Tok : int64 \{\n    NUM = 5000000000l\n\}\n", body = NUM_RULE,
                   message = "[bison] tokens = Tok: NUM = 5000000000 does not fit a token kind, an int", line = 13),
        MacroError(head = "enum Tok \{\n    NUM = 70000\n\}\n", body = NUM_RULE,
                   message = "[bison] token kind 70000 is past 65535, the largest the kind map holds", line = 13),
        MacroError(head = "enum Tok \{\n    NUM = 256, PLUS = 43\n\}\n",
                   body = "    prec_left(\"+\", \"PLUS\")\n{NUM_RULE}",
                   message = "[bison] PLUS and '+' are the same token kind 43", line = 15),
        MacroError(head = TOK_ENUM, body = "{NUM_RULE}    rule(\"e\", \"e + NUM\") <| $(a : int; n : FlexToken) => a\n",
                   message = "[bison] unexpected '+' at offset 2: a symbol is a name or a quoted character", line = 16),
        MacroError(head = TOK_ENUM, body = "    root(\"e\")\n",
                   message = "[bison] the grammar has no rules", line = 13),
        MacroError(head = TOK_ENUM, body = "{NUM_RULE}    root(\"f\")\n",
                   message = "[bison] root 'f' is not a rule", line = 13)
    ]
    for (i, c in count(), cases) {
        let issues = compile_issues("macro_error{i}.das", bison_module(c.head, c.body))
        t |> has_issue(issues, c.message)
        t |> has_issue(issues, "macro_error{i}.das:{c.line}:")
    }
    let two_args = replace(grammar_module(NUM_RULE), "def calc(var p : Parser)",
                           "def calc(var p : Parser; q : int)")
    t |> has_issue(compile_issues("two_args.das", two_args),
                   "[bison] takes one argument: var p : Parser")
    let no_lexer = replace(grammar_module(NUM_RULE), "lexer = lx)", "expected = 0)")
    t |> has_issue(compile_issues("no_lexer.das", no_lexer),
                   "[bison] needs tokens = <the token enum> and lexer = <the scan function>")
}
