/*
Author: David Holmqvist <daae19@student.bth.se>
*/

#include "analysis.hpp"
#include "dataset.hpp"
#include <iostream>
#include <cstdlib>
#include <string>

int main(int argc, char const* argv[])
{
    if (argc != 4) {
        std::cerr << "Usage: " << argv[0] << " [dataset] [outfile] [num_threads]" << std::endl;
        std::exit(1);
    }
    
    const char* dataset_file = argv[1];
    const char* outfile = argv[2];
    
    int num_threads = 0;
    try {
        num_threads = std::stoi(argv[3]);
        if (num_threads <= 0) {
            std::cerr << "Error: Number of threads must be a positive integer." << std::endl;
            std::exit(1);
        }
    } catch (const std::invalid_argument& e) {
        std::cerr << "Error: Invalid argument for number of threads." << std::endl;
        std::exit(1);
    } catch (const std::out_of_range& e) {
        std::cerr << "Error: Number of threads out of range." << std::endl;
        std::exit(1);
    }

    auto datasets { Dataset::read(dataset_file) };
    if (datasets.size() <= 1) {
        Dataset::write({}, outfile);
        return 0;
    }

    auto corrs { Analysis::correlation_coefficients(datasets, num_threads) };
    Dataset::write(corrs, outfile);

    return 0;
}
