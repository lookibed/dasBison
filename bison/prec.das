options gen2
options indenting = 4
options strict_smart_pointers = true

module prec shared public

require bison/lalr
require math
require daslib/strings_boost

// Precedence and associativity as yacc declares them, kept in the builder's `prec_terms` and
// `prec_prods`; `build_lalr` never reads them.

//! How equal precedences break a shift/reduce tie: left reduces, right shifts, nonassoc errs.
enum PrecAssoc {
    left = 1
    right
    nonassoc
}

def private declare_level(var gb : LalrBuilder; terms : array<int>; assoc : PrecAssoc) {
    var level = 1
    for (p in gb.prec_terms) {
        level = max(level, p.x + 1)
    }
    for (term in terms) {
        if (term >= length(gb.prec_terms)) {
            gb.prec_terms |> resize(term + 1)
        }
        gb.prec_terms[term] = int2(level, int(assoc))
    }
}

//! `%left terms`: the terminals get the next precedence level, left-associative.
def prec_left(var gb : LalrBuilder; terms : array<int>) {
    declare_level(gb, terms, PrecAssoc.left)
}

//! `%right terms`: the terminals get the next precedence level, right-associative.
def prec_right(var gb : LalrBuilder; terms : array<int>) {
    declare_level(gb, terms, PrecAssoc.right)
}

//! `%nonassoc terms`: the terminals get the next precedence level, non-associative.
def prec_nonassoc(var gb : LalrBuilder; terms : array<int>) {
    declare_level(gb, terms, PrecAssoc.nonassoc)
}

//! `%prec term` on production `prod` (its index in `gb.prods`, `length(gb.prods) - 1` right after
//! `add_production`): the production takes the precedence of `term` instead of its last terminal's.
def prec_of_production(var gb : LalrBuilder; prod, term : int) {
    let from = length(gb.prec_prods)
    if (prod >= from) {
        gb.prec_prods |> resize(prod + 1)
        for (i in range(from, prod + 1)) {
            gb.prec_prods[i] = -1
        }
    }
    gb.prec_prods[prod] = term
}

//! How `resolve_precedence` settled one conflicting cell.
enum PrecHow {
    precedence  //!< precedence and associativity left one action
    nonassoc    //!< a non-associative tie made the cell an error
    by_default  //!< yacc's default: the shift over every reduce, else the earliest production
}

//! One conflicting cell of the input tables and what became of it.
struct PrecCell {
    state : int
    term : int
    how : PrecHow
    chosen : int                //!< the cell's action in the resolved tables; 0 for an error
    removed : array<int>        //!< actions precedence took out of the cell
    kept : array<int>           //!< the default's losers, still in the resolved tables' `alt`
    token : string              //!< the terminal's name
    words : array<string>       //!< bison's words for `chosen`, then for each of `kept`
}

//! Every conflicting cell, how many each way, and bison's conflict counts over the default ones.
struct PrecReport {
    by_precedence : int
    by_default : int
    nonassoc_errors : int
    shift_reduce : int          //!< default cells with a shift and a reduce
    reduce_reduce : int         //!< over default cells: their reduces past the first
    cells : array<PrecCell>     //!< by cell index
}

//! The resolved copy of the tables and the report of what changed.
struct PrecResult {
    tables : LalrTables
    report : PrecReport
}

def private term_prec(gb : LalrBuilder; term : int) : int2 =>
    term < length(gb.prec_terms) ? gb.prec_terms[term] : int2(0, 0)

// table production `p` is builder production `p - 1`; production 0, the augmented start, has none
def private prod_prec(t : LalrTables; gb : LalrBuilder; p : int) : int2 {
    return int2(0, 0) if (p == 0)
    let over = p - 1 < length(gb.prec_prods) ? gb.prec_prods[p - 1] : -1
    return term_prec(gb, over) if (over >= 0)
    var last = -1
    for (s in t.prods[p].rhs) {
        if (s >= 0) {
            last = s
        }
    }
    return last >= 0 ? term_prec(gb, last) : int2(0, 0)
}

def private is_shift(a : int) : bool => a > 0 && a != LALR_ACCEPT

def private reduce_action(p : int) : int => p == 0 ? LALR_ACCEPT : -(1 + p)

// an action as `bison -v` words it
def private bison_action(t : LalrTables; a : int) : string {
    if (a == LALR_ACCEPT) {
        return "accept"
    } elif (a > 0) {
        return "shift, and go to state {a - 1}"
    } elif (a < 0) {
        return "reduce using rule {-1 - a} ({describe_prod(t, -1 - a)})"
    }
    return "error (nonassociative)"
}

