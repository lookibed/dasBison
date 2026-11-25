options gen2
options indenting = 4
options strict_smart_pointers = true

module bison_reader shared public

require daslib/ast_boost
require daslib/strings_boost
require strings
require math

// `%bison~ name : Type, tokens = Enum, lexer = scan` ... `%%` at module level: a yacc-like text form
// of a grammar. The reader turns the text into the source of a `[bison]` function - one output line
// per input line, so every diagnostic points at the line the user wrote - and the parser reads that
// source in place of the reader. `[bison]` builds the tables; the reader only rewrites text.

//! The source the reader writes for a `%bison~` text, or the first error and its line in the text.
struct BisonReaderOutput {
    source : string
    err : string
    line : int          //!< 0-based line of the error within the text
}

struct private RScan {
    d : array<uint8>
    pos : int
    line : int
    err : string
    err_line : int
}

def private fail_at(var s : RScan; msg : string; line : int) {
    if (empty(s.err)) {
        s.err = msg
        s.err_line = line
    }
}

def private fail(var s : RScan; msg : string) {
    fail_at(s, msg, s.line)
}

def private peek(s : RScan; k : int = 0) : int => s.pos + k < length(s.d) ? int(s.d[s.pos + k]) : -1

def private is_blank(c : int) : bool => c == ' ' || c == '\t' || c == '\r'

def private is_ident(c : int; first : bool) : bool =>
    is_alpha(c) || c == '_' || (!first && is_number(c))

def private skip_blanks(var s : RScan) {
    while (is_blank(peek(s))) {
        s.pos++
    }
}

//! the rest of the line, the newline not consumed
def private rest_of_line(var s : RScan) : string {
    let start = s.pos
    while (peek(s) >= 0 && peek(s) != '\n') {
        s.pos++
    }
    return slice(s.d, start, s.pos)
}

//! past the newline that ends the current line; false at the end of the text
def private next_line(var s : RScan) : bool {
    return false if (peek(s) != '\n')
    s.pos++
    s.line++
    return true
}

//! an identifier at the cursor, "" when there is none
def private ident(var s : RScan) : string {
    let start = s.pos
    while (is_ident(peek(s), s.pos == start)) {
        s.pos++
    }
    return slice(s.d, start, s.pos)
}

//! a string literal of daslang source holding `text`
def private das_string_literal(text : string) : string =>
    "\"" + replace(replace(escape(text), "\{", "\\\{"), "\}", "\\\}") + "\""

//! blanks, newlines, `//` and `/* */` comments
def private skip_space(var s : RScan) {
    while (true) {
        let c = peek(s)
        if (is_blank(c)) {
            s.pos++
        } elif (c == '\n') {
            next_line(s)
        } elif (c == '/' && peek(s, 1) == '/') {
            rest_of_line(s)
        } elif (c == '/' && peek(s, 1) == '*') {
            s.pos += 2
            while (peek(s) >= 0 && !(peek(s) == '*' && peek(s, 1) == '/')) {
                if (!next_line(s)) {
                    s.pos++
                }
            }
            s.pos += 2
        } else {
            return
        }
    }
}

//! a quoted character as written (`'+'`, `'\''`), the quote at the cursor; "" when malformed
def private quoted_char(var s : RScan) : string {
    let start = s.pos
    let k = peek(s, 1) == '\\' ? 3 : 2
    if (peek(s, 1) < 0 || peek(s, 1) == '\n' || peek(s, k) != '\''
        || (k == 2 && peek(s, 1) == '\'')) {
        fail(s, "a quoted character is one character between single quotes")
        return ""
    }
    s.pos += k + 1
    return slice(s.d, start, s.pos)
}

//! One `$n` an action reads, and the line it reads it on.
struct private DollarUse {
    n : int
    line : int
}

//! One alternative of a rule: its symbols as written, `%prec`, its action translated to daslang.
struct private RAlt {
    lhs : string
    syms : array<string>
    prec : string
    action : string             //!< the `{ ... }` block with `$$ = ` and `$n` rewritten, "" for none
    uses : array<DollarUse>
    writes : bool               //!< the action writes `$$` or returns a value
    line : int                  //!< the line its `rule(...)` call goes on: the action's first, else the last symbol's
    action_line : int
}

