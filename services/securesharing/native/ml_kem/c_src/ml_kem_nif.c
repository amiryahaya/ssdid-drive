/**
 * ML-KEM NIF - Elixir NIF bindings for ML-KEM (FIPS 203) using liboqs
 *
 * Supports ML-KEM-512, ML-KEM-768, and ML-KEM-1024
 */

#include <erl_nif.h>
#include <string.h>
#include <stdlib.h>
#include <oqs/oqs.h>

// Thread safety
static ErlNifMutex *ml_kem_mutex = NULL;

// Current security level
static int current_level = 0;  // 0 = not initialized

// Current KEM instance
static OQS_KEM *kem = NULL;

// Algorithm names
static const char* get_algorithm_name(int level) {
    switch (level) {
        case 128: return OQS_KEM_alg_ml_kem_512;
        case 192: return OQS_KEM_alg_ml_kem_768;
        case 256: return OQS_KEM_alg_ml_kem_1024;
        default: return NULL;
    }
}

// NIF: Initialize ML-KEM with security level
static ERL_NIF_TERM ml_kem_init(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    int level;

    if (argc != 1 || !enif_get_int(env, argv[0], &level)) {
        return enif_make_badarg(env);
    }

    const char *alg_name = get_algorithm_name(level);
    if (alg_name == NULL) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "invalid_level"));
    }

    enif_mutex_lock(ml_kem_mutex);

    // Cleanup previous instance
    if (kem != NULL) {
        OQS_KEM_free(kem);
        kem = NULL;
    }

    // Create new KEM instance
    kem = OQS_KEM_new(alg_name);
    if (kem == NULL) {
        enif_mutex_unlock(ml_kem_mutex);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "algorithm_not_available"));
    }

    current_level = level;
    enif_mutex_unlock(ml_kem_mutex);

    return enif_make_atom(env, "ok");
}

// NIF: Check if initialized
static ERL_NIF_TERM nif_is_initialized(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    enif_mutex_lock(ml_kem_mutex);
    int initialized = (kem != NULL);
    enif_mutex_unlock(ml_kem_mutex);

    return initialized ? enif_make_atom(env, "true") : enif_make_atom(env, "false");
}

// NIF: Get current security level
static ERL_NIF_TERM nif_get_level(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    enif_mutex_lock(ml_kem_mutex);
    int level = current_level;
    enif_mutex_unlock(ml_kem_mutex);

    if (level == 0) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "not_initialized"));
    }

    return enif_make_tuple2(env,
        enif_make_atom(env, "ok"),
        enif_make_int(env, level));
}

// NIF: Get key sizes for current level
static ERL_NIF_TERM nif_get_sizes(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    enif_mutex_lock(ml_kem_mutex);

    if (kem == NULL) {
        enif_mutex_unlock(ml_kem_mutex);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "not_initialized"));
    }

    size_t pk_len = kem->length_public_key;
    size_t sk_len = kem->length_secret_key;
    size_t ct_len = kem->length_ciphertext;
    size_t ss_len = kem->length_shared_secret;

    enif_mutex_unlock(ml_kem_mutex);

    return enif_make_tuple2(env,
        enif_make_atom(env, "ok"),
        enif_make_tuple4(env,
            enif_make_int(env, pk_len),
            enif_make_int(env, sk_len),
            enif_make_int(env, ct_len),
            enif_make_int(env, ss_len)));
}

// NIF: Generate keypair
static ERL_NIF_TERM nif_keypair(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    enif_mutex_lock(ml_kem_mutex);

    if (kem == NULL) {
        enif_mutex_unlock(ml_kem_mutex);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "not_initialized"));
    }

    size_t pk_len = kem->length_public_key;
    size_t sk_len = kem->length_secret_key;

    ERL_NIF_TERM pk_term, sk_term;
    uint8_t *pk = enif_make_new_binary(env, pk_len, &pk_term);
    uint8_t *sk = enif_make_new_binary(env, sk_len, &sk_term);

    if (pk == NULL || sk == NULL) {
        enif_mutex_unlock(ml_kem_mutex);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "memory_allocation_failed"));
    }

    OQS_STATUS status = OQS_KEM_keypair(kem, pk, sk);

    enif_mutex_unlock(ml_kem_mutex);

    if (status != OQS_SUCCESS) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "keypair_generation_failed"));
    }

    return enif_make_tuple3(env,
        enif_make_atom(env, "ok"),
        pk_term,
        sk_term);
}

