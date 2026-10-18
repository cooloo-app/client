/* File commits: never truncate the destination before a complete replacement.
 * Exclusive writes are used for recovery, and never reopen a reserved name.
 * No power-loss durability promise (there is deliberately no fsync contract).
 */
#ifndef _WIN32
#define _XOPEN_SOURCE 700
#endif
#include "file.h"
#include <lauxlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#ifdef _WIN32
#include <windows.h>
#include <wchar.h>
#else
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#if defined(__linux__) || defined(__APPLE__)
#include <sys/xattr.h>
#endif
#ifdef __APPLE__
#include <sys/acl.h>
#endif
#endif

static unsigned long serial;

#ifndef _WIN32
/* Preserve ACLs and other extended metadata; fail closed if it cannot be copied. */
static int copy_xattrs(const char *path, int fd) {
#ifdef __APPLE__
    acl_t acl=acl_get_file(path,ACL_TYPE_EXTENDED);
    if(!acl) {
        /* Darwin reports ENOENT for an existing file without an extended ACL. */
        int error=errno;
        struct stat st;
        if(error!=ENOENT || stat(path,&st))return error;
    } else {
        int error=acl_set_fd_np(fd,acl,ACL_TYPE_EXTENDED)?errno:0;
        acl_free(acl);
        if(error)return error;
    }
#endif
#if defined(__linux__) || defined(__APPLE__)
#ifdef __APPLE__
#define LIST_ATTR(p,b,n) listxattr(p,b,n,0)
#define GET_ATTR(p,k,b,n) getxattr(p,k,b,n,0,0)
#define SET_ATTR(f,k,b,n) fsetxattr(f,k,b,n,0,0)
#else
#define LIST_ATTR(p,b,n) listxattr(p,b,n)
#define GET_ATTR(p,k,b,n) getxattr(p,k,b,n)
#define SET_ATTR(f,k,b,n) fsetxattr(f,k,b,n,0)
#endif
    ssize_t size=LIST_ATTR(path,NULL,0);
    if(size<0)return errno==ENOTSUP?0:errno;
    if(!size)return 0;
    char *names=malloc((size_t)size);
    if(!names)return ENOMEM;
    ssize_t got=LIST_ATTR(path,names,(size_t)size);
    int error=got<0?errno:0;
    for(char *name=names; !error && name<names+got; name+=strlen(name)+1) {
        ssize_t length=GET_ATTR(path,name,NULL,0);
        if(length<0){error=errno;break;}
        void *value=malloc(length?(size_t)length:1);
        if(!value){error=ENOMEM;break;}
        ssize_t actual=GET_ATTR(path,name,value,(size_t)length);
        if(actual<0)error=errno;
        else if(SET_ATTR(fd,name,value,(size_t)actual))error=errno;
        free(value);
    }
    free(names);return error;
#undef LIST_ATTR
#undef GET_ATTR
#undef SET_ATTR
#else
    (void)path;(void)fd;return 0;
#endif
}
#endif

#ifdef _WIN32
static wchar_t *file_wide(lua_State *L, const char *s) {
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, NULL, 0);
    if (!n) luaL_error(L, "invalid UTF-8 filename");
    wchar_t *w = malloc((size_t)n * sizeof *w);
    if (!w) luaL_error(L, "out of memory");
    MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n);
    return w;
}
#endif

