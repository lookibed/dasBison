options gen2
options indenting = 4
options strict_smart_pointers = true

module lalr shared public

require daslib/strings_boost

// An LALR(1) table builder over integer terminals: terminal ids 0..n-1 a program declares, rules
// by name, productions as sequences of terminal ids and rules. The end of input is the terminal id
// after the last declared one. A cell more than one action claims keeps every action (`alt`);
// nothing is resolved here. `lr_parse` runs the tables deterministically over a token array.

//! One production: `rhs` holds terminal ids (`>= 0`) and rules (`-(1 + rule)`, see `rule_sym`).
struct Production {
    lhs : int
    rhs : array<int>
}

//! Assembles a grammar: terminals and rules by name or count, productions over them.
struct LalrBuilder {
    term_names : array<string>
    term_index : table<string; int>
    rule_names : array<string>
    rule_index : table<string; int>
    prods : array<Production>
    prec_terms : array<int2>    //!< per terminal: (level, associativity), written by `bison/prec`
    prec_prods : array<int>     //!< per production: the terminal whose precedence it takes, or -1
}

//! The finished tables. `action[state * nterms + term]`: 0 = error, `1 + s` = shift to state s,
//! `-(1 + p)` = reduce by production p, `LALR_ACCEPT` on the end-of-input column `eof`.
//! `goto_nt[state * nrules + rule]` = the state after a reduce, or -1. A cell with more than one
//! action keeps the first in `action` and the others in `alt`, keyed by the cell index;
//! `conflicts` counts such cells and `first_conflict` names the first.
struct LalrTables {
    term_names : array<string>  //!< `eof` last, named `<end>`
    rule_names : array<string>  //!< the augmented start `<start>` last
    prods : array<Production>   //!< production 0 is `<start> ::= root`
    nterms : int                //!< declared terminals plus the end of input
    eof : int                   //!< `nterms - 1`
    nrules : int
    nstates : int
    action : array<int>
    alt : table<int; array<int>>
    goto_nt : array<int>
    root : int
    conflicts : int
    first_conflict : string
    err : string                //!< "" when the build succeeded, else why not
    err_rule : string           //!< the rule `err` is about, "" when it is about no rule
}

let LALR_ACCEPT = 2147483647   //!< the end-of-input action that marks acceptance

//! A terminal id as a right-hand-side symbol.
def term_sym(term : int) : int => term

//! A rule as a right-hand-side symbol.
def rule_sym(rule : int) : int => -(1 + rule)

def sym_is_rule(s : int) : bool => s < 0

def sym_rule_of(s : int) : int => -1 - s

//! The id of `name` in a name list and its index: its position, the name appended on first mention.
def intern(var names : array<string>; var index : table<string; int>; name : string) : int {
    let found = index?[name] ?? -1
    return found if (found >= 0)
    let id = length(names)
    names |> push(name)
    index[name] = id
    return id
}

//! The id of rule `name`, declared on first mention.
def rule_id(var gb : LalrBuilder; name : string) : int => intern(gb.rule_names, gb.rule_index, name)

//! The id of terminal `name`, declared on first mention.
def term_id(var gb : LalrBuilder; name : string) : int => intern(gb.term_names, gb.term_index, name)

//! Make terminal ids `0 .. count-1` exist; the ones not yet named are named `#<id>`.
def declare_terms(var gb : LalrBuilder; count : int) {
    for (i in range(length(gb.term_names), count)) {
        term_id(gb, "#{i}")
    }
}

//! Add `lhs -> rhs`; an empty `rhs` is the epsilon production.
def add_production(var gb : LalrBuilder; lhs : int; rhs : array<int>) {
    var p = Production(lhs = lhs)
    p.rhs := rhs
    gb.prods |> emplace(p)
}

struct private Item {
    prod : int
    dot : int
}

struct private LrState {
    kernel : array<Item>
    la : array<table<int>>          //!< per kernel item: lookahead terminals
    trans : table<int; int>         //!< symbol -> state
}

