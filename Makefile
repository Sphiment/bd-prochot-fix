CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -Wpedantic
CPPFLAGS ?=
LDFLAGS ?=

BUILD_DIR := build
TARGET := $(BUILD_DIR)/bd-prochot-fix
SOURCE := src/bd-prochot-fix.c

.PHONY: all clean test

all: $(TARGET)

$(TARGET): $(SOURCE)
	mkdir -p $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -o $@ $<

test: $(TARGET)
	./$(TARGET) --help

clean:
	rm -rf -- $(BUILD_DIR)