//! one daslang string literal of an action, the quote at the cursor: interpolations are code
def private action_string(var s : RScan; var w : StringBuilderWriter; var alt : RAlt) {
    w |> write_char('"')
    s.pos++
    while (empty(s.err)) {
        let c = peek(s)
        if (c < 0) {
            fail(s, "a string in the action ends at the end of the rules")
            return
        }
        if (c == '{') {
            action_code(s, w, alt)
            continue
        }
        if (c == '\\' && peek(s, 1) >= 0) {
            w |> write_char(c)
            s.pos++
        }
        w |> write_char(peek(s))
        if (peek(s) == '\n') {
            s.line++
        }
        s.pos++
        return if (c == '"')
    }
}

//! `$$ = ` as `return `, `$n` as `_n`; anything else after `$` (a block, a qmacro tag) unchanged
def private action_dollar(var s : RScan; var w : StringBuilderWriter; var alt : RAlt) {
    if (peek(s, 1) == '$') {
        s.pos += 2
        skip_blanks(s)
        if (peek(s) != '=' || peek(s, 1) == '=') {
            fail(s, "$$ is written as `$$ = value`, which returns the value")
            return
        }
        s.pos++
        w |> write("return")
        alt.writes = true
        return
    }
    if (!is_number(peek(s, 1))) {
        w |> write_char('$')
        s.pos++
        return
    }
    s.pos++
    let start = s.pos
    while (is_number(peek(s))) {
        s.pos++
    }
    let n = to_int(slice(s.d, start, s.pos))
    let nsyms = length(alt.syms)
    if (n < 1 || n > nsyms) {
        fail(s, "${n}: the right-hand side of '{alt.lhs}' has {nsyms} symbols")
        return
    }
    alt.uses |> push(DollarUse(n = n, line = s.line))
    w |> write("_{n}")
}

//! whether the `return` that ends at the cursor carries a value: the next token on its line,
//! past blanks, block comments and opening parentheses, is neither `;`, `}`, `)` nor the line's end
def private return_has_value(s : RScan) : bool {
    var k = 0
    var depth = 0
    while (true) {
        let c = peek(s, k)
        let next = peek(s, k + 1)
        if (depth > 0) {
            return false if (c < 0)
            depth += c == '/' && next == '*' ? 1 : (c == '*' && next == '/' ? -1 : 0)
            k += (c == '/' && next == '*') || (c == '*' && next == '/') ? 2 : 1
        } elif (c == '/' && next == '*') {
            depth = 1
            k += 2
        } elif (is_blank(c) || c == '(') {
            k++
        } else {
            return !(c < 0 || c == '\n' || c == ';' || c == '}' || c == ')'
                     || (c == '/' && next == '/'))
        }
    }
    return false
}

//! one daslang block comment of an action, copied as written, the `/*` at the cursor: nested
//! comments balanced, as daslang reads them, lines counted
def private action_comment(var s : RScan; var w : StringBuilderWriter) {
    var depth = 0
    while (empty(s.err)) {
        let c = peek(s)
        if (c < 0) {
            fail(s, "a comment in the action ends at the end of the rules")
            return
        }
        let pair = c == '/' && peek(s, 1) == '*' ? 1 : (c == '*' && peek(s, 1) == '/' ? -1 : 0)
        if (pair != 0) {
            depth += pair
            w |> write_char(c)
            w |> write_char(peek(s, 1))
            s.pos += 2
            return if (depth == 0)
            continue
        }
        if (c == '\n') {
            s.line++
        }
        w |> write_char(c)
        s.pos++
    }
}

