/* pthread + atomics smoke test — exercises libpthread/ld.so under qemu-user,
 * where thread emulation is the classic weak spot. */
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>

#define N 8
#define ITER 100000

static atomic_long counter;

static void *worker(void *arg) {
    (void)arg;
    for (int i = 0; i < ITER; i++)
        atomic_fetch_add(&counter, 1);
    return NULL;
}

int main(void) {
    pthread_t t[N];
    for (int i = 0; i < N; i++)
        if (pthread_create(&t[i], NULL, worker, NULL)) {
            perror("pthread_create");
            return 1;
        }
    for (int i = 0; i < N; i++)
        pthread_join(t[i], NULL);
    long v = atomic_load(&counter);
    printf("counter=%ld expected=%d %s\n", v, N * ITER,
           v == (long)N * ITER ? "OK" : "MISMATCH");
    return v != (long)N * ITER;
}
