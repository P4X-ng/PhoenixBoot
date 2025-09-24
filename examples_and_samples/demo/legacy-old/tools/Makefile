# PhoenixGuard Security Suite Makefile
# Simple build system for demonstration purposes

CC = gcc
CFLAGS = -Wall -Wextra -std=c99 -DPHOENIXGUARD_DEMO -I.

# Source files
SOURCES = \
	PhoenixGuardMain.c \
	BootkitSentinel.c \
	BootstrapGuardian.c \
	IntegrityValidator.c \
	ImmutableRecovery.c \
	BootChainHoneypot.c \
	OsIntegrityValidator.c \
	SentinelAnalysis.c \
	ParanoiaMode.c

# Object files
OBJECTS = $(SOURCES:.c=.o)

# Target executable
TARGET = phoenixguard_demo

# Build rules
all: $(TARGET)

$(TARGET): $(OBJECTS)
	@echo "🔗 Linking PhoenixGuard Demo..."
	@$(CC) $(OBJECTS) -o $(TARGET)
	@echo "✅ Build complete: $(TARGET)"

%.o: %.c
	@echo "🔨 Compiling $<..."
	@$(CC) $(CFLAGS) -c $< -o $@

clean:
	@echo "🧹 Cleaning build artifacts..."
	@rm -f $(OBJECTS) $(TARGET)
	@echo "✅ Clean complete"

demo: $(TARGET)
	@echo "🚀 Running PhoenixGuard demo..."
	@./$(TARGET)

install: $(TARGET)
	@echo "📦 Installing PhoenixGuard..."
	@cp $(TARGET) /usr/local/bin/
	@echo "✅ Installed to /usr/local/bin/$(TARGET)"

.PHONY: all clean demo install

# Help target
help:
	@echo "PhoenixGuard Security Suite Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all     - Build PhoenixGuard demo"
	@echo "  clean   - Remove build artifacts"
	@echo "  demo    - Build and run demonstration"
	@echo "  install - Install to system"
	@echo "  help    - Show this help"
