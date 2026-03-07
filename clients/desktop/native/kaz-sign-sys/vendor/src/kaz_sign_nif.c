/**
 * KAZ-SIGN Elixir NIF Bindings
 *
 * Provides native Elixir bindings for the KAZ-SIGN post-quantum
 * digital signature scheme.
 */

#include <erl_nif.h>
#include <string.h>
#include <stdbool.h>
#include "kaz/sign.h"

/* Thread safety for initialization */
static ErlNifMutex *kaz_mutex = NULL;
static bool is_loaded = false;

/* Atoms */
static ERL_NIF_TERM atom_ok;
static ERL_NIF_TERM atom_error;
static ERL_NIF_TERM atom_true;
static ERL_NIF_TERM atom_false;
static ERL_NIF_TERM atom_public_key;
static ERL_NIF_TERM atom_private_key;
static ERL_NIF_TERM atom_signature;
static ERL_NIF_TERM atom_message;

/* Error atoms */
static ERL_NIF_TERM atom_invalid_level;
static ERL_NIF_TERM atom_not_initialized;
static ERL_NIF_TERM atom_init_failed;
static ERL_NIF_TERM atom_keypair_failed;
static ERL_NIF_TERM atom_sign_failed;
static ERL_NIF_TERM atom_verify_failed;
static ERL_NIF_TERM atom_invalid_argument;
static ERL_NIF_TERM atom_memory_error;
static ERL_NIF_TERM atom_invalid_signature;

/* Helper: Create atom */
static ERL_NIF_TERM make_atom(ErlNifEnv *env, const char *name) {
    ERL_NIF_TERM atom;
    if (enif_make_existing_atom(env, name, &atom, ERL_NIF_LATIN1)) {
        return atom;
    }
    return enif_make_atom(env, name);
}

/* Helper: Create error tuple */
static ERL_NIF_TERM make_error(ErlNifEnv *env, ERL_NIF_TERM reason) {
    return enif_make_tuple2(env, atom_error, reason);
}

/* Helper: Create ok tuple */
static ERL_NIF_TERM make_ok(ErlNifEnv *env, ERL_NIF_TERM value) {
    return enif_make_tuple2(env, atom_ok, value);
}

/* Helper: Map KAZ error code to atom */
static ERL_NIF_TERM error_code_to_atom(ErlNifEnv *env, int code) {
    switch (code) {
        case KAZ_SIGN_ERROR_MEMORY:
            return atom_memory_error;
        case KAZ_SIGN_ERROR_RNG:
            return make_atom(env, "rng_failed");
        case KAZ_SIGN_ERROR_INVALID:
            return atom_invalid_argument;
        case KAZ_SIGN_ERROR_VERIFY:
            return atom_invalid_signature;
        default:
            return make_atom(env, "unknown_error");
    }
}

/* Helper: Get level enum from int */
static kaz_sign_level_t int_to_level(int level) {
    switch (level) {
        case 128: return KAZ_LEVEL_128;
        case 192: return KAZ_LEVEL_192;
        case 256: return KAZ_LEVEL_256;
        default: return (kaz_sign_level_t)-1;
    }
}

/**
 * Initialize KAZ-SIGN random number generator.
 *
 * Returns: :ok | {:error, reason}
 */
static ERL_NIF_TERM sign_init(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    enif_mutex_lock(kaz_mutex);
    int result = kaz_sign_init_random();
    enif_mutex_unlock(kaz_mutex);

    if (result != KAZ_SIGN_SUCCESS) {
        return make_error(env, atom_init_failed);
    }

    return atom_ok;
}

/**
 * Initialize a specific security level.
 *
 * Args: [level :: 128 | 192 | 256]
 * Returns: :ok | {:error, reason}
 */
static ERL_NIF_TERM nif_init_level(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    int level;

    if (argc != 1 || !enif_get_int(env, argv[0], &level)) {
        return enif_make_badarg(env);
    }

    kaz_sign_level_t kaz_level = int_to_level(level);
    if ((int)kaz_level == -1) {
        return make_error(env, atom_invalid_level);
    }

    enif_mutex_lock(kaz_mutex);

    /* Initialize RNG if not already */
    if (!kaz_sign_is_initialized()) {
        int result = kaz_sign_init_random();
        if (result != KAZ_SIGN_SUCCESS) {
            enif_mutex_unlock(kaz_mutex);
            return make_error(env, atom_init_failed);
        }
    }

    int result = kaz_sign_init_level(kaz_level);
    enif_mutex_unlock(kaz_mutex);

    if (result != KAZ_SIGN_SUCCESS) {
        return make_error(env, atom_init_failed);
    }

    return atom_ok;
}

