/**
 * KAZ-KEM Elixir NIF Bindings
 *
 * Provides native Elixir bindings for the KAZ-KEM post-quantum
 * key encapsulation mechanism.
 */

#include <erl_nif.h>
#include <string.h>
#include <stdbool.h>
#include "kaz/kem.h"

/* Thread safety for initialization */
static ErlNifMutex *kaz_mutex = NULL;
static bool is_loaded = false;

/* Atoms */
static ERL_NIF_TERM atom_ok;
static ERL_NIF_TERM atom_error;
static ERL_NIF_TERM atom_public_key;
static ERL_NIF_TERM atom_private_key;
static ERL_NIF_TERM atom_ciphertext;
static ERL_NIF_TERM atom_shared_secret;

/* Error atoms */
static ERL_NIF_TERM atom_invalid_level;
static ERL_NIF_TERM atom_not_initialized;
static ERL_NIF_TERM atom_init_failed;
static ERL_NIF_TERM atom_keypair_failed;
static ERL_NIF_TERM atom_encapsulate_failed;
static ERL_NIF_TERM atom_decapsulate_failed;
static ERL_NIF_TERM atom_invalid_argument;
static ERL_NIF_TERM atom_memory_error;

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
        case KAZ_KEM_ERROR_INVALID_PARAM:
            return atom_invalid_argument;
        case KAZ_KEM_ERROR_RNG:
            return make_atom(env, "rng_failed");
        case KAZ_KEM_ERROR_MEMORY:
            return atom_memory_error;
        case KAZ_KEM_ERROR_OPENSSL:
            return make_atom(env, "openssl_error");
        case KAZ_KEM_ERROR_MSG_TOO_LARGE:
            return make_atom(env, "message_too_large");
        case KAZ_KEM_ERROR_NOT_INIT:
            return atom_not_initialized;
        case KAZ_KEM_ERROR_INVALID_LEVEL:
            return atom_invalid_level;
        default:
            return make_atom(env, "unknown_error");
    }
}

/**
 * Initialize KAZ-KEM with a security level.
 *
 * Args: [level :: 128 | 192 | 256]
 * Returns: :ok | {:error, reason}
 */
static ERL_NIF_TERM kem_init(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    int level;

    if (argc != 1 || !enif_get_int(env, argv[0], &level)) {
        return enif_make_badarg(env);
    }

    if (level != 128 && level != 192 && level != 256) {
        return make_error(env, atom_invalid_level);
    }

    enif_mutex_lock(kaz_mutex);

    /* Cleanup any previous initialization */
    if (kaz_kem_is_initialized()) {
        kaz_kem_cleanup();
    }

    int result = kaz_kem_init(level);

    enif_mutex_unlock(kaz_mutex);

    if (result != KAZ_KEM_SUCCESS) {
        return make_error(env, atom_init_failed);
    }

    return atom_ok;
}

/**
 * Check if KAZ-KEM is initialized.
 *
 * Returns: boolean()
 */
static ERL_NIF_TERM nif_is_initialized(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    if (kaz_kem_is_initialized()) {
        return make_atom(env, "true");
    }
    return make_atom(env, "false");
}

/**
 * Get the current security level.
 *
 * Returns: {:ok, level} | {:error, :not_initialized}
 */
static ERL_NIF_TERM nif_get_level(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    int level = kaz_kem_get_level();

    if (level == 0) {
        return make_error(env, atom_not_initialized);
    }

    return make_ok(env, enif_make_int(env, level));
}

/**
 * Get key and ciphertext sizes for current level.
 *
 * Returns: {:ok, %{public_key: size, private_key: size, ciphertext: size, shared_secret: size}}
 *        | {:error, :not_initialized}
 */
static ERL_NIF_TERM nif_get_sizes(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    if (!kaz_kem_is_initialized()) {
        return make_error(env, atom_not_initialized);
    }

    ERL_NIF_TERM map = enif_make_new_map(env);

    enif_make_map_put(env, map, atom_public_key,
                      enif_make_uint64(env, kaz_kem_publickey_bytes()), &map);
    enif_make_map_put(env, map, atom_private_key,
                      enif_make_uint64(env, kaz_kem_privatekey_bytes()), &map);
    enif_make_map_put(env, map, atom_ciphertext,
                      enif_make_uint64(env, kaz_kem_ciphertext_bytes()), &map);
    enif_make_map_put(env, map, atom_shared_secret,
                      enif_make_uint64(env, kaz_kem_shared_secret_bytes()), &map);

    return make_ok(env, map);
}