// NIF: Encapsulate - generates ciphertext and shared secret
static ERL_NIF_TERM nif_encapsulate(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary pk_bin;

    if (argc != 1 || !enif_inspect_binary(env, argv[0], &pk_bin)) {
        return enif_make_badarg(env);
    }

    enif_mutex_lock(ml_kem_mutex);

    if (kem == NULL) {
        enif_mutex_unlock(ml_kem_mutex);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "not_initialized"));
    }

    if (pk_bin.size != kem->length_public_key) {
        enif_mutex_unlock(ml_kem_mutex);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "invalid_public_key_size"));
    }

    size_t ct_len = kem->length_ciphertext;
    size_t ss_len = kem->length_shared_secret;

    ERL_NIF_TERM ct_term, ss_term;
    uint8_t *ct = enif_make_new_binary(env, ct_len, &ct_term);
    uint8_t *ss = enif_make_new_binary(env, ss_len, &ss_term);

    if (ct == NULL || ss == NULL) {
        enif_mutex_unlock(ml_kem_mutex);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "memory_allocation_failed"));
    }

    OQS_STATUS status = OQS_KEM_encaps(kem, ct, ss, pk_bin.data);

    enif_mutex_unlock(ml_kem_mutex);

    if (status != OQS_SUCCESS) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "encapsulation_failed"));
    }

    return enif_make_tuple3(env,
        enif_make_atom(env, "ok"),
        ct_term,
        ss_term);
}

// NIF: Decapsulate - recovers shared secret from ciphertext
static ERL_NIF_TERM nif_decapsulate(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary ct_bin, sk_bin;

    if (argc != 2 ||
        !enif_inspect_binary(env, argv[0], &ct_bin) ||
        !enif_inspect_binary(env, argv[1], &sk_bin)) {
        return enif_make_badarg(env);
    }

    enif_mutex_lock(ml_kem_mutex);

    if (kem == NULL) {
        enif_mutex_unlock(ml_kem_mutex);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "not_initialized"));
    }

    if (ct_bin.size != kem->length_ciphertext) {
        enif_mutex_unlock(ml_kem_mutex);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "invalid_ciphertext_size"));
    }

    if (sk_bin.size != kem->length_secret_key) {
        enif_mutex_unlock(ml_kem_mutex);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "invalid_secret_key_size"));
    }

    size_t ss_len = kem->length_shared_secret;

    ERL_NIF_TERM ss_term;
    uint8_t *ss = enif_make_new_binary(env, ss_len, &ss_term);

    if (ss == NULL) {
        enif_mutex_unlock(ml_kem_mutex);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "memory_allocation_failed"));
    }

    OQS_STATUS status = OQS_KEM_decaps(kem, ss, ct_bin.data, sk_bin.data);

    enif_mutex_unlock(ml_kem_mutex);

    if (status != OQS_SUCCESS) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "decapsulation_failed"));
    }

    return enif_make_tuple2(env,
        enif_make_atom(env, "ok"),
        ss_term);
}

// NIF: Cleanup
static ERL_NIF_TERM nif_cleanup(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    enif_mutex_lock(ml_kem_mutex);

    if (kem != NULL) {
        OQS_KEM_free(kem);
        kem = NULL;
    }
    current_level = 0;

    enif_mutex_unlock(ml_kem_mutex);

    return enif_make_atom(env, "ok");
}

// NIF: Get version info
static ERL_NIF_TERM nif_version(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    const char *oqs_version = OQS_VERSION_TEXT;

    return enif_make_tuple2(env,
        enif_make_atom(env, "ok"),
        enif_make_tuple2(env,
            enif_make_string(env, "1.0.0", ERL_NIF_LATIN1),
            enif_make_string(env, oqs_version, ERL_NIF_LATIN1)));
}

// NIF function table
static ErlNifFunc nif_funcs[] = {
    {"nif_init", 1, ml_kem_init, 0},
    {"nif_is_initialized", 0, nif_is_initialized, 0},
    {"nif_get_level", 0, nif_get_level, 0},
    {"nif_get_sizes", 0, nif_get_sizes, 0},
    {"nif_keypair", 0, nif_keypair, 0},
    {"nif_encapsulate", 1, nif_encapsulate, 0},
    {"nif_decapsulate", 2, nif_decapsulate, 0},
    {"nif_cleanup", 0, nif_cleanup, 0},
    {"nif_version", 0, nif_version, 0}
};

// NIF load callback
static int load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM load_info) {
    (void)env;
    (void)priv_data;
    (void)load_info;

    ml_kem_mutex = enif_mutex_create("ml_kem_mutex");
    if (ml_kem_mutex == NULL) {
        return -1;
    }

    return 0;
}

// NIF unload callback
static void unload(ErlNifEnv *env, void *priv_data) {
    (void)env;
    (void)priv_data;

    if (kem != NULL) {
        OQS_KEM_free(kem);
        kem = NULL;
    }

    if (ml_kem_mutex != NULL) {
        enif_mutex_destroy(ml_kem_mutex);
        ml_kem_mutex = NULL;
    }
}

ERL_NIF_INIT(Elixir.MlKem.Nif, nif_funcs, load, NULL, NULL, unload)