def private resolve_cell(var t : LalrTables; gb : LalrBuilder; cell : int; var rep : PrecReport) {
    var c = PrecCell(state = cell / t.nterms, term = cell % t.nterms)
    var shift = 0
    var inscope reds : array<int>
    var inscope actions <- [t.action[cell]]
    actions |> push_from(t.alt[cell])
    for (a in actions) {
        if (is_shift(a)) {
            shift = a
        } else {
            reds |> push(a == LALR_ACCEPT ? 0 : -1 - a)
        }
    }
    sort(reds)
    let tp = term_prec(gb, c.term)
    var nonassoc = false
    var inscope left : array<int>
    for (p in reds) {
        let pp = prod_prec(t, gb, p)
        if (shift == 0 || pp.x == 0 || tp.x == 0) {
            left |> push(p)
        } elif (pp.x > tp.x || (pp.x == tp.x && tp.y == int(PrecAssoc.left))) {
            c.removed |> push(shift)
            shift = 0
            left |> push(p)
        } elif (pp.x < tp.x || tp.y == int(PrecAssoc.right)) {
            c.removed |> push(reduce_action(p))
        } else {
            c.removed |> push_from([shift, reduce_action(p)])
            shift = 0
            nonassoc = true
        }
    }
    var inscope survivors <- [for (p in left); reduce_action(p)]
    if (shift != 0) {
        survivors |> push(shift, 0)
    }
    t.alt |> erase(cell)
    if (nonassoc) {
        c.removed |> push_from(survivors)
        c.how = PrecHow.nonassoc
        rep.nonassoc_errors++
    } else {
        c.chosen = survivors[0]
        if (length(survivors) == 1) {
            c.how = PrecHow.precedence
            rep.by_precedence++
        } else {
            c.how = PrecHow.by_default
            rep.by_default++
            if (shift != 0) {
                rep.shift_reduce++
            }
            rep.reduce_reduce += max(0, length(left) - 1)
            c.kept <- [for (i in range(1, length(survivors))); survivors[i]]
            t.alt[cell] := c.kept
        }
    }
    t.action[cell] = c.chosen
    c.token = t.term_names[c.term]
    c.words |> push(bison_action(t, c.chosen))
    c.words |> push_from([for (a in c.kept); bison_action(t, a)])
    rep.cells |> emplace(c)
}

//! Resolve every conflicting cell of `t` by the precedence declared in `gb` (the builder `t` was
//! built from), the way yacc does, into a copy; `t` itself is not changed.
def resolve_precedence(t : LalrTables; gb : LalrBuilder) : PrecResult {
    var res : PrecResult
    res.tables := t
    var inscope cells <- [for (c in keys(t.alt)); c]
    sort(cells)
    for (cell in cells) {
        resolve_cell(res.tables, gb, cell, res.report)
    }
    res.tables.conflicts = res.report.by_default
    res.tables.first_conflict = ""
    for (c in res.report.cells) {
        if (c.how == PrecHow.by_default) {
            let kind = is_shift(c.chosen) ? "shift/reduce" : "reduce/reduce"
            let on = t.term_names[c.term]
            let what = describe_action(t, c.kept[0])
            res.tables.first_conflict = "{kind} conflict in state {c.state} on {on}: {what}"
            break
        }
    }
    return <- res
}

// a default cell's share of bison's per-state counts: (shift/reduce, reduce/reduce)
def private default_counts(c : PrecCell) : int2 =>
    is_shift(c.chosen) ? int2(1, length(c.kept) - 1) : int2(0, length(c.kept))

//! The default-resolved cells as `bison -v` lists them: `State N conflicts: K shift/reduce` (and
//! `M reduce/reduce`) per state, then per cell the token with the chosen action and, in brackets,
//! each action it won over. Empty when precedence resolved every cell.
def format_report(report : PrecReport) : string {
    return build_string() $(var w) {
        var state = -1
        for (i, c in count(), report.cells) {
            continue if (c.how != PrecHow.by_default)
            if (c.state != state) {
                state = c.state
                var n = int2(0, 0)
                for (j in range(i, length(report.cells))) {
                    let d & = unsafe(report.cells[j])
                    break if (d.state != state)
                    n += d.how == PrecHow.by_default ? default_counts(d) : int2(0, 0)
                }
                let sr = n.x > 0 ? "{n.x} shift/reduce" : ""
                let rr = n.y > 0 ? "{n.y} reduce/reduce" : ""
                let sep = n.x > 0 && n.y > 0 ? ", " : ""
                w |> write("State {state} conflicts: {sr}{sep}{rr}\n")
            }
            for (k, words in count(), c.words) {
                let shown = k == 0 ? words : "[{words}]"
                w |> write("    {c.token}  {shown}\n")
            }
        }
    }
}
