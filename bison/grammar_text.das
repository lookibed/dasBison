options gen2
options indenting = 4
options strict_smart_pointers = true

module grammar_text shared public

require bison/lalr
require bison/prec
require daslib/strings_boost
require strings

// A grammar written as yacc-like text: one right-hand side string per production over rule names,
// token names and quoted characters, built into an `LalrBuilder` whose terminals carry the token
// kind a lexer emits. `bison/bison_macro` reads its `[bison]` function into this shape.

//! One symbol of a right-hand side: a name (a rule or a token) or a quoted character.
struct TextSymbol {
    name : string           //!< the name, or the character as written (`'+'`)
    ch : int = -1           //!< the byte of a quoted character, -1 for a name
}

//! A right-hand side read from its text: the symbols, the `%prec` token, or what is wrong with it.
struct TextRhs {
    syms : array<TextSymbol>
    prec : string           //!< the name after `%prec`, "" when none
    err : string
}

//! One `rule("lhs", "rhs")`.
struct TextRule {
    lhs : string
    rhs : string
}

//! One precedence line: `left`, `right` or `nonassoc` and its tokens as `prec_left(...)` names them.
struct TextPrec {
    assoc : PrecAssoc
    names : array<string>
}

//! The builder of a text grammar and how its terminals map to token kinds.
struct TextGrammar {
    builder : LalrBuilder
    root : int = -1
    term_kinds : array<int>     //!< per terminal: the token kind it stands for, -1 for a `%prec` name
    syms : array<array<TextSymbol>> //!< per production: its symbols as written
    err : string
    err_rule : int = -1         //!< the rule `err` is about, -1 when it is about no rule
    err_prec : int = -1         //!< the precedence line `err` is about, -1 when it is about none
}

def private is_name_start(c : int) : bool => is_alpha(c) || c == '_'

def private is_name_char(c : int) : bool => is_name_start(c) || is_number(c)

// the byte of a quoted character at `i` (`'c'`, `'\''`, `'\\'`), and where it ends; (-1, i) when none
def private quoted_char(bytes : array<uint8>; i : int) : int2 {
    let n = length(bytes)
    if (i + 2 < n && int(bytes[i + 1]) != '\\' && int(bytes[i + 2]) == '\'') {
        return int2(int(bytes[i + 1]), i + 3)
    }
    if (i + 3 < n && int(bytes[i + 1]) == '\\' && int(bytes[i + 3]) == '\'') {
        let c = int(bytes[i + 2])
        let esc = c == 'n' ? '\n' : (c == 't' ? '\t' : (c == 'r' ? '\r' : c))
        return int2(esc, i + 4)
    }
    return int2(-1, i)
}

// the quoted character as a right-hand side writes byte `c`: `'+'`, and `'\\'`, `'\''`, `'\n'`,
// `'\t'`, `'\r'` escaped as `quoted_char` reads them
def private quoted_name(c : int) : string {
    let esc = (c == '\\' ? "\\\\" : c == '\'' ? "\\'" : c == '\n' ? "\\n" : c == '\t' ? "\\t"
        : c == '\r' ? "\\r" : "")
    return empty(esc) ? "'{to_char(c)}'" : "'{esc}'"
}

//! Read a right-hand side: names, quoted characters, and an optional trailing `%prec NAME`.
def parse_rhs(text : string) : TextRhs {
    var res : TextRhs
    let bytes <- to_bytes(text)
    let n = length(bytes)
    var i = 0
    var want_prec = false
    while (i < n) {
        let c = int(bytes[i])
        if (is_white_space(c)) {
            i++
        } elif (is_name_start(c)) {
            let from = i
            while (i < n && is_name_char(int(bytes[i]))) {
                i++
            }
            let name = slice(bytes, from, i)
            if (want_prec) {
                res.prec = name
                want_prec = false
            } elif (!empty(res.prec)) {
                res.err = "'{name}' after %prec {res.prec}: %prec ends the right-hand side"
                return <- res
            } else {
                res.syms |> push(TextSymbol(name = name))
            }
        } elif (c == '\'') {
            let q = quoted_char(bytes, i)
            if (q.x < 0) {
                res.err = "a quoted character is one character between single quotes, at offset {i}"
                return <- res
            }
            if (want_prec) {
                res.prec = slice(bytes, i, q.y)
                want_prec = false
            } elif (!empty(res.prec)) {
                res.err = "{slice(bytes, i, q.y)} after %prec {res.prec}: %prec ends the right-hand side"
                return <- res
            } else {
                res.syms |> push(TextSymbol(name = slice(bytes, i, q.y), ch = q.x))
            }
            i = q.y
        } elif (c == '%' && slice(bytes, i, i + 5) == "%prec"
                && !(i + 5 < n && is_name_char(int(bytes[i + 5])))) {
            want_prec = true
            i += 5
        } else {
            res.err = "unexpected '{slice(bytes, i, i + 1)}' at offset {i}: a symbol is a name or a quoted character"
            return <- res
        }
    }
    if (want_prec) {
        res.err = "%prec needs a token name"
    }
    return <- res
}