/**
 * Generate a KEM keypair.
 *
 * Returns: {:ok, %{public_key: binary, private_key: binary}} | {:error, reason}
 */
static ERL_NIF_TERM nif_keypair(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    if (!kaz_kem_is_initialized()) {
        return make_error(env, atom_not_initialized);
    }

    size_t pk_size = kaz_kem_publickey_bytes();
    size_t sk_size = kaz_kem_privatekey_bytes();

    ERL_NIF_TERM pk_term, sk_term;
    unsigned char *pk = enif_make_new_binary(env, pk_size, &pk_term);
    unsigned char *sk = enif_make_new_binary(env, sk_size, &sk_term);

    if (pk == NULL || sk == NULL) {
        return make_error(env, atom_memory_error);
    }

    enif_mutex_lock(kaz_mutex);
    int result = kaz_kem_keypair(pk, sk);
    enif_mutex_unlock(kaz_mutex);

    if (result != KAZ_KEM_SUCCESS) {
        return make_error(env, error_code_to_atom(env, result));
    }

    ERL_NIF_TERM map = enif_make_new_map(env);
    enif_make_map_put(env, map, atom_public_key, pk_term, &map);
    enif_make_map_put(env, map, atom_private_key, sk_term, &map);

    return make_ok(env, map);
}

/**
 * Encapsulate a shared secret.
 *
 * Args: [shared_secret :: binary, public_key :: binary]
 * Returns: {:ok, ciphertext} | {:error, reason}
 */
static ERL_NIF_TERM nif_encapsulate(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary ss_bin, pk_bin;

    if (argc != 2) {
        return enif_make_badarg(env);
    }

    if (!enif_inspect_binary(env, argv[0], &ss_bin) ||
        !enif_inspect_binary(env, argv[1], &pk_bin)) {
        return enif_make_badarg(env);
    }

    if (!kaz_kem_is_initialized()) {
        return make_error(env, atom_not_initialized);
    }

    size_t pk_size = kaz_kem_publickey_bytes();
    if (pk_bin.size != pk_size) {
        return make_error(env, make_atom(env, "invalid_public_key_size"));
    }

    size_t ct_size = kaz_kem_ciphertext_bytes();
    ERL_NIF_TERM ct_term;
    unsigned char *ct = enif_make_new_binary(env, ct_size, &ct_term);

    if (ct == NULL) {
        return make_error(env, atom_memory_error);
    }

    unsigned long long ct_len;

    enif_mutex_lock(kaz_mutex);
    int result = kaz_kem_encapsulate(ct, &ct_len, ss_bin.data, ss_bin.size, pk_bin.data);
    enif_mutex_unlock(kaz_mutex);

    if (result != KAZ_KEM_SUCCESS) {
        return make_error(env, error_code_to_atom(env, result));
    }

    /* Resize binary to actual ciphertext length if different */
    if (ct_len < ct_size) {
        ERL_NIF_TERM resized;
        unsigned char *new_ct = enif_make_new_binary(env, ct_len, &resized);
        memcpy(new_ct, ct, ct_len);
        return make_ok(env, resized);
    }

    return make_ok(env, ct_term);
}

/**
 * Decapsulate a ciphertext to recover the shared secret.
 *
 * Args: [ciphertext :: binary, private_key :: binary]
 * Returns: {:ok, shared_secret} | {:error, reason}
 */
