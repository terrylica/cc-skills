#import "RelativeLuminance.h"

double FCRelativeLuminance(double r, double g, double b) {
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
