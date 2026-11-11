#include <errno.h>
#include <stdio.h>
#include <sys/stat.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        return 1;
    }

    const char *staged = argv[1];
    const char *output = argv[2];
    if (renamex_np(staged, output, RENAME_EXCL) == 0) {
        return 0;
    }
    if (errno == EEXIST) {
        struct stat existing;
        if (lstat(output, &existing) == 0 && S_ISDIR(existing.st_mode)) {
            // Atomically exchange both directories. The old app stays in staging for cleanup.
            if (renamex_np(staged, output, RENAME_SWAP) == 0) {
                return 0;
            }
        } else {
            errno = EEXIST;
        }
    }

    perror(output);
    return 1;
}
