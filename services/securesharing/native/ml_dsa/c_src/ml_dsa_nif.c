/**
 * ML-DSA NIF - Elixir NIF bindings for ML-DSA (FIPS 204) using liboqs
 *
 * Supports ML-DSA-44, ML-DSA-65, and ML-DSA-87
 */

#include <erl_nif.h>
#include <string.h>
#include <stdlib.h>
#include <oqs/oqs.h>

// Thread safety
static ErlNifMutex *ml_dsa_mutex = NULL;

// Current security level
static int current_level = 0;  // 0 = not initialized

// Current SIG instance
static OQS_SIG *sig = NULL;

// Algorithm names
static const char* get_algorithm_name(int level) {
    switch (level) {
        case 128: return OQS_SIG_alg_ml_dsa_44;
        case 192: return OQS_SIG_alg_ml_dsa_65;
        case 256: return OQS_SIG_alg_ml_dsa_87;
        default: return NULL;
    }
}

// NIF: Initialize ML-DSA with security level
static ERL_NIF_TERM ml_dsa_init(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
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

    enif_mutex_lock(ml_dsa_mutex);

    // Cleanup previous instance
    if (sig != NULL) {
        OQS_SIG_free(sig);
        sig = NULL;
    }

    // Create new SIG instance
    sig = OQS_SIG_new(alg_name);
    if (sig == NULL) {
        enif_mutex_unlock(ml_dsa_mutex);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "algorithm_not_available"));
    }

    current_level = level;
    enif_mutex_unlock(ml_dsa_mutex);

    return enif_make_atom(env, "ok");
}

// NIF: Check if initialized
static ERL_NIF_TERM nif_is_initialized(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    enif_mutex_lock(ml_dsa_mutex);
    int initialized = (sig != NULL);
    enif_mutex_unlock(ml_dsa_mutex);

    return initialized ? enif_make_atom(env, "true") : enif_make_atom(env, "false");
}

// NIF: Get current security level
static ERL_NIF_TERM nif_get_level(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    enif_mutex_lock(ml_dsa_mutex);
    int level = current_level;
    enif_mutex_unlock(ml_dsa_mutex);

    if (level == 0) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "not_initialized"));
    }

    return enif_make_tuple2(env,
        enif_make_atom(env, "ok"),
        enif_make_int(env, level));
}

// NIF: Get key and signature sizes for current level
static ERL_NIF_TERM nif_get_sizes(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    enif_mutex_lock(ml_dsa_mutex);

    if (sig == NULL) {
        enif_mutex_unlock(ml_dsa_mutex);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "not_initialized"));
    }

    size_t pk_len = sig->length_public_key;
    size_t sk_len = sig->length_secret_key;
    size_t sig_len = sig->length_signature;

    enif_mutex_unlock(ml_dsa_mutex);

    return enif_make_tuple2(env,
        enif_make_atom(env, "ok"),
        enif_make_tuple3(env,
            enif_make_int(env, pk_len),
            enif_make_int(env, sk_len),
            enif_make_int(env, sig_len)));
}

// NIF: Generate keypair
static ERL_NIF_TERM nif_keypair(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    enif_mutex_lock(ml_dsa_mutex);

    if (sig == NULL) {
        enif_mutex_unlock(ml_dsa_mutex);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "not_initialized"));
    }

    size_t pk_len = sig->length_public_key;
    size_t sk_len = sig->length_secret_key;

    ERL_NIF_TERM pk_term, sk_term;
    uint8_t *pk = enif_make_new_binary(env, pk_len, &pk_term);
    uint8_t *sk = enif_make_new_binary(env, sk_len, &sk_term);

    if (pk == NULL || sk == NULL) {
        enif_mutex_unlock(ml_dsa_mutex);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "memory_allocation_failed"));
    }

    OQS_STATUS status = OQS_SIG_keypair(sig, pk, sk);

    enif_mutex_unlock(ml_dsa_mutex);

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

