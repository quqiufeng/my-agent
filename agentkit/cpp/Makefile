CXX      = g++
CXXFLAGS = -shared -fPIC -O2 -Wall -std=c++17 $(shell pkg-config --cflags opencv4)
LDLIBS   = $(shell pkg-config --libs opencv4) -lX11 -lXtst
OUT      = ../lib/libagentkit.so

.PHONY: all clean
all:
	mkdir -p ../lib
	$(CXX) $(CXXFLAGS) agentkit.cpp -o $(OUT) $(LDLIBS)
	@echo "  -> $(OUT)"

clean:
	rm -f $(OUT)