/**
 * Check if KAZ-SIGN is initialized.
 *
 * Returns: boolean()
 */
static ERL_NIF_TERM nif_is_initialized(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    if (kaz_sign_is_initialized()) {
        return atom_true;
    }
    return atom_false;
}

/**
 * Get sizes for a specific security level.
 *
 * Args: [level :: 128 | 192 | 256]
 * Returns: {:ok, %{...}} | {:error, reason}
 */
static ERL_NIF_TERM nif_get_sizes(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    int level;

    if (argc != 1 || !enif_get_int(env, argv[0], &level)) {
        return enif_make_badarg(env);
    }

    kaz_sign_level_t kaz_level = int_to_level(level);
    if ((int)kaz_level == -1) {
        return make_error(env, atom_invalid_level);
    }

    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(kaz_level);
    if (params == NULL) {
        return make_error(env, atom_invalid_level);
    }

    ERL_NIF_TERM map = enif_make_new_map(env);

    enif_make_map_put(env, map, atom_public_key,
                      enif_make_uint64(env, params->public_key_bytes), &map);
    enif_make_map_put(env, map, atom_private_key,
                      enif_make_uint64(env, params->secret_key_bytes), &map);
    enif_make_map_put(env, map, make_atom(env, "hash"),
                      enif_make_uint64(env, params->hash_bytes), &map);
    enif_make_map_put(env, map, make_atom(env, "signature_overhead"),
                      enif_make_uint64(env, params->signature_overhead), &map);

    return make_ok(env, map);
}

/**
 * Generate a signing keypair.
 *
 * Args: [level :: 128 | 192 | 256]
 * Returns: {:ok, %{public_key: binary, private_key: binary}} | {:error, reason}
 */
static ERL_NIF_TERM nif_keypair(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    int level;

    if (argc != 1 || !enif_get_int(env, argv[0], &level)) {
        return enif_make_badarg(env);
    }

    kaz_sign_level_t kaz_level = int_to_level(level);
    if ((int)kaz_level == -1) {
        return make_error(env, atom_invalid_level);
    }

    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(kaz_level);
    if (params == NULL) {
        return make_error(env, atom_invalid_level);
    }

    size_t pk_size = params->public_key_bytes;
    size_t sk_size = params->secret_key_bytes;

    ERL_NIF_TERM pk_term, sk_term;
    unsigned char *pk = enif_make_new_binary(env, pk_size, &pk_term);
    unsigned char *sk = enif_make_new_binary(env, sk_size, &sk_term);

    if (pk == NULL || sk == NULL) {
        return make_error(env, atom_memory_error);
    }

    enif_mutex_lock(kaz_mutex);

    /* Ensure initialized */
    if (!kaz_sign_is_initialized()) {
        int init_result = kaz_sign_init_random();
        if (init_result != KAZ_SIGN_SUCCESS) {
            enif_mutex_unlock(kaz_mutex);
            return make_error(env, atom_init_failed);
        }
    }

    int result = kaz_sign_keypair_ex(kaz_level, pk, sk);
    enif_mutex_unlock(kaz_mutex);

    if (result != KAZ_SIGN_SUCCESS) {
        return make_error(env, error_code_to_atom(env, result));
    }

    ERL_NIF_TERM map = enif_make_new_map(env);
    enif_make_map_put(env, map, atom_public_key, pk_term, &map);
    enif_make_map_put(env, map, atom_private_key, sk_term, &map);

    return make_ok(env, map);
}

/**
 * Sign a message.
 *
 * Args: [level :: integer, message :: binary, private_key :: binary]
 * Returns: {:ok, signature} | {:error, reason}
 */
