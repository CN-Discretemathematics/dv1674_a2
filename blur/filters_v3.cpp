/*
Author: David Holmqvist <daae19@student.bth.se>
*/

#include "filters.hpp"
#include "matrix.hpp"
#include "ppm.hpp"
#include <cmath>

namespace Filter
{
    namespace Gauss
    {
        void get_weights(int n, double *weights_out)
        {
            for (auto i{0}; i <= n; i++)
            {
                double x{static_cast<double>(i) * max_x / n};
                weights_out[i] = exp(-x * x * pi);
            }
        }
    }

    Matrix blur(Matrix m, const int radius)
    {
        Matrix scratch{PPM::max_dimension};
        auto dst{m};
        double w[Gauss::max_radius]{};
        Gauss::get_weights(radius, w);
        
        for (auto y{0}; y < dst.get_y_size(); y++)
        {
            for (auto x{0}; x < dst.get_x_size(); x++)
            {
                auto r{w[0] * dst.r(x, y)}, g{w[0] * dst.g(x, y)}, b{w[0] * dst.b(x, y)}, n{w[0]};
                for (auto wi{1}; wi <= radius; wi++)
                {
                    auto wc{w[wi]};
                    if (x - wi >= 0) {
                        r += wc * dst.r(x - wi, y); g += wc * dst.g(x - wi, y); b += wc * dst.b(x - wi, y); n+=wc;
                    }
                    if (x + wi < dst.get_x_size()) {
                        r += wc * dst.r(x + wi, y); g += wc * dst.g(x + wi, y); b += wc * dst.b(x + wi, y); n+=wc;
                    }
                }
                scratch.r(x, y) = r / n; scratch.g(x, y) = g / n; scratch.b(x, y) = b / n;
            }
        }

        for (auto y{0}; y < dst.get_y_size(); y++)
        {
            for (auto x{0}; x < dst.get_x_size(); x++)
            {
                auto r{w[0] * scratch.r(x, y)}, g{w[0] * scratch.g(x, y)}, b{w[0] * scratch.b(x, y)}, n{w[0]};
                for (auto wi{1}; wi <= radius; wi++)
                {
                    auto wc{w[wi]};
                    if (y - wi >= 0) {
                        r += wc * scratch.r(x, y - wi); g += wc * scratch.g(x, y - wi); b += wc * scratch.b(x, y - wi); n+=wc;
                    }
                    if (y + wi < dst.get_y_size()) {
                        r += wc * scratch.r(x, y + wi); g += wc * scratch.g(x, y + wi); b += wc * scratch.b(x, y + wi); n+=wc;
                    }
                }
                dst.r(x, y) = r / n; dst.g(x, y) = g / n; dst.b(x, y) = b / n;
            }
        }
        return dst;
    }
}