//! a `{ ... }` of action code, the open brace at the cursor: braces balanced outside strings,
//! characters and comments, lines counted, `$$` and `$n` rewritten
def private action_code(var s : RScan; var w : StringBuilderWriter; var alt : RAlt) {
    var depth = 0
    while (empty(s.err)) {
        let c = peek(s)
        if (c < 0) {
            fail(s, "the action ends at the end of the rules")
            return
        }
        if (c == '"') {
            action_string(s, w, alt)
        } elif (c == '\'') {
            let start = s.pos
            s.pos++
            while (peek(s) >= 0 && peek(s) != '\'' && peek(s) != '\n') {
                s.pos += peek(s) == '\\' ? 2 : 1
            }
            s.pos++
            w |> write(slice(s.d, start, s.pos))
        } elif (c == '/' && peek(s, 1) == '/') {
            w |> write(rest_of_line(s))
        } elif (c == '/' && peek(s, 1) == '*') {
            action_comment(s, w)
        } elif (c == '$') {
            action_dollar(s, w, alt)
        } elif (is_ident(c, true)) {
            let word = ident(s)
            w |> write(word)
            if (word == "return") {
                alt.writes ||= return_has_value(s)
            }
        } else {
            if (c == '\n') {
                s.line++
            } elif (c == '{') {
                depth++
            } elif (c == '}') {
                depth--
            }
            w |> write_char(c)
            s.pos++
            return if (depth == 0)
        }
    }
}

//! `%prec NAME` or `%empty` in an alternative, the `%` at the cursor
def private alt_directive(var s : RScan; var alt : RAlt) {
    s.pos++
    let word = ident(s)
    if (word == "empty") {
        return
    }
    if (word != "prec") {
        fail(s, "%{word} in a rule: only %prec and %empty belong there")
        return
    }
    skip_blanks(s)
    alt.prec = peek(s) == '\'' ? quoted_char(s) : ident(s)
    if (empty(alt.prec) && empty(s.err)) {
        fail(s, "%prec needs a token name")
    }
}

//! whether a name at the cursor is the next rule's `name :`, the cursor kept
def private starts_rule(var s : RScan) : bool {
    let pos = s.pos
    let line = s.line
    ident(s)
    skip_space(s)
    let yes = peek(s) == ':'
    s.pos = pos
    s.line = line
    return yes
}

//! one alternative up to its `|` or `;`; true when `;` ended the rule
def private alternative(var s : RScan; var alt : RAlt; var last_line : int&) : bool {
    while (empty(s.err)) {
        skip_space(s)
        let c = peek(s)
        if (c < 0 || (is_ident(c, true) && starts_rule(s))) {
            fail_at(s, "the rule '{alt.lhs}' ends with ';'", last_line)
            return true
        }
        if (c == '|' || c == ';') {
            if (alt.line < 0) {
                alt.line = s.line
            }
            s.pos++
            last_line = s.line
            return c == ';'
        }
        if (c == '%') {
            alt_directive(s, alt)
        } elif (!empty(alt.action)) {
            fail(s, "an action ends its alternative: '|' or ';' expected after it")
        } elif (c == '{') {
            alt.line = s.line
            alt.action_line = s.line
            alt.action = build_string() $(var w) {
                action_code(s, w, alt)
            }
        } elif (c == '\'') {
            alt.syms |> push(quoted_char(s))
            alt.line = s.line
        } elif (is_ident(c, true)) {
            alt.syms |> push(ident(s))
            alt.line = s.line
        } else {
            fail(s, "unexpected '{slice(s.d, s.pos, s.pos + 1)}' in the rule '{alt.lhs}'")
        }
        last_line = s.line
    }
    return true
}

//! the rules section: `name : alternative | alternative ;`, one after another
def private rules_section(var s : RScan) : array<RAlt> {
    var alts : array<RAlt>
    var last_line = s.line
    while (empty(s.err)) {
        skip_space(s)
        break if (peek(s) < 0)
        let lhs = ident(s)
        if (empty(lhs)) {
            fail(s, "a rule starts with its name: `name : symbols \{ action \} | ... ;`")
            break
        }
        skip_space(s)
        if (peek(s) != ':') {
            fail(s, "'{lhs}' is followed by ':'")
            break
        }
        s.pos++
        var done = false
        while (!done && empty(s.err)) {
            var alt = RAlt(lhs = lhs, line = -1)
            done = alternative(s, alt, last_line)
            alts |> emplace(alt)
        }
    }
    return <- alts
}