struct private Builder {
    prods : array<Production>
    nrules : int
    nterms : int
    item_base : array<int>          //!< per production: the dense id of its dot-0 item
    nullable : array<bool>
    first : array<table<int>>       //!< per rule: terminals that can start it
    by_lhs : array<array<int>>      //!< per rule: its productions
    states : array<LrState>
    state_index : table<string; int>
    first_cell : int = -1           //!< the first conflicting cell and the action that made it one
    first_want : int
}

//! the dense id of an item, one per (production, dot) pair
def private item_id(b : Builder; it : Item) : int => b.item_base[it.prod] + it.dot

[arch(at="../ARCHITECTURE.md#item-key")]
def private item_la_key(b : Builder; it : Item; la : int) : int64 =>
    int64(item_id(b, it)) * int64(b.nterms + 1) + int64(la)

def private compute_first(var b : Builder) {
    b.nullable |> resize(b.nrules)
    b.first |> resize(b.nrules)
    var changed = true
    while (changed) {
        changed = false
        for (p in b.prods) {
            var all_null = true
            for (s in p.rhs) {
                if (!sym_is_rule(s)) {
                    if (!(b.first[p.lhs] |> key_exists(s))) {
                        b.first[p.lhs] |> insert(s)
                        changed = true
                    }
                    all_null = false
                    break
                }
                let r = sym_rule_of(s)
                for (c in keys(b.first[r])) {
                    if (!(b.first[p.lhs] |> key_exists(c))) {
                        b.first[p.lhs] |> insert(c)
                        changed = true
                    }
                }
                if (!b.nullable[r]) {
                    all_null = false
                    break
                }
            }
            if (all_null && !b.nullable[p.lhs]) {
                b.nullable[p.lhs] = true
                changed = true
            }
        }
    }
}

// FIRST of `syms[from..]` followed by lookahead `la`, added into `out`
def private first_of_tail(b : Builder; syms : array<int>; from : int; la : int;
                          var out : table<int>) {
    for (i in range(from, length(syms))) {
        let s = syms[i]
        if (!sym_is_rule(s)) {
            out |> insert(s)
            return
        }
        let r = sym_rule_of(s)
        for (c in keys(b.first[r])) {
            out |> insert(c)
        }
        return if (!b.nullable[r])
    }
    out |> insert(la)
}

def private closure0(b : Builder; kernel : array<Item>) : array<Item> {
    var items := kernel
    var seen : table<int>
    for (it in items) {
        seen |> insert(item_id(b, it))
    }
    var i = 0
    while (i < length(items)) {
        let it = items[i]
        let p & = unsafe(b.prods[it.prod])
        if (it.dot < length(p.rhs) && sym_is_rule(p.rhs[it.dot])) {
            for (q in b.by_lhs[sym_rule_of(p.rhs[it.dot])]) {
                let ni = Item(prod = q, dot = 0)
                if (!(seen |> key_exists(item_id(b, ni)))) {
                    seen |> insert(item_id(b, ni))
                    items |> push(ni)
                }
            }
        }
        i++
    }
    return <- items
}

def private kernel_key(b : Builder; kernel : array<Item>) : string {
    var ids <- [for (it in kernel); item_id(b, it)]
    sort(ids)
    return join(ids, ",")
}

def private goto_kernel(b : Builder; closure : array<Item>; sym : int) : array<Item> {
    var out : array<Item>
    for (it in closure) {
        let p & = unsafe(b.prods[it.prod])
        if (it.dot < length(p.rhs) && p.rhs[it.dot] == sym) {
            out |> push(Item(prod = it.prod, dot = it.dot + 1))
        }
    }
    return <- out
}

def private state_of(var b : Builder; var kernel : array<Item>) : int {
    let key = kernel_key(b, kernel)
    let found = b.state_index?[key] ?? -1
    return found if (found >= 0)
    let id = length(b.states)
    var st : LrState
    st.kernel <- kernel
    st.la |> resize(length(st.kernel))
    b.states |> emplace(st)
    b.state_index[key] = id
    return id
}