// NIF: Sign a message
static ERL_NIF_TERM nif_sign(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary msg_bin, sk_bin;

    if (argc != 2 ||
        !enif_inspect_binary(env, argv[0], &msg_bin) ||
        !enif_inspect_binary(env, argv[1], &sk_bin)) {
        return enif_make_badarg(env);
    }

    enif_mutex_lock(ml_dsa_mutex);

    if (sig == NULL) {
        enif_mutex_unlock(ml_dsa_mutex);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "not_initialized"));
    }

    if (sk_bin.size != sig->length_secret_key) {
        enif_mutex_unlock(ml_dsa_mutex);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "invalid_secret_key_size"));
    }

    size_t sig_len = sig->length_signature;

    ERL_NIF_TERM sig_term;
    uint8_t *signature = enif_make_new_binary(env, sig_len, &sig_term);

    if (signature == NULL) {
        enif_mutex_unlock(ml_dsa_mutex);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "memory_allocation_failed"));
    }

    size_t actual_sig_len = 0;
    OQS_STATUS status = OQS_SIG_sign(sig, signature, &actual_sig_len,
                                     msg_bin.data, msg_bin.size, sk_bin.data);

    enif_mutex_unlock(ml_dsa_mutex);

    if (status != OQS_SUCCESS) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "signing_failed"));
    }

    // Return the actual signature (may be shorter than max)
    ERL_NIF_TERM actual_sig_term;
    uint8_t *actual_sig = enif_make_new_binary(env, actual_sig_len, &actual_sig_term);
    if (actual_sig == NULL) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "memory_allocation_failed"));
    }
    memcpy(actual_sig, signature, actual_sig_len);

    return enif_make_tuple2(env,
        enif_make_atom(env, "ok"),
        actual_sig_term);
}

// NIF: Verify a signature
static ERL_NIF_TERM nif_verify(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary msg_bin, sig_bin, pk_bin;

    if (argc != 3 ||
        !enif_inspect_binary(env, argv[0], &msg_bin) ||
        !enif_inspect_binary(env, argv[1], &sig_bin) ||
        !enif_inspect_binary(env, argv[2], &pk_bin)) {
        return enif_make_badarg(env);
    }

    enif_mutex_lock(ml_dsa_mutex);

    if (sig == NULL) {
        enif_mutex_unlock(ml_dsa_mutex);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "not_initialized"));
    }

    if (pk_bin.size != sig->length_public_key) {
        enif_mutex_unlock(ml_dsa_mutex);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "invalid_public_key_size"));
    }

    OQS_STATUS status = OQS_SIG_verify(sig, msg_bin.data, msg_bin.size,
                                       sig_bin.data, sig_bin.size, pk_bin.data);

    enif_mutex_unlock(ml_dsa_mutex);

    if (status == OQS_SUCCESS) {
        return enif_make_atom(env, "true");
    } else {
        return enif_make_atom(env, "false");
    }
}

// NIF: Cleanup
static ERL_NIF_TERM nif_cleanup(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    enif_mutex_lock(ml_dsa_mutex);

    if (sig != NULL) {
        OQS_SIG_free(sig);
        sig = NULL;
    }
    current_level = 0;

    enif_mutex_unlock(ml_dsa_mutex);

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
    {"nif_init", 1, ml_dsa_init, 0},
    {"nif_is_initialized", 0, nif_is_initialized, 0},
    {"nif_get_level", 0, nif_get_level, 0},
    {"nif_get_sizes", 0, nif_get_sizes, 0},
    {"nif_keypair", 0, nif_keypair, 0},
    {"nif_sign", 2, nif_sign, 0},
    {"nif_verify", 3, nif_verify, 0},
    {"nif_cleanup", 0, nif_cleanup, 0},
    {"nif_version", 0, nif_version, 0}
};

// NIF load callback
static int load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM load_info) {
    (void)env;
    (void)priv_data;
    (void)load_info;

    ml_dsa_mutex = enif_mutex_create("ml_dsa_mutex");
    if (ml_dsa_mutex == NULL) {
        return -1;
    }

    return 0;
}

// NIF unload callback
static void unload(ErlNifEnv *env, void *priv_data) {
    (void)env;
    (void)priv_data;

    if (sig != NULL) {
        OQS_SIG_free(sig);
        sig = NULL;
    }

    if (ml_dsa_mutex != NULL) {
        enif_mutex_destroy(ml_dsa_mutex);
        ml_dsa_mutex = NULL;
    }
}

ERL_NIF_INIT(Elixir.MlDsa.Nif, nif_funcs, load, NULL, NULL, unload)
