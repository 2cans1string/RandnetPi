#include <pppd/pppd.h>
#include <pppd/chap-new.h>
#include <string.h>
#include <stdio.h>

char pppd_version[] = VERSION;

static int randnet_chap_verify(char *name, char *ourname, int id,
                                struct chap_digest_type *digest,
                                unsigned char *challenge,
                                unsigned char *response,
                                char *message, int message_space)
{
    /* Accept any CHAP response — the 64DD uses a proprietary format */
    slprintf(message, message_space, "Welcome");
    return 1;
}

void plugin_init(void)
{
    const char *required = "2.4.7";

    if (strcmp(pppd_version, required) != 0) {
        fprintf(stderr, "randnet_chap: skipping plugin, incompatible pppd version %s (requires %s)\n",
                pppd_version, required);
        return;
    }

    chap_verify_hook = randnet_chap_verify;
}