static ERL_NIF_TERM nif_sign(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    int level;
    ErlNifBinary msg_bin, sk_bin;

    if (argc != 3) {
        return enif_make_badarg(env);
    }

    if (!enif_get_int(env, argv[0], &level) ||
        !enif_inspect_binary(env, argv[1], &msg_bin) ||
        !enif_inspect_binary(env, argv[2], &sk_bin)) {
        return enif_make_badarg(env);
    }

    kaz_sign_level_t kaz_level = int_to_level(level);
    if ((int)kaz_level == -1) {
        return make_error(env, atom_invalid_level);
    }

    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(kaz_level);
    if (params == NULL) {
        return make_error(env, atom_invalid_level);
    }

    if (sk_bin.size != params->secret_key_bytes) {
        return make_error(env, make_atom(env, "invalid_private_key_size"));
    }

    /* Signature size = overhead + message length */
    size_t sig_max_size = params->signature_overhead + msg_bin.size;

    ERL_NIF_TERM sig_term;
    unsigned char *sig = enif_make_new_binary(env, sig_max_size, &sig_term);

    if (sig == NULL) {
        return make_error(env, atom_memory_error);
    }

    unsigned long long sig_len;

    enif_mutex_lock(kaz_mutex);

    /* Ensure initialized */
    if (!kaz_sign_is_initialized()) {
        int init_result = kaz_sign_init_random();
        if (init_result != KAZ_SIGN_SUCCESS) {
            enif_mutex_unlock(kaz_mutex);
            return make_error(env, atom_init_failed);
        }
    }

    int result = kaz_sign_signature_ex(kaz_level, sig, &sig_len,
                                        msg_bin.data, msg_bin.size,
                                        sk_bin.data);
    enif_mutex_unlock(kaz_mutex);

    if (result != KAZ_SIGN_SUCCESS) {
        return make_error(env, error_code_to_atom(env, result));
    }

    /* Resize to actual signature length */
    if (sig_len < sig_max_size) {
        ERL_NIF_TERM resized;
        unsigned char *new_sig = enif_make_new_binary(env, sig_len, &resized);
        memcpy(new_sig, sig, sig_len);
        return make_ok(env, resized);
    }

    return make_ok(env, sig_term);
}

/**
 * Verify a signature and recover the message.
 *
 * Args: [level :: integer, signature :: binary, public_key :: binary]
 * Returns: {:ok, message} | {:error, :invalid_signature} | {:error, reason}
 */
static ERL_NIF_TERM nif_verify(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    int level;
    ErlNifBinary sig_bin, pk_bin;

    if (argc != 3) {
        return enif_make_badarg(env);
    }

    if (!enif_get_int(env, argv[0], &level) ||
        !enif_inspect_binary(env, argv[1], &sig_bin) ||
        !enif_inspect_binary(env, argv[2], &pk_bin)) {
        return enif_make_badarg(env);
    }

    kaz_sign_level_t kaz_level = int_to_level(level);
    if ((int)kaz_level == -1) {
        return make_error(env, atom_invalid_level);
    }

    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(kaz_level);
    if (params == NULL) {
        return make_error(env, atom_invalid_level);
    }

    if (pk_bin.size != params->public_key_bytes) {
        return make_error(env, make_atom(env, "invalid_public_key_size"));
    }

    if (sig_bin.size < params->signature_overhead) {
        return make_error(env, atom_invalid_signature);
    }

    /* Message size is signature size minus overhead */
    size_t msg_max_size = sig_bin.size - params->signature_overhead;

    unsigned char *msg = enif_alloc(msg_max_size + 1);
    if (msg == NULL) {
        return make_error(env, atom_memory_error);
    }

    unsigned long long msg_len;

    enif_mutex_lock(kaz_mutex);

    /* Ensure initialized */
    if (!kaz_sign_is_initialized()) {
        int init_result = kaz_sign_init_random();
        if (init_result != KAZ_SIGN_SUCCESS) {
            enif_mutex_unlock(kaz_mutex);
            enif_free(msg);
            return make_error(env, atom_init_failed);
        }
    }

    int result = kaz_sign_verify_ex(kaz_level, msg, &msg_len,
                                     sig_bin.data, sig_bin.size,
                                     pk_bin.data);
    enif_mutex_unlock(kaz_mutex);

    if (result != KAZ_SIGN_SUCCESS) {
        enif_free(msg);
        return make_error(env, atom_invalid_signature);
    }

    ERL_NIF_TERM msg_term;
    unsigned char *msg_out = enif_make_new_binary(env, msg_len, &msg_term);
    memcpy(msg_out, msg, msg_len);

    enif_free(msg);

    return make_ok(env, msg_term);
}

/**
 * Hash a message using the level-specific hash function.
 *
 * Args: [level :: integer, message :: binary]
 * Returns: {:ok, hash} | {:error, reason}
 */