static ERL_NIF_TERM nif_decapsulate(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary ct_bin, sk_bin;

    if (argc != 2) {
        return enif_make_badarg(env);
    }

    if (!enif_inspect_binary(env, argv[0], &ct_bin) ||
        !enif_inspect_binary(env, argv[1], &sk_bin)) {
        return enif_make_badarg(env);
    }

    if (!kaz_kem_is_initialized()) {
        return make_error(env, atom_not_initialized);
    }

    size_t sk_size = kaz_kem_privatekey_bytes();
    if (sk_bin.size != sk_size) {
        return make_error(env, make_atom(env, "invalid_private_key_size"));
    }

    /* Allocate buffer for shared secret - use general_bytes from params */
    size_t ss_max_size = kaz_kem_shared_secret_bytes();
    if (ss_max_size == 0) {
        /* Fallback to a reasonable max */
        ss_max_size = 256;
    }

    unsigned char *ss = enif_alloc(ss_max_size);
    if (ss == NULL) {
        return make_error(env, atom_memory_error);
    }
    memset(ss, 0, ss_max_size);

    unsigned long long ss_len = 0;

    enif_mutex_lock(kaz_mutex);
    int result = kaz_kem_decapsulate(ss, &ss_len, ct_bin.data, ct_bin.size, sk_bin.data);
    enif_mutex_unlock(kaz_mutex);

    if (result != KAZ_KEM_SUCCESS) {
        memset(ss, 0, ss_max_size);
        enif_free(ss);
        return make_error(env, error_code_to_atom(env, result));
    }

    /* Validate ss_len is reasonable */
    if (ss_len == 0 || ss_len > ss_max_size) {
        ss_len = ss_max_size;
    }

    ERL_NIF_TERM ss_term;
    unsigned char *ss_out = enif_make_new_binary(env, ss_len, &ss_term);
    memcpy(ss_out, ss, ss_len);

    /* Secure cleanup */
    memset(ss, 0, ss_max_size);
    enif_free(ss);

    return make_ok(env, ss_term);
}

/**
 * Cleanup KAZ-KEM state.
 *
 * Returns: :ok
 */
static ERL_NIF_TERM nif_cleanup(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    enif_mutex_lock(kaz_mutex);
    /* Use kaz_kem_cleanup() not kaz_kem_cleanup_full() to allow reinit */
    kaz_kem_cleanup();
    enif_mutex_unlock(kaz_mutex);

    return atom_ok;
}

/**
 * Get KAZ-KEM version string.
 *
 * Returns: version_string
 */
static ERL_NIF_TERM nif_version(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    const char *version = kaz_kem_version();
    return enif_make_string(env, version, ERL_NIF_LATIN1);
}

/* NIF initialization */
static int load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM load_info) {
    (void)priv_data;
    (void)load_info;

    /* Create mutex for thread safety */
    kaz_mutex = enif_mutex_create("kaz_kem_mutex");
    if (kaz_mutex == NULL) {
        return -1;
    }

    /* Initialize atoms */
    atom_ok = make_atom(env, "ok");
    atom_error = make_atom(env, "error");
    atom_public_key = make_atom(env, "public_key");
    atom_private_key = make_atom(env, "private_key");
    atom_ciphertext = make_atom(env, "ciphertext");
    atom_shared_secret = make_atom(env, "shared_secret");

    atom_invalid_level = make_atom(env, "invalid_level");
    atom_not_initialized = make_atom(env, "not_initialized");
    atom_init_failed = make_atom(env, "init_failed");
    atom_keypair_failed = make_atom(env, "keypair_failed");
    atom_encapsulate_failed = make_atom(env, "encapsulate_failed");
    atom_decapsulate_failed = make_atom(env, "decapsulate_failed");
    atom_invalid_argument = make_atom(env, "invalid_argument");
    atom_memory_error = make_atom(env, "memory_error");

    is_loaded = true;

    return 0;
}

static void unload(ErlNifEnv *env, void *priv_data) {
    (void)env;
    (void)priv_data;

    if (kaz_mutex != NULL) {
        enif_mutex_lock(kaz_mutex);
        if (kaz_kem_is_initialized()) {
            kaz_kem_cleanup_full();
        }
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
    {"nif_init", 1, kem_init, 0},
    {"nif_is_initialized", 0, nif_is_initialized, 0},
    {"nif_get_level", 0, nif_get_level, 0},
    {"nif_get_sizes", 0, nif_get_sizes, 0},
    {"nif_keypair", 0, nif_keypair, 0},
    {"nif_encapsulate", 2, nif_encapsulate, 0},
    {"nif_decapsulate", 2, nif_decapsulate, 0},
    {"nif_cleanup", 0, nif_cleanup, 0},
    {"nif_version", 0, nif_version, 0}
};

ERL_NIF_INIT(Elixir.KazKem.Nif, nif_funcs, load, NULL, upgrade, unload)
