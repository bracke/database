#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef O_DIRECTORY
#define O_DIRECTORY 0
#endif

int database_posix_open_file(const char *path, int read_only, int create)
{
    int flags = read_only ? O_RDONLY : O_RDWR;

    if (create) {
        return open(path, flags | O_CREAT, (mode_t)0666);
    }
    return open(path, flags);
}

int database_posix_open_directory(const char *path)
{
    return open(path, O_RDONLY | O_DIRECTORY);
}
