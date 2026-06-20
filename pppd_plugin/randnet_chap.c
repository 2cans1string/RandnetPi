#include <stddef.h>
#include <string.h>
#include "pppd.h"
#include "chap-new.h"

char pppd_version[] = "2.4.7";

static int randnet_chap_verify(char *name, char *ourname, int id,
    struct chap_digest_type *digest,
    unsigned char *challenge, unsigned char *response,
    char *message, int message_space)
{
    slprintf(message, message_space, "Access granted");
    notice("Randnet CHAP: accepted peer authentication for '%s'", name ? name : "(unknown)");
    return 1;
}

void plugin_init(void)
{
    chap_verify_hook = randnet_chap_verify;
    notice("Randnet CHAP bypass plugin loaded");
}
