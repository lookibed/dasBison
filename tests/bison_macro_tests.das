options gen2
options indenting = 4

require dastest/testing_boost public
require bison/bison_macro
require bison/grammar_text
require bison/lalr
require bison/prec
require flex/flex_macro
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

[test(description = "the dangling else through [bison] shifts by default, binding else to the inner if; the warning the macro gives names the conflict as bison -v does, and expected = 1 silences exactly it")]
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
    let warning = "[bison] ifs: 1 shift/reduce, 0 reduce/reduce conflicts, resolved by default:\nState 4 conflicts: 1 shift/reduce\n    ELSE  shift, and go to state 5\n    ELSE  [reduce using rule 1 (stmt ::= IF stmt)]\n"
    t |> equal(conflict_warning("ifs", res.report, -1), warning)
    t |> equal(conflict_warning("ifs", res.report, 1), "")
    t |> equal(conflict_warning("ifs", res.report, 0),
               replace(warning, "conflicts, resolved", "conflicts (expected = 0), resolved"))
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
    t |> equal(length(parse_rhs("").syms), 0)
    t |> equal(parse_rhs("a 'bc'").err,
               "a quoted character is one character between single quotes, at offset 2")
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
