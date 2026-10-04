CXX      ?= g++
CXXFLAGS ?= -O2 -std=c++17 -Wall -Wextra
LDLIBS   := -lasound -lpthread

listen: listen.cpp
	$(CXX) $(CXXFLAGS) -o $@ $< $(LDLIBS)

clean:
	rm -f listen

.PHONY: clean
