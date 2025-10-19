/*
Author: David Holmqvist <daae19@student.bth.se>
*/

#include "vector.hpp"
#include <vector>

#if !defined(ANALYSIS_HPP)
#define ANALYSIS_HPP


struct ThreadData {
    const std::vector<Vector>* datasets; 

    int output_start_index; 
    int output_end_index;
    
    double* results_out;
};

namespace Analysis {
std::vector<double> correlation_coefficients(const std::vector<Vector>& datasets, int num_threads);
void* pearson_worker(void* arg);
double pearson(const Vector& vec1, const Vector& vec2);
};

#endif