// the terminal of token kind `kind` named `name`, declared on first use; -1 (and `g.err`) when
// another name already stands for the same kind
def private kind_term(var g : TextGrammar; var by_kind : table<int; int>; name : string;
                      kind : int) : int {
    let found = by_kind?[kind] ?? -1
    if (found >= 0) {
        let have = g.builder.term_names[found]
        if (have != name) {
            g.err = "{name} and {have} are the same token kind {kind}"
        }
        return found
    }
    let id = term_id(g.builder, name)
    if (id >= length(g.term_kinds)) {
        g.term_kinds |> resize(id + 1)
    }
    g.term_kinds[id] = kind
    by_kind[kind] = id
    return id
}

// a precedence or `%prec` name: a quoted or bare punctuation character, a token, or else a name of
// its own that no token kind reaches (yacc's `%prec UMINUS`)
def private prec_term(var g : TextGrammar; var by_kind : table<int; int>;
                      tokens : table<string; int>; name : string) : int {
    let bytes <- to_bytes(name)
    if (length(bytes) == 1 && !is_name_char(int(bytes[0]))) {
        return kind_term(g, by_kind, quoted_name(int(bytes[0])), int(bytes[0]))
    }
    let q = !empty(bytes) && int(bytes[0]) == '\'' ? quoted_char(bytes, 0) : int2(-1, 0)
    if (q.x >= 0 && q.y == length(bytes)) {
        return kind_term(g, by_kind, name, q.x)
    }
    let kind = tokens?[name] ?? -1
    if (kind >= 0) {
        return kind_term(g, by_kind, name, kind)
    }
    let found = g.builder.term_index?[name] ?? -1
    return found if (found >= 0)
    let id = term_id(g.builder, name)
    g.term_kinds |> resize(id + 1)
    g.term_kinds[id] = -1
    return id
}

// the precedence lines into the builder, each the next level up
def private declare_precs(var g : TextGrammar; var by_kind : table<int; int>;
                          tokens : table<string; int>; precs : array<TextPrec>) {
    for (pi, pl in count(), precs) {
        var inscope ids <- [for (name in pl.names); prec_term(g, by_kind, tokens, name)]
        if (!empty(g.err)) {
            g.err_prec = pi
            return
        }
        if (pl.assoc == PrecAssoc.left) {
            prec_left(g.builder, ids)
        } elif (pl.assoc == PrecAssoc.right) {
            prec_right(g.builder, ids)
        } else {
            prec_nonassoc(g.builder, ids)
        }
    }
}

// one rule's production and its `%prec`; `g.err` says what is wrong with it
def private add_text_rule(var g : TextGrammar; var by_kind : table<int; int>;
                          tokens : table<string; int>; r : TextRule) {
    var inscope parsed <- parse_rhs(r.rhs)
    if (!empty(parsed.err)) {
        g.err = parsed.err
        return
    }
    var inscope rhs : array<int>
    for (s in parsed.syms) {
        let rule = s.ch < 0 ? g.builder.rule_index?[s.name] ?? -1 : -1
        let kind = s.ch >= 0 ? s.ch : tokens?[s.name] ?? -1
        if (rule >= 0) {
            rhs |> push(rule_sym(rule))
        } elif (kind >= 0) {
            rhs |> push(term_sym(kind_term(g, by_kind, s.name, kind)))
        } else {
            g.err = "'{s.name}' is neither a rule nor a token"
        }
        return if (!empty(g.err))
    }
    add_production(g.builder, rule_id(g.builder, r.lhs), rhs)
    if (!empty(parsed.prec)) {
        let term = prec_term(g, by_kind, tokens, parsed.prec)
        prec_of_production(g.builder, length(g.builder.prods) - 1, term)
    }
    g.syms |> emplace(parsed.syms)
}

//! Build `rules` into a builder: an identifier that is some rule's left-hand side is that rule, one
//! in `tokens` (name -> kind) is that token, a quoted character is the token of its byte. `precs`
//! are the precedence lines in order, `root` the start rule ("" for the first rule's left-hand side).
def grammar_from_text(rules : array<TextRule>; precs : array<TextPrec>; root : string;
                      tokens : table<string; int>) : TextGrammar {
    var g <- TextGrammar()
    if (empty(rules)) {
        g.err = "the grammar has no rules"
        return <- g
    }
    var by_kind : table<int; int>
    for (r in rules) {
        rule_id(g.builder, r.lhs)
    }
    declare_precs(g, by_kind, tokens, precs)
    return <- g if (!empty(g.err))
    for (ri, r in count(), rules) {
        add_text_rule(g, by_kind, tokens, r)
        if (!empty(g.err)) {
            g.err_rule = ri
            return <- g
        }
    }
    let root_name = empty(root) ? rules[0].lhs : root
    g.root = g.builder.rule_index?[root_name] ?? -1
    if (g.root < 0) {
        g.err = "root '{root_name}' is not a rule"
    }
    return <- g
}

//! The compile warning a grammar's default-resolved conflicts give, "" when there is none to give:
//! no conflict is left, or `expected` (yacc's `%expect`, -1 when absent) is the shift/reduce count
//! and no reduce/reduce conflict is left.
def conflict_warning(name : string; report : PrecReport; expected : int) : string {
    let sr = report.shift_reduce
    let rr = report.reduce_reduce
    return "" if (rr == 0 && (expected >= 0 ? sr == expected : sr == 0))
    let wanted = expected >= 0 ? " (expected = {expected})" : ""
    return "[bison] {name}: {sr} shift/reduce, {rr} reduce/reduce conflicts{wanted}, resolved by default:\n{format_report(report)}"
}