//! The header and the declarations: what the generated function's signature and body start with.
struct private RDecls {
    name : string
    result : string
    tokens : string
    lexer : string
    expected : int = -1
    start : string
    start_line : int
    types : table<string; string>
    type_lines : table<string; int>
    calls : array<tuple<line : int; call : string>>    //!< `prec_*` and `root` calls, in line order
}

//! a type up to the first `,` outside brackets
def private type_text(line : string) : string {
    var depth = 0
    for (i, c in count(), line) {
        if (c == '<' || c == '(' || c == '[') {
            depth++
        } elif (c == '>' || c == ')' || c == ']') {
            depth--
        } elif (c == ',' && depth == 0) {
            return slice(line, 0, i)
        }
    }
    return line
}

//! the header `name : Type, tokens = Enum, lexer = scan`
def private header(var s : RScan; var decls : RDecls) {
    let line = rest_of_line(s)
    let colon = find(line, ":")
    let usage = "the header is `%bison~ name : Type, tokens = TokenEnum, lexer = scan`"
    if (colon < 0) {
        fail(s, usage)
        return
    }
    decls.name = trim(slice(line, 0, colon))
    let rest = slice(line, colon + 1)
    let ty = type_text(rest)
    decls.result = trim(ty)
    for (part in split(slice(rest, length(ty) + 1), ",")) {
        continue if (empty(trim(part)))
        var inscope kv <- split(part, "=")
        let key = length(kv) == 2 ? trim(kv[0]) : ""
        if (key == "tokens") {
            decls.tokens = trim(kv[1])
        } elif (key == "lexer") {
            decls.lexer = trim(kv[1])
        } else {
            fail(s, "{usage}, not `{trim(part)}`")
            return
        }
    }
    var ok = !empty(decls.result)
    for (part in [decls.name, decls.tokens, decls.lexer]) {
        ok &&= !empty(part)
        for (i, c in count(), part) {
            ok &&= is_ident(c, i == 0)
        }
    }
    if (!ok) {
        fail(s, usage)
    }
}

//! `%type <T> names`, the `<` after the directive
def private type_line(var s : RScan; var decls : RDecls; line : string) {
    let open = find(line, "<")
    var depth = 0
    var close = -1
    for (i, c in count(), line) {
        if (c == '<') {
            depth++
        } elif (c == '>') {
            depth--
            if (depth == 0) {
                close = i
                break
            }
        }
    }
    var any = false
    let names = close > open ? slice(line, close + 1) : ""
    let ty = close > open ? trim(slice(line, open + 1, close)) : ""
    for (n in split_by_chars(names, " \t")) {
        if (!empty(n)) {
            decls.types[n] = ty
            decls.type_lines[n] = s.line
            any = true
        }
    }
    if (open < 0 || close < 0 || !any) {
        fail(s, "%type is `%type <Type> name ...`")
    }
}

//! a declaration line without its comments: `//` to the end, `/* */` within the line; a quoted
//! character is no comment
def private strip_comments(line : string) : string {
    return build_string() $(var w) {
        peek_data(line) $(d) {
            let n = length(d)
            var i = 0
            while (i < n) {
                let c = int(d[i])
                let next = i + 1 < n ? int(d[i + 1]) : -1
                if (c == '\'') {
                    let k = min(i + (next == '\\' ? 4 : 3), n)
                    for (j in range(i, k)) {
                        w |> write_char(int(d[j]))
                    }
                    i = k
                } elif (c == '/' && next == '/') {
                    break
                } elif (c == '/' && next == '*') {
                    w |> write_char(' ')
                    i += 2
                    while (i < n && !(int(d[i]) == '*' && i + 1 < n && int(d[i + 1]) == '/')) {
                        i++
                    }
                    i = min(i + 2, n)
                } else {
                    w |> write_char(c)
                    i++
                }
            }
        }
    }
}

