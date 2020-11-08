#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

const char *c_check_password(const char *state_str, const char *password, uint8_t *error);

const char *c_seed_new(uint8_t seed_length, uint8_t *error);

const char *c_set_logger(uint8_t *error);

const char *c_slatepack_decode(const char *state_json, const char *slatepack, uint8_t *error);

const char *c_start_listen_with_tor(const char *state_json, uint8_t *error);

const char *c_tx_cancel(const char *state_json, uint32_t id, uint8_t *error);

const char *c_tx_create(const char *state_json,
                        uint64_t amount,
                        bool selection_strategy_is_use_all,
                        uint8_t *error);

const char *c_tx_finalize(const char *state_json, const char *slate_armored, uint8_t *error);

const char *c_tx_get(const char *state_json,
                     bool refresh_from_node,
                     const char *tx_slate_id,
                     uint8_t *error);

const char *c_tx_post(const char *state_json, const char *tx_slate_id, uint8_t *error);

const char *c_tx_receive(const char *state_json, const char *slate_armored, uint8_t *error);

const char *c_tx_send_https(const char *state_json,
                            uint64_t amount,
                            bool selection_strategy_is_use_all,
                            const char *url,
                            uint8_t *error);

const char *c_tx_strategies(const char *state_json, uint64_t amount, uint8_t *error);

const char *c_txs_get(const char *state_json, bool refresh_from_node, uint8_t *error);

const char *c_wallet_init(const char *state,
                          const char *phrase,
                          const char *password,
                          uint8_t *error);

const char *c_wallet_phrase(const char *state_json, uint8_t *error);

const char *c_wallet_pmmr_range(const char *state, uint8_t *error);

const char *c_wallet_scan_outputs(const char *state,
                                  uint64_t last_retrieved_index,
                                  uint64_t highest_index,
                                  uint8_t *error);

void cstr_free(char *s);