def private build_lr0(var b : Builder) {
    var start : array<Item>
    start |> push(Item(prod = 0, dot = 0))
    state_of(b, start)
    var i = 0
    while (i < length(b.states)) {
        var inscope closure <- closure0(b, b.states[i].kernel)
        var inscope syms : array<int>
        var inscope seen : table<int>
        for (it in closure) {
            let p & = unsafe(b.prods[it.prod])
            if (it.dot < length(p.rhs)) {
                let s = p.rhs[it.dot]
                if (!(seen |> key_exists(s))) {
                    seen |> insert(s)
                    syms |> push(s)
                }
            }
        }
        for (s in syms) {
            var k <- goto_kernel(b, closure, s)
            let to = state_of(b, k)
            b.states[i].trans[s] = to
        }
        i++
    }
}

struct private Prop {
    from_state : int
    from_item : int
    to_state : int
    to_item : int
}

def private kernel_item_index(st : LrState; it : Item) : int {
    for (i, k in count(), st.kernel) {
        return i if (k.prod == it.prod && k.dot == it.dot)
    }
    return -1
}

// LR(1) closure of one item with lookahead `la0`: (item, lookahead) pairs
def private closure1(b : Builder; it0 : Item; la0 : int) : array<tuple<it : Item; la : int>> {
    var items : array<tuple<it : Item; la : int>>
    var seen : table<int64>
    items |> push((it = it0, la = la0))
    seen |> insert(item_la_key(b, it0, la0))
    var i = 0
    while (i < length(items)) {
        let cur = items[i]
        let p & = unsafe(b.prods[cur.it.prod])
        if (cur.it.dot < length(p.rhs) && sym_is_rule(p.rhs[cur.it.dot])) {
            var inscope las : table<int>
            first_of_tail(b, p.rhs, cur.it.dot + 1, cur.la, las)
            for (q in b.by_lhs[sym_rule_of(p.rhs[cur.it.dot])]) {
                let ni = Item(prod = q, dot = 0)
                for (la in keys(las)) {
                    let key = item_la_key(b, ni, la)
                    if (!(seen |> key_exists(key))) {
                        seen |> insert(key)
                        items |> push((it = ni, la = la))
                    }
                }
            }
        }
        i++
    }
    return <- items
}

//! The propagation marker (the dragon book's #) is the column past the end of input.
def private hash_la(b : Builder) : int => b.nterms

[arch(at="../ARCHITECTURE.md#lookaheads")]
def private compute_lookaheads(var b : Builder) {
    var props : array<Prop>
    let hash = hash_la(b)
    b.states[0].la[0] |> insert(b.nterms - 1)
    for (si in range(length(b.states))) {
        for (ki in range(length(b.states[si].kernel))) {
            var inscope cl <- closure1(b, b.states[si].kernel[ki], hash)
            for (c in cl) {
                let p & = unsafe(b.prods[c.it.prod])
                continue if (c.it.dot >= length(p.rhs))
                let to = b.states[si].trans[p.rhs[c.it.dot]]
                let ti = kernel_item_index(b.states[to], Item(prod = c.it.prod, dot = c.it.dot + 1))
                if (c.la == hash) {
                    let link = Prop(from_state = si, from_item = ki, to_state = to, to_item = ti)
                    props |> push(link)
                } else {
                    b.states[to].la[ti] |> insert(c.la)
                }
            }
        }
    }
    var changed = true
    while (changed) {
        changed = false
        for (pr in props) {
            for (la in keys(b.states[pr.from_state].la[pr.from_item])) {
                if (!(b.states[pr.to_state].la[pr.to_item] |> key_exists(la))) {
                    b.states[pr.to_state].la[pr.to_item] |> insert(la)
                    changed = true
                }
            }
        }
    }
}

//! `A ::= x y z` with rule and terminal names.
def describe_prod(t : LalrTables; p : int) : string {
    let pr & = unsafe(t.prods[p])
    return build_string() $(var w) {
        w |> write(t.rule_names[pr.lhs])
        w |> write(" ::=")
        for (s in pr.rhs) {
            w |> write(" ")
            w |> write(sym_is_rule(s) ? t.rule_names[sym_rule_of(s)] : t.term_names[s])
        }
    }
}

//! A cell's action in words: `shift to 12`, `reduce A ::= x`, `accept`, `error`.
def describe_action(t : LalrTables; a : int) : string {
    if (a == LALR_ACCEPT) {
        return "accept"
    } elif (a > 0) {
        return "shift to {a - 1}"
    } elif (a < 0) {
        return "reduce {describe_prod(t, -1 - a)}"
    }
    return "error"
}

