#include <math.h>
#include <netcdf.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK_NC(call)                                                     \
    do {                                                                   \
        int status__ = (call);                                              \
        if (status__ != NC_NOERR) {                                         \
            fprintf(stderr, "NetCDF error at %s:%d: %s\n", __FILE__,        \
                    __LINE__, nc_strerror(status__));                       \
            return 2;                                                       \
        }                                                                  \
    } while (0)

static const char *default_vars[] = {
    "hs", "hswe", "tps", "tm01", "tm02", "tmm10",
    "theta0", "thetap", "spread", "L"
};

static int has_float_attr(int ncid, int varid, const char *name, float *out) {
    nc_type xtype;
    size_t len;
    if (nc_inq_att(ncid, varid, name, &xtype, &len) != NC_NOERR || len < 1) {
        return 0;
    }
    return nc_get_att_float(ncid, varid, name, out) == NC_NOERR;
}

static int has_double_attr(int ncid, int varid, const char *name, double *out) {
    nc_type xtype;
    size_t len;
    if (nc_inq_att(ncid, varid, name, &xtype, &len) != NC_NOERR || len < 1) {
        return 0;
    }
    return nc_get_att_double(ncid, varid, name, out) == NC_NOERR;
}

static int check_var(int ncid, const char *name) {
    int varid, ndims, dimids[NC_MAX_VAR_DIMS];
    nc_type xtype;
    size_t total = 1;

    if (nc_inq_varid(ncid, name, &varid) != NC_NOERR) {
        return 0;
    }
    CHECK_NC(nc_inq_var(ncid, varid, NULL, &xtype, &ndims, dimids, NULL));
    if (xtype != NC_FLOAT && xtype != NC_DOUBLE && xtype != NC_INT &&
        xtype != NC_SHORT && xtype != NC_BYTE) {
        printf("%s: skipped non-numeric variable\n", name);
        return 1;
    }

    for (int i = 0; i < ndims; i++) {
        size_t len = 0;
        CHECK_NC(nc_inq_dimlen(ncid, dimids[i], &len));
        total *= len;
    }

    float *data = (float *)malloc(total * sizeof(float));
    if (!data) {
        fprintf(stderr, "%s: allocation failed for %zu values\n", name, total);
        return 2;
    }

    CHECK_NC(nc_get_var_float(ncid, varid, data));

    float fill = 9.96921e36f, missing = 9.96921e36f;
    int has_fill = has_float_attr(ncid, varid, "_FillValue", &fill);
    int has_missing = has_float_attr(ncid, varid, "missing_value", &missing);
    double scale = 1.0, offset = 0.0;
    has_double_attr(ncid, varid, "scale_factor", &scale);
    has_double_attr(ncid, varid, "add_offset", &offset);

    size_t valid = 0, miss = 0;
    double minv = 0.0, maxv = 0.0;
    for (size_t i = 0; i < total; i++) {
        float raw = data[i];
        int is_missing = !isfinite(raw);
        if (has_fill && fabsf(raw - fill) <= fmaxf(1.0f, fabsf(fill)) * 1e-6f) {
            is_missing = 1;
        }
        if (has_missing &&
            fabsf(raw - missing) <= fmaxf(1.0f, fabsf(missing)) * 1e-6f) {
            is_missing = 1;
        }
        if (is_missing) {
            miss++;
            continue;
        }
        double x = (double)raw * scale + offset;
        if (!isfinite(x)) {
            miss++;
            continue;
        }
        if (valid == 0) {
            minv = maxv = x;
        } else {
            if (x < minv) minv = x;
            if (x > maxv) maxv = x;
        }
        valid++;
    }

    if (valid > 0) {
        printf("%s: total=%zu, valid=%zu, miss=%zu, min=%g, max=%g\n",
               name, total, valid, miss, minv, maxv);
    } else {
        printf("%s: total=%zu, valid=0, miss=%zu, min=nan, max=nan\n",
               name, total, miss);
    }

    free(data);
    return 1;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s file.nc [var ...]\n", argv[0]);
        return 1;
    }

    int ncid;
    CHECK_NC(nc_open(argv[1], NC_NOWRITE, &ncid));

    if (argc > 2) {
        for (int i = 2; i < argc; i++) {
            int rc = check_var(ncid, argv[i]);
            if (rc == 2) {
                nc_close(ncid);
                return 2;
            }
        }
    } else {
        printf("candidate_vars:");
        for (size_t i = 0; i < sizeof(default_vars) / sizeof(default_vars[0]); i++) {
            int varid;
            if (nc_inq_varid(ncid, default_vars[i], &varid) == NC_NOERR) {
                printf(" %s", default_vars[i]);
            }
        }
        printf("\n");

        for (size_t i = 0; i < sizeof(default_vars) / sizeof(default_vars[0]); i++) {
            int rc = check_var(ncid, default_vars[i]);
            if (rc == 2) {
                nc_close(ncid);
                return 2;
            }
        }
    }

    CHECK_NC(nc_close(ncid));
    return 0;
}
