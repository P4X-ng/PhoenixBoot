# PhoenixGuard Module Verification Library Makefile
# Part of the edk2-bootkit-defense project

CC = gcc
CFLAGS = -Wall -Wextra -std=c99 -fPIC -O2 -g
LDFLAGS = -shared
LIBS = -lssl -lcrypto

# Library name and version
LIBNAME = libpgmodverify
VERSION = 1.0.0
SONAME = $(LIBNAME).so.1

# Source files
SOURCES = pgmodverify.c
OBJECTS = $(SOURCES:.c=.o)
HEADERS = pgmodverify.h

# Build targets
STATIC_LIB = $(LIBNAME).a
SHARED_LIB = $(LIBNAME).so.$(VERSION)
TEST_PROG = pgmodverify_test

# Installation directories
PREFIX = /usr/local
LIBDIR = $(PREFIX)/lib
INCDIR = $(PREFIX)/include

.PHONY: all clean install uninstall test

# Default target
all: $(STATIC_LIB) $(SHARED_LIB) $(TEST_PROG)

# Static library
$(STATIC_LIB): $(OBJECTS)
	@echo "Creating static library: $@"
	ar rcs $@ $^
	ranlib $@

# Shared library
$(SHARED_LIB): $(OBJECTS)
	@echo "Creating shared library: $@"
	$(CC) $(LDFLAGS) -Wl,-soname,$(SONAME) -o $@ $^ $(LIBS)
	ln -sf $@ $(LIBNAME).so
	ln -sf $@ $(SONAME)

# Object files
%.o: %.c
	@echo "Compiling: $<"
	$(CC) $(CFLAGS) -c $< -o $@

# Test program
$(TEST_PROG): pgmodverify.c
	@echo "Building test program: $@"
	$(CC) $(CFLAGS) -DPG_TEST_MAIN -o $@ $< $(LIBS)

# Header file (generate from source)
pgmodverify.h: pgmodverify.c
	@echo "Generating header file: $@"
	@echo "/* PhoenixGuard Module Verification Library Header */" > $@
	@echo "/* Generated from pgmodverify.c */" >> $@
	@echo "" >> $@
	@echo "#ifndef PGMODVERIFY_H" >> $@
	@echo "#define PGMODVERIFY_H" >> $@
	@echo "" >> $@
	@echo "#include <time.h>" >> $@
	@echo "#include <stddef.h>" >> $@
	@echo "" >> $@
	@echo "/* Verification result structure */" >> $@
	@grep -A 10 "typedef struct {" pgmodverify.c | head -11 >> $@
	@echo "" >> $@
	@echo "/* Public API functions */" >> $@
	@echo "int pg_load_certificates_from_dir(const char *cert_dir);" >> $@
	@echo "pg_verify_result_t *pg_verify_module_signature(const char *module_path);" >> $@
	@echo "void pg_free_verify_result(pg_verify_result_t *result);" >> $@
	@echo "void pg_cleanup(void);" >> $@
	@echo "" >> $@
	@echo "#endif /* PGMODVERIFY_H */" >> $@

# Install targets
install: $(STATIC_LIB) $(SHARED_LIB) $(HEADERS)
	@echo "Installing library files..."
	install -d $(DESTDIR)$(LIBDIR)
	install -d $(DESTDIR)$(INCDIR)
	install -m 644 $(STATIC_LIB) $(DESTDIR)$(LIBDIR)/
	install -m 755 $(SHARED_LIB) $(DESTDIR)$(LIBDIR)/
	ln -sf $(SHARED_LIB) $(DESTDIR)$(LIBDIR)/$(SONAME)
	ln -sf $(SHARED_LIB) $(DESTDIR)$(LIBDIR)/$(LIBNAME).so
	install -m 644 $(HEADERS) $(DESTDIR)$(INCDIR)/
	ldconfig

# Uninstall
uninstall:
	@echo "Removing installed files..."
	rm -f $(DESTDIR)$(LIBDIR)/$(STATIC_LIB)
	rm -f $(DESTDIR)$(LIBDIR)/$(SHARED_LIB)
	rm -f $(DESTDIR)$(LIBDIR)/$(SONAME)
	rm -f $(DESTDIR)$(LIBDIR)/$(LIBNAME).so
	rm -f $(DESTDIR)$(INCDIR)/pgmodverify.h
	ldconfig

# Test target
test: $(TEST_PROG)
	@echo "Running basic functionality test..."
	@echo "Note: This requires certificates and a signed module for full testing"
	./$(TEST_PROG) ../secureboot_certs /lib/modules/$(shell uname -r)/kernel/drivers/char/mem.ko || true

# Development test with dummy module
test-dummy: $(TEST_PROG)
	@echo "Creating dummy module for testing..."
	@echo -e "\\x7eModule signature appended~\\n" > test_module.ko
	./$(TEST_PROG) ../secureboot_certs test_module.ko || true
	rm -f test_module.ko

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -f $(OBJECTS)
	rm -f $(STATIC_LIB)
	rm -f $(SHARED_LIB)
	rm -f $(SONAME)
	rm -f $(LIBNAME).so
	rm -f $(TEST_PROG)
	rm -f pgmodverify.h
	rm -f test_module.ko

# Debug build
debug: CFLAGS += -DDEBUG -O0
debug: all

# Show build information
info:
	@echo "PhoenixGuard Module Verification Library Build Info"
	@echo "=================================================="
	@echo "Compiler: $(CC)"
	@echo "CFLAGS: $(CFLAGS)"
	@echo "LDFLAGS: $(LDFLAGS)"
	@echo "Libraries: $(LIBS)"
	@echo "Static Library: $(STATIC_LIB)"
	@echo "Shared Library: $(SHARED_LIB)"
	@echo "Test Program: $(TEST_PROG)"
	@echo "Install Prefix: $(PREFIX)"

# Check dependencies
check-deps:
	@echo "Checking build dependencies..."
	@which $(CC) > /dev/null || (echo "ERROR: $(CC) not found" && exit 1)
	@pkg-config --exists openssl || (echo "ERROR: OpenSSL development packages not found" && exit 1)
	@echo "All dependencies satisfied"
