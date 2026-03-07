# Makefile for KAZ-KEM Elixir NIF

# Erlang paths
ERL_INCLUDE_PATH ?= $(shell erl -eval 'io:format("~s", [lists:concat([code:root_dir(), "/erts-", erlang:system_info(version), "/include"])])' -s init stop -noshell)
ERL_INTERFACE_INCLUDE_PATH ?= $(shell erl -eval 'io:format("~s", [code:lib_dir(erl_interface, include)])' -s init stop -noshell)
ERL_INTERFACE_LIB_PATH ?= $(shell erl -eval 'io:format("~s", [code:lib_dir(erl_interface, lib)])' -s init stop -noshell)

# KAZ-KEM source paths (relative to this directory)
KAZ_INCLUDE = kaz_lib/include
KAZ_SRC = kaz_lib/src

# OpenSSL paths (platform detection)
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    # macOS with Homebrew
    OPENSSL_PREFIX ?= $(shell brew --prefix openssl 2>/dev/null || echo /usr/local/opt/openssl)
else
    # Linux
    OPENSSL_PREFIX ?= /usr
endif

OPENSSL_INCLUDE = $(OPENSSL_PREFIX)/include
OPENSSL_LIB = $(OPENSSL_PREFIX)/lib

# Version information
VERSION_MAJOR=2
VERSION_MINOR=1
VERSION_PATCH=0
VERSION=$(VERSION_MAJOR).$(VERSION_MINOR).$(VERSION_PATCH)

VERSION_FLAGS=-DKAZ_KEM_VERSION=\"$(VERSION)\" \
              -DKAZ_KEM_VERSION_MAJOR=$(VERSION_MAJOR) \
              -DKAZ_KEM_VERSION_MINOR=$(VERSION_MINOR) \
              -DKAZ_KEM_VERSION_PATCH=$(VERSION_PATCH)

# Compiler settings
CC ?= cc
CFLAGS = -O3 -Wall -Wextra -fPIC -std=c11
CFLAGS += -I$(ERL_INCLUDE_PATH)
CFLAGS += -I$(KAZ_INCLUDE)
CFLAGS += -I$(OPENSSL_INCLUDE)
CFLAGS += -DKAZ_KEM_USE_OPENSSL
CFLAGS += $(VERSION_FLAGS)

# Linker settings
LDFLAGS = -shared
LDFLAGS += -L$(OPENSSL_LIB)
LIBS = -lcrypto

# Platform-specific settings
ifeq ($(UNAME_S),Darwin)
    LDFLAGS += -dynamiclib -undefined dynamic_lookup
    LDFLAGS += -Wl,-rpath,$(OPENSSL_LIB)
    SO_EXT = so
else
    LDFLAGS += -Wl,-rpath,$(OPENSSL_LIB)
    SO_EXT = so
endif

# Output
PRIV_DIR = priv
NIF_SO = $(PRIV_DIR)/kaz_kem_nif.$(SO_EXT)

# Source files
NIF_SRC = c_src/kaz_kem_nif.c
KAZ_SRC_FILES = $(KAZ_SRC)/kem_secure.c

# Object files
NIF_OBJ = c_src/kaz_kem_nif.o
KAZ_OBJ = c_src/kem_secure.o

.PHONY: all clean

all: $(PRIV_DIR) $(NIF_SO)

$(PRIV_DIR):
	mkdir -p $(PRIV_DIR)

$(NIF_SO): $(NIF_OBJ) $(KAZ_OBJ)
	$(CC) $(LDFLAGS) -o $@ $^ $(LIBS)

c_src/kaz_kem_nif.o: c_src/kaz_kem_nif.c
	$(CC) $(CFLAGS) -c -o $@ $<

c_src/kem_secure.o: $(KAZ_SRC)/kem_secure.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f $(NIF_SO) $(NIF_OBJ) $(KAZ_OBJ)
	rm -rf $(PRIV_DIR)
