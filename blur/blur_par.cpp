#include "filters.hpp"
#include "matrix.hpp"
#include "ppm.hpp"
#include <iostream>
#include <pthread.h>
#include <vector>

struct Barrier {
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    int count;
    int total;
};

void barrier_init(Barrier* b, int n) {
    pthread_mutex_init(&b->mutex, NULL);
    pthread_cond_init(&b->cond, NULL);
    b->count = 0;
    b->total = n;
}

void barrier_wait(Barrier* b) {
    pthread_mutex_lock(&b->mutex);
    b->count++;
    if (b->count == b->total) {
        b->count = 0;
        pthread_cond_broadcast(&b->cond);
    } else {
        pthread_cond_wait(&b->cond, &b->mutex);
    }
    pthread_mutex_unlock(&b->mutex);
}

void barrier_destroy(Barrier* b) {
    pthread_mutex_destroy(&b->mutex);
    pthread_cond_destroy(&b->cond);
}

struct ThreadData {
    int thread_id;
    int num_threads;
    int radius;
    const Matrix* input_m;
    Matrix* temp_m;
    Matrix* result_m;
    const double* weights;
    Barrier* barrier;  
};

void* blur_worker(void* arg) {
    ThreadData* data = (ThreadData*)arg;
    const int height = data->input_m->get_y_size();
    const int width = data->input_m->get_x_size();
    const int radius = data->radius;
    const double* w = data->weights;
    
    int rows_per_thread = height / data->num_threads;
    int start_row = data->thread_id * rows_per_thread;
    int end_row = (data->thread_id == data->num_threads - 1) ? height : start_row + rows_per_thread;
    
    for (int y = start_row; y < end_row; y++) {
        for (int x = 0; x < width; x++) {
            auto r = w[0] * data->input_m->r(x, y);
            auto g = w[0] * data->input_m->g(x, y);
            auto b = w[0] * data->input_m->b(x, y);
            auto n = w[0];
            
            for (int wi = 1; wi <= radius; wi++) {
                auto wc = w[wi];
                if (x - wi >= 0) {
                    r += wc * data->input_m->r(x - wi, y);
                    g += wc * data->input_m->g(x - wi, y);
                    b += wc * data->input_m->b(x - wi, y);
                    n += wc;
                }
                if (x + wi < width) {
                    r += wc * data->input_m->r(x + wi, y);
                    g += wc * data->input_m->g(x + wi, y);
                    b += wc * data->input_m->b(x + wi, y);
                    n += wc;
                }
            }
            data->temp_m->r(x, y) = r / n;
            data->temp_m->g(x, y) = g / n;
            data->temp_m->b(x, y) = b / n;
        }
    }
    
    barrier_wait(data->barrier);
    
    for (int y = start_row; y < end_row; y++) {
        for (int x = 0; x < width; x++) {
            auto r = w[0] * data->temp_m->r(x, y);
            auto g = w[0] * data->temp_m->g(x, y);
            auto b = w[0] * data->temp_m->b(x, y);
            auto n = w[0];
            
            for (int wi = 1; wi <= radius; wi++) {
                auto wc = w[wi];
                if (y - wi >= 0) {
                    r += wc * data->temp_m->r(x, y - wi);
                    g += wc * data->temp_m->g(x, y - wi);
                    b += wc * data->temp_m->b(x, y - wi);
                    n += wc;
                }
                if (y + wi < height) {
                    r += wc * data->temp_m->r(x, y + wi);
                    g += wc * data->temp_m->g(x, y + wi);
                    b += wc * data->temp_m->b(x, y + wi);
                    n += wc;
                }
            }
            data->result_m->r(x, y) = r / n;
            data->result_m->g(x, y) = g / n;
            data->result_m->b(x, y) = b / n;
        }
    }
    
    pthread_exit(NULL);
}

int main(int argc, char** argv) {
    if (argc != 5) { 
        std::cerr << "Usage: " << argv[0] << " [radius] [infile] [outfile] [num_threads]" << std::endl;
        return 1;
    }
    
    int radius = std::stoi(argv[1]);
    const char* infile = argv[2];
    const char* outfile = argv[3];
    int num_threads = std::stoi(argv[4]);
    
    PPM::Reader reader{};
    Matrix input_m = reader(infile);
    
    if (input_m.get_x_size() == 0 || input_m.get_y_size() == 0) {
        std::cerr << "Error: Failed to read input file or image is empty: " << infile << std::endl;
        return 1;
    }
    
    Matrix temp_m{input_m};
    Matrix result_m{input_m};

    double weights[Filter::Gauss::max_radius]{};
    Filter::Gauss::get_weights(radius, weights);
    
    Barrier barrier;
    barrier_init(&barrier, num_threads);
    
    std::vector<pthread_t> threads(num_threads);
    std::vector<ThreadData> thread_data(num_threads);
    
    for (int i = 0; i < num_threads; ++i) {
        thread_data[i] = {i, num_threads, radius, &input_m, &temp_m, &result_m, weights, &barrier};
        pthread_create(&threads[i], NULL, blur_worker, &thread_data[i]);
    }
    
    for (int i = 0; i < num_threads; ++i) {
        pthread_join(threads[i], NULL);
    }
    
    barrier_destroy(&barrier);
    
    PPM::Writer writer{};
    writer(result_m, outfile);
    
    return 0;
}
