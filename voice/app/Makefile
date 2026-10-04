CXX      ?= g++
CXXFLAGS ?= -O2 -std=c++17 -Wall -Wextra
PKGS     := opencv4 sdl2
CXXFLAGS += $(shell pkg-config --cflags $(PKGS))
LDLIBS   := $(shell pkg-config --libs $(PKGS)) -lasound -lpthread

app: app.cpp
	$(CXX) $(CXXFLAGS) -o $@ $< $(LDLIBS)

clean:
	rm -f app

.PHONY: clean
