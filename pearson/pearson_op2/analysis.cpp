/*
Author: David Holmqvist <daae19@student.bth.se>
*/

#include "analysis.hpp"
#include <algorithm>
#include <cmath>
#include <iostream>
#include <list>
#include <vector>

namespace Analysis {

std::vector<double> correlation_coefficients(const std::vector<Vector>& datasets)
{
    std::vector<double> result {};

    for (auto sample1 { 0 }; sample1 < datasets.size() - 1; sample1++) {
        for (auto sample2 { sample1 + 1 }; sample2 < datasets.size(); sample2++) {
            auto corr { pearson(datasets[sample1], datasets[sample2]) };
            result.push_back(corr);
        }
    }

    return result;
}

double pearson(const Vector& vec1, const Vector& vec2)
{
    unsigned n = vec1.get_size();
    if (n == 0) return 0.0;
    
    const double* x_data = vec1.get_data();
    const double* y_data = vec2.get_data();
    
    double sum_x = 0.0;
    double sum_y = 0.0;
    double sum_x2 = 0.0; 
    double sum_y2 = 0.0; 
    double sum_xy = 0.0; 
    
    // fusion
    for (unsigned i = 0; i < n; i++) {
        double x = x_data[i]; 
        double y = y_data[i]; 
        
        sum_x += x;
        sum_y += y;
        sum_x2 += x * x;
        sum_y2 += y * y;
        sum_xy += x * y;
    }
    
    double N_double = static_cast<double>(n);
    double numerator = N_double * sum_xy - sum_x * sum_y;
    
    // Denominator 
    double term_x = N_double * sum_x2 - sum_x * sum_x;
    double term_y = N_double * sum_y2 - sum_y * sum_y;
    
    if (term_x <= 0.0 || term_y <= 0.0) {
        return 0.0;
    }
    
    double denominator = std::sqrt(term_x * term_y);
    
    double r = numerator / denominator;

    return std::max(std::min(r, 1.0), -1.0);
}
};
