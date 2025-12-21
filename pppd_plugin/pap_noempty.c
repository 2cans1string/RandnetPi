#include <pppd/pppd.h>
#include <stdlib.h>
#include <string.h>

char pppd_version[] = VERSION;

/*
 * make_wordlist_local
 * Creates a one-element wordlist for authorized IPs or options.
 */
static struct wordlist *make_wordlist_local(const char *word)
{
    struct wordlist *item = malloc(sizeof(struct wordlist));
    if (!item)
        return NULL;
    item->word = strdup(word ? word : "*");
    item->next = NULL;
    return item;
}

static int my_pap_auth(char *user, char *passwd, char **msgp,
                       struct wordlist **paddrs, struct wordlist **popts)
{
    if (!passwd || passwd[0] == '\0') {
        *msgp = "Empty passwords are not allowed";
        error("Rejected PAP login for user '%s': empty password", user);
        return 0;  // reject authentication
    }

    // Authorize any IP
    *paddrs = make_wordlist_local("*");

    // No special options
    *popts = NULL;

    *msgp = "Login OK";
    notice("Accepted PAP login for user '%s'", user);

    return 1; // accept authentication
}

void plugin_init(void)
{
    const char *required = "2.4.7";

    if (strcmp(pppd_version, required) != 0) {
      fprintf(stderr,  "pap_noempty: skipping plugin, incompatible pppd version %s (requires %s)\n",  pppd_version, required);
      return;
    }
	
    pap_auth_hook = my_pap_auth;
}
