options gen2
options indenting = 4

// Parse preprocessed C11 files (`gcc -E` output) with the [bison] C11 grammar of `c11_parser`:
// prints `path: accepted, N tokens, M typedefs` per file, or the error with its position. With
// `--time N` each file is parsed N times and the line ends with the median pass, lex and parse.
//
// Run: daslang -load_module <dasBison> -load_module <dasFlex> examples/c11/parse_c11.das -- [--time N] files.i...

require c11_parser
require daslib/fio
require daslib/sort_boost
require daslib/strings_convert

//! the command line after `--`: the passes `--time N` asks for (0 without it), the files to
//! parse, and the usage message when the count is bad
struct C11Args {
    passes : int
    files : array<string>
    err : string
}

//! reads `args`, the whole command line: `--time N` right after `--`, then the files
def parse_c11_args(args : array<string>) : C11Args {
    var res : C11Args
    var first = find_index(args, "--") + 1
    if (first + 1 < length(args) && args[first] == "--time") {
        res.passes = try_to_int(args[first + 1]) ?? 0
        if (res.passes < 1) {
            res.err = "--time takes a pass count of 1 or more"
            return <- res
        }
        first += 2
    }
    res.files := args[first..length(args)]
    return <- res
}

//! the milliseconds of each of `passes` parses of `src`, in order
def timed_passes(src, path : string; passes : int) : array<double> {
    var times : array<double>
    times |> reserve(passes)
    for (_ in range(passes)) {
        let t0 = ref_time_ticks()
        parse_c11(src, path)
        times |> push(double(get_time_usec(t0)) / 1000.0lf)
    }
    return <- times
}

//! the median of `times`, the upper one of an even count; sorts `times`
def median_ms(var times : array<double>) : double {
    sort(times)
    return times[length(times) / 2]
}

//! the line an accepted file prints; `passes` 0 leaves the median off
def accepted_line(path : string; tokens, typedefs : int; median : double; passes : int) : string {
    let timed = passes > 0 ? ", median {fmt(":.3f", median)} ms of {passes}" : ""
    return "{path}: accepted, {tokens} tokens, {typedefs} typedefs{timed}"
}

[export]
def main() {
    var failed = false
    let args <- parse_c11_args(get_command_line_arguments())
    if (!empty(args.err)) {
        print("{args.err}\n")
        unsafe(fio::exit(2))
    }
    for (path in args.files) {
        let src = fread(path)
        let res = parse_c11(src, path)
        if (!res.accepted) {
            print("{res.err}\n")
            failed = true
            continue
        }
        var median = 0.0lf
        if (args.passes > 0) {
            var inscope times <- timed_passes(src, path, args.passes)
            median = median_ms(times)
        }
        print("{accepted_line(path, c11_token_count(src), res.typedefs, median, args.passes)}\n")
    }
    unsafe {
        fio::exit(failed ? 1 : 0)
    }
}
