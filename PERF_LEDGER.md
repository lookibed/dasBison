# dasBison performance ledger (round 1)

Every row is one measured fact or step with its effect. Numbers come from one exclusive run per column set
(`heavy --exclusive`, quiet machine); a row without numbers has not been measured yet. Interp and JIT are
separate columns.

| step | what is measured | interp | jit | verdict |
|---|---|---|---|---|
| 0 C11 parse, five files, lex+parse vs lex | `parse_c11` (the `[bison]` C11 grammar over the dasFlex C lexer, typedef names learned by the grammar's actions) against the dasFlex lexer alone (`c_lex_compare --mode flex`), same five files | doom_am_map 39.22 vs 10.92 ms (parse share 72%), doom_p_mobj 30.77 vs 9.34 (70%), wasm3_m3_parse 36.69 vs 11.18 (70%); qsort_cmp 0.70 vs 0.17 (76%), first_member 1.31 vs 0.33 (75%); lex+parse 2.1-2.4 MB/s, ~440 tokens/ms on the big files | doom_am_map 1.726 vs 1.037 ms (40%), doom_p_mobj 1.317 vs 0.894 (32%), wasm3_m3_parse 1.601 vs 0.995 (38%); qsort_cmp 0.031 vs 0.014 (55%), first_member 0.058 vs 0.032 (45%); lex+parse 47-57 MB/s, 8.4-10.2 k tokens/ms on the big files | base of the parser's speed: all five accepted on every pass; in the interpreter the parse is ~70% of the time, under JIT ~35-40%; JIT is 22-24x the interpreter. The lex-only driver builds a string per token and the parser's lexer does not, so the parse share is a lower bound |
| 1 compile with tables vs cached | wall clock of the whole `parse_c11.das` process on qsort_cmp.i (943 bytes): `-no-module-cache` (the `[bison]` macro builds and resolves the C11 tables, every module parses and infers) against a warm module cache | 1.528 s vs 0.430 s | 2.132 s vs 0.349 s (JIT object cache warm in both) | the cache removes ~1.1 s (interp) / ~1.8 s (jit) of front-end work per start; the table build is inside it, not isolated. The runtime build of the same grammar in the dasLR1 probe (98 byte classes) was 3.16 s interp / 0.50 s JIT per start |

Measured cells: median of 3 rounds of in-process medians of 9 passes (rounds alternate the order of the four
processes per file); the compile row is the median of 3 process runs. dasBison = 66e7e6a, dasFlex = 29393f3,
daslang 0.6.6. Run `TIMING-dasbison-c11`, 2026-11-25 03:46 MSK, `heavy --exclusive`, machine quiet (cpu busy 1%);
raw lines, the timing driver and tables are kept locally, not in the repository.
