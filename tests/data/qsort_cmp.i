void qsort(void *, unsigned long, unsigned long, int (*)(const void *, const void *));
typedef struct { int key; int tag; } rec_t;
static volatile int count = 2048;
static rec_t recs[4096];
static int result;
static int by_key(const void *a, const void *b) {
    const rec_t *x = (const rec_t *) a;
    const rec_t *y = (const rec_t *) b;
    return x->key < y->key ? -1 : x->key > y->key ? 1 : x->tag - y->tag;
}
static int sorted_sum(int n) {
    unsigned seed = 12345u;
    unsigned sum = 0;
    int i;
    for (i = 0; i < n; i++) {
        seed = seed * 1103515245u + 12345u;
        recs[i].key = (int) ((seed >> 16) & 1023u);
        recs[i].tag = i;
    }
    qsort(recs, (unsigned long) n, sizeof(rec_t), by_key);
    for (i = 0; i < n; i++) sum = sum * 31u + (unsigned) recs[i].tag;
    return (int) (sum & 0x7fffffffu);
}
static void kernel_run(void) { result = sorted_sum(count); }
static int kernel_result(void) { return result; }
