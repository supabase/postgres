#ifndef SUPABASE_GLIBC_COMPAT_SHIM_H
#define SUPABASE_GLIBC_COMPAT_SHIM_H

/* -include forces this into .S files too, which the C bits below can't survive. */
#ifndef __ASSEMBLER__

/* Must come before any system header: glibc locks in feature-test-macro visibility (e.g. GNU extensions) at first include. */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

/* Include order locks in __GLIBC__ and glibc's own inline atoi/atol before any override below exists. */
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/random.h>
#include <sys/stat.h>

#if defined(__linux__) && defined(__GLIBC__)

#define GLIBC_COMPAT_VER "GLIBC_2.17"

__asm__(".symver dlopen,dlopen@" GLIBC_COMPAT_VER);
__asm__(".symver dlsym,dlsym@" GLIBC_COMPAT_VER);
__asm__(".symver dlerror,dlerror@" GLIBC_COMPAT_VER);
__asm__(".symver dlclose,dlclose@" GLIBC_COMPAT_VER);
__asm__(".symver sem_init,sem_init@" GLIBC_COMPAT_VER);
__asm__(".symver sem_wait,sem_wait@" GLIBC_COMPAT_VER);
__asm__(".symver sem_post,sem_post@" GLIBC_COMPAT_VER);
__asm__(".symver sem_trywait,sem_trywait@" GLIBC_COMPAT_VER);
__asm__(".symver sem_destroy,sem_destroy@" GLIBC_COMPAT_VER);
__asm__(".symver shm_open,shm_open@" GLIBC_COMPAT_VER);
__asm__(".symver shm_unlink,shm_unlink@" GLIBC_COMPAT_VER);
__asm__(".symver pthread_sigmask,pthread_sigmask@" GLIBC_COMPAT_VER);
__asm__(".symver pthread_getattr_np,pthread_getattr_np@" GLIBC_COMPAT_VER);

extern void *dlvsym(void *handle, const char *symbol, const char *version);
__asm__(".symver dlvsym,dlvsym@" GLIBC_COMPAT_VER);

/* _GNU_SOURCE redirects strtol/strtoul/sscanf/fscanf to distinct __isoc23_* symbols; resolve the old ones by hand. */

static inline long
glibc_compat_strtol(const char *nptr, char **endptr, int base)
{
    long (*fn)(const char *, char **, int) =
        (long (*)(const char *, char **, int)) dlvsym(NULL, "strtol", GLIBC_COMPAT_VER);
    return fn ? fn(nptr, endptr, base) : 0;
}
#undef strtol
#define strtol(a, b, c) glibc_compat_strtol(a, b, c)

static inline unsigned long
glibc_compat_strtoul(const char *nptr, char **endptr, int base)
{
    unsigned long (*fn)(const char *, char **, int) =
        (unsigned long (*)(const char *, char **, int)) dlvsym(NULL, "strtoul", GLIBC_COMPAT_VER);
    return fn ? fn(nptr, endptr, base) : 0;
}
#undef strtoul
#define strtoul(a, b, c) glibc_compat_strtoul(a, b, c)

static inline int
glibc_compat_vsscanf(const char *str, const char *format, va_list ap)
{
    int (*fn)(const char *, const char *, va_list) =
        (int (*)(const char *, const char *, va_list)) dlvsym(NULL, "vsscanf", GLIBC_COMPAT_VER);
    return fn ? fn(str, format, ap) : -1;
}

static inline int
glibc_compat_sscanf(const char *str, const char *format, ...)
{
    va_list ap;
    int ret;
    va_start(ap, format);
    ret = glibc_compat_vsscanf(str, format, ap);
    va_end(ap);
    return ret;
}
#undef sscanf
#define sscanf(...) glibc_compat_sscanf(__VA_ARGS__)

static inline int
glibc_compat_vfscanf(FILE *stream, const char *format, va_list ap)
{
    int (*fn)(FILE *, const char *, va_list) =
        (int (*)(FILE *, const char *, va_list)) dlvsym(NULL, "vfscanf", GLIBC_COMPAT_VER);
    return fn ? fn(stream, format, ap) : -1;
}

