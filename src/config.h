/*
 * config.h - ~/.config/cooloo persistence (D22)
 *
 * Files (dir overridable via $COOLOO_CONFIG, mainly for tests):
 *   identity       32-byte X25519 secret, mode 0600
 *   known_servers  TOFU pins: "<host:port> <fingerprint64>"
 *   config         "key value" lines: host, port, nick, offset.<room>
 */
#ifndef COOLOO_CONFIG_H
#define COOLOO_CONFIG_H

#include <stddef.h>
#include <stdint.h>

/* Config dir into buf (creates it 0700 if missing). 0 ok, -1 error. */
int  cfg_dir(char *buf, size_t buflen);

/* Effective server: config file host/port, defaults 43.133.202.144:4222,
 * env COOLOO_HOST (host[:port]) overrides everything. */
void cfg_server(char *host, size_t host_cap, int *port);

/* identity: load 32-byte secret; 0 ok, -1 missing/unreadable. */
int  cfg_identity_load(uint8_t sk[32]);
/* keygen: create identity (0600), fail if it already exists. 0 ok. */
int  cfg_identity_create(const uint8_t sk[32]);

/* known_servers: 1 found (fp_out set), 0 not found. */
int  cfg_known_server_get(const char *hostport, char fp_out[65]);
/* append/replace pin. 0 ok. */
int  cfg_known_server_set(const char *hostport, const char *fp_hex);

/* generic small kv store in `config`; key e.g. "nick" or "offset.general" */
int  cfg_get(const char *key, char *val, size_t val_cap);
int  cfg_set(const char *key, const char *val);

#endif /* COOLOO_CONFIG_H */
