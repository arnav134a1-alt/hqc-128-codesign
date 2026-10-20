CC = gcc
CFLAGS = -O2 -Wall -Wextra -Wpedantic -Iinclude -std=c99
SRC = src/hqc_hal.c test/main_demo.c
TARGET = hqc_demo

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $^

run: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(TARGET) $(TARGET).exe 2>/dev/null || del /f /q $(TARGET) $(TARGET).exe 2>nul || true

.PHONY: all run clean
