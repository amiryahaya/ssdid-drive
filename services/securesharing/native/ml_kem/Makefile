# Makefile for ML-KEM Elixir NIF using liboqs

# Erlang paths
ERL_INCLUDE_PATH ?= $(shell erl -eval 'io:format("~s", [lists:concat([code:root_dir(), "/erts-", erlang:system_info(version), "/include"])])' -s init stop -noshell)

# Platform detection
UNAME_S := $(shell uname -s)

# liboqs paths
ifeq ($(UNAME_S),Darwin)
    # macOS with Homebrew
    LIBOQS_PREFIX ?= $(shell brew --prefix liboqs 2>/dev/null || echo /opt/homebrew)
    OPENSSL_PREFIX ?= $(shell brew --prefix openssl 2>/dev/null || echo /usr/local/opt/openssl)
else
    # Linux
    LIBOQS_PREFIX ?= /usr/local
    OPENSSL_PREFIX ?= /usr
endif

LIBOQS_INCLUDE = $(LIBOQS_PREFIX)/include
LIBOQS_LIB = $(LIBOQS_PREFIX)/lib
OPENSSL_INCLUDE = $(OPENSSL_PREFIX)/include
OPENSSL_LIB = $(OPENSSL_PREFIX)/lib

# Version information
VERSION_MAJOR=1
VERSION_MINOR=0
VERSION_PATCH=0
VERSION=$(VERSION_MAJOR).$(VERSION_MINOR).$(VERSION_PATCH)

VERSION_FLAGS=-DML_KEM_VERSION=\"$(VERSION)\" \
              -DML_KEM_VERSION_MAJOR=$(VERSION_MAJOR) \
              -DML_KEM_VERSION_MINOR=$(VERSION_MINOR) \
              -DML_KEM_VERSION_PATCH=$(VERSION_PATCH)

# Compiler settings
CC ?= cc
CFLAGS = -O3 -Wall -Wextra -fPIC -std=c11
CFLAGS += -I$(ERL_INCLUDE_PATH)
CFLAGS += -I$(LIBOQS_INCLUDE)
CFLAGS += -I$(OPENSSL_INCLUDE)
CFLAGS += $(VERSION_FLAGS)

# Linker settings
LDFLAGS = -shared
LDFLAGS += -L$(LIBOQS_LIB)
LDFLAGS += -L$(OPENSSL_LIB)
LIBS = -loqs -lcrypto

# Platform-specific settings
ifeq ($(UNAME_S),Darwin)
    LDFLAGS += -dynamiclib -undefined dynamic_lookup
    LDFLAGS += -Wl,-rpath,$(LIBOQS_LIB)
    LDFLAGS += -Wl,-rpath,$(OPENSSL_LIB)
    SO_EXT = so
else
    LDFLAGS += -Wl,-rpath,$(LIBOQS_LIB)
    LDFLAGS += -Wl,-rpath,$(OPENSSL_LIB)
    SO_EXT = so
endif

# Output
PRIV_DIR = priv
NIF_SO = $(PRIV_DIR)/ml_kem_nif.$(SO_EXT)

# Source files
NIF_SRC = c_src/ml_kem_nif.c

# Object files
NIF_OBJ = c_src/ml_kem_nif.o

.PHONY: all clean

all: $(PRIV_DIR) $(NIF_SO)

$(PRIV_DIR):
	mkdir -p $(PRIV_DIR)

$(NIF_SO): $(NIF_OBJ)
	$(CC) $(LDFLAGS) -o $@ $^ $(LIBS)

c_src/ml_kem_nif.o: c_src/ml_kem_nif.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f $(NIF_SO) $(NIF_OBJ)
	rm -rf $(PRIV_DIR)