//! one line of the declarations: `%left` / `%right` / `%nonassoc`, `%expect`, `%start`, `%type`
def private declaration(var s : RScan; var decls : RDecls; line : string) {
    var inscope items : array<string>
    for (word in split_by_chars(line, " \t")) {
        if (!empty(word)) {
            items |> push(word)
        }
    }
    let head = items[0]
    if (head == "%left" || head == "%right" || head == "%nonassoc") {
        var inscope names <- [for (i in range(1, length(items))); das_string_literal(items[i])]
        if (empty(names)) {
            fail(s, "{head} names its tokens")
        }
        decls.calls |> push((line = s.line, call = "prec_{slice(head, 1)}({join(names, ", ")})"))
    } elif (head == "%expect" && length(items) == 2) {
        var digits = !empty(items[1])
        for (c in items[1]) {
            digits &&= is_number(c)
        }
        decls.expected = digits ? to_int(items[1]) : -1
        if (decls.expected < 0) {
            fail(s, "%expect takes the number of shift/reduce conflicts")
        }
    } elif (head == "%start" && length(items) == 2) {
        decls.start = items[1]
        decls.start_line = s.line
        decls.calls |> push((line = s.line, call = "root({das_string_literal(decls.start)})"))
    } elif (head == "%type") {
        type_line(s, decls, line)
    } else {
        fail(s, "a declaration is %left, %right, %nonassoc, %expect N, %start NAME or %type <Type> NAMES")
    }
}

//! What every rule's values are: whether it yields one, and its type when the text declares it.
struct private RRules {
    yields : table<string; bool>
    types : table<string; string>
}

def private plan_rules(var s : RScan; decls : RDecls; alts : array<RAlt>; root : string) : RRules {
    var rr : RRules
    for (a in alts) {
        rr.yields[a.lhs] = (rr.yields?[a.lhs] ?? false) || a.writes
    }
    for (name, ty in keys(decls.types), values(decls.types)) {
        if (!key_exists(rr.yields, name)) {
            fail_at(s, "%type names '{name}', which is no rule", decls.type_lines?[name] ?? 0)
        }
        rr.yields[name] = true
        rr.types[name] = ty
    }
    rr.yields[root] = true
    if (!key_exists(rr.types, root)) {
        rr.types[root] = decls.result
    }
    return <- rr
}

//! `$n` of `alt` as the reader sees it: the value it reads, or why it reads none
def private symbol_value(rr : RRules; alt : RAlt; j : int) : tuple<carries : bool; ty : string; why : string> {
    let sym = alt.syms[j]
    if (starts_with(sym, "'")) {
        return (carries = false, ty = "", why = "{sym}, a quoted character, which carries no value")
    }
    if (!key_exists(rr.yields, sym)) {
        return (carries = true, ty = "FlexToken", why = "")
    }
    if (!(rr.yields?[sym] ?? false)) {
        return (carries = false, ty = "", why = "'{sym}', a rule that yields no value")
    }
    return (carries = true, ty = rr.types?[sym] ?? "", why = "")
}

//! an alternative as a `rule(...)` call: the action's arguments are every value of the right-hand
//! side when it reads one, `_n` for `$n`, and its result the rule's declared type
def private rule_call(var s : RScan; rr : RRules; alt : RAlt) : string {
    let rhs = join(alt.syms, " ") + (empty(alt.prec) ? "" : " %prec {alt.prec}")
    let call = "rule({das_string_literal(alt.lhs)}, {das_string_literal(rhs)})"
    return call if (empty(alt.action))
    for (u in alt.uses) {
        let v = symbol_value(rr, alt, u.n - 1)
        if (!v.carries) {
            fail_at(s, "${u.n} is {v.why}", u.line)
        }
    }
    var inscope args : array<string>
    if (!empty(alt.uses)) {
        for (j in range(length(alt.syms))) {
            let v = symbol_value(rr, alt, j)
            continue if (!v.carries)
            if (empty(v.ty)) {
                fail_at(s, "${j + 1} is '{alt.syms[j]}', whose type the text does not declare: `%type <Type> {alt.syms[j]}`", alt.action_line)
            }
            args |> push("_{j + 1} : {v.ty}")
        }
    }
    let ty = (rr.yields?[alt.lhs] ?? false) ? rr.types?[alt.lhs] ?? "" : ""
    let result = empty(ty) ? "" : " : {ty}"
    return "{call} <| $({join(args, "; ")}){result} {alt.action}"
}