static inline int
glibc_compat_fscanf(FILE *stream, const char *format, ...)
{
    va_list ap;
    int ret;
    va_start(ap, format);
    ret = glibc_compat_vfscanf(stream, format, ap);
    va_end(ap);
    return ret;
}
#undef fscanf
#define fscanf(...) glibc_compat_fscanf(__VA_ARGS__)

/* fcntl64 is a distinct symbol from fcntl (GLIBC_2.28, no older alias); call fcntl@2.17 instead, arg forwarded as long. */

static inline int
glibc_compat_fcntl(int fd, int cmd, ...)
{
    va_list ap;
    long arg;
    int (*fn)(int, int, long);
    va_start(ap, cmd);
    arg = va_arg(ap, long);
    va_end(ap);
    fn = (int (*)(int, int, long)) dlvsym(NULL, "fcntl", GLIBC_COMPAT_VER);
    return fn ? fn(fd, cmd, arg) : -1;
}
#undef fcntl64
#define fcntl64(...) glibc_compat_fcntl(__VA_ARGS__)
#undef fcntl
#define fcntl(...) glibc_compat_fcntl(__VA_ARGS__)

/* stat/fstat/lstat moved to GLIBC_2.33; struct stat's layout didn't change on 64-bit archs, so __xstat@2.17 is equivalent (verified byte-for-byte on aarch64-linux). Version tag is 1 on x86_64, 0 elsewhere. */

#if defined(__x86_64__)
#define GLIBC_COMPAT_STAT_VER 1
#else
#define GLIBC_COMPAT_STAT_VER 0
#endif

extern int __xstat(int ver, const char *path, struct stat *buf);
extern int __fxstat(int ver, int fd, struct stat *buf);
extern int __lxstat(int ver, const char *path, struct stat *buf);
__asm__(".symver __xstat,__xstat@" GLIBC_COMPAT_VER);
__asm__(".symver __fxstat,__fxstat@" GLIBC_COMPAT_VER);
__asm__(".symver __lxstat,__lxstat@" GLIBC_COMPAT_VER);

#undef stat
#define stat(path, buf) __xstat(GLIBC_COMPAT_STAT_VER, path, buf)
#undef fstat
#define fstat(fd, buf) __fxstat(GLIBC_COMPAT_STAT_VER, fd, buf)
#undef lstat
#define lstat(path, buf) __lxstat(GLIBC_COMPAT_STAT_VER, path, buf)
#undef stat64
#define stat64(path, buf) __xstat(GLIBC_COMPAT_STAT_VER, path, buf)
#undef fstat64
#define fstat64(fd, buf) __fxstat(GLIBC_COMPAT_STAT_VER, fd, buf)
#undef lstat64
#define lstat64(path, buf) __lxstat(GLIBC_COMPAT_STAT_VER, path, buf)

/* arc4random family is GLIBC_2.36 with no older alias; forward straight to the kernel via getrandom (GLIBC_2.25). */

static inline void
glibc_compat_arc4random_buf(void *buf, size_t n)
{
    unsigned char *p = buf;
    while (n > 0)
    {
        ssize_t r = getrandom(p, n, 0);
        if (r <= 0)
            continue;
        p += r;
        n -= (size_t) r;
    }
}
#undef arc4random_buf
#define arc4random_buf(buf, n) glibc_compat_arc4random_buf(buf, n)

static inline unsigned int
glibc_compat_arc4random(void)
{
    unsigned int v;
    glibc_compat_arc4random_buf(&v, sizeof v);
    return v;
}
#undef arc4random
#define arc4random() glibc_compat_arc4random()

static inline unsigned int
glibc_compat_arc4random_uniform(unsigned int bound)
{
    unsigned int min, r;
    if (bound < 2)
        return 0;
    min = -bound % bound;
    do
        r = glibc_compat_arc4random();
    while (r < min);
    return r % bound;
}
#undef arc4random_uniform
#define arc4random_uniform(bound) glibc_compat_arc4random_uniform(bound)

#endif /* __linux__ && __GLIBC__ */

#endif /* __ASSEMBLER__ */

#endif /* SUPABASE_GLIBC_COMPAT_SHIM_H */