def private add_action(var b : Builder; var t : LalrTables; si, la, want : int) {
    let cell = si * t.nterms + la
    let have = t.action[cell]
    if (have == 0) {
        t.action[cell] = want
        return
    }
    return if (have == want)
    if (t.alt |> key_exists(cell)) {
        for (a in t.alt[cell]) {
            return if (a == want)
        }
    } else {
        t.conflicts++
        if (b.first_cell < 0) {
            b.first_cell = cell
            b.first_want = want
        }
    }
    t.alt[cell] |> push(want)
}

def private build_tables(var b : Builder; var t : LalrTables) {
    let hash = hash_la(b)
    t.nstates = length(b.states)
    t.action |> resize(t.nstates * t.nterms)
    t.goto_nt |> resize(t.nstates * t.nrules)
    for (g in t.goto_nt) {
        g = -1
    }
    for (si in range(length(b.states))) {
        for (s, to in keys(b.states[si].trans), values(b.states[si].trans)) {
            if (sym_is_rule(s)) {
                t.goto_nt[si * t.nrules + sym_rule_of(s)] = to
            } else {
                t.action[si * t.nterms + s] = 1 + to
            }
        }
        // a completed item reached through `#` takes every lookahead of its kernel item
        for (ki in range(length(b.states[si].kernel))) {
            var inscope cl <- closure1(b, b.states[si].kernel[ki], hash)
            for (c in cl) {
                let p & = unsafe(b.prods[c.it.prod])
                continue if (c.it.dot < length(p.rhs))
                let want = c.it.prod == 0 ? LALR_ACCEPT : -(1 + c.it.prod)
                if (c.la != hash) {
                    add_action(b, t, si, c.la, want)
                } else {
                    for (la in keys(b.states[si].la[ki])) {
                        add_action(b, t, si, la, want)
                    }
                }
            }
        }
    }
}

def private check_symbols(gb : LalrBuilder; root : int; var t : LalrTables) {
    let nrules = length(gb.rule_names)
    let nterms = length(gb.term_names)
    if (root < 0 || root >= nrules) {
        t.err = "root rule {root} is not a declared rule"
        return
    }
    for (i, p in count(), gb.prods) {
        if (p.lhs < 0 || p.lhs >= nrules) {
            t.err = "production {i} has left-hand side {p.lhs}, not a declared rule"
            return
        }
        for (s in p.rhs) {
            if (sym_is_rule(s) ? sym_rule_of(s) >= nrules : s >= nterms) {
                let what = sym_is_rule(s) ? "rule {sym_rule_of(s)}" : "terminal {s}"
                let lhs = gb.rule_names[p.lhs]
                t.err = "production {i} of '{lhs}' uses {what}, which is not declared"
                return
            }
        }
    }
}

// every rule the root reaches derives some terminal string; a rule it never reaches is not checked
def private check_well_formed(b : Builder; var t : LalrTables) {
    var productive : array<bool>
    productive |> resize(b.nrules)
    var changed = true
    while (changed) {
        changed = false
        for (p in b.prods) {
            continue if (productive[p.lhs])
            var ok = true
            for (s in p.rhs) {
                if (sym_is_rule(s) && !productive[sym_rule_of(s)]) {
                    ok = false
                    break
                }
            }
            if (ok) {
                productive[p.lhs] = true
                changed = true
            }
        }
    }
    var reach : array<bool>
    reach |> resize(b.nrules)
    var todo : array<int>
    todo |> push(b.prods[0].lhs)
    reach[b.prods[0].lhs] = true
    while (!empty(todo)) {
        let r = todo[length(todo) - 1]
        todo |> pop()
        for (q in b.by_lhs[r]) {
            for (s in b.prods[q].rhs) {
                if (sym_is_rule(s) && !reach[sym_rule_of(s)]) {
                    reach[sym_rule_of(s)] = true
                    todo |> push(sym_rule_of(s))
                }
            }
        }
    }
    for (r in range(b.nrules)) {
        if (reach[r] && !productive[r]) {
            t.err = "rule '{t.rule_names[r]}' derives no terminal string"
            t.err_rule = t.rule_names[r]
            return
        }
    }
}

