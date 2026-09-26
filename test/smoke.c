// Smoke test for a packaged ncnn archive: load SqueezeNet and run one inference.
// usage: smoke <model.param> <model.bin> [gpu]
#include <stdio.h>
#include <string.h>
#include <ncnn/c_api.h>

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <model.param> <model.bin> [gpu]\n", argv[0]);
        return 2;
    }
    int gpu = argc > 3 && strcmp(argv[3], "gpu") == 0;

    ncnn_net_t net = ncnn_net_create();
    // ncnn falls back to CPU if no Vulkan device is found
    if (gpu) ncnn_option_set_use_vulkan_compute(ncnn_net_get_option(net), 1);

    if (ncnn_net_load_param(net, argv[1]) || ncnn_net_load_model(net, argv[2])) {
        fprintf(stderr, "failed to load model\n");
        return 1;
    }

    ncnn_mat_t in = ncnn_mat_create_3d(227, 227, 3, NULL);
    ncnn_mat_fill_float(in, 0.5f);

    ncnn_extractor_t ex = ncnn_extractor_create(net);
    ncnn_extractor_input_index(ex, ncnn_net_get_input_index(net, 0), in);

    ncnn_mat_t out = NULL;
    ncnn_extractor_extract_index(ex, ncnn_net_get_output_index(net, 0), &out);
    if (!out) {
        fprintf(stderr, "inference failed\n");
        return 1;
    }

    const float *p = ncnn_mat_get_data(out);
    int w = ncnn_mat_get_w(out), best = 0;
    for (int i = 1; i < w; i++)
        if (p[i] > p[best]) best = i;
    printf("ncnn %s: %d classes, top class %d (%.4f)\n", ncnn_version(), w, best, p[best]);

    ncnn_mat_destroy(out);
    ncnn_extractor_destroy(ex);
    ncnn_mat_destroy(in);
    ncnn_net_destroy(net);
    return w == 1000 ? 0 : 1;
}
