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
    auto x_mean { vec1.mean() };
    auto y_mean { vec2.mean() };
    
    unsigned size = vec1.get_size();
    if (size == 0) return 0.0;
    
    double numerator { 0.0 };      // Sum of (x_i - x_mean) * (y_i - y_mean)
    double x_variance_sum { 0.0 }; // Sum of (x_i - x_mean)^2
    double y_variance_sum { 0.0 }; // Sum of (y_i - y_mean)^2
    
    for (unsigned i = 0; i < size; i++) {
        double x_diff = vec1[i] - x_mean;
        double y_diff = vec2[i] - y_mean;
        
        numerator += x_diff * y_diff;

        x_variance_sum += x_diff * x_diff;
        y_variance_sum += y_diff * y_diff;
    }
    
    double denominator = std::sqrt(x_variance_sum * y_variance_sum);
    
    if (denominator == 0.0) {
        return 0.0;
    }
    
    double r = numerator / denominator;

    return std::max(std::min(r, 1.0), -1.0);
}
};
