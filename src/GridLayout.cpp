#include "GridLayout.hpp"
#include <cmath>
#include <iostream>

void GridLayout::ApplyLayout(const std::vector<ClientWindow*>& windows)
{
    if (windows.empty()) return;

    // Filter out floating windows, we only tile non-floating ones
    std::vector<ClientWindow*> tiledWindows;
    for (auto* w : windows)
    {
        if (!w->is_floating)
        {
            tiledWindows.push_back(w);
        }
    }

    if (tiledWindows.empty()) return;

    // A simple infinite grid: expanding to the right and down.
    // Instead of fitting to a screen, we give each window a fixed comfortable size.
    double defaultWidth = 1200.0;
    double defaultHeight = 800.0;
    double gap = 30.0;

    // Calculate how many columns we want based on the square root of window count 
    // to keep it roughly square.
    int cols = std::ceil(std::sqrt(tiledWindows.size()));
    if (cols == 0) cols = 1;

    for (size_t i = 0; i < tiledWindows.size(); ++i)
    {
        int row = i / cols;
        int col = i % cols;

        tiledWindows[i]->absolute_x = col * (defaultWidth + gap);
        tiledWindows[i]->absolute_y = row * (defaultHeight + gap);
        tiledWindows[i]->width = defaultWidth;
        tiledWindows[i]->height = defaultHeight;
    }

    std::cout << "Applied GridLayout to " << tiledWindows.size() << " windows." << std::endl;
}
