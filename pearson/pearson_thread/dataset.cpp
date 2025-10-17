/*
Author: David Holmqvist <daae19@student.bth.se>
*/
#include "dataset.hpp"
#include "vector.hpp"
#include <fstream>
#include <iostream>
#include <sstream>
#include <iterator>
#include <algorithm>
#include <iomanip>
#include <limits>
#include <cstdio>

namespace Dataset
{
    std::vector<Vector> read(const std::string& filename)
    {
        unsigned dimension{};
        std::vector<Vector> result{};
        
        std::ifstream f(filename);

        if (!f)
        {
            std::cerr << "Failed to read dataset(s) from file " << filename << std::endl;
            return result;
        }

        f >> dimension;
        std::string line;

        
        std::getline(f, line); // consume first newline

        while (std::getline(f, line))
        {
            result.emplace_back(dimension);
            Vector& new_vec = result.back();
            double* data_ptr = new_vec.get_data();

            const char* cur = line.c_str();
            char* endptr = nullptr;

            for (unsigned i = 0; i < dimension; ++i) {
                double val = std::strtod(cur, &endptr);
     
                if (cur == endptr) {
                    break;
                }
                
                data_ptr[i] = val;
                cur = endptr; 
            }
        }

        return result;
    }

    void write(std::vector<double> data, std::string filename)
    {
        std::ofstream f{};

        f.open(filename);

        if (!f)
        {
            std::cerr << "Failed to write data to file " << filename << std::endl;
            return;
        }

        for (unsigned i{0}; i < data.size(); i++)
        {
            f << std::setprecision(std::numeric_limits<double>::digits10 + 1) << data[i] << std::endl;
        }
    }

};