//! Build the LALR(1) tables of `gb` with `root` as the start rule. The result's `err` is
//! non-empty for an undeclared symbol or a reachable rule that derives no terminal string, and the
//! tables are then empty. A conflict is not an error: every action of the cell is kept (`alt`).
def build_lalr(gb : LalrBuilder; root : int) : LalrTables {
    var t : LalrTables
    t.root = root
    t.term_names := gb.term_names
    t.term_names |> push("<end>")
    t.nterms = length(t.term_names)
    t.eof = t.nterms - 1
    t.rule_names := gb.rule_names
    let start_rule = length(t.rule_names)
    t.rule_names |> push("<start>")
    t.nrules = length(t.rule_names)
    check_symbols(gb, root, t)
    return <- t if (!empty(t.err))
    var b = Builder(nrules = t.nrules, nterms = t.nterms)
    var p0 = Production(lhs = start_rule)
    p0.rhs |> push(rule_sym(root))
    b.prods |> reserve(length(gb.prods) + 1)
    b.prods |> emplace(p0)
    for (p in gb.prods) {
        var q = Production(lhs = p.lhs)
        q.rhs := p.rhs
        b.prods |> emplace(q)
    }
    b.by_lhs |> resize(b.nrules)
    b.item_base |> reserve(length(b.prods))
    var next_item = 0
    for (i, p in count(), b.prods) {
        b.by_lhs[p.lhs] |> push(i)
        b.item_base |> push(next_item)
        next_item += length(p.rhs) + 1
    }
    check_well_formed(b, t)
    if (empty(t.err)) {
        compute_first(b)
        build_lr0(b)
        compute_lookaheads(b)
        build_tables(b, t)
    }
    t.prods <- b.prods
    if (b.first_cell >= 0) {
        let have = t.action[b.first_cell]
        let kind = have > 0 && have != LALR_ACCEPT ? "shift/reduce" : "reduce/reduce"
        let on = t.term_names[b.first_cell % t.nterms]
        let what = describe_action(t, b.first_want)
        t.first_conflict = "{kind} conflict in state {b.first_cell / t.nterms} on {on}: {what}"
    }
    return <- t
}

//! Every conflicting cell in words, one line each: the state, the terminal, then every action.
def describe_conflicts(t : LalrTables) : array<string> {
    var cells <- [for (c in keys(t.alt)); c]
    sort(cells)
    var out <- [for (cell in cells); build_string() $(var w) {
            w |> write("state {cell / t.nterms} on {t.term_names[cell % t.nterms]}: ")
            w |> write(describe_action(t, t.action[cell]))
            t.alt |> get(cell) $(extra) {
                for (a in extra) {
                    w |> write(" | ")
                    w |> write(describe_action(t, a))
                }
            }
        }]
    return <- out
}

//! What `lr_parse` found: acceptance, or where it stopped and what it would have taken there.
struct LrParse {
    ok : bool
    pos : int                   //!< the refused token's index; `length(tokens)` at the end of input
    state : int                 //!< the state that refused it
    token : int                 //!< the refused terminal id (`eof` at the end of input)
    expected : array<int>       //!< terminal ids the parser would have taken at `pos`, ascending,
                                //!< from the stack the refused token was read on
    reductions : array<int>     //!< the productions reduced, in order (indexes into `prods`)
    err : string
}

// the action a single stack takes on `term`: the primary action of its cell
def private cell_action(t : LalrTables; state, term : int) : int =>
    t.action[state * t.nterms + term]

// reduce `stack` by production `p`; false when the goto is missing
def private reduce_on(t : LalrTables; var stack : array<int>; p : int) : bool {
    stack |> resize(length(stack) - length(t.prods[p].rhs))
    let to = t.goto_nt[stack[length(stack) - 1] * t.nrules + t.prods[p].lhs]
    return false if (to < 0)
    stack |> push(to)
    return true
}

//! The most reductions `lr_parse` runs between two shifts.
let LR_MAX_REDUCES = 1000000

