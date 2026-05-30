#pragma once

#include "ILayout.hpp"

class GridLayout : public ILayout
{
public:
    void ApplyLayout(const std::vector<ClientWindow*>& windows) override;
};
