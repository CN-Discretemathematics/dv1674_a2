# Author: David Holmqvist <daae19@student.bth.se>
# Modified for multi-version compilation with isolated -O3 step

CXX=g++
# Base CXXFLAGS without optimization for the baseline version
CXXFLAGS_BASE=-std=c++17 -g -Wunused -Wall
# CXXFLAGS with optimization for optimized versions
CXXFLAGS_OPT=-std=c++17 -O3 -Wall
# Linker flags for pthreads
LDFLAGS=-lpthread

# --- Targets ---
all: blur blur_v2 blur_v3 blur_v4 blur_par

# --- Object file rules ---
# Common object files are compiled once
matrix.o: matrix.cpp matrix.hpp
	$(CXX) $(CXXFLAGS_BASE) -c matrix.cpp -o matrix.o

ppm.o: ppm.cpp ppm.hpp
	$(CXX) $(CXXFLAGS_BASE) -c ppm.cpp -o ppm.o

blur.o: blur.cpp
	$(CXX) $(CXXFLAGS_BASE) -c blur.cpp -o blur.o

# --- Executable Rules ---

# V1 - Baseline target: blur
# Uses filters.cpp compiled WITHOUT optimization
filters.o: filters.cpp filters.hpp matrix.hpp
	$(CXX) $(CXXFLAGS_BASE) -c filters.cpp -o filters.o

blur: blur.o matrix.o ppm.o filters.o
	$(CXX) $(CXXFLAGS_BASE) $^ -o blur

# V2 - Compiler Optimization target: blur_v2
# Uses filters.cpp compiled WITH optimization
filters_o3.o: filters.cpp filters.hpp matrix.hpp
	$(CXX) $(CXXFLAGS_OPT) -c filters.cpp -o filters_o3.o

blur_v2: blur.o matrix.o ppm.o filters_o3.o
	$(CXX) $(CXXFLAGS_OPT) $^ -o blur_v2

# V3 - Algorithmic Optimization A target: blur_v3
# Uses filters_v2.cpp compiled WITH optimization
filters_v2.o: filters_v2.cpp filters.hpp matrix.hpp
	$(CXX) $(CXXFLAGS_OPT) -c filters_v2.cpp -o filters_v2.o

blur_v3: blur.o matrix.o ppm.o filters_v2.o
	$(CXX) $(CXXFLAGS_OPT) $^ -o blur_v3

# V4 - Algorithmic Optimization B target: blur_v4
# Uses filters_v3.cpp compiled WITH optimization
filters_v3.o: filters_v3.cpp filters.hpp matrix.hpp
	$(CXX) $(CXXFLAGS_OPT) -c filters_v3.cpp -o filters_v3.o

blur_v4: blur.o matrix.o ppm.o filters_v3.o
	$(CXX) $(CXXFLAGS_OPT) $^ -o blur_v4

# Parallel Version (for later)
blur_par.o: blur_par.cpp
	$(CXX) $(CXXFLAGS_OPT) -c blur_par.cpp -o blur_par.o

blur_par: blur_par.o matrix.o ppm.o filters_v3.o # Uses the fastest sequential filter logic
	$(CXX) $(CXXFLAGS_OPT) $^ -o blur_par $(LDFLAGS)

clean:
	rm -rf *.o blur blur_v2 blur_v3 blur_v4 blur_par *.ppm *.dSYM 2> /dev/null