//! The `[bison]` function's text, written line by line: a piece goes on its input line.
struct private ROut {
    text : string
    line : int
    empty_line : bool
}

def private put(var o : ROut; line : int; piece : string) {
    if (line > o.line) {
        o.text += repeat("\n", line - o.line)
        o.line = line
        o.empty_line = true
    }
    if (!o.empty_line) {
        o.text += "; "
    }
    o.text += piece
    o.line += count(piece, "\n")
    o.empty_line = false
}

//! the translation: the `[bison]` function, one output line per line of `text`
def bison_reader_source(text : string) : BisonReaderOutput {
    var s = RScan(d <- to_bytes(text))
    var decls = RDecls()
    header(s, decls)
    var sep_found = false
    while (empty(s.err) && next_line(s)) {
        let line = trim(strip_comments(rest_of_line(s)))
        if (line == "%rules") {
            sep_found = true
            break
        }
        if (!empty(line)) {
            declaration(s, decls, line)
        }
    }
    if (!sep_found && empty(s.err)) {
        fail(s, "the rules section starts at a line `%rules`")
    }
    let rules_line = s.line
    var inscope alts <- empty(s.err) ? rules_section(s) : array<RAlt>()
    if (empty(alts) && empty(s.err)) {
        fail_at(s, "the rules section holds no rule", rules_line)
    }
    let root = empty(decls.start) ? (empty(alts) ? "" : alts[0].lhs) : decls.start
    var root_known = false
    for (a in alts) {
        root_known ||= a.lhs == root
    }
    if (empty(s.err) && !root_known) {
        fail_at(s, "%start {root}: no rule has that name", decls.start_line)
    }
    if (!empty(s.err)) {
        return BisonReaderOutput(err = s.err, line = s.err_line)
    }
    let rr <- plan_rules(s, decls, alts, root)
    let expected = decls.expected >= 0 ? ", expected = {decls.expected}" : ""
    var o = ROut(text = "[bison(tokens = {decls.tokens}, lexer = {decls.lexer}{expected})] def {decls.name}(var p : Parser) : {decls.result} \{")
    for (dc in decls.calls) {
        put(o, dc.line, dc.call)
    }
    for (a in alts) {
        put(o, a.line, rule_call(s, rr, a))
    }
    if (!empty(s.err)) {
        return BisonReaderOutput(err = s.err, line = s.err_line)
    }
    put(o, count(text, "\n"), "\}")
    return BisonReaderOutput(source = o.text + "\n")
}

//! the reader ends at the first `%%`, as every reader does, so tools that skip reader text agree
def private bison_reader_accept(var expr : ExprReader?; ch : int) : bool {
    if (ch != '\r') {
        append(expr.sequence, ch)
    }
    return true if (ch != '%' || !ends_with(expr.sequence, "%%"))
    resize(expr.sequence, length(expr.sequence) - 2)
    return false
}

[reader_macro(name="bison")]
class BisonReader : AstReaderMacro {
    def override accept(prog : ProgramPtr; mod : Module?; var expr : ExprReader?; ch : int;
                        info : LineInfo) : bool => bison_reader_accept(expr, ch)
    def override suffix(prog : ProgramPtr; mod : Module?; var expr : ExprReader?; info : LineInfo;
                        var outLine : int&; var outFile : FileInfo?&) : string {
        let out = bison_reader_source(string(expr.sequence))
        if (!empty(out.err)) {
            var at = info
            at.line = uint(int(info.line) + out.line)
            prog |> macro_error(at, "%bison~: {out.err}")
            return ""
        }
        outLine = int(info.line)
        outFile = expr.at.fileInfo
        return out.source
    }
}