/* Returns true, or nil/message/collision. Only a name collision is retryable. */
int platform_write_file(lua_State *L) {
    size_t path_len, length;
    const char *path = luaL_checklstring(L, 1, &path_len);
    const char *data = luaL_checklstring(L, 2, &length);
    int exclusive = lua_toboolean(L, 3), collision = 0;
    luaL_argcheck(L, strlen(path) == path_len, 1, "embedded NUL in filename");
#ifdef _WIN32
    DWORD error = 0;
    wchar_t *target = file_wide(L, path), *temp = NULL;
    HANDLE fp = INVALID_HANDLE_VALUE;
    int exists = 0;
    if (!exclusive) {
        HANDLE old = CreateFileW(target, GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
            OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
        if (old != INVALID_HANDLE_VALUE) {
            BY_HANDLE_FILE_INFORMATION info;
            if (!GetFileInformationByHandle(old, &info)) error = GetLastError();
            else if ((info.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_READONLY))
                     || info.nNumberOfLinks > 1) error = ERROR_ACCESS_DENIED;
            DWORD n = GetFinalPathNameByHandleW(old, NULL, 0, FILE_NAME_NORMALIZED);
            if (!error && !n) error = GetLastError();
            if (!error) {
                wchar_t *canonical = malloc(((size_t)n + 1) * sizeof *canonical);
                if (!canonical) error = ERROR_NOT_ENOUGH_MEMORY;
                else {
                    DWORD got = GetFinalPathNameByHandleW(old, canonical, n + 1, FILE_NAME_NORMALIZED);
                    if (!got || got > n) { error = GetLastError(); free(canonical); }
                    else { free(target); target = canonical; }
                }
            }
            CloseHandle(old);
            exists = 1;
        } else {
            error = GetLastError();
            if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND) {
                /* A dangling reparse point must not be replaced by a regular file. */
                DWORD attrs = GetFileAttributesW(target);
                if (attrs == INVALID_FILE_ATTRIBUTES) error = 0;
            }
        }
        if (error) goto done;
        temp = malloc((wcslen(target) + 80) * sizeof *temp);
        if (!temp) { error = ERROR_NOT_ENOUGH_MEMORY; goto done; }
        wcscpy(temp, target);
        wchar_t *slash = wcsrchr(temp, L'\\'), *forward = wcsrchr(temp, L'/');
        if (forward && (!slash || forward > slash)) slash = forward;
        wchar_t *base = slash ? slash + 1 : temp;
        for (int attempt = 0; attempt < 10000; attempt++) {
            swprintf(base, 80, L".cooloo-save-%lu-%lu", GetCurrentProcessId(), ++serial);
            fp = CreateFileW(temp, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
            if (fp != INVALID_HANDLE_VALUE) break;
            error = GetLastError();
            if (error != ERROR_FILE_EXISTS && error != ERROR_ALREADY_EXISTS) goto done;
        }
    } else {
        fp = CreateFileW(target, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    }
    if (fp == INVALID_HANDLE_VALUE) {
        error = GetLastError();
        collision = exclusive && (error == ERROR_FILE_EXISTS || error == ERROR_ALREADY_EXISTS);
        goto done;
    }
    error = 0;
    for (size_t at = 0; at < length;) {
        DWORD count = 0, chunk = (DWORD)((length - at) > 1048576 ? 1048576 : length - at);
        if (!WriteFile(fp, data + at, chunk, &count, NULL)) { error = GetLastError(); break; }
        if (!count) { error = ERROR_WRITE_FAULT; break; }
        at += count;
    }
    if (!CloseHandle(fp) && !error) error = GetLastError();
    if (!error && !exclusive) {
        BOOL ok = exists ? ReplaceFileW(target, temp, NULL, 0, NULL, NULL)
                         : MoveFileExW(temp, target, 0);
        if (!ok) error = GetLastError();
    }
    if (error) DeleteFileW(exclusive ? target : temp);
done:
    free(temp); free(target);
    if (error) {
        lua_pushnil(L);
        lua_pushfstring(L, "file write failed (%d); hard-linked/read-only files require Save As: %s", (int)error, path);
        lua_pushboolean(L, collision);
        return 3;
    }
#else
    int error = 0, fd = -1, exists = 0;
    char *target = NULL, *temp = NULL;
    struct stat info;
    if (!exclusive) {
        target = realpath(path, NULL);
        if (!target) {
            error = errno;
            if (error != ENOENT) goto done;
            if (lstat(path, &info) == 0 || errno != ENOENT) { error = EINVAL; goto done; }
            target = strdup(path);
            if (!target) { error = ENOMEM; goto done; }
        } else {
            exists = 1;
            if (stat(target, &info)) { error = errno; goto done; }
            /* Atomic replacement cannot preserve other hard-link aliases. Refuse
             * explicitly rather than silently split them or risk an in-place write. */
            if (!S_ISREG(info.st_mode) || info.st_nlink > 1 || !(info.st_mode & 0222)) {
                error = EACCES; goto done;
            }
            if (access(target, W_OK)) { error = errno; goto done; }
        }
        temp = malloc(strlen(target) + 80);
        if (!temp) { error = ENOMEM; goto done; }
        strcpy(temp, target);
        char *slash = strrchr(temp, '/'), *base = slash ? slash + 1 : temp;
        for (int attempt = 0; attempt < 10000; attempt++) {
            snprintf(base, 80, ".cooloo-save-%lu-%lu", (unsigned long)getpid(), ++serial);
            fd = open(temp, O_WRONLY | O_CREAT | O_EXCL, 0600);
            if (fd >= 0 || errno != EEXIST) break;
        }
    } else {
        fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0600);
    }
    if (fd < 0) { error = errno; collision = exclusive && error == EEXIST; goto done; }
    error = 0;
    for (size_t at = 0; at < length;) {
        size_t chunk = length - at > 1048576 ? 1048576 : length - at;
        ssize_t count = write(fd, data + at, chunk);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) { error = count ? errno : EIO; break; }
        at += (size_t)count;
    }
    if (!error && exists) {
        struct stat created;
        if (fstat(fd, &created)) error = errno;
        else if ((created.st_uid != info.st_uid || created.st_gid != info.st_gid)
                 && fchown(fd, info.st_uid, info.st_gid)) error = errno;
        if (!error && fchmod(fd, info.st_mode & 0777)) error = errno;
        if (!error) error = copy_xattrs(target, fd);
    }
    if (close(fd) && !error) error = errno;
    if (!error && !exclusive && rename(temp, target)) error = errno;
    if (error) unlink(exclusive ? path : temp);
done:
    free(temp); free(target);
    if (error) {
        lua_pushnil(L);
        lua_pushfstring(L, "file write failed: %s: %s (hard-linked files require Save As)", path, strerror(error));
        lua_pushboolean(L, collision);
        return 3;
    }
#endif
    lua_pushboolean(L, 1);
    return 1;
}
