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

//! the median of `passes` parses of `src`, in milliseconds
def median_ms(src, path : string; passes : int) : double {
    var times : array<double>
    times |> reserve(passes)
    for (_ in range(passes)) {
        let t0 = ref_time_ticks()
        parse_c11(src, path)
        times |> push(double(get_time_usec(t0)) / 1000.0lf)
    }
    sort(times)
    return times[passes / 2]
}

[export]
def main() {
    var failed = false
    let args <- get_command_line_arguments()
    var first = find_index(args, "--") + 1
    var passes = 0
    if (first + 1 < length(args) && args[first] == "--time") {
        passes = try_to_int(args[first + 1]) ?? 0
        if (passes < 1) {
            print("--time takes a pass count of 1 or more\n")
            unsafe(fio::exit(2))
        }
        first += 2
    }
    for (path in args[first..length(args)]) {
        let src = fread(path)
        let res = parse_c11(src, path)
        if (!res.accepted) {
            print("{res.err}\n")
            failed = true
            continue
        }
        let timed = passes > 0 ? ", median {fmt(":.3f", median_ms(src, path, passes))} ms of {passes}" : ""
        print("{path}: accepted, {c11_token_count(src)} tokens, {res.typedefs} typedefs{timed}\n")
    }
    unsafe {
        fio::exit(failed ? 1 : 0)
    }
}
