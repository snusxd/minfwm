#pragma once

#include <vector>
#include "ClientWindow.hpp"

class ILayout
{
public:
    virtual ~ILayout() = default;

    // Applies the layout algorithm to the provided list of windows,
    // updating their absolute_x, absolute_y, width, and height.
    virtual void ApplyLayout(const std::vector<ClientWindow*>& windows) = 0;
};