static ERL_NIF_TERM nif_hash(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    int level;
    ErlNifBinary msg_bin;

    if (argc != 2) {
        return enif_make_badarg(env);
    }

    if (!enif_get_int(env, argv[0], &level) ||
        !enif_inspect_binary(env, argv[1], &msg_bin)) {
        return enif_make_badarg(env);
    }

    kaz_sign_level_t kaz_level = int_to_level(level);
    if ((int)kaz_level == -1) {
        return make_error(env, atom_invalid_level);
    }

    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(kaz_level);
    if (params == NULL) {
        return make_error(env, atom_invalid_level);
    }

    ERL_NIF_TERM hash_term;
    unsigned char *hash = enif_make_new_binary(env, params->hash_bytes, &hash_term);

    if (hash == NULL) {
        return make_error(env, atom_memory_error);
    }

    int result = kaz_sign_hash_ex(kaz_level, msg_bin.data, msg_bin.size, hash);

    if (result != KAZ_SIGN_SUCCESS) {
        return make_error(env, error_code_to_atom(env, result));
    }

    return make_ok(env, hash_term);
}

/**
 * Cleanup KAZ-SIGN state.
 *
 * Returns: :ok
 */
static ERL_NIF_TERM nif_cleanup(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    enif_mutex_lock(kaz_mutex);
    kaz_sign_clear_all();
    kaz_sign_clear_random();
    enif_mutex_unlock(kaz_mutex);

    return atom_ok;
}

/**
 * Get KAZ-SIGN version string.
 *
 * Returns: version_string
 */
static ERL_NIF_TERM nif_version(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    const char *version = kaz_sign_version();
    return enif_make_string(env, version, ERL_NIF_LATIN1);
}

/* NIF initialization */
static int load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM load_info) {
    (void)priv_data;
    (void)load_info;

    /* Create mutex for thread safety */
    kaz_mutex = enif_mutex_create("kaz_sign_mutex");
    if (kaz_mutex == NULL) {
        return -1;
    }

    /* Initialize atoms */
    atom_ok = make_atom(env, "ok");
    atom_error = make_atom(env, "error");
    atom_true = make_atom(env, "true");
    atom_false = make_atom(env, "false");
    atom_public_key = make_atom(env, "public_key");
    atom_private_key = make_atom(env, "private_key");
    atom_signature = make_atom(env, "signature");
    atom_message = make_atom(env, "message");

    atom_invalid_level = make_atom(env, "invalid_level");
    atom_not_initialized = make_atom(env, "not_initialized");
    atom_init_failed = make_atom(env, "init_failed");
    atom_keypair_failed = make_atom(env, "keypair_failed");
    atom_sign_failed = make_atom(env, "sign_failed");
    atom_verify_failed = make_atom(env, "verify_failed");
    atom_invalid_argument = make_atom(env, "invalid_argument");
    atom_memory_error = make_atom(env, "memory_error");
    atom_invalid_signature = make_atom(env, "invalid_signature");

    is_loaded = true;

    return 0;
}

static void unload(ErlNifEnv *env, void *priv_data) {
    (void)env;
    (void)priv_data;

    if (kaz_mutex != NULL) {
        enif_mutex_lock(kaz_mutex);
        kaz_sign_clear_all();
        kaz_sign_clear_random();
        enif_mutex_unlock(kaz_mutex);
        enif_mutex_destroy(kaz_mutex);
        kaz_mutex = NULL;
    }

    is_loaded = false;
}

static int upgrade(ErlNifEnv *env, void **priv_data, void **old_priv_data, ERL_NIF_TERM load_info) {
    (void)old_priv_data;
    return load(env, priv_data, load_info);
}

/* NIF function table */
static ErlNifFunc nif_funcs[] = {
    {"nif_init", 0, sign_init, 0},
    {"nif_init_level", 1, nif_init_level, 0},
    {"nif_is_initialized", 0, nif_is_initialized, 0},
    {"nif_get_sizes", 1, nif_get_sizes, 0},
    {"nif_keypair", 1, nif_keypair, 0},
    {"nif_sign", 3, nif_sign, 0},
    {"nif_verify", 3, nif_verify, 0},
    {"nif_hash", 2, nif_hash, 0},
    {"nif_cleanup", 0, nif_cleanup, 0},
    {"nif_version", 0, nif_version, 0}
};

ERL_NIF_INIT(Elixir.KazSign.Nif, nif_funcs, load, NULL, upgrade, unload)