// whether `term` would be shifted or accepted from `stack` after its reduce chain
def private lr_takes(action, goto_nt, lhs, len : array<int>; nterms, nrules : int;
                     stack : array<int>; term : int) : bool {
    var inscope probe := stack
    for (_ in range(LR_MAX_REDUCES)) {
        let a = action[probe[length(probe) - 1] * nterms + term]
        return a > 0 if (a >= 0)
        let p = -1 - a
        let depth = length(probe) - len[p]
        let to = goto_nt[probe[depth - 1] * nrules + lhs[p]]
        return false if (to < 0)
        probe |> resize(depth + 1)
        probe[depth] = to
    }
    return false
}

//! The left-hand side and the length of every production of `t`: the per-production columns
//! `lr_expected` and a `[bison]` parser's driver read.
def prod_columns(t : LalrTables) : tuple<lhs : array<int>; len : array<int>> =>
    <- (lhs <- [for (pr in t.prods); pr.lhs], len <- [for (pr in t.prods); length(pr.rhs)])

//! The terminals some reduce chain from `stack` ends in a shift or accept for, ascending: the
//! tables as flat arrays (`action`, `goto_nt`, the left-hand side and length of every production,
//! `nterms`, `nrules`), so `lr_parse` and a `[bison]` parser's emitted globals share one walk.
def lr_expected(action, goto_nt, lhs, len : array<int>; nterms, nrules : int;
                stack : array<int>) : array<int> =>
    <- [for (x in range(nterms)); x;
        where lr_takes(action, goto_nt, lhs, len, nterms, nrules, stack, x)]

//! Before a reduce cuts `stack` down to `depth`: every state under `low` the cut removes goes to
//! `saved`, last removed first, and `low` follows the cut. `low` is `length(stack)` and `saved`
//! empty when a token is read, so `stack[0 .. low)` and `saved` keep the stack it was read on.
def lr_keep_popped(stack : array<int>; var low : int&; var saved : array<int>; depth : int) {
    while (low > depth) {
        low--
        saved |> push(stack[low])
    }
}

//! The state stack as it stood when the current token was read: `stack[0 .. low)`, then the
//! states `lr_keep_popped` saved, in stack order.
def lr_stack_at_read(stack : array<int>; low : int; saved : array<int>) : array<int> {
    var out : array<int>
    out |> reserve(low + length(saved))
    for (i in range(low)) {
        out |> push(stack[i])
    }
    for (k in range(length(saved))) {
        out |> push(saved[length(saved) - 1 - k])
    }
    return <- out
}

//! Run the tables over `tokens` (terminal ids, the end of input implied) with one stack, taking the
//! primary action of a conflicting cell (`action`, never `alt`).
[arch(at="../ARCHITECTURE.md#driver")]
def lr_parse(t : LalrTables; tokens : array<int>) : LrParse {
    var res : LrParse
    if (!empty(t.err)) {
        res.err = t.err
        return <- res
    }
    var stack : array<int>
    stack |> push(0)
    var pos = 0
    var reduces = 0
    var low = 1
    var saved : array<int>
    while (true) {
        let term = pos < length(tokens) ? tokens[pos] : t.eof
        let top = stack[length(stack) - 1]
        let known = pos >= length(tokens) || (term >= 0 && term < t.eof)
        let a = known ? cell_action(t, top, term) : 0
        if (a == LALR_ACCEPT) {
            res.ok = true
            return <- res
        } elif (a > 0) {
            stack |> push(a - 1)
            pos++
            reduces = 0
            low = length(stack)
            saved |> clear()
        } elif (a < 0 && reduces < LR_MAX_REDUCES) {
            res.reductions |> push(-1 - a)
            reduces++
            lr_keep_popped(stack, low, saved, length(stack) - length(t.prods[-1 - a].rhs))
            if (!reduce_on(t, stack, -1 - a)) {
                res.err = "no goto after reducing {describe_prod(t, -1 - a)}"
                return <- res
            }
        } else {
            res.pos = pos
            res.state = top
            res.token = term
            var inscope cols <- prod_columns(t)
            var inscope at_read <- lr_stack_at_read(stack, low, saved)
            res.expected <- lr_expected(t.action, t.goto_nt, cols.lhs, cols.len, t.nterms, t.nrules,
                                        at_read)
            let why = a < 0 ? "reduce loop" : "unexpected terminal {term}"
            res.err = "{why} in state {top}"
            return <- res
        }
    }
    return <- res
}
