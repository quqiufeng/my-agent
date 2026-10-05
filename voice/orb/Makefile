CXX ?= g++
CXXFLAGS ?= -O2 -std=c++17 -Wall -Wextra $(shell sdl2-config --cflags)
LDLIBS = $(shell sdl2-config --libs)

orb: orb.cpp
	$(CXX) $(CXXFLAGS) -o orb orb.cpp $(LDLIBS)

clean:
	rm -f orb

.PHONY: clean
