options gen2
options indenting = 4
options strict_smart_pointers = true

module bytes shared public

require bison/lalr public
require daslib/strings_boost

// The byte front end of the LALR(1) core: productions over byte sets, partitioned into the finest
// byte classes, each class one terminal id of the core and the end of input the id after the last.
// The adapter only declares terminals, rules and productions through the core's builder; the
// tables it hands back are the core's.

//! A set of bytes: one flag per byte value.
typedef ByteSet = bool[256]

//! A right-hand-side symbol before the build: a byte set, or a rule.
struct GrammarSym {
    is_rule : bool
    rule : int          //!< the rule id when is_rule
    bytes : ByteSet     //!< the terminal's byte set otherwise
}

//! Assembles a byte grammar: rules by name, productions as sequences of byte sets and rules.
struct GrammarBuilder {
    rule_names : array<string>
    rule_index : table<string; int>
    prods : array<tuple<lhs : int; rhs : array<GrammarSym>>>
}

//! A built byte grammar: `byte_class[b]` is byte b's class, and class c is terminal id c of
//! `tables`, whose end of input is `nclasses`. A byte set that spans several classes is a rule of
//! `tables` named `<setN>`, one production per class.
struct Grammar {
    byte_class : array<int>     //!< 256 entries
    nclasses : int
    tables : LalrTables
}

//! The id of rule `name`, declared on first mention.
def rule_id(var gb : GrammarBuilder; name : string) : int =>
    intern(gb.rule_names, gb.rule_index, name)

def sym_rule(rule : int) : GrammarSym => GrammarSym(is_rule = true, rule = rule)

def sym_byte(b : int) : GrammarSym {
    var s : GrammarSym
    s.bytes[b] = true
    return s
}

def sym_bytes(bytes : ByteSet) : GrammarSym {
    var s : GrammarSym
    s.bytes = bytes
    return s
}

//! Add `lhs -> rhs`; an empty `rhs` is the epsilon production.
def add_production(var gb : GrammarBuilder; lhs : int; var rhs : array<GrammarSym>) {
    gb.prods |> emplace((lhs = lhs, rhs <- rhs))
}

// the finest partition of the byte alphabet that every terminal set of the grammar is a union of:
// refine a single class by each set in turn, then number the classes in byte order
def private byte_classes(gb : GrammarBuilder; var cls : array<int>) : int {
    cls |> resize(256)
    var n = 1
    for (p in gb.prods) {
        for (s in p.rhs) {
            continue if (s.is_rule)
            var inscope remap : table<int; int>
            for (b in range(256)) {
                continue if (!s.bytes[b])
                let old = cls[b]
                if (!(remap |> key_exists(old))) {
                    var outside = false
                    for (c in range(256)) {
                        if (cls[c] == old && !s.bytes[c]) {
                            outside = true
                            break
                        }
                    }
                    remap[old] = outside ? n : old
                    if (outside) {
                        n++
                    }
                }
                cls[b] = remap[old]
            }
        }
    }
    var seen : table<int; int>
    for (b in range(256)) {
        let old = cls[b]
        if (!(seen |> key_exists(old))) {
            seen[old] = length(seen)
        }
        cls[b] = seen[old]
    }
    return length(seen)
}

// a class's terminal name: its byte when it holds one, else `class N`
def private class_name(cls : array<int>; c : int) : string {
    var only = -1
    for (b in range(256)) {
        continue if (cls[b] != c)
        return "class {c}" if (only >= 0)
        only = b
    }
    if (only > 32 && only < 127 && only != '\'') {
        return "'{to_char(only)}'"
    }
    return "byte {only}"
}

//! Finalize `gb` with `root` as the start rule: the byte classes, then the core's LALR(1) tables
//! over them. `tables.err` is the core's verdict.
def build_grammar(gb : GrammarBuilder; root : int) : Grammar {
    var g : Grammar
    g.nclasses = byte_classes(gb, g.byte_class)
    var lb : LalrBuilder
    for (c in range(g.nclasses)) {
        term_id(lb, class_name(g.byte_class, c))
    }
    for (name in gb.rule_names) {
        rule_id(lb, name)
    }
    var set_rules : table<string; int>
    for (gp in gb.prods) {
        var inscope rhs : array<int>
        for (s in gp.rhs) {
            if (s.is_rule) {
                rhs |> push(rule_sym(s.rule))
                continue
            }
            var inscope classes : array<int>
            var inscope seen : table<int>
            for (b in range(256)) {
                if (s.bytes[b] && !(seen |> key_exists(g.byte_class[b]))) {
                    seen |> insert(g.byte_class[b])
                    classes |> push(g.byte_class[b])
                }
            }
            if (length(classes) == 1) {
                rhs |> push(term_sym(classes[0]))
                continue
            }
            sort(classes)
            let key = join(classes, ",")
            var set_rule = set_rules?[key] ?? -1
            if (set_rule < 0) {
                set_rule = rule_id(lb, "<set{length(lb.rule_names)}>")
                set_rules[key] = set_rule
                for (c in classes) {
                    add_production(lb, set_rule, [term_sym(c)])
                }
            }
            rhs |> push(rule_sym(set_rule))
        }
        add_production(lb, gp.lhs, rhs)
    }
    g.tables <- build_lalr(lb, root)
    return <- g
}

//! The terminal ids of `s`: one byte class per byte.
def byte_terms(g : Grammar; s : string) : array<int> {
    var out : array<int>
    out |> reserve(length(s))
    peek_data(s) $(d) {
        for (b in d) {
            out |> push(g.byte_class[int(b)])
        }
    }
    return <- out
}

//! Run the deterministic driver over the bytes of `s`.
def lr_parse_bytes(g : Grammar; s : string) : LrParse => <- lr_parse(g.tables, byte_terms(g, s))
