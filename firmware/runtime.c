#include <stddef.h>
/* GCC may emit memcpy for structure assignment even in freestanding mode.
 * Byte-wise implementation needs neither libc nor ISA extensions. */
void *memcpy(void *destination, const void *source, size_t length)
{
    unsigned char *out=(unsigned char *)destination;
    const unsigned char *in=(const unsigned char *)source;
    size_t i;
    for (i=0; i<length; ++i) out[i]=in[i];
    return destination;
}
